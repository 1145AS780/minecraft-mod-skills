# Boss 与 AI：契约前缀、候选池冷却、延迟任务链、第三方实体复用

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.31 Boss 实体：`maidspell$` 契约前缀 + 枚举状态机 + 阶段内一次性标志

3930 行的 Boss 类里，原版覆写（`m_xxx_`）与自有扩展点混在一起。作者给**所有自有扩展点**加了统一前缀：

```java
maidspell$authoritativeHealth()          maidspell$authoritativeMaxHealth()
maidspell$bossMaxHealth()                maidspell$setMaxHealth(float)
maidspell$encounterState()               maidspell$setEncounterState(state)
maidspell$isAdaptiveDamageActive()       maidspell$maxDamagePerHit(float)
maidspell$protectSyncedDataWrite(accessor, value)
```

三个好处：① 一眼分辨「哪些是我的、哪些是原版覆写」② 永不与第三方模组同名方法冲突
③ **ASM transformer 用固定字符串定位**（`maidspell$authoritativeHealth`），
前缀让这个方法成为**显式契约**——改名等于破坏 ABI，改之前一定会犹豫。

**① 枚举状态机：迁移函数返回 `boolean`（是否真的变了）**

```java
private boolean maidspell$setEncounterState(WinefoxEncounterState state) {
    WinefoxEncounterState previous = this.maidspell$encounterState();
    if (previous == state) return false;        // 没变
    ...
    return true;
}
```

调用方靠返回值做幂等：`if (boss.maidspell$beginEncounter(COMBAT)) { 只执行一次的进场逻辑 }`。
**状态迁移函数返回 `boolean` 是幂等入口的标准写法**——比调用方自己写 `if (state != X)` 可靠。

状态用 `Byte` 同步（`ENCOUNTER_STATE` / `REWARD_STATE`），配一个 `ENCOUNTER_SERIAL: Integer`
在每次迁移时自增：客户端靠 serial 判断「这是一次新的遭遇」，而不是「同一状态又刷了一遍」。

> **陷阱**：用 `ordinal` 存枚举 → **枚举项顺序永久冻结**，新项只能追加在末尾。
> 一旦重排，旧存档的 `Byte` 会解出错误的阶段。

**② 大数值用 `String` 同步，避免 float 精度丢失**

```java
public static final EntityDataAccessor<String> BOSS_HEALTH     = SynchedEntityData.defineId(..., STRING);
static       final EntityDataAccessor<String> BOSS_MAX_HEALTH = SynchedEntityData.defineId(..., STRING);
```

Boss 血量可能到几十万，`float` 只有 24 位有效位（约 7 位十进制），血条百分比与精确血量都会抖。
**超出 float 精确范围的值一律用 `String` 传**，客户端再解析。

**③ 「阶段内一次性」标志，阶段切换时统一 reset**

```java
private boolean summonSwordsUsedThisPhase;
private boolean palmBlackHoleTriggeredThisPhase;
```

比「给大招设冷却」更可控：**每阶段最多放一次**，语义明确，阶段切换时一并复位，
不需要记住「上次用是什么时候」。

**④ 卡住的施法标志必须有兜底清理**

```java
this.maidspell$clearStaleCastingFlag("immobile");
this.maidspell$clearStaleCastingFlag("cancel");
```

施法标志可能因异常路径（被中断、实体卸载、客户端断线）没清掉，实体就永远「僵住不动」。
做法是每 tick 比对「实际状态」与「标志」，不一致就清，**并把 reason 传进去**——
日志里能直接定位是哪条路径漏了清理。

### 14.32 Boss 战斗 AI：候选池查表 + 分级冷却 + 错峰判定

**① 技能候选池按「阶段 × 距离」二维查表，不写 if-else**

```java
private static final List<WinefoxBossSpellAction> PHASE_ONE_SPELLS       = List.of(...);
private static final List<WinefoxBossSpellAction> PHASE_TWO_CLOSE_SPELLS = List.of(...);
private static final List<WinefoxBossSpellAction> PHASE_TWO_FAR_SPELLS   = List.of(...);
private static final double PHASE_TWO_STANDOFF_DISTANCE = 2.0;      // 远近分界
```

选技能 = 「取当前阶段/距离对应的 List → 过滤冷却中的 → 加权随机」。
新增技能只改列表，不动决策逻辑。**这是数据驱动 AI 最小可行的形态。**

**② 冷却表用 `EnumMap`，第三方技能用 `Map<String,Integer>`**

```java
private final EnumMap<WinefoxBossSpellAction, Integer> spellCooldowns = new EnumMap<>(WinefoxBossSpellAction.class);
private final Map<String, Integer> customSpellCooldowns = new HashMap<>();   // 第三方法术按 ID
```

`EnumMap` 内部是数组索引，比 `HashMap` 快且零装箱；枚举作 key 一律用它。
软依赖技能只能用字符串 ID，单独一张表（同 §14.27 的字符串软依赖）。

**③ 阶段用「冷却缩放系数」，不维护两套技能表**

```java
PHASE_ONE_COOLDOWN_SCALE = 0.2;    // 一阶段：几乎不放技能（教学阶段）
PHASE_TWO_COOLDOWN_SCALE = 0.5;    // 二阶段：冷却砍半
```

`实际冷却 = 基础冷却 × scale`。**改难度只改一个系数。**

**④ 每种周期性判定各自一个间隔常量，并错峰**

```java
SPELL_DECISION_INTERVAL             = 20;
ESCAPE_TELEPORT_CHECK_INTERVAL      = 200;
COUNTERSPELL_CHECK_INTERVAL         = 20;
SPEAR_CHECK_INTERVAL                = 400;
VOID_PHASE_CHECK_INTERVAL           = 200;
HEAL_CHECK_INTERVAL                 = 200;
COMPANION_BLACK_HOLE_CHECK_INTERVAL = 600;
```

不要「每 tick 把所有判定跑一遍」，也不要「所有判定共用一个计数器」。
**每个判定独立周期 + 独立相位偏移**，避免某一 tick 集中算完造成尖峰帧。

**⑤ 血线阶梯用「首个阈值 + 步长」**

```java
ABYSSAL_SHROUD_FIRST_HEALTH_THRESHOLD = 0.9;
ABYSSAL_SHROUD_HEALTH_THRESHOLD_STEP  = 0.1;    // 90% → 80% → 70% …
```

不要写 `0.9f / 0.8f / 0.7f` 一串魔数。**「首值 + 步长」既表达意图，又方便改密度。**

**⑥ 浮空 Boss 的近战判定必须带垂直容差**

```java
COMBAT_ALTITUDE_TOLERANCE          = 1.75;   // 与玩家保持的高度差
PHASE_TWO_MELEE_VERTICAL_TOLERANCE = 1.0;    // 近战垂直判定范围
```

只判水平距离 → 「看着贴脸打，其实一直没命中」。浮空/大型实体一律补垂直容差。

**⑦ 卡住检测用平方距离，避免开方**

```java
STUCK_TICKS_BEFORE_HOP = 20;
STUCK_MOVE_EPSILON_SQR = 0.0025;    // 0.05² —— 直接和 distanceToSqr 比
```

每 tick 记位置，20 tick 内位移平方 < 0.0025 判定卡住 → 跳一下（`HOP_VERTICAL_SPEED = 0.55`）。
**距离比较一律用 `distanceToSqr` + 平方常量**，不要调 `Math.sqrt`。

**⑧ 防风筝与施法打断**

```java
COMBAT_TELEPORT_DISTANCE             = 15.0;  // 玩家跑太远 → 瞬移追上
SPELLBREAKING_ECHO_STILL_TICKS       = 40;    // 原地不动 40 tick = 正在施法
SPELLBREAKING_ECHO_MOVE_DISTANCE_SQR = 1.0;
```

「不动 = 施法」是打断判定最简可靠的信号——比查询第三方法术状态稳得多
（第三方法术的内部状态通常拿不到，而位移是所有人都有的公开信息）。

### 14.45 轻量延迟任务链调度器（`SwordRingScheduler`）

需要「N tick 后执行某件事」，而且多次调用之间要**严格串行**（连招动画不能重叠）。Forge 没有现成工具，手写一个 74 行的调度器就够了。

```java
public final class SwordRingScheduler {
    private static final List<ScheduledTask> PENDING = new ArrayList<>();
    private static boolean registered, clockSynced;
    private static long serverTick;

    public static void schedule(ServerLevel level, int delayTicks, boolean chain, Runnable task) {
        MinecraftServer server = level.getServer();
        if (server == null) return;                       // ① 客户端/已卸载世界直接放弃
        ensureRegistered();                                // ② 懒注册事件总线
        if (!clockSynced) {                                // ③ 懒同步时钟起点
            serverTick = server.getTickCount();
            clockSynced = true;
        }
        long executeAt;
        if (chain && !PENDING.isEmpty()) {                 // ④ 链式：接在队尾之后
            executeAt = PENDING.get(PENDING.size() - 1).executeAt() + delayTicks;
        } else {
            executeAt = serverTick + delayTicks;           //    独立：从现在算
        }
        PENDING.add(new ScheduledTask(server, level, executeAt, task));
    }
}
```

**① 时钟用自增 `serverTick`，不要用 `level.getGameTime()`**

```java
@SubscribeEvent
public static void onServerTick(ServerTickEvent event) {
    if (event.phase != Phase.END) return;                 // 每 tick 只加一次
    serverTick++;
    while (!PENDING.isEmpty() && PENDING.get(0).executeAt() <= serverTick) {
        ScheduledTask s = PENDING.remove(0);
        if (s.server().isRunning() && s.level().getServer() == s.server()) {   // ⑤ 执行前双守卫
            s.task().run();
        }
    }
}
```

- **`level.getGameTime()` 不可靠**：每个维度的 gameTime 独立，且**维度没加载时 gameTime 不走**
  （`server.getTickCount()` 才是一直走的全局时钟）。用维度时间做延迟，跨维度/未加载维度会永远不触发。
- **`serverTick++` 放在 END 阶段**：START 阶段世界状态还在变，END 才是本 tick 的稳定状态（见 §14.44 ⑥）。
- **队首 `while` 弹出**：因为 `delayTicks >= 0` 且链式是在队尾累加，队列天然按 `executeAt` 有序，
  只需看队首。**不要每 tick 遍历整个列表**——那是 O(n) × 20/s。

**② 链式（`chain=true`）：接在队尾之后累加**

连招场景（剑环连续 3 段），三次 `schedule` 在同一 tick 内连续调用：

```java
schedule(level, 10, false, step1);   // t+10
schedule(level, 10, true,  step2);   // t+20  ← 接 step1 之后
schedule(level, 10, true,  step3);   // t+30
```

- **`chain` 依赖「队尾」而不是「最后一次自己的任务」**：实现简单，但要求**同一批链式任务在同一 tick 内全部 schedule 完**。
  如果 step2 是在 step1 的回调里才 schedule 的，此时 step1 已经从队列弹出，`PENDING` 为空 → 退化成 `serverTick + delay`，
  链条就断了（视觉上是「两段同时播」）。**跨 tick 的连招要用 `chain=false` 并自己算累计延迟**。

**③ 懒注册事件总线**

```java
private static void ensureRegistered() {
    if (!registered) { MinecraftForge.EVENT_BUS.register(SwordRingScheduler.class); registered = true; }
}
```

调度器可能整个游戏都没被用到（玩家没装对应模组）。**用 `@EventBusSubscriber` 会无条件注册**，
用懒注册就只在第一次 `schedule` 时才挂上去。代价是类里不能有 `@Mod.EventBusSubscriber` 注解（会和手动注册冲突，导致双份回调）。

**④ 执行前双守卫，防止「世界已没了还跑任务」**

```java
s.server().isRunning() && s.level().getServer() == s.server()
```

- `isRunning()`：服务器正在关闭时不再执行。
- `level.getServer() == server`：**世界已被卸载**（换存档、维度销毁）时 `level.getServer()` 返回 `null` 或别的 server，
  此时执行任务会 NPE 或改到错误的世界。

**⑤ `ServerStoppedEvent` 清空 + 重置时钟**

```java
@SubscribeEvent
public static void onServerStopped(ServerStoppedEvent event) {
    PENDING.clear();
    serverTick = 0L;
    clockSynced = false;
}
```

单人游戏「退出世界 → 进另一个世界」不会重启 JVM。**不清空的话，旧世界的任务会在新世界里执行**，
`clockSynced` 不复位则新世界的 `serverTick` 起点是旧世界的值，延迟全部错乱。

**⑥ `ArrayList` 而不是并发容器**

任务只在服务器主线程（tick）里增删，**不需要 `CopyOnWriteArrayList`**。
反过来，这里用 `CopyOnWriteArrayList` 会让每次 `remove(0)` 都复制整个数组，反而更慢。

### 14.46 复用第三方模组实体：继承基类 + 重写 Goal + 加权抽法术

Iron's Spellbooks 自带一批法术生物（精灵圣殿骑士、守护女巫、圣光构装体）。要加自己的变体，
**不要自己写实体**，继承它的基类，只改 AI 和属性。

**① 继承 `AbstractSpellMeleeMob` / 实现 `IMagicEntity`**

```java
public class ElfTemplarEntity extends AbstractSpellMeleeMob implements IMerchantWizard {
    public ElfTemplarEntity(EntityType<? extends ElfTemplarEntity> type, Level level) { super(type, level); }

    public static Builder createAttributes() {                    // 属性表用静态 Builder
        return Mob.createMobAttributes()
            .add(Attributes.MAX_HEALTH, 40.0)
            .add(Attributes.ATTACK_DAMAGE, 6.0)
            /* ... */;
    }
}
```

- **继承基类拿到全部法术能力**：`AbstractSpellMeleeMob` 已经实现了法术数据、施法动画、同步。
  自己写一个 `Monster` 再实现一遍，等于把 Iron's 的 3000 行重写一次。
- **属性用静态 `createAttributes()`**：在 `EntityAttributeCreationEvent` 里注册，
  **不要在构造函数里设属性**——构造期设的值会被 `finalizeSpawn` 覆盖，且客户端实体会拿到不一致的值。
- **软依赖边界**：这个类整体只在 Iron's 加载时注册（§14.2），类加载器不会碰到缺失的父类。

**② 交易型实体：自己维护交易状态，不要复用村民的**

```java
private static final int DAILY_TRADE_MAX_USES = 5;
private Player tradingPlayer;
private MerchantOffers offers;
private long lastRestockGameTime;
private int numberOfRestocksToday;
private long lastRestockCheckDayTime;
```

- 实现 `IMerchantWizard`（Iron's 的接口）而不是原版 `Merchant`：**接口只要求「有 offers / 有交易玩家」**，
  内部状态完全自己管。
- **每日限购要自己算**：`copyOfferWithDailyUseLimit(offer)` —— **复制一份 offer 再改 `maxUses`，
  不要改原始 offer 对象**。原始 `MerchantOffers` 是共享/缓存的，改它会污染所有同类实体。
- `lastRestockCheckDayTime` 与 `lastRestockGameTime` **两个时间戳都要存**：
  一个判「是否跨天」（重置次数），一个判「距上次补货多久」（防刷）。
  只存一个的话，玩家反复开关交易界面就能无限补货。

**③ 自定义 `AttackGoal`：继承 `WizardAttackGoal`，只改选法术逻辑**

```java
public class HolyConstructAttackGoal extends WizardAttackGoal {
    private static final float PREFERRED_COMBAT_RANGE     = 6.0F;
    private static final float PREFERRED_COMBAT_RANGE_SQR = 36.0F;   // ← 平方值也存一份
    private static final float TOO_CLOSE_RANGE            = 3.0F;
    private static final float TOO_CLOSE_RANGE_SQR        = 9.0F;
    private static final int CHARGE_REUSE_COOLDOWN_TICKS  = 1200;
    private static final int CHARGE_PRIORITY_BONUS        = 90;
}
```

- **距离常量同时存「值」和「平方值」**：`distanceToSqr` 是热路径（每 tick 多次），
  每次 `sqrt` 是浪费。**命名上明确标 `_SQR`，避免拿错**。
- **`TOO_CLOSE_RANGE` 与 `PREFERRED_COMBAT_RANGE` 形成距离带**：太近要后退/换近战法术，太远要靠近。
  只有一个「理想距离」的 AI 会在边界来回抖动。
- **继承 `WizardAttackGoal` 而不是 `Goal`**：父类已经处理了「施法期间不能移动」「施法打断」「冷却计时」，
  子类只需要 `castSelectedSpell()` 里决定放什么。

**④ 加权抽法术：bucket + 重复惩罚 + 特殊法术优先级加分**

```java
private int appendWeightedCategories(List<SpellBucket> buckets) { ... }   // 每类给一个权重
private int repeatPenalty(ArrayList<AbstractSpell> category, int penalty) { ... }  // 同类重复抽降权
private ArrayList<AbstractSpell> pickBucket(List<SpellBucket> buckets, int roll) { ... }  // 按权重落桶
```

- **分桶 + 权重**：直接给每个法术一个权重，配置会膨胀到几十项。分 3~5 个类别桶，每桶一个权重，
  **新增法术只加进桶里，不动权重表**。
- **`repeatPenalty`**：连续抽到同一个类别要降权，否则「加权随机」会退化成「一直放同一个法术」
  （概率上完全可能连抽 5 次同一个桶，玩家观感就是 AI 傻了）。
- **特殊法术用「独立冷却 + 优先级加分」而不是塞进权重**：大招（冲锋、橡木皮肤）需要「多久能再用一次」
  这种**状态**，纯权重表达不了。`lastChargeCastTick` + `CHARGE_REUSE_COOLDOWN_TICKS` 判可用，
  可用时给 `CHARGE_PRIORITY_BONUS = 90` 让它排到最前。
- **`NO_SPELL = SpellRegistry.none()` 作为哨兵**：Iron's 用空法术对象而不是 `null` 表示「这次不放」。
  自己的代码里也用同一套哨兵，避免 `null` 检查散落各处。

**⑤ NBT 必须覆盖所有自定义字段**

```java
@Override public void addAdditionalSaveData(CompoundTag tag) { super.addAdditionalSaveData(tag); /* 全部自定义字段 */ }
@Override public void readAdditionalSaveData(CompoundTag tag) { super.readAdditionalSaveData(tag); /* 全部还原 */ }
```

- **先调 `super` 再写自己的**，读的时候顺序无所谓但要一一对应。
- **漏一个字段的后果是「静默重置」**：例如忘了存 `numberOfRestocksToday`，玩家重进世界就能无限刷交易。
- 交易型实体还要在 `readAdditionalSaveData` 里**重建 `offers`**（`MerchantOffers` 不是自动反序列化的）。

### 14.50 4000 行 Boss 怎么拆：状态枚举 + 状态对象 + 守卫类 + 控制器

`MagicalWinefoxBossEntity` 单文件 **3930 行**，但 `winefox/` 包里另有 **23 个类**分担职责（该包共 24 个 java 文件）。
拆分逻辑是「**宿主只留契约与委托，所有可变状态都搬成独立对象**」——不是按行数切，是按**生命周期**切。

**① 宿主实体：只做 5 件事**

`MagicalWinefoxBossEntity` 里留下的只有：

| 职责 | 为什么必须在宿主 |
|---|---|
| `defineSynchedData` / `addAdditionalSaveData` / `readAdditionalSaveData` | 原版回调，只能写在实体类里 |
| `registerGoals` | 同上 |
| 对外暴露 `maidspell$*` 访问器（给 Mixin / 插桩 / 控制器调） | 插桩方法名必须是实体上的真实方法 |
| 事件分派（`tick` → 状态机推进 → 各 Controller） | 单一时间源 |
| 数据同步（`getEntityData().set(...)`） | 只有实体持有 `SynchedEntityData` |

**其余全部外置**：血量、法术、动作、对话、交易、BossBar、不可见追踪、奖励。

**② 状态 = 枚举，且转移表显式穷举**

```java
public enum WinefoxEncounterState {
    SEATED, CHALLENGE_START, COMBAT, DEFEATED, RETURNING;

    public boolean canTransitionTo(WinefoxEncounterState next) {
        if (this == next) return false;                       // 自转移一律非法
        return switch (this) {
            case SEATED          -> next == CHALLENGE_START || next == COMBAT;
            case CHALLENGE_START -> next == COMBAT || next == SEATED || next == RETURNING;
            case COMBAT          -> next == DEFEATED || next == RETURNING;
            case DEFEATED        -> next == RETURNING;
            case RETURNING       -> next == SEATED;
        };
    }

    public static WinefoxEncounterState fromId(int id) {
        return id >= 0 && id < values().length ? values()[id] : SEATED;   // 越界回默认
    }
}
```

- **`switch` 表达式穷举、不写 `default`**：以后加一个状态，javac 直接编译失败，逼你补转移规则。
  写 `default -> true` 等于把「非法转移」放进来，战斗状态会卡死。
- **`fromId` 越界回默认而不是 `values()[id]`**：网络/存档里被改过的 id 会 `ArrayIndexOutOfBounds`。
- **`this == next` 返回 `false`**：自转移算失败，调用方据此区分「真的推进了」和「原地踏步」——
  否则「COMBAT → COMBAT」会让「阶段是否变化」的判断永远为真。

同类枚举还有 `WinefoxRewardState`（`NONE/GRANTING/GRANTED/NOT_ELIGIBLE`，默认 `NOT_ELIGIBLE`）、
`WinefoxTermination`（`NONE/ONE_SHOT/LOOP/HOLD_LAST_FRAME`）。**枚举 = 数据表**，见 §14.11。

**③ 可变状态搬成「小对象」，每个对象只管一件事**

| 类 | 职责 | 关键点 |
|---|---|---|
| `WinefoxHealthState` | 权威血量容器 | `AtomicReference<Float>`，`null` = 未初始化（§14.49） |
| `WinefoxHighDamageGuard` | 高伤后 100 tick 内伤害 ×0.7 | 自带 `expiresAt`，**过期自动失效**，不需要外部 tick 清 |
| `WinefoxInvisibilityTracker` | 隐身玩家的「注意到/已找到」两阶段 | `noticedPlayers` / `foundPlayers` 两个 `Set` + `remainingTicks` 宽限 |
| `WinefoxBossHealthController` | 所有血量写入的唯一入口 | 归因栈 + 白名单（§14.49） |
| `WinefoxSpellController` | 施法生命周期 | `cast / castInstant / cancel / tick / activeAction` |

- **守卫对象自己管过期**（`HighDamageGuard.multiplier(now)` 里判 `now > expiresAt` 就自清）：
  外部 tick 清理会漏（Boss 被卸区块时 tick 不跑，守卫状态就永久残留）。
- **`InvisibilityTracker.observe(...)` 返回一个小 `record`**（`Reaction(noticed, found)`），
  调用方一次拿到「首次注意到 / 首次找到」两个布尔，不用连调两次再比对 Set——**避免两次 `Set.add` 的时序 bug**。

**④ 守卫类：全部用 `@SubscribeEvent` 的优先级站位，不进实体**

```java
public final class WinefoxNonLethalGuard {
    @SubscribeEvent(priority = EventPriority.LOWEST)
    public static void activateNormalMobCombat(LivingChangeTargetEvent event) { ... }

    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void blockRetiredMaidInteraction(InteractMaidEvent event) { ... }
}
```

- **`LOWEST` 用来「最后决定要不要让位」**：别人的目标切换逻辑先跑完，我再决定是否取消。
- **`HIGHEST` 用来「抢先拦住交互」**：退役女仆的交互必须在任何 UI 逻辑之前否掉。
- **同一个守卫类里两个事件用相反优先级**是正常的：优先级由「我要不要看到别人的结果」决定，不是全局统一。
- **守卫是 `final` + 全静态 + 私有构造**：它没有状态，有状态的部分都在 ③ 的对象里。

**⑤ 1005 行的 `WinefoxCombatGoal` 再拆：按「阶段 × 关注点」二维切**

方法名本身就是路由表：

| 维度 | 方法 |
|---|---|
| 阶段推进 | `tickPhaseOne` / `tickPhaseTwo` / `onPhaseChanged` |
| 移动 | `movePhaseOne` / `movePhaseTwo` / `holdPosition` / `moveTowardClearPosition` |
| 选招 | `chooseSpell` / `choosePhaseTwoSpell` / `maidspell$pickWeighted` / `maidspell$weight` |
| 连发 | `startBurst` / `tickBurst` / `castAction` |
| 冷却 | `getSpellCooldown` / `isSpellReady` / `tickCooldowns` |
| 死锁 | `trackProgress` / `breakDeadlock` / `resetStationaryTracking` |
| 阈值触发 | `tickPalmBlackHoleAtThreshold` / `tryPeriodicCompanionBlackHole` / `tryStationaryEcho` |

- **`tickXxx` 统一返回 `boolean`（是否已消耗本 tick）**：上层 `if (tickA()) return; if (tickB()) return;`
  —— 一个 tick 只做一件事，避免「同一 tick 同时放两个大招」。
- **死锁处理必须单独一组方法**（`trackProgress` 记「最近 N tick 位移没变」→ `breakDeadlock` 换目标位）：
  飞行 Boss 卡在方块里是必现 bug，不能指望「移动逻辑自己会解决」。
- **权重选择 `pickWeighted` 返回 `null` 表示无可用**，调用方必须判空并退回默认招；
  候选池全被冷却/条件过滤掉是常态（§14.32）。

**⑥ 拆分的边界：什么时候**不该**再拆**

- **数据表不拆**：`WinefoxBossSpells`（286 行）、`WinefoxTrades`（260）、`WinefoxDialogue`（233）
  是「一张表 + 少量查询方法」，拆成三个类只会让引用跳转变多。
- **纯函数不搬**：`horizontalDistance` / `horizontalDirection` 是 `static` 工具方法，留在 Goal 里最方便。
- **只被一个类用的 5 行 helper 不搬**：搬出去就变成「为了分层而分层」，反而更难读。

**判据**：**有独立生命周期 / 有独立过期条件 / 需要在多个入口被共享** → 搬成对象；否则留在原类。