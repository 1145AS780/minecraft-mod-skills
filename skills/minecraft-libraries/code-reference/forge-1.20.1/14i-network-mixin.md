# 网络层与 Mixin 拦截：请求响应分道、限流、实体复原、四种拦截手法

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.35 网络层：请求/响应分道 + 客户端 handler 隔离 + 服务端限流

`NetworkHandler` 里 12 条消息全挤在一个 `SimpleChannel`，但没有一条是随手写的——这套结构可以直接照抄。

**① 协议版本号写成常量，且三参数同时校验**

```java
private static final String PROTOCOL_VERSION = "11";
public static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
    new ResourceLocation(MODID, "main"),
    () -> PROTOCOL_VERSION, PROTOCOL_VERSION::equals, PROTOCOL_VERSION::equals);
```

第三个/第四个参数分别是「客户端校验服务端」「服务端校验客户端」。**只给版本字符串不给校验函数**，
等于版本号写了不生效——两端版本不一致时照样连上，然后在 decode 阶段炸成 `DecoderException`，
排查成本比连不上高一个数量级。

**② message id 手工自增，方向必须显式声明**

```java
private static int id = 0;
CHANNEL.registerMessage(id++, XxxMessage.class,
    XxxMessage::encode, XxxMessage::decode, XxxMessage::handle,
    Optional.of(NetworkDirection.PLAY_TO_SERVER));   // 别省这个 Optional
```

省掉方向参数时 Forge 按「收发双方都注册」处理，结果是**本该只往服务端发的包也能被服务端发出去**，
一旦有人误调 `CHANNEL.sendToPlayer(...)` 就变成客户端崩溃。方向显式声明是最便宜的防误用。

**③ 一包多义：用 Action 枚举而不是开一堆类**

```java
private static void encode(Msg m, FriendlyByteBuf buf) {
    buf.writeEnum(m.action);
    switch (m.action) {
        case REQUEST_MAID_LIST: buf.writeBoolean(m.fromMaidBackpack); break;
        case REQUEST_HUD_DATA:  break;                                   // 无载荷
        case OPEN_MAID_INVENTORY:
        case TELEPORT_TO_MAID:  buf.writeUUID(m.maidUuid); break;
    }
}

public static Msg decode(FriendlyByteBuf buf) {
    Action action = buf.readEnum(Action.class);
    return switch (action) {
        case REQUEST_MAID_LIST -> new Msg(action, buf.readBoolean(), null);
        case REQUEST_HUD_DATA  -> new Msg(action, false, null);
        case OPEN_MAID_INVENTORY, TELEPORT_TO_MAID -> new Msg(action, false, buf.readUUID());
    };
}
```

铁律：**encode 与 decode 的 switch 必须逐分支对称**，且构造器私有、只暴露 `requestXxx()` 静态工厂。
私有构造 + 工厂方法 = 编码端不可能造出「decode 读不出」的载荷组合。

**④ 请求与响应分成两个类、两个方向**

```
EnderPocketRequestMessage   PLAY_TO_SERVER   （客户端点按钮）
EnderPocketDataMessage      PLAY_TO_CLIENT   （服务端回数据）
EnderPocketMaidReadyMessage PLAY_TO_SERVER   （客户端回执"我准备好了"）
```

一个 `Action` 请求配一个专用响应类，而不是「同一个类双向复用」。复用类会让
`encode` 里出现 `if (isResponse)` 分支，两端字段集不同步时最难查。

**⑤ handle 只做三件事：enqueueWork / 侧别判断 / setPacketHandled**

```java
public static void handle(Msg message, Supplier<Context> ctx) {
    Context context = ctx.get();
    context.enqueueWork(() -> {
        if (context.getDirection().getReceptionSide().isClient()) {
            DistExecutor.unsafeRunWhenOn(Dist.CLIENT, () -> () -> ClientHandler.handle(message));
        }
    });
    context.setPacketHandled(true);
}
```

三个易漏点：
- **业务逻辑一行都不许写在 handle 里**，全部下沉到 `XxxClientHandler` / `XxxServerHandler`。
  这样专用服务端（Dedicated Server）加载这个 message 类时不会碰到任何客户端类。
- 客户端分支必须走 `DistExecutor.unsafeRunWhenOn`，**不能直接调客户端方法**——直接调会在专用服务端上
  触发 `NoClassDefFoundError`（类加载期，不是运行期，try/catch 兜不住）。
- `setPacketHandled(true)` 放在 `enqueueWork` 外面：表示「这个包我收下了」，
  与任务何时执行无关。漏掉会导致 Forge 打「unhandled message」警告并可能重复投递。

**⑥ 大小上限在 encode 和 decode 双侧都硬校验**

```java
public static final int MAX_ENTITY_TYPE_ID_LENGTH = 256;
public static final int MAX_ENTITY_DATA_VALUES = 255;

// encode 侧
buf.writeUtf(message.entityTypeId.toString(), 256);
if (message.entityData.size() > 255)
    throw new IllegalArgumentException("Entity data count exceeds limit: " + size);

// decode 侧
String s = buf.readUtf(256);
ResourceLocation id = ResourceLocation.tryParse(s);
if (id == null) throw new DecoderException("Invalid entity type id: " + s);
int n = buf.readVarInt();
if (n < 0 || n > 255) throw new DecoderException("Entity data count exceeds limit: " + n);
```

**只在校验一侧做上限 = 没做**。恶意客户端可以发 `Integer.MAX_VALUE` 让服务端
`new ArrayList<>(n)` 直接 OOM。decode 侧必须**先校验范围、再分配容器**，顺序反了就是内存炸弹。
`readUtf(256)` 的第二个参数是上限而不是长度，这一点也常被误用。

**⑦ 服务端限流：WeakHashMap + 每动作独立冷却 + 不可变状态整体替换**

```java
private static final Map<ServerPlayer, RateLimitState> RATE_LIMITS =
    Collections.synchronizedMap(new WeakHashMap<>());

private static boolean tryAcquire(ServerPlayer player, Action action) {
    long now = System.nanoTime();
    synchronized (RATE_LIMITS) {
        RateLimitState s = RATE_LIMITS.getOrDefault(player, RateLimitState.EMPTY);
        long last = switch (action) { ... };
        long cooldown = switch (action) {
            case REQUEST_MAID_LIST -> LIST_REQUEST_COOLDOWN_NANOS;   // 250ms
            case REQUEST_HUD_DATA -> HUD_REQUEST_COOLDOWN_NANOS;
            case OPEN_MAID_INVENTORY -> OPEN_REQUEST_COOLDOWN_NANOS; // 250ms
            case TELEPORT_TO_MAID -> TELEPORT_REQUEST_COOLDOWN_NANOS;// 1s
        };
        if (last != 0L && now - last < cooldown) return false;
        RATE_LIMITS.put(player, /* 整体替换为新 record */);
        return true;
    }
}
```

- `WeakHashMap<ServerPlayer, ...>`：玩家退出后条目自动可回收，**不用手写 logout 清理**（但有 logout 钩子仍要清，见 §14.28 的双保险思路）。
- 冷却按 Action 分开记：玩家列表刷新可以 250ms 一次，传送必须 1s 一次。**统一冷却会让「高频无害操作」拖累「低频危险操作」**。
- `RateLimitState` 是 `record` 且 4 个字段全 `final`：每次整体替换，不做字段级 `set`。可变状态 + `synchronized` 是最容易漏同步的组合。
- 时间用 `System.nanoTime()` + `TimeUnit.MILLISECONDS.toNanos(...)`，不要用 `currentTimeMillis` 做差值（会被系统时间调整影响）。

**⑧ 客户端「复原被删掉的实体」标准七步**

服务端把远处女仆删了（区块卸载/传送），但客户端还想显示它，消息到达后按顺序：

```java
ClientMaidRemovalGuard.markProtected(message.entityId());   // ① 先挂牌，防这条消息自己触发移除
Entity entity = level.getEntity(message.entityId());        // ② 找现存实体
if (entity == null) {
    entity = createEntity(level, message);                  // ③ 按 typeId 造
    if (entity == null) return;                             //    typeId 未注册 → 安静退出
    level.putNonPersistedEntity(message.entityId(), entity);// ④ 用【原 entityId】重新登记
}
((EntityInvoker) entity).maidspell$invokeUnsetRemoved();    // ⑤ 清 removed 标志
if (!message.entityData().isEmpty())
    entity.getEntityData().assignValues(message.entityData()); // ⑥ 覆写同步数据
entity.moveTo(x, y, z, yRot, xRot);
entity.setOldPosAndRot();                                   // ⑦ 防插值「飞过去」
entity.refreshDimensions();                                 //    尺寸可能变了
```

关键点：
- **必须用 `putNonPersistedEntity(id, entity)` 这类「指定 id 登记」接口**。直接 `addFreshEntity` 会分配新 id，
  之后所有按 id 索引的消息（特效、移除、同步）全部错位。
- `setRemoved(false)` 是 protected，靠 `@Invoker` 或 accessor mixin 打通，别反射。
- `setOldPosAndRot()` 必须在 `moveTo` 之后：否则客户端下一帧从旧位置插值到新位置，看起来像瞬移。
- 造实体失败要**安静 return**（`Optional<EntityType>` 为空说明对方没装那个模组），不能抛异常——一条包崩掉整个客户端不值得。

### 14.36 Mixin 层：拦截第三方频道消息的四种手法

本项目 90 个 mixin 里最有价值的一批，都在干同一件事：**不改第三方源码，让它的消息处理「看见」我的实体**。
四种手法按侵入性递增，能低就不高。

**手法 A：`@Redirect` 换掉一次 `getEntity` 调用 —— 一次改，14 个类全生效**

TLM（东方小女仆）有 **15 个** message mixin，其中 **14 个**的 `handle` 里写着 `level.getEntity(entityId)`
（唯一例外是 `RefreshMaidBrainMessageMixin`——它不按 id 解析实体，`getEntity` 命中 0 次，所以不在改造名单里）。
远处女仆在客户端不存在，这些包全部静默失败（掉血特效、模型同步、音效都不显示）。做法是逐类 `@Redirect`：

```java
@Mixin(value = MaidConfigMessage.class, remap = false)
public class MaidConfigMessageMixin {
    @Redirect(
        method = {"lambda$handle$0(Lnet/minecraftforge/network/NetworkEvent$Context;L...MaidConfigMessage;)V"},
        at = @At(value = "INVOKE",
                 target = "Lnet/minecraft/world/level/Level;getEntity(I)Lnet/minecraft/world/entity/Entity;",
                 remap = true),
        remap = true)
    private static Entity maidspell$resolveRemoteMaid(Level level, int entityId) {
        return EnderPocketService.resolvePacketEntity(level, entityId);   // 本地没有就去代理缓存找
    }
}
```

- 目标类 `remap = false`（第三方 mod 的类不做 SRG 映射），`@At.target` 里的 **minecraft 方法要 `remap = true`**。
  这两处 `remap` 是独立的，写错一边就 `Mixin apply failed`。
- `method` 必须写**完整描述符**，包括 lambda 的合成名 `lambda$handle$0(...)V`。反编译产物里能看到，但名字随编译器变，
  升级模组版本时要重新核对——**这是这套方案最脆的地方**。
- 这 14 个里 **11 个正好 28 行**（`RemoteMaidClientMessageMixin` 30 行、`SyncBaubleMessageMixin` 30 行、`OpenMaidGuiMessageMixin` 47 行），
  全是复制粘贴改一个类名。看着笨，但比 `@WrapOperation` 一次性包 14 个方法稳。
- 客户端版本多一层回退：

```java
Entity local = level.getEntity(entityId);
return local instanceof EntityMaid ? local : EnderPocketMaidProxyCache.find(level, entityId);
```

**先认本地实体，再认代理**。顺序反了会让真实女仆被代理壳顶掉，出现「双份女仆」。

**手法 B：`@WrapOperation` 拿返回值再过滤**

```java
@WrapOperation(method = {"applyEffectTick(...)V"},
    at = @At(value = "INVOKE",
             target = "Lnet/minecraft/world/level/Level;getEntitiesOfClass(...)Ljava/util/List;",
             remap = true),
    remap = true)
private List maidspell$filterTargets(Level level, Class cls, AABB area, Predicate pred,
                                     Operation<List> original, @Local(argsOnly = true) LivingEntity caster) {
    List targets = original.call(level, cls, area, pred);      // 先让它自己算
    targets.removeIf(t -> ThunderstormTargetFilter.shouldProtect(caster, (LivingEntity) t));
    return targets;
}
```

`@WrapOperation` 优于 `@Redirect` 的点：**能拿到原调用结果并二次加工**，且可 `original.call` 多次。
`@Local(argsOnly = true)` 直接拿方法参数（这里是施法者），不用写 `@Inject` 再 `@Local` 组合。

⚠️ 陷阱：`getEntitiesOfClass` 返回的 `List` 有时是内部集合的引用，`removeIf` 可能污染原集合。
保守写法是 `new ArrayList<>(original.call(...))` 再过滤。

**手法 C：`@Inject(HEAD, cancellable)` 做守卫，内部 try/catch 兜底**

```java
@Inject(method = {"remove(Lnet/minecraft/world/entity/Entity$RemovalReason;)V"},
        at = {@At("HEAD")}, cancellable = true, remap = true)
private void maidspell$blockUnexpectedRemove(RemovalReason reason, CallbackInfo ci) {
    try {
        if (AnchorCoreProtection.shouldBlockMaidRemove((EntityMaid) this, reason, "remove")) ci.cancel();
    } catch (Exception e) {
        Global.LOGGER.error("Failed to check maid removal source", e);
    }
}
```

- **守卫方法体必须整体 try/catch**。mixin 里抛异常不是「这个功能失效」，是**直接崩游戏**（Mixin 注入的方法没有上层兜底）。
  日志里至少留下「哪个守卫挂了」，否则只能靠二分注释 mixin。
- `ci.cancel()` 在 `HEAD` + `cancellable` 时等于「整个原方法不执行」。所以只能拦**确定不该跑**的路径，
  例如「活着的锚定女仆不该掉墓碑」——拦错了就是功能永久失效。
- 同一思路套三个方法（`addAdditionalSaveData` / `remove` / `dropEquipment`），构成 §14.28 生命周期保护的最外层闸门。

**手法 D：`@ModifyExpressionValue` 只改一个表达式，保留其余逻辑**

```java
@ModifyExpressionValue(method = {"tick"},
    at = @At(value = "INVOKE",
             target = "Lnet/minecraft/world/entity/LivingEntity;getUseItemRemainingTicks()I", remap = true),
    remap = true)
private int maidspell$keepChannelAlive(int original) {
    if (caster instanceof EntityMaid maid && (level.isClientSide || isManagedMaidChannel(maid)))
        return Math.max(original, 1);     // 只把 0 抬到 1，其余原样
    return original;
}
```

「第三方用 `remainingTicks == 0` 判定引导结束 → 实体自毁」，我只想让女仆的引导别结束。
`@ModifyExpressionValue` 精确到「那一次调用」，**不碰判断语句本身**，比 `@Redirect` 换整个方法调用安全得多。
配套用 `@WrapOperation` 换 `getUseItem()` 返回值（让第三方读到我们的法术书），
再用 `@Inject(HEAD)` 丢弃「不该存在的引导实体」——三件套组合起来才是完整的「接管第三方引导法术」。

**⑤ 时序锚点：挂到「主线程断言之后」**

```java
@Inject(method = {"handleRemoveEntities(...)V"},
    at = {@At(value = "INVOKE",
              target = "Lnet/minecraft/network/protocol/PacketUtils;ensureRunningOnSameThread(...)V",
              shift = Shift.AFTER)})
private void maidspell$blockClientRemoval(ClientboundRemoveEntitiesPacket packet, CallbackInfo ci) {
    for (int id : packet.getEntityIds()) {
        Entity e = level.getEntity(id);
        if (e != null && ClientMaidRemovalGuard.shouldBlockRemoval(e, id)) { blockedAny = true; }
        else { level.removeEntity(id, RemovalReason.DISCARDED); removedAny = true; }
    }
    if (blockedAny || removedAny) ci.cancel();     // 自己处理完了，别再走原逻辑
}
```

为什么要 `shift = AFTER`：原方法第一句是「断言在主线程」，在网络线程里读 `level.getEntity` 是数据竞争。
**挂在断言之后，等于免费拿到一次线程保证**。这是「找锚点」而不是「找行号」的典型用法——
目标方法体改版也不影响，因为 `ensureRunningOnSameThread` 是网络包处理的固定入口。

`ci.cancel()` 前必须把**没被拦的那部分自己做掉**（上面 `else` 分支的 `removeEntity`）。
只 cancel 不补做 = 该删的实体永远删不掉，客户端会积累幽灵实体。

**⑥ 一条铁律：拦「解析结果」比拦「业务逻辑」安全**

| 侵入度 | 手法 | 影响面 | 出问题时的表现 |
| --- | --- | --- | --- |
| 最低 | `@Redirect` 换 `getEntity` | 只影响「从 id 拿实体」 | 消息找不到实体 → 功能不生效（可降级） |
| 低 | `@WrapOperation` 过滤返回值 | 只影响一次查询 | 目标列表少几个 → 数值不对（可观察） |
| 中 | `@ModifyExpressionValue` 改单个表达式 | 只影响一个判断 | 第三方状态机走向不同分支 |
| 高 | `@Inject(HEAD, cancellable)` 拦整个方法 | 整个方法不执行 | 功能直接消失（最难定位） |

优先级：**能改「查到的对象」就不要改「判断」，能改「判断」就不要拦「整个方法」**。
本项目 14 个带 `getEntity` 的 message mixin 全停在最低侵入度，正是因为「解析实体」这一层是所有消息的共同瓶颈——
在这里做一次代理转发，等于给 TLM 全部同步通道装了个路由器。