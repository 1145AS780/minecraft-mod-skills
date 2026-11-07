# 实体生命周期：归属解析、硬保护、状态归零、区块加载

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.27 跨模组「归属解析」：反射软依赖 + owner 链上溯 + 三层缓存

同时兼容 Iron's / Ars / Goety / SlashBlade / Wizardry 五个模组的「谁是谁的人」，
实测 `MaidSpellAllyResolver` 的做法是**一个 import 都不写**：

```java
private static final String IRONS_MAGIC_SUMMON  = "io.redspace.ironsspellbooks.entity.mobs.MagicSummon";
private static final String ARS_SUMMON          = "com.hollingsworth.arsnouveau.api.entity.ISummon";
private static final String GOETY_OWNED         = "com.Polarice3.Goety.api.entities.IOwned";
private static final String SLASHBLADE_SHOOTABLE= "mods.flammpfeil.slashblade.entity.IShootable";
private static final String WIZARDRY_SERVICES   = "com.binaris.wizardry.core.platform.Services";
```

全部靠**类名字符串 + 反射**定位：编译期零依赖，任一目标模组缺失也不影响加载
（对照 §14.23 的「第三方饰品用字符串 ID 列表」，同一套思想在两类资源上都成立）。

**统一抽象 `getDirectOwner(entity)` 覆盖 7 种「归属」语义**：

| 来源 | 语义 |
| --- | --- |
| `OwnableEntity#getOwner` | 原版可驯服生物 |
| `Projectile#getOwner` | 原版弹射物 |
| Iron's `MagicSummon#getOwner` | 法术召唤物 |
| Ars `ISummon#getOwner` | 召唤物 |
| Goety `IOwned#getTrueOwner` | 仆从（注意是 `TrueOwner`，不是 `Owner`） |
| SlashBlade `IShootable#getShooter` | 拔刀剑弹射物（语义是「射击者」不是「主人」） |
| Wizardry `Services.OBJECT_DATA` 静态字段 | 归属 API 藏在静态字段里的对象上 |

有了这一个函数，上层就不用关心对方是哪个模组。

**三层缓存，缺一层就掉帧**：

```java
Map<String, Optional<Class<?>>>            OPTIONAL_TYPES;      // 类查找结果（含「找不到」）
Map<MethodKey, Optional<Method>>           METHODS;             // 方法查找结果（含「找不到」）
Map<Class<?>, Boolean>                     OWNER_CAPABLE_CACHE; // 该类是否「可能有 owner」
```

**失败结果必须也缓存成 `Optional.empty()`**：`areFriendly` 每次伤害/索敌都会被调，
每帧 `Class.forName` / `getMethod` 是直接的帧率杀手。

**owner 链上溯必须有双保险**：

```java
private static final int OWNER_TRACE_LIMIT = 8;
for (int depth = 0; depth < 8 && current != null && visited.add(current.getUUID()); depth++) { ... }
```

`depth` 限层 + `visited` 防环**两个都要**：只限层会漏掉「深度没超但已绕成环」，
只防环在超长链上会退化成 O(n²)。

**友军判定顺序（每一步都不能省）**：

```java
① !couldHaveOwner(first) && !couldHaveOwner(second) → false     // 性能前置，快速淘汰普通生物
② hasExplicitTeamAlliance(first, second)             → true     // 原版队伍/结盟优先
③ 收集双方 affinity 集合（自身 + 整条 owner 链）
④ 两集合有交集 → friendly；否则 false
```

`first == second` 单独判为友好（自己打自己）；`first != second` 且任一集合为空 → 不友好。

**`isFriendlyDamage(target, causing, direct)` 的判据**：

```java
if (causing instanceof Player || direct instanceof Player) return false;   // 玩家永远可以打
return areFriendly(target, causing)
    || areFriendly(target, direct)
    || resolveResponsibleEntity(direct).map(o -> areFriendly(target, o)).orElse(false);
```

直接来源是玩家 → 一律不算友伤；否则三层都查一遍（再次印证 §14.24 的「穿透到责任实体」）。

**`maidOwningPlayer(entity)` 的细节**：沿链走，**遇到 Player 立刻返回；遇到 maid 只记录不返回**
（因为 maid 的 `getOwnerUUID()` 才是玩家），链走完再用 `getOwnerUUID` → `level.getPlayerByUUID` 反查。
直接返回「链上第一个 Player」在「玩家 → 女仆 → 女仆的召唤物」这种链上会拿到错误结果。

### 14.28 实体生命周期保护：白名单原因 + 堆栈回溯 + 恢复状态机

女仆 / 持久 Boss 会被各种模组「顺手删掉」：区块卸载、刷怪上限、`/kill`、捕捉、转换、传送。
实测是「两层防护 + 一个纯函数恢复策略」。

**① 拦截 `setRemoved` 用「白名单原因」，不用黑名单**

```java
public static boolean shouldBlockRemoval(Entity entity, RemovalReason reason) {
    if (!(entity instanceof IPersistentEncounterEntity p) || !p.maidspell$shouldProtectLifecycle())
        return AnchorCoreProtection.shouldBlockSetRemoved(entity, reason);          // 非持久实体走另一套
    return BossLifecycleAccess.canRemove(entity, reason) ? false
         : reason != RemovalReason.UNLOADED_TO_CHUNK && reason != RemovalReason.UNLOADED_WITH_PLAYER;
}
```

不是「拦 `DISCARDED`」，而是「**只放行这两个合法卸载原因**」。
白名单的好处：Minecraft 以后新增 `RemovalReason` 时默认被拦，不会因为忘了补黑名单而失效。

三个「防变形」入口复用同一判定：

```java
shouldBlockCapture(entity)      // 防止被刷怪蛋/捕捉罐装走
shouldBlockConversion(entity)   // 直接复用 capture 判定（转换 = 换个实体继续存在）
conflictsWithLoadedEncounter()  // 用 encounterId 在 level.getEntities() 里查重，防存档/传送后出现双份 Boss
```

**② 删除请求要能定位「谁在删」——堆栈回溯**

```java
if (!isForcingProtectionCheck() && AnchorCoreBauble.findIllegalCaller() == null) return false;
```

不是无条件拦截，而是**回溯调用栈找出「非法调用者」**：能识别出自己的合法删除路径就放行，
识别不出才拦。配合 `ThreadLocal<Boolean> ALLOW_HARD_REMOVAL` 做自证（同 §14.26 的重入守卫思想）。

**③ 服务端拦住了，客户端必须同步「别删」**

服务端 cancel 掉 `setRemoved` 后，客户端仍会按旧数据包移除实体 → **玩家看到女仆凭空消失**。
实测用 `MaidClientRemovalGuardMessage` 反向通知客户端，并有
`CLIENT_RESTORE_RESEND_TICKS = 10` 的重发兜底（客户端可能因卡顿漏收一次）。
**凡是在服务端 cancel 掉「同步类」操作，都要单独补一条反向同步。**

**④ 日志必须限频**

```java
PERIODIC_CHECK_INTERVAL_TICKS = 20;   // 定期自检
WARN_INTERVAL_TICKS = 100;            // 同一实体最多 5 秒一条警告
Map<UUID, Long> LAST_WARN_TICK;       // 按实体限流
```

一个每 tick 都失败的防护会瞬间刷爆日志并拖垮服务器。**「被拦住的异常」一定要按实体限频。**

**⑤ 恢复策略写成纯函数状态机（`AnchorRestorePolicy`）**

```java
static RestoreStep forRestore(boolean chunkLoaded, boolean storageLoaded, boolean present, boolean valid) {
    if (!chunkLoaded)   return new RestoreStep(WAITING_CHUNK,    WAIT);
    if (!storageLoaded) return new RestoreStep(WAITING_ENTITIES, WAIT);
    return new RestoreStep(WAITING_ENTITIES, present && valid ? COMMIT : DISCARD);
}
```

输入 4 个布尔，输出 `(phase, action)` 两个枚举。把「区块没加载 → 等 / 实体存储没加载 → 等 /
加载完但实体不存在或不合法 → 丢弃 / 一切正常 → 提交」四条规则从 if-else 泥潭里提炼出来，
可单测、可打印、可复用于「跨维度恢复」与「登录恢复」。

**这里有个最经典的坑**：

```java
forEntity(storageLoaded, present, valid):
    if (!storageLoaded) return RETRY;                  // 读不到 ≠ 不存在
    return present && valid ? CONTINUE : DISCARD;
```

「**暂时读不到**」和「**确实不存在**」必须分成两个分支。
把「查不到」当成「不存在」直接 `DISCARD`，就是「玩家重登后女仆永久丢失」的标准成因。

### 14.29 让实体「彻底停下」：12 处状态变更，一个都不能漏

女仆 / 生物要「立刻静止」，调一个 `navigation.stop()` 是**远远不够的**。实测 `utils/MaidMovementHelper.java`
（全文 30 行，方法 `stopAllMovement` 占 L12–L29），方法体内共 **22 处方法调用**，其中
**12 处是状态写入**（下表的 ①–⑫），另 **10 处是读取**（`m_21573_`、`getNavigationManager`、`m_6274_`×2、
`m_20184_`、`m_21569_`、`m_21566_`、`m_20185_`、`m_20186_`、`m_20189_`）。本节标题说的「12 处」就是这 12 处写入，
口径写清楚以免「说 12 个、数出 22 个」的口径打架：

```text
stopAllMovement(女仆) 的 12 处状态写入（按原方法顺序编号，行为描述而非源码）：
① 原版导航 停
② 女仆模组自己的导航层 resetNavigation
③ 记忆系统 擦除 行走目标
④ 记忆系统 擦除 注视目标
⑤ setJumping(false)
⑥ setXxa(0)
⑦ setYya(0)
⑧ setZza(0)
⑨ setSpeed(0)
⑩ setDeltaMovement(0, 保留当前 Y 分量, 0)
⑪ 取到跳跃控制后把 jump 置 false（通过 accessor 写只读字段）
⑫ 位置同步 setPos(当前 X, 当前 Y, 当前 Z, yaw = 0)
```

调用点计数（按「`方法名(`」出现次数统计，不含 `new` 与字段访问）：L13 2 处、L14 2 处、L15 2 处、L16 2 处、
L17–L23 各 1 处（7 处）、L24 1 处、L25 1 处、L28 5 处 → 合计 **22**。其中**写入 12**、**读取 10**。

### 14.29.1 每个 `m_xxx_` 到底是谁：三方交叉实证表

映射不是靠「看着像」翻译的。做法是三方交叉，任一方都不单独作结论：

1. **SRG 侧**：`joined-1.20.1-20230612.114412-srg.jar` 里取该类，`javap -p` 导出成员**类文件顺序**；
2. **obf 侧**：`client.jar` 里取对应的混淆类（`Mob→bgb`、`LivingEntity→bfz`、`Entity→bfj`、`Brain→bha`、
   `PathNavigation→bpj`、`MoveControl→bly`），同样导出**类文件顺序**；重映射不重排成员，所以两侧下标一一对应；
3. **官方名侧**：`client_mappings.txt`（ProGuard）里按「obf 名 + 参数类型」反查官方人类名。

前提校验（不把「位置对齐」当普适定律）：6 个类的方法数逐一相等 ——
`Mob 136=136`、`LivingEntity 303=303`、`Entity 437=437`、`Brain 53=53`、`PathNavigation 43=43`、`MoveControl 11=11`。
另取一个本文件没用的方法做对照：`Mob` 第 10 位 `m_21563_` → obf `E()` → 官方 `getLookControl()`，对齐成立。

| 序号 | SRG 调用 | 所属类 | 官方人类名 | 定位依据 |
| --- | --- | --- | --- | --- |
| ① | `m_21573_` | `Mob` | `getNavigation()` | 第 13 位 → obf `J()` → `getNavigation()`。注意 `Mob` 里另有 `j()` → `getTarget()`，只差大小写，按 obf 名精确过滤时不会混 |
| ① | `m_26573_` | `PathNavigation` | `stop()` | 第 28 位 → obf `n()` → `stop()`。同组 8 个无参 void 的修饰符序列（public,public,public,protected,private,private,**public**,protected）两侧完全一致；obf `g/i/c/k/e/f/n/L_` 依次反查为 `resetMaxVisitedNodesMultiplier / recomputePath / tick / followThePath / timeoutPath / resetStuckTimeout / stop / trimPath` |
| ③④ | `m_6274_` | `LivingEntity` | `getBrain()` | 第 1 位 → obf `dK()` → `getBrain()`。本类返回 `Brain` 系的方法只有 3 个（第 1/2/3 位：`public m_6274_()`、`protected m_5490_()` 返回 `Brain$Provider`、`protected m_8075_(Dynamic)`），`m_6274_` 是唯一 public 无参版 |
| ③④ | `m_21936_` | `Brain` | `eraseMemory(MemoryModuleType)` | 第 7 位 → obf `b(bpb)` → `eraseMemory(...)` |
| ③ | `f_26370_` | `MemoryModuleType` | `WALK_TARGET` | 字段第 12 位 → obf `m`；SRG 泛型为 `MemoryModuleType<WalkTarget>`，候选 `WALK_TARGET`(WalkTarget) / `PLAY_DEAD_TICKS`(Integer) 中唯一匹配 |
| ④ | `f_26371_` | `MemoryModuleType` | `LOOK_TARGET` | 字段第 13 位 → obf `n`；SRG 泛型为 `MemoryModuleType<PositionTracker>`，候选 `LOOK_TARGET`(PositionTracker) / `TEMPTING_PLAYER`(Player) 中唯一匹配 |
| ⑤ | `m_6862_` | `LivingEntity` | `setJumping(boolean)` | 第 212 位 → obf `r(boolean)` → `setJumping(boolean)` |
| ⑥ | `m_21570_` | `Mob` | `setXxa(float)` | 第 42 位 → obf `B(float)` → `setXxa(float)` |
| ⑦ | `m_21567_` | `Mob` | `setYya(float)` | 第 41 位 → obf `A(float)` → `setYya(float)` |
| ⑧ | `m_21564_` | `Mob` | `setZza(float)` | 第 40 位 → obf `z(float)` → `setZza(float)` |
| ⑨ | `m_7910_` | `LivingEntity` / `Mob` | `setSpeed(float)` | `LivingEntity` 第 186 位 → obf `w(float)` → `setSpeed(float)`；`Mob` 第 43 位同样 → obf `w(float)` → `setSpeed(float)`（子类覆写，SRG 名一致） |
| ⑩ | `m_20184_` | `Entity` | `getDeltaMovement()` | 第 380 位 → obf `dl()` → `getDeltaMovement()` |
| ⑩ | `m_20334_` | `Entity` | `setDeltaMovement(double,double,double)` | 第 383 位 → obf `o(double,double,double)` → `setDeltaMovement(double,double,double)` |
| ⑩ | `f_82480_` | `Vec3` | `y` | 三个 `final double` 字段位 0/1/2 → obf `c`/`d`/`e` → ProGuard `x→c`、`y→d`、`z→e` |
| ⑫ | `m_21566_` | `Mob` | `getMoveControl()` | 第 11 位 → obf `G()` → `getMoveControl()` |
| ⑫ | `m_6849_` | `MoveControl` | `setWantedPosition(double,double,double,double)` | 第 3 位 → obf `a(double,double,double,double)` → `setWantedPosition(...)`；本类唯一四 double 入参方法 |
| ⑫ | `m_20185_` | `Entity` | `getX()` | 第 385 位 → obf `dn()` → `getX()` |
| ⑫ | `m_20186_` | `Entity` | `getY()` | 第 389 位 → obf `dp()` → `getY()` |
| ⑫ | `m_20189_` | `Entity` | `getZ()` | 第 394 位 → obf `dt()` → `getZ()`；`getZ` 是 `final double` 且紧跟在 `final int getBlockZ` 之后，不与 `getZ(double)` 混淆 |
| ⑪ | `m_21569_` | `Mob` | `getJumpControl()` | 第 12 位 → obf `I()` → `getJumpControl()` |

注意「同名不同义」的陷阱：`m_7910_` 在 `LivingEntity` 和 `Mob` 上都存在（后者覆写前者），两处都指向
`setSpeed(float)`；而 `m_7638_` 在 `PathNavigation` 上是 `tick()`——不要拿「SRG 名字」当跨类唯一标识。

- `xxa` / `yya` / `zza` 在 vanilla 是 **public 字段**（`LivingEntity.java` L198–L200，实测声明为
  `public float xxa; public float yya; public float zza;`），同时 `Mob` 也提供了 `setXxa/setYya/setZza` setter，
  所以模板里「直接赋值」和「调 setter」两条路都合法。

**为什么必须全清**：

| 漏掉哪一项 | 症状 |
| --- | --- |
| `WALK_TARGET` 记忆（③） | 当 tick 看起来停了，下一 tick goal 立刻重新导航 → 「抽搐式原地走」 |
| `navigationManager`（②，女仆模组层） | 原版 `navigation.stop()` 停不到它，仍然自己走 |
| 输入轴 `xxa`/`yya`/`zza` + `setSpeed`（⑥⑦⑧⑨） | 客户端按键状态与内部速度还在推动实体 |
| `setDeltaMovement` 只清水平（⑩） | 若把 y 也清零，**正在下落/飞行的实体会冻在半空** |
| `JumpControl`（⑪） | 没有公开 API，只能用 `@Accessor` mixin 反射进 `JumpControl` 把 `jump` 置 false |
| `MoveControl.setWantedPosition(当前位置, 0)`（⑫） | 否则 move control 仍朝旧目标推进 |

**最关键的一条**：`setDeltaMovement(0, d.y, 0)` **只清水平分量**。
顺手写成 `Vec3.ZERO` 是很常见的错误——重力/浮空实体会被「钉」在空中，看起来像卡死。

**推广判据**：任何「强制静止/强制传送前」的清理，都要按「原版导航 → 模组导航 → AI 记忆 →
输入轴 → 速度 → 位移向量 → 跳跃控制 → move control」这个清单逐项过一遍。
少一项就表现为「偶发不生效」，而且**极难复现**（取决于当时哪个状态位恰好非零）。

### 14.30 区块加载（ForgeChunkManager）：异步纪律 + Ticket 分级 + epoch 代际

`ChunkLoadingManager` 是本项目最复杂的一个类（20+ 张状态表）。它的复杂度几乎全部来自
**「异步发起 → 延迟执行 → 服务器可能已换实例」** 这条链，四条纪律值得直接照抄。

**① `executeOnServer`：主线程直接跑，别无条件排队**

```java
private static void executeOnServer(MinecraftServer server, Runnable action) {
    if (server.isSameThread()) action.run();     // 已在主线程 → 立即执行
    else server.execute(action);                 // 异步线程 → 排队到下一 tick
}
```

无条件 `server.execute()` 会把主线程的调用推迟一整 tick：
「设了 ticket 但当前 tick 还没生效」这类时序 bug 就从这里来。

**② 延迟执行时必须把发起时的假设全部重新验证一遍**

```java
executeOnServer(server, () -> {
    if (isActiveSession(server)
        && !maid.isRemoved()
        && maid.isAlive()
        && maid.level() == serverLevel
        && server.getLevel(serverLevel.dimension()) == serverLevel
        && maid.chunkPosition().equals(chunkKey.chunkPos())     // 位置没变
        && BaubleStateManager.hasBauble(maid, ANCHOR_CORE)) {   // 饰品还在
        performChunkOperationOnServer(server, maidId, chunkKey, true);
    }
});
```

发起请求时女仆在 A 区块，真正执行时可能已经走到 B 区块、已被收回饰品、甚至已跨维度。
**七个条件全过才执行，任一不满足就静默丢弃**——这是异步编程里唯一可靠的写法。

**③ `SERVER_EPOCH` 代际号：换服务器实例后旧任务必须作废**

```java
private static final AtomicLong SERVER_EPOCH = new AtomicLong();
private static volatile MinecraftServer activeServer;
private static volatile boolean acceptingRequests;

private static boolean isActiveSession(MinecraftServer server) {
    return server != null && activeServer == server && acceptingRequests;   // 三重校验
}
```

单机反复进出存档 / 集成服务器重载时，`MinecraftServer` 会换实例，
异步回调里捕获的旧 `server` 引用指向已停止的世界。所有待处理记录都带 `epoch`，
回调先比 `epoch == SERVER_EPOCH.get()` 再干活。

**④ 每个异步阶段一张表，每张表都带「token + 重试 + 截止」**

```java
record RestoreRequest(long epoch, MinecraftServer server, ServerLevel level,
                      UUID token, int attemptsRemaining, long currentTick, long deadline, Phase phase) { }
```

`requestTokens` 单独存 token，用 `compute(key, (k, old) -> matchesEpochServerToken(old) ? old : newReq)`
**只在「同一个请求」时才替换**——旧请求的完成回调因此无法覆盖新请求的结果。
配套常量一眼看出全部节奏：

```java
CHECK_INTERVAL_TICKS              = 20;    // 自检
RESTORE_RETRY_INTERVAL_TICKS      = 20;    // 重试间隔
RESTORE_RETRY_ATTEMPTS            = 10;    // 重试上限
RESTORE_OBSERVATION_TIMEOUT_TICKS = 600;   // 观察超时
LEVEL_REQUEST_TIMEOUT_TICKS       = 600;   // 维度请求超时
RECOVERY_RETRY_INTERVAL_TICKS     = 600;   // 兜底恢复
```

**⑤ Ticket 分级：短期用 `TicketType`，长期才用 `forceChunk`**

```java
private static final TicketType<UUID> PROVISIONAL_TICKET_TYPE = TicketType.create(
    "maidspell_anchor_restore", (a, b) -> a.compareTo(b), 100);      // 100 tick 自动过期
private static final int PROVISIONAL_TICKET_DISTANCE = 2;
private static final boolean PROVISIONAL_TICKET_FORCE_TICKS = false;
private static final int PROVISIONAL_TICKET_RENEW_INTERVAL_TICKS = 20;   // 必须续期
```

`TicketType.create` **必须给 Comparator**（同类型 ticket 靠它去重合并）。
临时占位一律走 ticket：**自动过期，不会因为漏释放而永久加载区块**；
`ForgeChunkManager.forceChunk` 只用于正式加载，且必须成对释放（配套 `formalReleaseRetries`
和 `staleForcedTicketReleases` 兜底「漏释放」）。timeout=100 就必须每 20 tick 续期，否则会掉。

**⑥ 异步结果一律回主线程处理，且每 tick 限量**

```java
Queue<CompletedLevelRequest> completedLevelRequests = new ConcurrentLinkedQueue<>();  // 异步只 offer
onServerTick(Phase.END) → processCompletedLevelRequests(server);                       // 主线程 poll

MAX_LEVEL_COMPLETIONS_PER_TICK     = 8;     // 每 tick 最多处理 8 个
MAX_LEVEL_COMPLETION_SCANS_PER_TICK = 128;  // 每 tick 最多扫描 128 个
```

**异步线程里绝不直接改世界状态**；一次上千女仆同时加载会把服务器卡死，所以每 tick 都要限量。

**⑦ 全部收口到 `ServerTickEvent.END` 的一个入口**

```java
if (event.phase == Phase.END && isActiveSession(server)) {
    renewProvisionalTickets(server);      processProvisionalReleaseRetries(server);
    processTeleportPreloads(server);      processFormalReleaseRetries(server);
    processStaleForcedTicketReleases(server); processCompletedLevelRequests(server);
    processPendingLevelRequestTimeouts(server); processRestoreRequests(server);
    processRecoveryRetries(server);
    if (server.getTickCount() % 20 == 0) validateActiveChunkAnchors(server);
}
```

九个阶段各有独立方法、独立状态表，由一个 tick 钩子串起来。
**好处**：每个阶段可单独加日志/单独开关，出问题能定位到具体阶段，而不是一坨 800 行 tick 逻辑。