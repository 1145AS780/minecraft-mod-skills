# 饰品与伤害：handler 注册表、非致死决斗、ASM 补丁、血量改写

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.23 女仆饰品（Bauble）：物品类 + 行为类 + 9 张 handler 注册表

实测本模组 27 个饰品全部是**成对**的两个类：

```
item/bauble/<name>/
  ├── <Name>.java        extends Item           32~68 行   纯物品：堆叠 1、Rarity、isFoil、tooltip
  └── <Name>Bauble.java  implements IMaidBauble  4~584 行   行为
```

物品类最小模板（`SpringRing` 实测 33 行）：

```java
public class SpringRing extends Item {
    public SpringRing() { super(new Properties().stacksTo(1).rarity(Rarity.EPIC)); }
    @Override public boolean isFoil(ItemStack s) { return true; }   // 高级物品视觉
    @Override public void appendHoverText(ItemStack s, Level l, List<Component> tip, TooltipFlag f) { /* 见下 */ }
}
```

**关键：行为不写在 `IMaidBauble` 里。** `SpringBauble` 实测 **21 行（总行）/ 18 行（非空行）**——
早期版本写的 18 是非空行口径，不是总数（两套数都对，混用才错，同 14a §14.7 的口径约定）。
`implements IMaidBauble` 后**一个方法都没覆写**，全部逻辑在 `static {}` 块：

```java
public class SpringBauble implements IMaidBauble {
    static {
        Global.baubleDamageHandlers.put(MaidSpellItems.SPRING_RING.get(), (event, maid) -> {
            float p = clamp(Math.abs(1f - maid.getHealth() / maid.getMaxHealth()), 0f, Config.springRingMaxDamageBonus);
            event.setAmount(event.getAmount() * (1f + p));   // 越残血伤害越高，且 clamp 到配置上限
            return null;
        });
    }
}
```

原因：宿主 `IMaidBauble` 只给「穿戴/脱下/每 tick」几个粗钩子，**接不到伤害、效果、死亡这些关键时机**。
作者的做法是自建 9 张 `Item → Handler` 注册表挂在 `Global`：

| 注册表 | 时机 | 遍历点 |
| --- | --- | --- |
| `baubleHurtHandlers` | `LivingHurtEvent` | MaidSpellEventHandler |
| `baubleHurtEventHandlers` | `LivingHurtEvent`（另一阶段） | 同上 |
| `baubleDamageHandlers` | `LivingDamageEvent`（已定伤） | 同上 |
| `baubleSetHealthHandlers` | 写血前的伤害预计算 | MaidDamageProcessor |
| `baubleSetHealthFinalHandlers` | 同一管线收尾阶段 | 同上 |
| `baubleCooldownHandlers` | 法术冷却计算 | IMaidSpellData |
| `baubleEffectAddedHandlers` | `MobEffect` 被添加 | MaidSpellEventHandler |
| `baubleEffectBlockFilters` | `addEffect` 拦截（Mixin） | MobEffectMixin / LivingEntityMixin |
| `baubleDeathHandlers` | `LivingDeathEvent` | MaidSpellEventHandler |

全部 `ConcurrentHashMap`（唯一的 `List` 型 `baubleHurtHeadHandlers` 用 `CopyOnWriteArrayList`，
因为它装的是带 `Predicate` 的 record）。**必须用并发容器**：static 块在类加载期写入、运行时被遍历，
换成 `HashMap` 就是 CME。

**隐式依赖陷阱（排查第一顺位）**：能力靠 `new XxxBauble()` 的静态块「点火」，
而 `new` 发生在 `MaidBaubleRegistry` 里 `manager.bind(item, new XxxBauble())`。
一旦某个 bind 被 `if (MaidSpellItems.X != null)` 挡掉，**静态块不执行，饰品退化成无效果物品，且无任何日志**。
「饰品戴上没反应」第一步就查 bind 有没有跑到。

佩戴判定统一收口（`BaubleStateManager` 三个重载 `ItemStack` / `RegistryObject` / `Item`，调用方不用 `.get()`）：

```java
maid.getMaidBauble().containsItem(item)     // 内部就这一句
```

「饰品给免疫」的正确写法是**在 addEffect 处拦截**，不是每 tick `removeEffect`：

```java
Global.baubleEffectBlockFilters.put(DREAM_CAT_CRYSTAL,
    (maid, effect) -> effect.getCategory() != MobEffectCategory.BENEFICIAL);   // 返回 true = 拦掉
```

每 tick remove 会留下「先加上、再被移除」的一帧特效/音效泄漏。

tooltip 范式（`DreamCatCrystal` 实测）：

- `TooltipHelper.addShiftTooltip(tooltip, 常驻行, 展开行)`：常驻 3~4 行，Shift 才展开细节。
- **展开行按环境动态拼**：`if (IronsSpellbooksCompat.isLoaded())` 追加一行兼容说明；
  `if (Config.dreamCrystalExtraTrueDamageEnabled)` 追加一行配置相关说明。
  → tooltip 反映**当前实际生效**的能力，而不是永远写满一屏。
- **数字必须读 Config**：`String.format("%.0f", Config.springRingMaxDamageBonus * 100)`，不许硬编码。

第三方饰品劫持（软依赖的正确姿势，`MaidBaubleRegistry` 实测）：

```java
private static final IMaidBauble GOETY_CURIO_BAUBLE = new IMaidBauble() { };  // 空实现 = 只让女仆能戴，不加效果
private static final String[] GOETY_CURIO_ITEM_IDS = { "dark_hat", "frost_crown", ... };  // 纯字符串

for (String id : GOETY_CURIO_ITEM_IDS) {
    Item item = ForgeRegistries.ITEMS.getValue(new ResourceLocation("goety", id));
    if (item != null) manager.bind(item, GOETY_CURIO_BAUBLE);
}
```

不 import 目标模组任何类，只用**字符串 ID 列表 + 注册表查找**：目标模组改名、删物品都不崩，
`getValue` 返回 null 就跳过。入口统一为 `@LittleMaidExtension` + `implements ILittleMaid` 的单个注册类。

### 14.24 非致死决斗：伤害闸门必须在每一层重入

Boss 挑战要「打不死的玩家」，不能只在 `LivingDamageEvent` 里 clamp 一次。实测 `WinefoxNonLethalGuard`：

```java
float survivable = Math.max(0f, victim.getHealth() - duelSurvivalFloor());   // 保底血量
if (event.getAmount() >= survivable) event.setAmount(survivable);            // 一击不能致死
```

真正关键的是**追加伤害必须再过一次同一道闸**：

```java
public static float duelFollowUpLimit(LivingEntity victim, DamageSource src, float pendingDamage, float bonus) {
    float room = victim.getHealth() - pendingDamage - duelSurvivalFloor();   // 已挂账的伤害也要扣掉
    return Math.max(0f, Math.min(bonus, room));
}
```

**反模式**：只在 `LivingDamageEvent` 拦一次。持续伤害、多段连击、真实伤害、法术补伤
**各自走不同入口**，只要有一条没重入闸门，玩家就能被打死。
判据：**闸门写成无状态纯函数，每个伤害入口都调它。**

战斗还没开始（`!boss.isBattleActive()`）时直接 `amount = 0` —— 防「挑战未开始就被偷袭」。

**事件优先级不是随便选的**：

| 目标 | 优先级 | 实测用例 |
| --- | --- | --- |
| 要「最后说话」，覆盖别的模组的重定向 | `EventPriority.LOWEST` | `LivingChangeTargetEvent` 里撤销敌对目标 |
| 要「最先拦住」，抢在别的模组处理前 | `EventPriority.HIGHEST` | 拦截已退役女仆的交互 |

**交互拦截必须拦三个事件**：`InteractMaidEvent`（女仆模组自定义）、`EntityInteract`、
`EntityInteractSpecific`。右键实体 / 精确右键 / 模组自定义走的是不同事件，只拦一个必漏。

**伤害源要穿透到「责任实体」**：一次法术伤害的直接来源可能是召唤物、法术实体、甚至 AOE 场，
`source.getEntity()` 拿到的往往不是 Boss。实测双管齐下：

```java
for (Entity e : new Entity[]{source.getEntity(), source.getDirectEntity()}) {
    if (e instanceof Boss) return boss;
    Entity owner = AllyResolver.resolveResponsibleEntity(e).orElse(null);   // 召唤物 → 归属者
    if (owner instanceof Boss) return boss;
}
```

再加一层兜底：拿不到实体时（如爆炸类伤害）**就近查找**范围内的 Boss。
不穿透的结果是「Boss 召唤物打的伤害绕过了所有保护与倍率」。

整段逻辑用 `if (!level.isClientSide)` 包住，并提前 `return` 掉
`player.isDeadOrDying() || player.isSpectator()` —— 濒死/旁观者不该被改写伤害。

### 14.25 ASM 改写返回值的四个补丁级细节（§14.12 的实战补全）

§14.12 给了 FRETURN 前替换的标准手法，实测还有四条不写就翻车：

1. **方法名要同时匹配混淆名与官方名**：
   ```java
   Set.of("getHealth", "m_21223_")
   ```
   dev 环境与生产环境名字不同，只匹配一个必然在其中一端**静默失效**。
2. **找不到目标方法就放弃，别返回坏字节码**：
   ```java
   if (!found[0]) { LOGGER.error(...); return null; }   // 返回 null = 不改写，游戏照常启动
   ```
   没真插桩却返回 `writer.toByteArray()`，等于把未验证的字节码丢回 JVM。
3. **安装完要校验「真的改到了」再置 `installed`**：
   ```java
   if (!t.transformedHealth || !t.transformedMaxHealth) throw new IllegalStateException(...);
   installed = true;
   ```
   否则 `installed = true` 但实际没生效，后续再也不会重试。
4. **任何一步失败都要 `removeTransformer` 回滚**，并把 `installed` 留在 `false` 允许下次重试。

两条环境前提，缺一条直接放弃（不要硬来）：

```java
instrumentation.isRetransformClassesSupported()
 && instrumentation.isModifiableClass(Boss.class)
 && instrumentation.isModifiableClass(LivingEntity.class)
```

改 `LivingEntity` 这种**全游戏共享的基类**风险最高：插桩必须带
`instanceof IAuthoritativeHealth` 守卫，非目标实体原样走原逻辑，否则**所有生物的血量都会变**。

### 14.26 改写血量：三层守卫 + 可变载体 + 延迟聚合队列

想在 `setHealth` 处拦截「女仆掉血」，会立刻撞上三个问题：
① 自己的写血被自己拦（无限递归）② 回血/换维度/NBT 加载也走 `setHealth`，被当成掉血
③ 一次 tick 内多次扣血会重复触发死亡判定。实测 `utils/` 下用几个小类分别解决。

**① 重入守卫（`MaidHealthWriteGuard`）**

```java
private static final ThreadLocal<Integer> BYPASS_DEPTH = ThreadLocal.withInitial(() -> 0);

public static void runBypassing(Runnable action) {
    BYPASS_DEPTH.set(BYPASS_DEPTH.get() + 1);
    try { action.run(); }
    finally {
        int d = BYPASS_DEPTH.get() - 1;
        if (d <= 0) BYPASS_DEPTH.remove(); else BYPASS_DEPTH.set(d);
    }
}
```

用 `ThreadLocal` 而非 boolean 字段：多实体/多线程并发时字段会被别的线程误清。
**归零时必须 `remove()`**，否则线程复用会残留「永久 bypass」。
用 `Integer` 计数而非 boolean：嵌套调用要能正确还原。

**② 伤害真伪校验（`isCommonHurt`）**

```java
List<CombatEntry> entries = ((CombatTrackerMixin) entity.getCombatTracker()).getEntries();  // @Accessor 暴露
return entries.isEmpty() ? false
     : Math.abs(entries.get(entries.size() - 1).getDamage() - (currentHealth - requestedHealth)) <= 0.1F;
```

`setHealth(newHealth)` 本身无法告诉你「为什么掉血」，但 `CombatTracker` 最后一条记录带着
「官方认定的伤害值」。**用「官方伤害值 vs 本次血量差」的一致性（容差 0.1）反推**：
一致 = 真伤害；不一致 = 回血/传送/加载/命令，直接 `block()`。

**③ 可变载体 + 结果 record（`DataItem` / `MaidHealthChange`）**

```java
public class DataItem { EntityMaid maid; float amount; boolean isCanceled; }   // 处理器链逐级改同一对象

public record MaidHealthChange(boolean writeHealth, float health) {            // 管线只产出「结论」
    public static MaidHealthChange block()      { return new MaidHealthChange(false, 0f); }
    public static MaidHealthChange write(float h){ return new MaidHealthChange(true, h); }
}
```

处理器链**不返回新对象、不直接写血**，只改 `DataItem`；管线最后返回 record，由 Mixin 决定是否真调 `setHealth`。
→ 管线可单测、可嵌套、可叠加多个 handler（实测顺序：残血饰品 → 真伪校验 → 魂书 → bauble 两张表）。
（反例：该模组另有从 oshi 库借来的 `Pair<Boolean,Float>` 做双返回，语义远不如 record 清晰。）

**④ 友伤保护用「先记地板、事后回滚」（`FriendlyDamageHealthGuard`）**

```java
onDamageAttempt(target, source)  → friendly 且同帧未记录时 push 一个 DamageFrame（含 healthFloor / absorptionFloor）
restoreIfNeeded(target)          → 若当前血量 < 地板，setHealth(max(当前, 地板)) 并 restoreCount++
```

四个必要细节：

- `ThreadLocal<Deque<DamageFrame>>`：伤害可嵌套（A 打 B、B 反弹给 A），用单变量会互相覆盖。
- `alreadyCaptured` 判重：同帧嵌套调用时**第二次看到的血量已经被打掉**，
  若再记成地板就永远恢复不回来。
- `RESTORE_DEPTH` 再套一层重入守卫：`setHealth` 自身会再次触发 `restoreIfNeeded`。
- 用 `getGameTime()` 校验 entry 属于同一 tick，过期条目直接丢弃。

**⑤ 真伤走「延迟队列 + 按实体聚合」（`TrueDamageUtil`）**

```java
private static final Queue<TrueDamageRequest> QUEUE = new ConcurrentLinkedQueue<>();
private static final int MAX_QUEUED_DAMAGE_PER_TICK = 2048;

dealTrueDamage(target, dmg, attacker) → QUEUE.offer(new TrueDamageRequest(target, dmg, attacker));  // 只入队，不扣血
processQueuedTrueDamage()            → 按 entity.getId() 聚合成 AggregatedTrueDamage，再逐目标扣一次
```

为什么不能立即扣血：`setHealth` 内联执行会与护甲/无敌帧/`hurt()` 递归冲突，
同一 tick 多次扣血还会重复触发 `LivingDeathEvent`。**聚合成一次是唯一稳妥解**。

必备配套：

- `WeakReference` 持有 target/attacker，队列不阻止 GC，实体已卸载也能安全丢弃。
- `MAX_QUEUED_DAMAGE_PER_TICK` 上限 + 超限 `warn`：一次 AOE 命中上千目标不会卡死。
- `canNotBeApllied(target)` + `combatAlive(target)` 双重校验，已移除/已死的直接丢。
- `ITrueDamageRedirect` 接口让目标自己接管真伤（`maidspell$onTrueDamageQueued` / `maidspell$redirectTrueDamage`），
  Boss 类可实现它把真伤转到「权威血量」上。
- `applyingQueuedDamage` 用普通静态布尔即可 —— 队列只在服务端主线程处理，不需要 `ThreadLocal`。


> **下半部见 [14e2-authoritative-health.md](14e2-authoritative-health.md) §14.49**：当第三方模组**绕过你的伤害管线**
> 直接写 `entityData` 的 `HEALTH` 时，闸门和 ASM 补丁都会失效——此时要做的是「权威值 + getter 插桩 + 归因栈 + 镜像同步」，
> 以及最后的 L3 自挂 agent（含 6 条放弃条件）。写「锁血 / 不死 / 阶段血量」类效果前，先确认走哪条路。