# 施法落地：非玩家实体施法、法术实体、时间轴、女仆战斗任务

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.13 非玩家实体施法配方（5 条硬规则）

**① 别自己实现 `IMagicEntity`**——它只有 6 个必需方法（`getMagicData` / `setSyncedSpellData` / `isCasting` /
`initiateCastSpell` / `cancelCast` / `castComplete`），但第三方已有 `AbstractSpellCastingMob` 全部实现。
继承链实测：`NeutralWizard → AbstractSpellCastingMob → AbstractSpellMeleeMob → 自定义Boss实体`。

**② 目标型法术必须先塞 `TargetEntityCastData`**，否则 `preCastTargetHelper` 拿不到目标。

**③ `initiateCastSpell` 是异步的**（起手动画/吟唱要占 tick），必须轮询 `isCasting()`，不能一次调用就认为成功。

**④ `CastType.INSTANT` 不会自己走完**，要手动补 `onCast` + `castComplete`。

**⑤ `CastSource` 必须是 `MOB`**——写成 `SPELLBOOK` 会让法力/冷却结算走玩家分支而空指针。

```java
static boolean cast(Boss boss, AbstractSpell spell, LivingEntity target, int level) {
    MagicData data = boss.getMagicData();
    if (target != null) data.setAdditionalCastData(new TargetEntityCastData(target));
    boss.initiateCastSpell(spell, Math.max(1, Math.min(level, spell.getMaxLevel())));
    return boss.isCasting();
}

static boolean castInstant(Boss boss, AbstractSpell spell, int level) {
    MagicData data = boss.getMagicData();
    boss.initiateCastSpell(spell, level);
    spell.onCast(boss.level(), level, boss, CastSource.MOB, data);
    boss.castComplete();
    return true;
}
```

### 14.14 ⚠️「接口 default 覆盖父类具体方法」是零效果的（javac 实测验证）

**这是本次深挖发现的最隐蔽缺陷，值得单独立节。**

目标类的抽象父类里已有**具体方法**（`AbstractSpell.allowCrafting()` / `allowLooting()`，javap 确认无 `abstract` 修饰），
此时子类 `implements` 一个带 `default` 的同名方法接口——**default 一次都不会生效**。
JLS 规则：**类方法永远优先于接口 default 方法**（子类从父类继承到的具体方法不会被接口 default 覆盖）。

`javac` + `java` 实测（JDK 17）：

```java
abstract class Base { public boolean allowCrafting() { return true; } }
interface Marker    { default boolean allowCrafting() { return false; } }
class SubNoOverride extends Base implements Marker {}                       // 只 implements
class SubOverride   extends Base implements Marker {
    @Override public boolean allowCrafting() { return false; }              // 显式重写
}
```

```
NoOverride  allowCrafting=true    ← default 被忽略，标记接口形同虚设
Override    allowCrafting=false
```

**真实事故**：某模组 11 个 Boss 专属法术 `implements BossExclusiveSpell`，其中 **10 个**手动重写了
`allowCrafting()/allowLooting()`（作者显然踩过坑），**唯独漏掉 1 个** → 该法术实际可合成、可战利品掉落，
与「Boss 专属、禁止玩家获取」的设计意图完全相反。**编译器不报错、运行不报错、只有玩家能造出来。**

**判据（可脚本化）**：同一目录下 `implements 标记接口` 的文件数 ≠ 含 `allowCrafting()` 的文件数 → 必有漏网。

```powershell
Get-ChildItem *.java | ForEach-Object {
  $c = Get-Content $_.FullName -Raw
  [pscustomobject]@{ Name=$_.Name
    Impl = ($c -match 'MarkerName')
    Override = ($c -match 'allowCrafting\(\)') }
} | Where-Object { $_.Impl -and -not $_.Override }
```

**两种正确修法**：

1. **显式 override**（最小改动，与其余同类保持一致）——推荐，因为「标记接口 + default」在这里只是**注释**，不是约束。
2. **Mixin `@Inject(method="allowCrafting", at=@At("HEAD"), cancellable=true)` + `instanceof` 判断**——
   适合**改不了源码**（第三方 jar）的场景；代价是侵入所有法术、且依赖方法名不变。

**结论**：`default` 方法只能给「父类/接口都没有同名方法」的场景兜底。想用「标记接口 + default」做统一行为，
**先确认目标类里没有同名具体方法**；有的话这个设计从第一天就是无效的。

### 14.15 第三方同步机制「漏了你的实体」→ `doSync` TAIL 补发

第三方同步逻辑常写成「只处理实现了 `IMagicEntity` 的实体」，你的实体没实现（比如是女仆的附属数据），
于是**服务端算得对、客户端全是旧值**。标准补丁模板：

```java
@Mixin(value = SyncedSpellData.class, remap = false)
public abstract class SyncedSpellDataMixin {
   @Shadow private LivingEntity livingEntity;

   @Inject(method = "doSync", at = @At("TAIL"))
   public void afterDoSync(CallbackInfo ci) {
      if (this.livingEntity instanceof IMagicEntity) return;
      if (!(this.livingEntity instanceof 我的实体 maid)) return;
      if (我的数据.get(maid.getUUID()) == null) return;
      FriendlyByteBuf buf = new FriendlyByteBuf(Unpooled.buffer());
      buf.writeInt(maid.getId());
      SyncedSpellData.write(buf, (SyncedSpellData) this);
      PacketDistributor.sendToPlayersTrackingEntity(this.livingEntity,
          new SyncEntityDataPacket(buf));
   }
}
```

三个要点：
- **`TAIL` 而非 `HEAD`**：先让第三方跑完自己的逻辑，再补发，不干扰它。
- **复用第三方自己的 `write` 静态方法**，不要手写字段顺序——对方加字段时你自动跟上。
- **`sendToPlayersTrackingEntity`** 而非全服广播：只发追踪该实体的玩家，避免带宽爆炸。

### 14.16 Mixin 门控时序：`LoadingModList` 而非 `ModList`

`MixinConfigPlugin.onLoad()` 执行时，Forge 的 `ModList` **还没填充**，`ModList.get().isLoaded(id)` 一律返回 `false`，
于是**所有 mixin 被静默跳过**——不崩、不报错、功能就是不生效。正确写法：

```java
public void onLoad(String pkg) { loaded = LoadingModList.get().getModFileById(modId) != null; }
```

对照：正常业务代码（`@Mod` 构造器之后）才用 `ModList.get().isLoaded(id)`。**两个 API 分属不同阶段，别混用。**

### 14.21 自定义法术实体：先选基类，再补「必覆写 6 件套」

实测本模组 `compat/irons_spellbooks/` 下 **17 个具体实体类**的继承分布（`entity/` 直层 5 + `entity/spell` 11 +
`entity/winefox` 1；另有抽象基类 `entity/base/AbstractSpellMeleeMob` 295 行 `extends NeutralWizard`，不计入 17），可直接当选择表：

| 基类 | 来源 | 用它的实体 | 什么时候选它 |
| --- | --- | --- | --- |
| `AbstractMagicProjectile` | Iron's | WinefoxSwordProjectile、ModifiedMagicMissile | 会飞的投射物，要 Iron's 的弹道/命中回调 |
| `BlackHole` | Iron's | CompanionBlackHole、SpellbreakingEcho | 就是黑洞，直接继承吸力与渲染 |
| `AoeEntity` | Iron's | StarShadowStrike | 范围伤害 |
| `Comet` | Iron's | ModifiedStarfallComet | 陨石类 |
| `NeutralWizard` / `AbstractSpellCastingMob` | Iron's | GuardianWitch、ElfTemplar、CorruptedKnight、ShadowAssassin、HolyConstruct、MagicalWinefoxBoss | 会施法的怪 |
| `Projectile`（原版） | MC | SwordArray | 要投射物骨架、但不要 Iron's 弹道 |
| 裸 `Entity` | MC | PalmBlackHole、SevenStarGuidance、ThreeEnclosuresField、ModifiedStarfallCloud | 纯舞台特效 + 自己算判定 |

判据：**先问「Iron's 有没有现成的」→ 有就继承 → 不够退到原版基类 → 都不合适才裸 `Entity`**。
裸 `Entity` 的唯一代价是自己写 `getAddEntityPacket`，收益是完全掌控 tick 与命中判定。

「6 件套」的**最完整样本是 `PalmBlackHoleEntity`（6/6 项全覆写：① ② ③ ④ ⑤ ⑥）**，但别把它当成「缺一就崩」的铁律——
本项目 4 个裸 `Entity` 法术实体的实际覆写率如下（2026-11-03 逐类 grep；反编译快照 `.autopilot/decompile`，SRG 名逐条核对：`f_19794_`=noPhysics、`m_20242_`=setNoGravity、`m_5654_`=getAddEntityPacket、`m_6921_`=getBoundingBoxForCulling、`m_6783_`=shouldRenderAtSqrDistance、`m_7822_`=handleEntityEvent）：

| 项 | 覆写数 | 谁没写 |
| --- | --- | --- |
| ① `noPhysics = true` | **4/4** | — |
| ② `setNoGravity(true)` | **4/4** | — |
| ③ `getAddEntityPacket` | 2/4 | SevenStarGuidance、ModifiedStarfallCloud |
| ④ `getBoundingBoxForCulling` | **2/4** | ThreeEnclosuresField、ModifiedStarfallCloud |
| ⑤ `shouldRenderAtSqrDistance` | **2/4** | ThreeEnclosuresField、ModifiedStarfallCloud |
| ⑥ `handleEntityEvent` | **1/4** | SevenStarGuidance、ThreeEnclosuresField、ModifiedStarfallCloud（另 3 个非裸 Entity 也写：`StarShadowSpearEntity`、`ModifiedStarfallCometEntity`、`WinefoxSwordProjectileEntity`） |

结论：**①② 是硬性**（不写就掉/穿模），**③④⑤ 是「按视觉半径决定要不要写」**——只在渲染体积远大于碰撞体积时才必须，
⑥ 是可选的省包手段。别照抄 6 条当 checklist，先问自己「这个特效在 100 格外还要不要看得见」。

```java
public XEntity(EntityType<? extends X> type, Level level) {
    super(type, level);
    this.noPhysics = true;        // ① 法术实体不参与碰撞（4/4 都写）
    this.setNoGravity(true);      // ② 否则每 tick 往下掉（4/4 都写）
}

@Override public Packet<ClientGamePacketListener> getAddEntityPacket() {
    return NetworkHooks.getEntitySpawningPacket(this);   // ③ Forge 必须这么写（写了才走 Forge 的 spawn 包）
}

@Override public AABB getBoundingBoxForCulling() {       // ④ 视觉体远大于碰撞体时必写，否则整块被剔除
    double top = Math.max(40.0, startHeight + 16.0);     // 实测结论：有 40 格下限，不是裸 startHeight+16
    return new AABB(getX() - 32, getY() - 16, getZ() - 32,
                    getX() + 32, getY() + top,  getZ() + 32);
}

@Override public boolean shouldRenderAtSqrDistance(double d) { return d < 16384.0; } // ⑤ 默认 4096（64 格）→ 128 格

@Override public void handleEntityEvent(byte id) {       // ⑥ 可选：事件字节做客户端特效，省一个自定义包
    if (id == 61) spawnVoidExplosionParticles();
    else super.handleEntityEvent(id);
}
```

实测三个坑：

- `getBoundingBoxForCulling` 不覆写 → 玩家转头时黑洞**整块消失**（视觉范围 16 格，物理盒不到 1 格）。
- `shouldRenderAtSqrDistance` 默认 4096（64 格）；大特效在 100 格外直接不渲染。
- **双构造器必须链式调用**：`(EntityType, Level)` 供反序列化与客户端，`(Level, caster)` 供服务端生成，
  后者第一行必须 `this(...)` 转到前者，否则 ①② 漏设，实体从天上往下掉（`SwordArrayEntity` 实测就是这么写的）。

数据同步分层（实测）：

| 放哪 | 放什么 | 理由 |
| --- | --- | --- |
| `SynchedEntityData` | age、casterId、releaseYaw、startHeight | 客户端渲染要用 |
| 普通字段 | casterUuid、hitTargets、伤害数值 | 只服务端判定用，同步纯浪费 |

- **复杂结构整块同步**：`SwordArrayEntity` 把剑阵布局 `SwordArrayLayout` 和 `BitSet` 已移除位
  都序列化成 `CompoundTag` 走 `EntityDataSerializers.COMPOUND_TAG` 一次同步，
  不要为每个字段加一个 accessor。
- **NBT 写同步数据必须 `.copy()`**：`tag.put("Layout", data.get(DATA_LAYOUT).copy())`。
  直接塞对象本体，后续被改写会串存档。
- `hitTargets` 用 `Set<UUID>` 去重：多段/穿透伤害不去重，一个目标会被扫 N 次。

Iron's 能力接口按需实现：`AntiMagicSusceptible` → `onAntiMagic(MagicData)` 里直接 `discard()`
（反魔法要能一键抹掉你的特效）；`NoKnockbackProjectile` 标记不吃击退。
注意 §14.14 的教训：**标记接口 + default 方法，若父类已有同名具体方法，覆盖是零效果的** ——
这类接口只在你确实没有父类实现时才起作用。

### 14.22 时间轴纯函数：只同步 age，其余双端算

`PalmBlackHoleTimeline` 实测是一个 53 行、零状态、全 `static` 的类，服务端判定与客户端渲染都调它：

```java
public final class XTimeline {
    private XTimeline() {}                                  // 禁止实例化
    public static boolean isPulseTick(int age) { return age >= 50 && age < 340 && (age - 50) % 20 == 0; }
    public static float waveRadius(double age) { return 16f * clamp01((age - 340.0) / 20.0); }
    public static double dropHeight(double age, double top) { /* 二次缓动 */ }
    public static boolean crossedWave(double d, float prev, float cur) { /* 见下 */ }
}
```

价值：**只要 `age` 这一个整数同步过去，脉冲节奏、波半径、下落高度、伤害曲线全部双端一致**，
不需要同步任何派生状态；改特效节奏只改一处。

`crossedWave` 是环形冲击波的正确判定（实测结论）：判定区间为
`[max(0, 上一帧半径 − 0.8), min(16, 当前帧半径 + 0.8)]`。

**反模式**：用 `distance <= radius` 判命中。半径每帧变大，结果是**远处目标第一帧就被判命中**，
近处反而漏；再叠加 `hitTargets` 去重，玩家看到的是「冲击波还没到我就掉血」。
用「上一帧半径 → 当前帧半径」的**环形带 + ±0.8 容差**，命中顺序自然由内向外，
快速移动目标也不会在两帧之间被跳过。**`0.8F` 是独立字面量**，数值上恰等于
`BLAST_RADIUS / WAVE_TICKS`（16/20），但源码未由这两个常量派生——改常量不会带动容差。

同型实证：`SevenStarGuidanceEntity` 把整条时间轴写成一组 `public static final int` 常量
（`FIRST_STRIKE_TICK=12` / `STRIKE_INTERVAL=10` / `FINAL_TICK=94` / `FINALE_DAMAGE_TICK=130`），
客户端渲染直接读常量——**渲染不猜时间，只查表**。

判据：**任何「第 N tick 该发生什么」的设定，都提到一个无状态纯函数类里，双端共用。**
放进实体内部当私有字段 = 客户端永远算不出和服务端一样的值。

> **同主题见 `14b-architecture.md` §14.51**：那一节把「时间轴纯函数」扩到**多点阵型**——
> `(seed, level, radius, startedAt)` 只同步 4 个参数，48 条轨迹在构造时一次积分成数组，
> `age` 是唯一驱动量（`launchAge/landingAge/expiryAge` 全是 `age` 的纯函数）。
> 写「箭雨 / 地刺 / 符文阵 / 多段爆发」这类**多个离散作用点**的技能时，先读 §14.51 再回来。

### 14.40 女仆自定义任务：`@LittleMaidExtension` + 优先级 2 的六件套

给 TLM 女仆加「自定义战斗任务」，只需一个入口类 + 一个任务类。

**① 入口：`@LittleMaidExtension` + `ILittleMaid`**

```java
@LittleMaidExtension
public class TaskRegistry implements ILittleMaid {
    @Override
    public void addMaidTask(TaskManager manager) {
        manager.add(new SpellCombatMeleeTask());
        manager.add(new SpellCombatFarTask());
    }
}
```

- 注解 `@LittleMaidExtension` 由 TLM 自己扫描，**不需要在 mod 主类里手动注册**。
- 一个入口类里把所有任务一次性 `add`，任务之间共享基类常量（射程、目标过滤），不要每个任务一个入口。

**② 任务类实现 `IRangedAttackTask`，UID 必须带 modid**

```java
public class SpellCombatMeleeTask implements IRangedAttackTask {
    public static final ResourceLocation UID = new ResourceLocation("maidspell", "spell_combat_melee");
    private static final MutableComponent NAME = Component.translatable("task.maidspell.spell_combat");

    public ResourceLocation getUid() { return UID; }
    public MutableComponent getName() { return NAME; }
    public boolean isEnable(EntityMaid maid) { return true; }
}
```

- `UID` 不带 modid 前缀会和别的模组任务撞车，撞了之后女仆的任务配置存档直接错乱。
- `getName()` 返回 `translatable`，**不要返回字面量**——玩家语言不同就是一堆英文混中文。
- `isEnable` 恒 `true` 表示「任务永远可选」；要按条件开放（例如需要某个饰品）就返回对应判断。

**③ `createBrainTasks` 六件套 + 优先级 1/2 的分工**

```java
BehaviorControl<EntityMaid> look       = new CombatLookControlTask();
BehaviorControl<EntityMaid> startAtk   = StartAttacking.create(this::hasSpellBook, this::findValidAttackTarget);
BehaviorControl<EntityMaid> stopAtk    = StopAttackingIfTargetInvalid.create(
                                            t -> farAway(t, maid) || !isValidSpellCombatTarget(maid, t));
BehaviorControl<EntityMaid> moveTo     = MaidRangedWalkToTarget.create(0.6F);
BehaviorControl<EntityMaid> cast       = createSpellCastingBehavior(false);
BehaviorControl<EntityMaid> strafe     = new SpellStrafingTask();

return List.of(Pair.of(1, look),          // 只有视线独占优先级 1
               Pair.of(2, startAtk), Pair.of(2, stopAtk),
               Pair.of(2, moveTo),   Pair.of(2, cast), Pair.of(2, strafe));
```

- **视线优先级 1，其余全 2**。同优先级的行为由 Brain 自然竞争（各自 `checkExtraStartConditions` 决定谁跑），
  不需要手工给每个行为排优先级——排了反而会出现「移动永远抢不到」。
- `StartAttacking` 的启动条件用 `this::hasSpellBook`：**没有法术书就不该进入战斗任务**，
  否则女仆会站着「举着手什么也不放」。
- `StopAttackingIfTargetInvalid` 的条件必须和 `canSee` 用同一套判定，否则会出现「锁定了但打不到」的僵持。

**④ 骑马版单独一套，不要在地面行为里 `if (骑马)`**

```java
public List<Pair<Integer, BehaviorControl<? super EntityMaid>>> createRideBrainTasks(EntityMaid maid) {
    // 少了 moveTo / strafe，多了一个「能否骑乘施法」的前置判断
}
```

骑马时不需要走位（马自己走），也不需要移动行为。**两套方法分开写**，
比在一个 `createBrainTasks` 里塞 `if (maid.isPassenger())` 清晰得多，也不会因为漏判让马上的女仆原地乱转。

**⑤ `canSee` 要自己实现：原版视线判定对法术太严**

```java
public boolean canSee(EntityMaid maid, LivingEntity target) {
    return isValidSpellCombatTarget(maid, target)
        && maid.distanceTo(target) <= SPELL_RANGE * 1.2      // 留 20% 缓冲
        && Math.abs(maid.getY() - target.getY()) < 5.0;      // 高度差限制
}
```

- **射程 ×1.2 缓冲**：目标在边界来回走时，严格等于射程会导致「能打→不能打→能打」的抖动，表现为女仆一顿一顿。
- **高度差 < 5**：防止女仆对头顶 30 格的怪「隔墙锁敌」，然后一直原地放空。
- 不直接用 `maid.canSee(target)`（原版射线检测）—— 法术很多是范围/追踪型，不需要严格视线，但需要距离与高度约束。

**⑥ 目标过滤四道闸**

```java
protected static boolean isValidSpellCombatTarget(EntityMaid maid, LivingEntity target) {
    if (maid == null || target == null || target instanceof Player) return false;   // ① 永不主动打玩家
    if (MaidSuppressionZone.suppresses(maid)) return false;                          // ② 压制区禁战
    if (target instanceof IMaid m && m.isMaidInSittingPose()) return false;          // ③ 不打待机女仆
    return !MaidSpellAllyResolver.areFriendly(maid, target);                         // ④ 不打友军
}
```

顺序很重要：**最便宜的判定（null / 类型）放最前**，`areFriendly` 会走归属链解析（见 §14.27），代价最高放最后。
四道闸写成**一个静态方法**，`StartAttacking` / `StopAttackingIfTargetInvalid` / `Strafing.checkExtraStartConditions`
全都调它——**判定只有一处，改规则不会漏改**。

**⑦ 走位（Strafing）：Memory 门控 + 超时 + 换向抖动**

```java
public SpellStrafingTask() {
    super(ImmutableMap.of(
        MemoryModuleType.ATTACK_TARGET,   MemoryStatus.VALUE_PRESENT,
        MemoryModuleType.WALK_TARGET,     MemoryStatus.VALUE_ABSENT,     // 有走路目标时让路
        MemoryModuleType.LOOK_TARGET,     MemoryStatus.REGISTERED,
        MemoryModuleType.NEAREST_VISIBLE_LIVING_ENTITIES, MemoryStatus.VALUE_PRESENT),
        1200);                                                            // ← 超时 1200 tick
}

// tick 内
if (distance < maxAttackDistance && maid.canSee(target)) strafingTime++;
else strafingTime = -1;

if (strafingTime >= 20) {                       // 每 20 tick 才有机会换向
    if (rand.nextFloat() < 0.3) strafingClockwise = !strafingClockwise;
    if (rand.nextFloat() < 0.3) strafingBackwards = !strafingBackwards;
    strafingTime = 0;
}

if (distance > optimalMax) strafingBackwards = false;   // 太远 → 前进
else if (distance < optimalMin) strafingBackwards = true;  // 太近 → 后退
maid.getMoveControl().setWantedPosition(forward, strafe, ...);
```

- **`WALK_TARGET = VALUE_ABSENT`**：有走路目标时走位行为直接不跑，避免和 `MaidRangedWalkToTarget` 抢移动控制。
- **`1200` tick 超时**：Brain 行为的硬超时，防止某个条件永远不满足导致行为永久占用。
- **换向用 20 tick 周期 + 30% 概率**，而不是每 tick 随机：每 tick 随机会让女仆抽搐。
- **距离带双阈值**（`optimalMin - 1` 到 `optimalMin + 1.5`）：只有太远才前进、太近才后退，中间保持横移。
- `stop()` 里 **必须 `setWantedPosition(0, 0)` 清零移动**，否则行为结束后女仆还会惯性走两步。

**⑧ `start` / `stop` 成对设置手臂摆动**

```java
protected void start(...)  { maid.setSwingingArms(true);  }
protected void stop(...)   { maid.setSwingingArms(false); maid.getMoveControl().setWantedPosition(0, 0, ...); }
```

`setSwingingArms(true)` 是「举起手臂」的渲染状态。**`stop` 里漏掉 `false`，女仆会永久举着手**——
而且这个状态会被存档（`addAdditionalSaveData` 里带），重进世界还是举着。所有 `start` 里设置的渲染标志，
`stop` 里都必须还原，一个都不能漏。