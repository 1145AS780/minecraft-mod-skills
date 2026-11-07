# 架构识别：多模组施法协议、状态建模、三层改造梯度

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.9 多模组施法协议：模板方法基类 > 接口

实测一个 `ISpellBookProvider<T extends IMaidSpellData, S>` 抽象基类，用构造器注入 5 个参数：

```java
protected ISpellBookProvider(
    Function<UUID, T> dataFactory,   // 建数据
    Function<UUID, T> dataLookup,    // 查数据
    Consumer<UUID> dataRemover,      // 删单条
    Runnable dataClearer,            // 清全部
    Class<S> spellClass)             // 法术类型标记（用于 instanceof 过滤）
```

子类只需实现 5 个抽象方法（实测 `ISpellBookProvider.java` L39/99/140/142/144）：

| 抽象方法 | 修饰符 | 职责 |
| --- | --- | --- |
| `collectSpellFromSingleSpellBook(stack, maid)` | `protected` | 从一本书里读出法术列表 |
| `isSpellBook(stack)` | `public` | 判断这个 `ItemStack` 是不是本模组的法术书 |
| `initiateCasting(maid)` | `protected` | 发起一次施法 |
| `processContinuousCasting(maid)` | `public` | 持续施法每 tick |
| `stopCasting(maid)` | `public` | 中断收尾 |

其余 20+ 个生命周期方法（`hasData` / `onMaidJoin` / `handleItemStack` / `clearSpellItems` /
`updateCooldown` / `refundCooldowns` / `setTarget` / `isCasting` …）全部由基类兜底。

> **别把这里的「5」和构造器注入的「4」搞混**：构造器是 4 个**方法引用**（`dataFactory` / `dataLookup` /
> `dataRemover` / `dataClearer`）+ 1 个 `Class<S>` 类型标记 = 5 个**参数**；
> 抽象方法是 5 个**待实现的方法**。早期本节漏了 `isSpellBook`，写成「4 个抽象方法」，已修正。

**价值**：8 个第三方施法模组（Iron's Spellbooks / Ars Nouveau / Psi / SlashBlade / Goety /
Youkai Homecoming / Wizardry / Mana and Artifice）的差异被压缩到「怎么读书」「怎么发起」两点，
冷却/目标/白名单/饰品槽/卸载清理只有一份实现。

**mods.toml 实测（版本冲突高发点）**：上述 8 家中实测 7 家（`irons_spellbooks` / `ars_nouveau` /
`goety` / `youkaishomecoming` / `mna` / `psi` / `slashblade`）在本模组 `mods.toml` 里全部是
`mandatory=false`（Wizardry 不在本次实测范围内）。其中 Iron 的声明只给下界 `[1.20.1-3.15.0,)`；
而**反向更硬：Iron 本体的 `mods.toml` 把 `irons_lib` 卡成 `[1.20.1-2,1.20.1-3)`，带上了界**。
一方只给下界、另一方锁死上界，这种非对称写法正是版本冲突的高发点——比只罗列模组名有用得多。

**为什么用抽象基类而不是接口**：这 20+ 个生命周期方法是**固定骨架 + 少量可覆盖**，
用接口就得让每个实现类复制一遍默认行为。接口适合「行为差异大」，基类适合「骨架相同、接入点少」。

适配层四个实战手法：

1. **索引缓存槽位**：白名单饰品槽每 tick 遍历 `getSlots()` 太贵 → 缓存命中的槽索引，仅失效时重扫。
2. **绕过第三方私有字段**：`PlayerRecasts.removeRecast()` 内部触发只有 Player 才有的回调（发包/HUD 同步），
   女仆调用会 NPE → 反射取私有 `recastLookup` Map 直接 `remove`，跳过全部回调。
3. **recast 首施白名单**：召唤类法术（`raise_dead` / `summon_swords` / `summon_horse` / `summon_vex` /
   `summon_polar_bear` / `portal`）recast 会重复召唤 → 用 `Set<String> FIRST_CAST_ONLY` 排除。
4. **失败兜底降级链**：法术施放失败时按动作类型降级（瞬移类 → 直接瞬移，非控制类 → 远程普攻），
   **绝不让 Boss 站着发呆**。

**调度器反模式**：`castSpell(maid)` 遍历**所有**已注册 Provider 各调一次。
玩家同时装两套施法系统时，女仆会在同一 tick 尝试两套施法。应改为按优先级顺序尝试，**首个成功即 `break`**。

### 14.10 Boss 战斗 AI：可抄的 7 条与必避的 7 条

**可抄的正模式**（全部来自实测 1005 行 `WinefoxCombatGoal`）：

| 模式 | 实现要点 |
| --- | --- |
| 加权轮盘随机 | 累加权重得 `total` → `random.nextInt(total)` → 逐个扣减，`roll<0` 即命中；比 `random*size` 可控得多 |
| 谓词过滤与选择器分离 | 先构造 `eligible` 列表（阶段/冷却/距离/溢出条件全在过滤里），再交给选择器；过滤规则集中一处，易测易改 |
| 存在即冷却 | `isSpellReady = !cooldownMap.containsKey(action)`；每 tick `replaceAll(v->v-1)` + `removeIf(v<=0)`，省掉「剩余>0」分支 |
| 卡死检测 + 随机脱困 | 位移平方 < 阈值（如 `0.0025`）累计 20 tick → 随机方向冲量 + 清空寻路 + 反转绕圈方向；**飞行 Boss 必备** |
| 阶梯式抬升寻位 | 目标 AABB 撞方块 → 按 0.5/1.0 步长逐级抬升，取第一个不撞的落点 |
| 切向 + 径向混合走位 | `tangent + away * clamp((dist-target)*0.2, -0.8, 0.8)`；一个 P 控制器把距离稳定在固定格数，同时绕圈，观赏性远胜直线追击 |
| 失败降级链 | 见 §14.9 第 4 条 |

**必避的反模式**：

| # | 反模式 | 症状 / 判定方法 | 修法 |
| --- | --- | --- | --- |
| 1 | 卫语句缺失，七层嵌套 if | `else if (!tryXxx())` 层层套娃，缩进 > 4 层 | 全部改早退：`if (tryXxx()) return;`，每行为一个独立可测方法 |
| 2 | 冷却状态碎片化 | 同文件 12 套冷却（1 个 EnumMap + 1 个 Map + 10 个 int 字段），`tickCooldowns()` 里 9 段复制粘贴的 `if(x>0)x--` | 统一成 `Map<CooldownKey,Integer>` 或 `IntCooldowns` 工具类；否则加一个行为要改 4 处（字段/递减/重置/换阶段） |
| 3 | 重复映射表漂移 | 同一张「法术→等级」表写两份，**已实测不一致**（同一法术走配置池=5 级、走默认池=1 级） | 抽成一张 `static Map<Action,Integer>`；凡出现两处同构 switch/if 链就是隐患 |
| 4 | 死常量 | 顶部定义 `SUMMON_SWORDS_SPELL_ID`，实际用字面量 `"irons_spellbooks:summon_swords"` | 常量与字面量必须二选一；改 ID 时改常量不生效 = 必踩 |
| 5 | 同型参数相邻 | `startBurst(action, shots, spellLevel, intervalTicks)`，两个 `int` 传反编译器不报错 | 改 `record BurstSpec(int shots, int level, int interval)` 或 Builder |
| 6 | 隐式状态机 | 5 个散落字段 + `startBurst()`/`tickBurst()` 构成状态机却没封装 | 收进一个 `final class XxxBurst { Step step; ... }`（对照 §14.11 正例） |
| 7 | 三元表达式塞布尔逻辑 | 两组布尔条件挤进一个三元式，需读三遍才敢确定优先级；`: 1` 分支还不可达（过滤已排除） | 拆成 `if` 或查表；不可达分支直接删。原始三元式见紧邻下方的代码块 |

第 7 行的原始三元式（内含 `||`，写进表格会撑破列结构，故移到表外单独列出）：

```java
level = (a != X || b) && (a != Y || !b) ? 2 : 1;
```

### 14.11 状态建模：枚举即数据表（本模组可复用度最高）

**动画/动作枚举带完整时间轴**——把不会变的常量编译进类型系统，而不是塞 JSON：

```java
PHASE_TRANSITION("phase_transition", 120, ONE_SHOT,
    Event.sound(1, "atked"),
    Event.sound(45, "shengyin"),
    Event.at(55, EventKind.KNOCKBACK),
    Event.at(55, EventKind.WEAPON_SWAP))
```

`Event` 用 `record` + 静态工厂 `at(tick, kind)` / `sound(tick, name)`；事件按 **tick 偏移**而非绝对时间，
动画时长一改事件自动跟随。新增动画 = 加一行枚举，不动任何逻辑；动画师能直接看枚举改参数。

**枚举转移表 + switch 表达式穷举**：

```java
public boolean canTransitionTo(WinefoxEncounterState next) {
    if (this == next) return false;
    return switch (this) {
        case SEATED          -> next == CHALLENGE_START || next == COMBAT;
        case CHALLENGE_START -> next == COMBAT || next == SEATED || next == RETURNING;
        case COMBAT          -> next == DEFEATED || next == RETURNING;
        case DEFEATED        -> next == RETURNING;
        case RETURNING       -> next == SEATED;
    };
}
```

Java 21 exhaustive switch 漏 case 编译不过，是「转移表」最安全的写法。**但它只是查询，没有强制**：
调用方拿到 `false` 仍可照样转。真正的守卫要把校验和赋值合并：

```java
boolean transitionTo(Next next) {
    if (!canTransitionTo(next)) { LOGGER.warn("illegal {} -> {}", this, next); return false; }
    this.state = next; return true;
}
```

**小状态机必须内聚封装**（实测 60 行 `WinefoxSwordCombo` 是全代码库最佳对照）：

```java
void castStarted(Action a) {
    if (step == Step.FLASH && a == MODIFIED_TELEPORT) step = Step.FLASH_CASTING;
    else if (step == Step.SLASH && a == STAR_SHADOW_STRIKE) step = Step.SLASH_CASTING;
}
void teleported() { if (step == Step.TELEPORT) step = Step.SLASH; }
```

每个转移方法都做前置状态校验，非法转移自动忽略；7 个步骤全收在 60 行内，可直接单测。
**同一个包里的 `WinefoxCombatGoal` 用 5 个散落字段实现同类需求**——差别不在能力，在是否愿意多花 30 分钟。

**`AtomicReference<Float>` 伪线程安全**：`float` 赋值在 JVM 上本就原子，`AtomicReference` 保证的是引用不是值语义，
且每次 `get/set` 都装箱拆箱分配对象（每 tick 多调路径纯浪费）。正确写法 `private volatile float health;`
（服务端 tick 单线程时连 volatile 都不必要）。**看起来线程安全、实则既不安全也没必要**。

### 14.12 三层改造梯度：官方 API → Mixin → ASM Agent（按侵入性递增，逐层降级）

适配一个第三方法术模组时，先查「有没有官方入口」，没有才升级手段。实测该模组三层全用上了，但**每层都有明确的适用边界**。

> **编号口径（先读这一段，否则跨文件会撞车）**：本节沿用 **14e2 §14.49 的 L0~L3 分级**，
> 但**省略了 L1（自己注册的类做 Mixin）与 L2.5（ModLauncher `ITransformationService` 类加载期 ASM）**——
> 本节场景全是「改别人的类」，这两级用不上。对应关系：
> 本节 **L0** = 官方 API、**L2** = 第三方类 Mixin、**L3** = 运行时自挂 agent。
> 权威定义与完整风险矩阵在 14e2 §14.49，**任何位置看到「L3」都指运行时自挂 agent**，别按本节的三档理解成「ASM」统称。
> （14a §14.1 的 `HurtHeadTransformationService` 属 **L2.5**，不是 L3——它走官方 coremod 路径，风险低一档。）
>
> **这是「跳号」不是「断链」**：L1 在本节**不适用**（本节没有「自己注册的类」可改），
> 编号**故意保留空洞、不重排为 L1/L2/L3**——重排会让本节的「L2」与 14e2 的「L2」错位。
> 看到本节从 L0 直接跳到 L2，是设计如此，不是漏写。

**L0 官方 API（首选，零侵入）**

```java
DeferredRegister<AbstractSpell> SPELLS =
    DeferredRegister.create(SpellRegistry.SPELL_REGISTRY_KEY, "自己modid");
```

**用别人的 registry key + 自己的 namespace**，完全合法。但有一条铁律：

> `getSpellResource()` 返回的 `ResourceLocation` 必须与 `register("名字")` 完全一致。

`SPELLS.register("star_shadow_strike", ...)` ↔ `new ResourceLocation("自己modid", "star_shadow_strike")`。
不一致**不会报错**，只会在 `SpellRegistry.getSpell(id)` 时静默返回 `SpellRegistry.none()`——最难查的一类问题。

官方事件入口（javap 抽取，非猜测）：`SpellPreCastEvent`（HEAD 取消施法）、`SpellOnCastEvent`、
`SpellDamageEvent`、`SpellHealEvent`、`SpellTeleportEvent`、`SpellSummonEvent`、`CounterSpellEvent`、
`ModifySpellLevelEvent`、`InscribeSpellEvent`、`SetSummonOwnerEvent`、`SpellCooldownAddedEvent$Pre/$Post`。

**L2 Mixin（必须改第三方类内部时）**——`mixin/` 下实测 **90 个 .java**（89 个 `@Mixin` + 1 个 `IMixinConfigPlugin`），
其中 **57 个**写 `remap = false`，另 **33 个**不写（31 个原版目标 + 1 个第三方例外 + 1 个插件，见下）。三个范式：

> **「全部 remap = false」是错的说法，别照抄。** `remap = false` 只对**第三方类**成立；
> 目标是原版类（`LivingEntity` / `Inventory` / `ItemStack` / `ChunkGenerator` / `MobEffect` …）时，
> 默认 `remap = true` 才是对的，写 `false` 反而 `Mixin apply failed`。
> 早期版本写「实测 15 个，全部 remap = false」——那个 15 是 `mixin/iss` 子包的文件数，不是全库。
> 精确分布（2026-11-01 逐文件复核）：`mixin/` 共 **90 个 .java** = 顶层 23（22 个 `@Mixin` + 1 个 `MaidSpellMixinPlugin`）
> + 13 个子包 67；其中 **57 个**写 `remap = false`，**33 个**不写（32 个 mixin + 1 个插件）。
> 这 32 个不写 `remap = false` 的 mixin 里，**31 个目标是原版类**（含 `accessor` 子包 7 个 `@Accessor`/`@Invoker`：
> `CombatTracker` / `Entity` / `JumpControl` / `LivingEntity`×2 / `Mob` / `SynchedEntityData`），
> **只剩 1 个例外**：`MaidFriendlyDamageMixin` 目标 `EntityMaid` 是第三方类，`@Mixin` 行与 `@At` 里都没写 `remap = false`。
> 【推论，未实测】它能跑大概率是因为 TLM 类不在 SRG 映射表里、Mixin 找不到映射就原样放行；
> 但成员名一旦撞上原版同名方法（`hurt` / `tick`），就有被误映射的风险——属于「能跑但脆」，
> 动它之前先确认目标方法名没有原版同名项。

| 范式 | 用例 | 要点 |
| --- | --- | --- |
| `@Inject(HEAD, cancellable)` 重写语义 | `Utils.preCastTargetHelper` | 第三方按「玩家视线」选目标，非玩家实体没有准星 → HEAD 处直接 cancel，改用自己的预设目标缓存 |
| `@Inject(TAIL)` 补漏 | `SyncedSpellData.doSync` | 见 §14.15 |
| MixinExtras `@WrapOperation` | `LivingEntity.actuallyHurt` 内的 `getHealth()` | **比 `@Redirect` 安全**（不抢占唯一匹配点，可与其他模组共存）；`Operation<Float> original` 保留原调用，非目标实体走原逻辑 |

**L3 Java Agent + ASM retransform（最后手段）**

实测用 ByteBuddy 自附加 + ASM 改写 `LivingEntity.getHealth()` / `getMaxHealth()` 的所有 `FRETURN`：

```java
ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
writer.visitFrame(Opcodes.F_SAME, 0, null, 0, null);
mv.visitInsn(Opcodes.POP);
mv.visitVarInsn(Opcodes.ALOAD, 0);
mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL, owner, "authoritativeHealth", "()F", false);
```

三个必踩的细节：

1. `COMPUTE_MAXS` **不算栈帧** → `visitFrame(F_SAME, ...)` 必须手写，否则校验器拒绝加载。
2. `pop` 丢掉原返回值再压新值——「替换所有 return」的标准字节码手法。
3. 自附加在 JDK9+ 被禁 → 用 `Unsafe` 把 `HotSpotVirtualMachine.ALLOW_ATTACH_SELF` 置 true。

**判词：这类需求（把 `getMaxHealth()` 的返回值换成权威值）用 `@Mixin(LivingEntity.class)` + `@Inject(HEAD, cancellable)` 就够，L3 是过度设计。**
选 ASM 的唯一理由是「不受 mixin 配置顺序影响」，代价是崩溃风险高一个数量级。**能 L0 就 L0，能 L2 就 L2，L3 只在 L2 确实做不到时上。**

### 14.51 多点技能阵型：布局数据 + 命中索引 + 位图回收（SwordArray 实证）

任何「多个离散作用点、按时间铺开」的技能（箭雨、地刺、符文阵、雷击阵、弹幕）都是同一个结构，
只有三样东西：**布局（纯数据）→ 空间索引（命中查询）→ 位图（哪些点已消耗）**。
本项目里这套只用了 3 个类：`SwordArrayLayout`（188 行）、`SwordArrayCollisionIndex`（57 行）、`SwordArrayEntity`（300 行）。

**① 布局 = `(seed, level, radius)` 的纯函数 —— 只同步参数，不同步坐标**

```java
public SwordArrayLayout(int spellLevel, double innerRadius, long seed) {
    Random random = new Random(seed);                            // ← 确定性：同 seed 必然同布局
    double baseAngle = random.nextDouble() * Math.PI * 2.0;      // ← 整体随机朝向
    ...
}
```

构造端只写 4 个字段，一次同步约 40 字节：

```java
CompoundTag descriptor = new CompoundTag();
descriptor.putInt("SpellLevel", spellLevel);
descriptor.putDouble("Radius", SwordArrayLayout.innerRadius(target.getBbWidth() * 0.5));
descriptor.putLong("Seed", level.random.nextLong());
descriptor.putLong("StartedAt", level.getGameTime());
this.entityData.set(DATA_LAYOUT, descriptor);
```

- **每条剑的 `positions[]` 都是 8~15 个 `Vec3`**，几十把剑一起同步就是几十 KB 的包（按条数线性放大）；
  同步 seed 是 **O(1)**，且布局天然一致。
- **必须 `new Random(seed)`，不能用 `level.random`**：`level.random` 在客户端和服务端是**两条独立序列**，
  用它会生成两个不同布局 → 客户端看到剑在 A 处、服务端在 B 处判定。
- **`baseAngle` 取随机值**：否则每次施法阵型完全一样，玩家一眼看出是模板。

**② 轨迹预计算成数组，运行时只查表**

```java
// Sword 构造：一次性积分到落地，把整条路径存下来
Vec3 position = spawn, movement = velocity;
while (true) {
    Vec3 next = position.add(movement);
    if (next.y <= 0.0) {
        double fraction = position.y / (position.y - next.y);        // ← 插值出真实落点
        Vec3 landing = position.add(movement.scale(fraction));
        path.add(new Vec3(landing.x, 0.0, landing.z));               // ← 强制 y=0
        this.plantedVelocity = movement;
        this.positions = path.toArray(Vec3[]::new);
        return;
    }
    path.add(next);
    position = next;
    movement = movement.add(0.0, -0.05, 0.0);                        // ← 每 tick 重力
}
```

- **服务端与客户端共用同一份 `positions[]`**：物理只在构造时跑一次，两侧永不漂移。
  实时逐 tick 各自积分会因 tick 顺序/区块加载时机产生位置差，表现为「客户端看到剑穿过怪，服务端没判定」。
- **`fraction` 插值不能省**：直接 `path.add(next)` 会把落点定在 `y < 0`，剑会埋在地下只露半截。
- **`position(age)` 只查表 + 线性插值**：`Mth.clamp(age - launchAge(), 0, positions.length - 1)`，
  取 `step` 与 `step+1` 之间 `lerp`（1.20.1 是 `Vec3#m_165921_`）。

**③ 一切判定都是 `age` 的纯函数，不存「状态机 + 每把剑的 timer」**

```java
public int launchAge()  { return ring * RING_INTERVAL; }                 // 5 tick/环，逐环发射
public int landingAge() { return launchAge() + positions.length - 1; }
public int expiryAge()  { return landingAge() + plantedLifetime; }

public boolean flying(int age)            { return age > launchAge() && age <= landingAge(); }
public boolean dealsContactDamage(int age) {
    int planted = age - landingAge();
    return planted > 0 && planted <= plantedLifetime && planted % 8 == 0;   // ← 固定间隔结算
}
```

- **`age` 从 `level.getGameTime() - startedAt` 算**，不是自己 `tickCounter++`：区块卸载/暂停后
  `tickCounter` 会落后而 `gameTime` 不会。记得 `Math.min(Integer.MAX_VALUE, ...)` 防溢出。
  > **置信度**：`SwordArrayEntity.java:86-87` 的实现是**逐字核对过的事实**
  > （`(int)Math.max(0L, Math.min(Integer.MAX_VALUE, getGameTime() - startedAt))`）；
  > 但「卸载后 `tickCounter` 落后、`gameTime` 不落后」这个**后果**是**由代码推出、未实测**——
  > 与 §14.52（14l）的标注保持一致。要把它当结论用，先跑一次「卸载区块 → 重新加载」观测。
- **持续伤害必须按固定间隔（`% 8`）结算**：每个已落地剑都每 tick 判一次，代价随剑数线性放大，服务器直接爆。
  「站在阵里持续掉血」= 固定间隔，这是所有持续区域技能的唯一正确写法。

**④ 三个常数决定手感：环数 / 密度 / 内半径**

```java
public static int ringCount(int spellLevel)    { return Math.max(1, spellLevel) + 1; }
public static int swordsForRadius(double r)    { return Mth.clamp((int) Math.ceil(Math.PI * 2 * r / 1.5), 3, 48); }
public static double innerRadius(double halfW) { return Math.max(1.2, halfW * 2.0 + 0.65); }
double offset = baseAngle + ring * Math.PI / count;              // ← 相邻环错开半个扇区
```

- **按周长定数量**（`2πr / 1.5`）：半径变大数量同比增加，**视觉密度恒定**；固定 8 把会让大阵变成稀疏圆点。
- **`innerRadius` 用目标半宽算**：环必须比目标大一圈，否则剑全落在目标本体上，「阵」等于单体命中。
- **`ring * PI / count` 错开**：不错开时各环剑在同一角度排成辐射线，看起来像「一把剑被拉长」。
- **最后补一支 `ring = 0` 直落圆心的剑**：不补的话**目标站在圆心反而完全安全**（内半径恒 > 0），这是必现漏洞。
- **`RING_INTERVAL = 5`**：够看清「层层落地」，又不至于最后一环晚到一秒。

**⚠ `swordsForRadius` 是「单环上限」，不是「总剑数上限」**

`Mth.clamp(..., 3, 48)` 的 `48` 只作用于**一圈**。构造函数里每环独立算数量，**环数本身没有上限**：

```text
构造每一环时：半径 = 内半径 + 环序号 × 1.2        // 1.2 是字面量，与常量 RADIUS_STEP 同值
              数量 = 按半径算的单环数量            // 该函数内部 clamp 到 3..48
```

总量 = Σ(每环数量) + 1（末尾圆心那支）。**环数随 `spellLevel` 线性增长，每环数量随半径线性增长，
两者相乘 → 总量近似平方增长**。`48` 只封住了「单环」这一项，封不住这个乘积。

- 单次施法要在**一个 tick 内**构造出全部 `Sword` 及各自的 `positions[]`（每条 8~15 个 `Vec3`）：
  总量翻倍 = 该 tick 的分配量翻倍，之后每 tick 的 `tickContacts` 遍历量也同比翻倍。
- **本节故意不给具体剑数**：`innerRadius` 由目标 `getBbWidth() * 0.5` 决定（运行时可变），
  `spellLevel` 由调用方传入，两者都不是常量——写死一个「实测 N 把」就是不可复现的假精确。
  要判断量级就现场按上面两行公式算，别抄文档里的数。
- **常量与字面量重复的坑**：第 14 行有 `public static final double RADIUS_STEP = 1.2`，
  但第 33 行用的是字面量 `1.2`。改常量**不会生效**——改环间距必须两处一起改。

修法：**外层再加一条显式总量上限，并在超限时按「由内向外」截断**（内环必留，外环砍掉）：

```java
static final int MAX_TOTAL_SWORDS = 96;                       // ← 与单环 48 是两个独立的量

// 先算全部候选，再按「内环优先」截断，不要边算边砍（否则外环随机缺失，阵型破口）
List<Sword> all = 生成全部;
if (all.size() > MAX_TOTAL_SWORDS) {
    all = new ArrayList<>(all.subList(0, MAX_TOTAL_SWORDS));   // 生成顺序即由内向外
}
```

- **截断必须按「内环优先」**：随机砍会让外环出现缺口，玩家看到的是「阵有洞、伤害漏一片」。
- **总上限与环数上限是两个独立旋钮**：只限环数（`Math.min(ringCount, 6)`）会把「高层级 = 更大范围」的手感砍掉；
  只限总量能保住「高层级更大但更稀疏」的观感。**推荐限总量、按半径动态调 `RADIUS_STEP`**。
- **反例**：先 `swordsForRadius` 再乘环数就以为「有上限了」——这是本节最容易漏的一条，
  因为 48 这个数字看着像个安全阀，实际只保护了单圈。

**⑤ 空间索引：均匀网格，一次建、N 次查**

```java
private static final double CELL_SIZE = 2.0;

private void visit(AABB box, LongConsumer visitor) {
    int minX = cell(Math.max(bounds.minX, box.minX));        // ← 裁剪到 bounds
    int maxX = cell(Math.min(bounds.maxX, box.maxX));
    int minZ = cell(Math.max(bounds.minZ, box.minZ));
    int maxZ = cell(Math.min(bounds.maxZ, box.maxZ));
    for (int x = minX; x <= maxX; x++)
        for (int z = minZ; z <= maxZ; z++)
            visitor.accept((long) x << 32 | (long) z & 0xFFFFFFFFL);   // ← x/z 打包成一个 long
}
```

使用顺序（**这个顺序是关键**）：

```java
AABB activeBounds = 只拼「本 tick 活跃」的剑盒;                       // flying 或 正好到结算 tick 的
SwordArrayCollisionIndex<Entity> index = new SwordArrayCollisionIndex<>(activeBounds);
for (Entity e : level.getEntities(this, activeBounds, e -> !e.isSpectator()))
    index.add(e, e.getBoundingBox().inflate(0.3));                   // ← 先装实体，每个一次
for (每把活跃剑) index.query(剑盒);                                    // ← 再查剑，每把一次
```

- **必须「一次建索引、N 次查」**：每把剑遍历全实体是 48 × 200 = 9600 次 AABB 相交；索引后是 48 × 邻格 2~3 个。
- **`visit` 里先 `Math.max/min` 裁剪**：完全在阵外的盒子会算出 `minX > maxX`，不裁剪会走空循环或负数格。
- **`activeBounds` 只拼活跃剑**：拼全部剑会让索引覆盖整个阵，`getEntities` 返回一堆无关实体，
  再逐剑判交等于白建索引。
- **`(long) x << 32 | (long) z & 0xFFFFFFFFL`**：`x` 为负时 `<< 32` 必须靠 `(long)` 强转，否则 int 移位溢出成同一个 key。
- **`query` 返回 `LinkedHashSet`**：一把剑的盒子跨多格时同一实体会被多次加入，必须去重（`addAll` 到 `Set`）。

**⑥ 位图回收：唯一必须同步的运行时状态**

```java
private BitSet removed = new BitSet();

private void removeSword(int i) {
    this.removed.set(i);
    CompoundTag state = new CompoundTag();
    state.putLongArray("Swords", this.removed.toLongArray());    // ← 位图序列化成 long[]
    this.entityData.set(DATA_REMOVED, state);
}
```

- **为什么位图必须同步、坐标不必**：位置能从 `(seed, age)` 推出来，**「哪把剑已被消耗」推不出来**（依赖运行时命中）。
- **用 `BitSet` 而不是 `List<Boolean>` / `Map<Integer,Boolean>`**：48 位 = 6 字节；`List<Boolean>` 是 48 个 NBT 元素。
- **命中后立刻 `removeSword(i)` 并 `break`**（一把剑只结算一次）；
  用 `contactProxy.isRemoved()` 作为「这一剑已用完」的信号，**不另建标志位**。
- **另配一张 `soundedRings` 位图**（按 `ring` 而不是剑索引）：落地音效每环只放一次，
  否则同 tick 12 把剑落地会叠放 12 次同一音效，音量爆掉。

**⑦ 客户端只做视觉，服务端只做判定**

```java
if (level.isClientSide()) tickVisuals(age);
else { tickContacts(age); if (age >= layout.lifetime()) discard(); }
```

大阵型的粒子必须带预算和轮转起点：

```java
int impactBudget = 24, trailBudget = 8;
for (int step = 0; step < swords.size(); step++) {
    int i = (step + age * 7) % swords.size();        // ← 轮转起点
    ...
}
```

- **`age * 7` 轮转**：固定从 0 开始的话，预算永远被最前面几把吃光，后面的剑**一根粒子都没有**。
- **每 tick 总预算上限**：不封顶时每把 2 粒子 × 剑数，环数一多总量就破百，客户端直接掉帧。
- **`lastVisualAge` 去重**：同一 `age` 只做一次视觉（`tick` 可能被多次调用或 age 跳变）。

**⑧ 包围盒与剔除距离必须自己覆写**

```java
public AABB getBoundingBox() {
    return layout == null ? super.getBoundingBox()
                          : layout.bounds().inflate(1.5).move(position());
}

public boolean shouldRenderAtSqrDistance(double d) {
    double range = 96.0 + layout.bounds().getSize() * 0.5;
    return d < range * range;
}
```

- **`layout.bounds()` 在构造时把所有轨迹点并成一个总 AABB**：默认 `Projectile` 包围盒只有 0.5 格，
  而阵型里的剑铺满整片半径 → **远处整块被剔除**（「走近才突然出现一整片剑」），射线/碰撞查询也会漏检。
- **剔除距离用 `bounds` 尺寸扩展**：固定 96 格对大阵型不够，尤其是轨迹从 8 格高处落下时。

**⑨ 存档只存参数，重建走 `onSyncedDataUpdated` 唯一入口**

```java
protected void addAdditionalSaveData(CompoundTag tag) {
    tag.put("Layout", this.entityData.get(DATA_LAYOUT).copy());        // 只有 seed/level/radius/startedAt
    tag.put("RemovedSwords", this.entityData.get(DATA_REMOVED).copy());
    tag.putFloat("Damage", this.damage);
}
```

- **`readAdditionalSaveData` 只回填 `entityData`，不直接 `new SwordArrayLayout(...)`**：
  `onSyncedDataUpdated` 是**唯一重建入口**，这样读档、网络同步、`/data merge` 改值走同一条路径，
  不会出现「读档后布局与服务端不一致」。
- **`copy()` 不能省**：直接 `put` 共享的 `CompoundTag` 会让存档对象与 `entityData` 引用同一份，改一处改两处。
- **`layout == null` 时服务端必须 `discard()`**：客户端可能先收到 tick 后收到 `DATA_LAYOUT`，
  服务端则说明数据丢了。**判空后走「结束」而不是抛 NPE**（降级优先，§14.50）。

**一句话**：阵型 = `(seed, level, radius, startedAt)` → 布局；布局 → 轨迹数组；`age` → 每把剑的位置与是否结算；
命中 → 位图。**四样东西全部可重建、可序列化、无状态机**，换任何形态（箭雨/地刺/符文）只换 `Sword` 的构造算法。

> **下一站**：本节的 A 形态（离散多点）只是三种持续区域形态之一。
> 需要「冲击波扫过一次」「每 N tick 判一次」的另外两种，以及三形态的选型判据、时间源对比、
> 双重节流 lcm 陷阱、`hitTargets` 去重与无敌帧绕过，见 `14l-zone-spells.md` §14.52。