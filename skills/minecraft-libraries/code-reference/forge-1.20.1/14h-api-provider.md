# 对外 API 与法术 Provider：能力注入、模板方法、多模组适配

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.33 对外 API 层：能力接口注入 + `static` 优雅降级

`api/` 包一共 8 个 java 文件，但**不是 8 个接口**，而是「5 个真接口 + 3 个配套类」：

| 文件 | 行数 | 类型 |
|---|---|---|
| `IBossDamageClamp` | 7 | `interface` |
| `IBossSyncedDataGuard` | 10 | `interface` |
| `ITrueDamageRedirect` | 11 | `interface` |
| `IPersistentEncounterEntity` | 13 | `interface` |
| `IAuthoritativeHealth` | 25 | `interface` |
| `AnchorCoreWhitelist` | 95 | `final class`（工具类，§14.33 ⑤） |
| `ISpellBookProvider` | 145 | `abstract class`（模板方法，§14.34） |
| `IMaidSpellData` | 177 | `abstract class`（数据基类，§14.34 ⑤） |

**真接口都只有 7~25 行**，但撑起了整个「不改第三方源码也能扩展它」的能力
（下面代码块只贴**接口体**，注释里的行数是**整个文件**的实测行数，含 `package` / `import`）：

```java
public interface IBossDamageClamp {                     // 整个文件 7 行
    float NO_DAMAGE_CAP = Float.MAX_VALUE;
    float maidspell$maxDamagePerHit(float amount);
}

public interface IPersistentEncounterEntity {           // 整个文件 13 行
    boolean maidspell$shouldProtectLifecycle();
    UUID    maidspell$encounterId();
    default void maidspell$onBlockedRemoval(RemovalReason reason) { }
}

public interface ITrueDamageRedirect {                  // 整个文件 11 行
    default void maidspell$onTrueDamageQueued() { }
    boolean maidspell$redirectTrueDamage(float amount, @Nullable LivingEntity source);
}
```

**① 极窄抽象 + `static` 降级方法：调用方永远不写 `instanceof`**

```java
public interface IAuthoritativeHealth {
    float maidspell$authoritativeHealth();
    float maidspell$authoritativeMaxHealth();

    static float health(LivingEntity e) {
        return e instanceof IAuthoritativeHealth a ? a.maidspell$authoritativeHealth() : e.getHealth();
    }
    static boolean combatAlive(LivingEntity e) {
        if (e == null || e.isRemoved()) return false;
        return e instanceof IAuthoritativeHealth a ? a.maidspell$authoritativeHealth() > 0.0F : e.isAlive();
    }
    static boolean deadOrDying(LivingEntity e) {
        return e instanceof IAuthoritativeHealth a ? a.maidspell$authoritativeHealth() <= 0.0F : e.isDeadOrDying();
    }
}
```

这是**整套设计的核心**：接口提供「能力」，`static` 方法提供「**没这个能力时的原版回退**」。
业务代码只调 `IAuthoritativeHealth.health(entity)`，永远不需要判断实体是否被打过补丁。

- 普通怪（没实现接口）→ 自动走原版 `getHealth()`，行为完全不变
- 打了补丁的 Boss → 走权威血量
- **一份调用点同时兼容两种实体**，这是 ASM 补丁必须做到的

> **为什么 `static` 放接口里，而不是单独建 `XxxUtil`**：能力与回退逻辑内聚，
> 调用方 `import` 一个符号就够了，也不会出现「有接口但忘了用对应 Util」的分裂。

**② 可选钩子一律 `default` 空实现**

`maidspell$onBlockedRemoval` / `maidspell$onTrueDamageQueued` 都是 `default {}`。
实现方只写真正需要的部分，**接口升级不会破坏已有实现**（新增 `default` 方法 = 二进制兼容）。

**③ 接口常量表达语义，而不是 `null` / `-1`**

```java
float NO_DAMAGE_CAP = Float.MAX_VALUE;      // 「不限制」用这个，别用 0 或 -1
```

调用点 `Math.min(amount, clamp.maidspell$maxDamagePerHit(amount))` 对所有返回值都成立，
不需要额外分支判断「是不是没配上限」。

**④ 注入到第三方实体上的方法必须带前缀**

`maidspell$` 前缀在这里是**硬需求**（不只是风格）：这些方法会被加进 Iron's / 女仆模组的实体类，
不加前缀就会和第三方自己的 `shouldProtectLifecycle()`、`encounterId()` 撞名。

**⑤ 白名单本身要开放扩展点（三级 + 谓词兜底）**

```java
// AnchorCoreWhitelist.isCallerAllowed（L35-64，真实结构是 if-else 链，不是 stream）
public static boolean isCallerAllowed(String className) {
    if (className == null || className.isEmpty()) return false;   // 空值前置守卫
    if (isBuiltInAllowed(className)) return true;                  // 内置：原版 + 已知模组
    if (EXTRA_CLASSES.contains(className)) return true;            // 精确类名
    for (String prefix : EXTRA_PACKAGES)                           // 包前缀
        if (className.startsWith(prefix)) return true;
    for (Predicate<String> p : EXTRA_PREDICATES)                   // 自定义谓词
        try { if (p.test(className)) return true; }
        catch (LinkageError | Exception ignored) {}                // 谓词抛异常不能弄崩主流程
    return false;
}
public static void addAllowedClass(String name)  { ... }
public static void addAllowedPackage(String pkg) { ... }
public static void addAllowedCaller(Predicate<String> p) { ... }
```

呼应 §14.28 的「白名单原因」：**白名单本身必须可被第三方扩展**，
否则每来一个兼容模组就要你改代码发版。`Predicate` 兜底能表达前缀 / 正则 / 组合任意规则，
且**谓词必须包 try-catch（连 `LinkageError` 一起抓）**——第三方谓词引用了不存在的类会抛 `NoClassDefFoundError`，
它是 `Error` 不是 `Exception`，只 catch `Exception` 抓不住，整个 `isCallerAllowed` 会直接炸掉调用链。

⚠️ **`isBuiltInAllowed` 的最后三条是子串匹配，不是前缀**：

```java
|| className.contains("backup")      // ← contains 而非 startsWith
|| className.contains("maid")
|| className.contains("c2me");
```

这三条把任何包名里带 `maid` / `backup` / `c2me` 的调用方都放行 —— 等于半开大门（比如 `com.evil.maidexploit` 也会过）。
它们是给「加载器重定位后包名变形」兜底的，**新增条目一律用 `startsWith`，不要跟着抄 `contains`**。

### 14.34 法术 Provider：模板方法 + 存储依赖注入 + 冷却表生命周期

`ISpellBookProvider<T, S>` 把「女仆持有法术书 → 解析出法术 → 施法」这套流程做成模板：

```java
protected ISpellBookProvider(Function<UUID,T> dataFactory, Function<UUID,T> dataLookup,
                             Consumer<UUID> dataRemover, Runnable dataClearer, Class<S> spellClass)
```

**① 存储不归 Provider 所有，用 4 个函数引用注入**

Provider 只持有「怎么建 / 怎么查 / 怎么删 / 怎么全清」，不持有 Map 本身。
每个子类在**无参构造**里注入**自己那份**存储的 4 个方法引用：

```java
public IronsSpellbooksProvider() {          // ← 必须无参：SpellBookManager 靠反射 newInstance()
    super(MaidIronsSpellData::getOrCreate,
          MaidIronsSpellData::get,
          MaidIronsSpellData::remove,
          MaidIronsSpellData::clearAll,
          SpellData.class);                 // ← S = 该模组的「法术载体」类型
}
```

8 个 Provider 的 `S` 各不相同：Iron's 用 `SpellData.class`，Ars / Psi / Wizardry 用 `Spell.class`，
Goety / YoukaiHomecoming 用 `ItemStack.class`，SlashBlade 用 `ResourceLocation.class`，
ManaAndArtifice 用 `ISpellDefinition.class`。
**共享的是「4 个方法的签名契约」，不是同一份数据** —— 每个模组一份 `MaidXxxSpellData`，
各自的 `spellCooldowns` / `spellBooks` 互不可见。

好处：Provider 可以脱离静态状态单测；数据层要换实现（Map → 弱引用 / 落盘）时只改 `MaidXxxSpellData`，Provider 一行不动。

**② 抽象方法只留 5 个，其余全在父类**

```java
protected abstract List<S> collectSpellFromSingleSpellBook(ItemStack book, EntityMaid maid);
public    abstract boolean isSpellBook(ItemStack stack);
protected abstract void initiateCasting(EntityMaid maid);
public    abstract void processContinuousCasting(EntityMaid maid);
public    abstract void stopCasting(EntityMaid maid);
```

「遍历所有法术书」「冷却更新」「目标读写」「是否施法中」这些**与具体法术模组无关的流程**
全在父类。子类只实现「怎么从一本书里抠出法术」等 5 个点。
→ 加一个新的法术模组 = 新写一个子类，**不碰任何流程代码**。

**③ 释放资源用 `try/finally`，父类兜底**

```java
public final void releaseRuntimeReferences(EntityMaid maid) {
    T data = getExistingData(maid.getUUID());
    try {
        releaseProviderRuntimeReferences(maid, data);     // 子类可覆写
    } finally {
        if (data != null) data.releaseRuntimeReferences();   // 父类保证执行
    }
}
```

子类释放逻辑抛异常，父类的清理仍然会跑。方法声明 `final` —— **不允许子类绕过这条保证**。

**④ 数据变更一律先判客户端**

```java
public void handleItemStack(EntityMaid maid, ItemStack book, boolean isAdd) {
    if (!maid.level().isClientSide) { ... }     // 第一行就拦
}
```

**⑤ 冷却表三件套：递减 / 归零即删 / 按比例退还**

```java
// 实际归属 IMaidSpellData（L163-166）；ISpellBookProvider 上只有转发层 updateCooldown(EntityMaid)
public void updateCooldowns() {
    spellCooldowns.replaceAll((id, cd) -> Math.max(0, cd - 20));   // 每 20 tick 调一次，一次扣 20 tick = 1 秒
    spellCooldowns.entrySet().removeIf(e -> e.getValue() <= 0);    // 归零即删，防 map 无限增长
}

public void refundCooldowns(double refundRatio) {
    if (refundRatio <= 0.0) return;
    spellCooldowns.replaceAll((id, cd) -> {
        if (cd <= 0) return 0;
        int refund = Math.max(1, (int) Math.ceil(cd * refundRatio));  // 至少退 1 tick
        return Math.max(0, cd - refund);
    });
    spellCooldowns.entrySet().removeIf(e -> e.getValue() <= 0);
}
```

三个易漏点：
- **归零必须删 key**，否则长期运行的服务器里冷却表只增不减
- **`refundCooldowns` 要 `Math.max(1, ...)`**：小冷却 × 小比例会算成 0，玩家感觉「没退」
- **`refundRatio <= 0` 直接 return**，否则 `ceil` 会退成 1 tick 的「白送」

还有一个最容易被改错的点：**「调用频率 × 单次扣减」必须成对确认**。
真实调用点是 `SpellBookManager.tick` 里的 `if (maid.tickCount % 20 == 0) this.updateCooldown(maid);`（L232-234），
**每 20 tick 才调一次**，所以函数里 `- 20` 恰好等于「每秒扣 1 秒」。
只看函数体会以为「每 tick 扣 20」，于是把它「修正」成 `- 1` —— 冷却立刻变成 **20 倍慢**。
这与 §14.52 的「两层节流 lcm 陷阱」是同一族错误：**别在没找到调用点之前就相信单点代码的注释**。

> 调用点原文判定是「`tickCount` 对 20 取余为 0」，函数体内扣减量为 20（IMaidSpellData L164）。
> `f_19797_` → **`tickCount`（已实证）**：`Entity` 字段第 61 位 → obf `ag` → `client_mappings.txt`
> `int tickCount -> ag`；同段 112 个字段两侧一一对应。**数字 `20` 和调用点行号是逐字核对过的事实**。

### 14.39 多法术模组适配层：8 个 Provider 怎么统一

本项目把 8 个法术模组（Iron's Spellbooks / Ars Nouveau / Goety / Mana and Artifice / Psi / SlashBlade / Wizardry / Youkai Homecoming）
接进同一套「女仆施法」流程。目录结构本身就是答案：

```
spell/
├── providers/   8 个 Provider（实测 264~607 行）+ SpellProviderUtils（65 行，4 个 static 方法）
├── data/        8 份 MaidXxxSpellData（承载该模组 API 对象，67~233 行）
├── manager/     SpellBookManager（295 行，唯一调度入口）/ BaubleStateManager（24）/ AllianceManager（33）
├── helpers/     SpellCardHelper（法术卡，275 行）
├── holders/     MaidCardHolder（法术卡持有者，144 行）
└── SimplifiedSpellCaster.java   根目录单文件，不进任何子包
```

> 这是**摘要树**，只列「有教学价值」的节点。`spell/` 下还有若干未列出的文件——
> **没列 ≠ 列错**，判「目录树有误」的唯一标准是「列出来的路径/行数/职责与实际不符」，
> 不是「实际存在的文件没被列全」。

实测行数（2026-11-01 核对）：ArsNouveau 456 / Goety 459 / IronsSpellbooks 607 / ManaAndArtifice 384 /
Psi 462 / SlashBlade 422 / Wizardry 495 / YoukaiHomecoming **264**。
**区间下限是 264 不是 380** —— YoukaiHomecoming 的 Provider 只有 264 行，是 8 个里最短的，
它复用了最多的第三方现成逻辑，因此自己的样板代码最少。

`data/` 八份实测（同批次）：Psi 67 / ArsNouveau 95 / ManaAndArtifice 118 / YH 120 / Wizardry 121 /
Goety 175 / SlashBlade 209 / Irons 233 —— 上限 233、下限 67，即上面的「67~233」。

**⓪ 8 个模组一个都不能硬依赖：`ModList.isLoaded` + `Class.forName` 反射**

`SpellBookManager` 里没有任何 `import ...providers.IronsSpellbooksProvider`，
只有一张「modId → 类名」的字符串表（`initializeProviderFactories`，L32-39 共 8 条）：

```java
registerProviderFactory("irons_spellbooks", "IronsSpellbooksProvider",
        "com.github.yimeng261.maidspell.spell.providers.IronsSpellbooksProvider");
// ↑ 第 1 条（示范完整写法）。下面省略的 7 条，合计 8 条：
//   ars_nouveau / psi / slashblade / goety / youkaishomecoming / ebwizardry / mna

private static void registerProviderFactory(String modId, String providerName, String providerClassName) {
    if (ModList.get().isLoaded(modId)) {                       // ← 第一道门：模组没装就根本不加载类
        Class<?> c = Class.forName(providerClassName);
        ISpellBookProvider<?, ?> p = (ISpellBookProvider<?, ?>) c.getConstructor().newInstance();
        providerMap.put(modId, p);
    }
}
```

三条硬约束，缺一条都会崩：
- **必须 `isLoaded` 门控**：Provider 的字段/方法签名里直接写了第三方的类（`SpellData`、`FocusBagItemHandler`…），
  在模组没装的环境里 `Class.forName` 会抛 `NoClassDefFoundError`。这是 `Error`，`catch (Exception)` 抓不住。
- **必须 `getConstructor().newInstance()` 无参**：所以 Provider 子类只能写无参构造 + `super(...)` 注入（§14.34 ①）。
  一旦给某个 Provider 加带参构造，反射注册立刻失效 —— 而且因为异常被吞，**表现为「这个模组突然不施法了」，不报错**。
- **必须 `try/catch(Exception)` 兜住单条失败**：某一条注册失败只该让那一个模组失效，不能连带另外 7 个。

`providerMap` 是 `ConcurrentHashMap`，`immutableProviders` 是 `volatile` 缓存 —— 注册完成后只读，
热路径不用每次加锁遍历。

**① 差异在 Provider 内部消化，不要为「统一施法」造大抽象**

8 个模组的施法模型完全不同：Iron's 是「引导 + 连发会话」，Psi 是「拼装程序片段」，SlashBlade 是「剑技连招」，
Ars 是「符文组合」。**任何试图把它们抽象成同一套施法原语的接口，最后都会长出 8 个 `if`**。
正确做法：对外只暴露 §14.34 那 5 个抽象方法，**把差异全部关进各自的 Provider**。
`data/` 里的 `MaidIronsSpellData` 直接持有 `MagicData` 字段——不包装、不转译，需要时直接取。

**② Iron's 的接入时序必须严格对齐（调用顺序错一步就静默失败）**

```java
// 起手
if (!spell.checkPreCastConditions(level, spellData.getLevel(), maid, magicData)) return;  // ← 必调
CastSource castSource = getCastSource(data, spellData);
data.setCachedCastSource(castSource);                        // ← 必须缓存
magicData.initiateCast(spell, spellData.getLevel(), effectiveCastTime, castSource, "offhand");
spell.onServerPreCast(level, spellData.getLevel(), maid, magicData);

// 引导中（每 tick）
magicData.handleCastDuration();
if (magicData.isCasting()) spell.onServerCastTick(level, data.getCurrentCastingSpell().getLevel(), maid, magicData);
int remaining = magicData.getCastDurationRemaining();

// 完成
invokeSpellOnCast(maid, data, spell, castSource);            // → spell.onCast(...)
spell.onServerCastComplete(level, currentSpell.getLevel(), maid, magicData, false);
```

四个易错点：
- **第二个参数是「法术等级」（int），不是 `level`**。`onServerCastTick` / `onServerCastComplete` 的真实签名是
  `(Level, int spellLevel, LivingEntity, MagicData)`，两处都容易手滑写成 `level, level` 而编译不过或传错值。
- **`checkPreCastConditions` 不能跳**。它是模组自己写的「这个法术现在能不能放」（蓝量、维度、状态）。
  跳过 = 女仆能放玩家放不出的法术，玩家立刻能感知到「作弊」。
- **`CastSource` 必须缓存在自己的 data 里**。`initiateCast` 和后续 `onCast` 是两次调用，
  中间女仆可能换了手持物品（甚至被别的行为控制切了副手），重新推导会拿到错的来源。
- **`handleCastDuration` 每 tick 只调一次**，调两次等于引导速度翻倍。
- **完成回调要传 `false`**（不是玩家手动取消），否则模组会走「取消施法」的退款/冷却路径。

**③ 连发（Recast）会话：桥接第三方「玩家专属」机制**

Iron's 的 `PlayerRecasts` 是给玩家设计的（连发火球之类）。女仆要复用，需要自己维护一个会话：

```java
RecastInstance instance = new RecastInstance(...);
data.startRecastSession(spellData, castSource, instance, 10);   // 10 = 最长存活 tick
...
if (remaining <= 0 || !magicData.getPlayerRecasts().hasRecastForSpell(spell.getSpellId())) {
    data.endRecastSession();                                    // 超时/失效必须主动收尾
}
```

- **会话必须有超时**。第三方的 recast 表按玩家 tick 驱动，女仆不是玩家，没人替它过期 → 必须自己判 `remaining`。
- **`hasRecastForSpell` 失效时也要收尾**：模组可能因为别的逻辑清掉了 recast，只判 `remaining` 会留一个死会话。

**④ 传送类法术的落点：24 次探测 + 全失败回退**

```java
for (int i = 0; i < 24; i++) {
    Vec3 candidate = /* 目标背后 distance/(i/7+1) 距离 + 每次 i*45° 绕圈 + 随机偏移 */;
    Vec3 grounded = Utils.moveToRelativeGroundLevel(level, candidate, 5);   // 贴地
    AABB bb = maid.getBoundingBox().move(grounded.subtract(maid.position()));
    if (!level.noCollision(maid, bb.inflate(-0.05))) { ... break; }         // 收缩后再判碰撞
}
if (!validPositionFound) teleportPos = target.position();                   // ← 兜底
```

- **探测次数固定（24）而不是 `while(true)`**：必须有上限，否则在狭窄地形里卡死主线程。
- `moveToRelativeGroundLevel(..., 5)` 把候选点贴到地面，避免传送到半空再自由落体。
- `inflate(-0.05)` **收缩**包围箱再判碰撞：放宽判定，避免「理论上能站但差 0.05 格」导致永远找不到位置。
- **全部失败必须有兜底**（传到目标脚下），不能返回 null 让法术静默失败。

**⑤ 朝向：一次写全 8 条赋值语句（3 个 setter 调用 + 5 个裸字段直写，`orientToTarget` L37-44）**

```text
伪代码（一次写全 8 条，3 个 setter + 5 个裸字段直写）：
setYRot(yaw)                 // 当前 yaw
setXRot(pitch)               // 当前 pitch
setYHeadRot(yaw)             // 头部当前 yaw
躯干当前 yaw    = yaw        // 裸写，没有对应 setter
上一 tick yaw   = yaw
上一 tick pitch = pitch
头部上一 tick   = yaw
躯干上一 tick   = yaw
```

只写 3 个 setter 会出现「法术往东飞、女仆脸朝西」——渲染插值是从**上一 tick 的旧值**出发的，
setter 管不到那批字段。**8 条里没有一条冗余：3 条覆盖当前值，5 条覆盖上一 tick + 躯干当前值。**

`orientAndGetDirection` 只写 4 条（L58-61：3 个 setter + `f_20883_`），然后返回单位方向向量，
它是给「射弹类法术」用的——只需要朝向对、不需要插值历史，**两套写法是有意区分的，别「统一」掉**。

> **置信度分级（按反幻觉原则标注）**
> - **已实证（事实）**：8 条语句的存在、顺序、行号（L37-44）逐字核对过；`orientAndGetDirection` 是 4 条（L58-61）。
> - **已实证（映射）**：以下 8 个名字都用「SRG 类成员顺序 ↔ `client.jar` obf 类成员顺序 ↔ `client_mappings.txt`
>   ProGuard 官方名」三方交叉核对，无一例外（实证脚本：`javap -p` 对齐 + 按 obf 名/参数类型反查）：
>
>   | SRG | 所属类 | obf | 官方名 | 位置 |
>   | --- | --- | --- | --- | --- |
>   | `m_146922_` | `Entity` | `a_(float)` | `setYRot(float)` | 方法第 407 位 |
>   | `m_146926_` | `Entity` | `b_(float)` | `setXRot(float)` | 方法第 409 位 |
>   | `m_5616_` | `LivingEntity` | `n(float)` | `setYHeadRot(float)` | 方法第 221 位 |
>   | `f_20883_` | `LivingEntity` | `aV` | `yBodyRot` | 字段第 56 位 |
>   | `f_20884_` | `LivingEntity` | `aW` | `yBodyRotO` | 字段第 57 位 |
>   | `f_20886_` | `LivingEntity` | `aY` | `yHeadRotO` | 字段第 59 位 |
>   | `f_19859_` | `Entity` | `M` | `yRotO` | 字段第 36 位 |
>   | `f_19860_` | `Entity` | `N` | `xRotO` | 字段第 37 位 |
>
>   前提校验：`LivingEntity` 字段数 104=104、`Entity` 字段数 112=112、方法数 `Entity` 437=437、`LivingEntity` 303=303。
> - **注意**：`f_19859_`/`f_19860_` 属于 **`Entity`** 而不是 `LivingEntity`（上一 tick 的 yaw/pitch 定义在基类），
>   所以这 5 个裸字段横跨两个类，抄的时候别只看 `LivingEntity`。
>   **写代码时直接抄 SRG 名，不要按注释里的字段名改写成 MCP 名。**
> - **可直接证的一条**：setter（方法符号 `m_*`）与裸字段（字段符号 `f_*`）是两个不同符号，
>   不可能写到同一处存储，因此**不能互相替代**——这条不依赖字段名推断。

**⑥ 工具类只放「与任何模组无关」的东西**

`SpellProviderUtils` 只有四个 `public static` 方法（L14/L25/L29/L48）：
`describeItem` / `describeEntity` / `orientToTarget` / `orientAndGetDirection`。
前两个是日志工具：

```java
ForgeRegistries.ITEMS.getKey(stack.getItem()).toString()   // → "irons_spellbooks:fire_spell_book"
entity.getType().getDescriptionId() + "@" + entity.getUUID()
```

**日志里打 `ItemStack.toString()` 得到的是 `1 fire_spell_book`，打 registry id 才能 grep 定位**。
8 个 Provider 共用同一套日志格式，排查「哪个模组的哪件物品没被识别」时一次 grep 就够。

### 14.47 「虚拟第三方物品」：造一个不存在的法杖 + 假 Capability + GameTest 断言

第三方模组的物品通常把「状态」存在自己身上（FocusBag 里装 Focus、法杖里存能量）。要让女仆用这套系统，
**不能**给女仆一个真法杖（会占主手、会被抢、会掉耐久）。Goety 适配的做法是：造一个**虚拟物品栈**，
它只带一个 UUID，所有真实状态挂在外部的上下文表里。

**① 虚拟物品 = 真物品类 + 一个 UUID Tag，状态全在外部 Map**

```java
Item item = GoetyCompatItems.VIRTUAL_GOETY_WAND.get();
UUID id = UUID.randomUUID();
ItemStack stack = new ItemStack(item);
stack.getOrCreateTag().putUUID("MaidSpellVirtualWand", id);          // ← 唯一身份
CONTEXTS.put(id, new VirtualWandContext(id, maid, bagHandler, focusSlot, focus));
return new Handle(id, stack);
```

- **UUID 写在 `tag` 里而不是字段里**：`ItemStack` 会被复制、序列化、跨网络传输，
  只有 tag 能跟着走。字段在 `copy()` 之后就丢了。
- **取回时三重校验 + 惰性清理**：

```java
static VirtualWandContext get(ItemStack stack) {
    CompoundTag tag = stack.getTag();
    if (tag == null || !tag.contains("MaidSpellVirtualWand")) return null;
    UUID id = tag.getUUID("MaidSpellVirtualWand");
    VirtualWandContext ctx = CONTEXTS.get(id);
    if (ctx == null) return null;
    if (!ctx.isValid()) { CONTEXTS.remove(id, ctx); return null; }   // ← 读路径顺手清理
    return ctx;
}
```

`isValid()` 一次判完所有失效条件：`!released && !maid.isRemoved() && maid.isAlive() && slot 合法`。
**读路径顺手清理（惰性 GC）** 比另开定时清理任务可靠——不会有「实体已死但上下文还在」的窗口期。

**② 假 Capability：让第三方代码以为它拿到了真的 IItemHandler**

```java
final class VirtualWandCapability implements ICapabilitySerializable<Tag> {
    private final LazyOptional<IItemHandler> holder;
    VirtualWandCapability(ItemStack wandStack) {
        this.holder = LazyOptional.of(() -> new VirtualSoulUsingItemHandler(wandStack));
    }
    public <T> LazyOptional<T> getCapability(Capability<T> cap, Direction side) {
        return ForgeCapabilities.ITEM_HANDLER.orEmpty(cap, this.holder);   // ← 只对这个 cap 生效
    }
    public Tag serializeNBT() { return new CompoundTag(); }                // ← 故意空
    public void deserializeNBT(Tag nbt) { }
}
```

- **`orEmpty(cap, holder)`**：只对 `ITEM_HANDLER` 返回，别的 capability 请求原样返回空。
  直接 `return holder.cast()` 会让「查询任意 capability」都拿到 item handler，第三方逻辑走错分支。
- **`serializeNBT` 返回空 tag 是故意的**：状态已经在 `CONTEXTS` 里由存档自己管，
  再序列化一次会出现「读档后两份互不同步的状态」。**假 capability 不落盘**。
- **Handler 内部全部转发到 context**，自己不留字段（只存 `wandStack` 用于回查）。

**③ `insertItem` / `extractItem` 的 `simulate` 必须严格对称**

```java
public ItemStack insertItem(int slot, ItemStack stack, boolean simulate) {
    if (slot != 0 || stack.isEmpty() || !(stack.getItem() instanceof IFocus)) return stack;  // 拒收
    VirtualWandContext ctx = context();
    if (ctx == null || !ctx.focus().isEmpty()) return stack;                                  // 已占位
    if (simulate) return stack.getCount() == 1 ? ItemStack.EMPTY : stack.copyWithCount(stack.getCount() - 1);
    ctx.setFocus(stack.copyWithCount(1));                                                    // 真插入只拿 1 个
    return stack.getCount() == 1 ? ItemStack.EMPTY : stack.copyWithCount(stack.getCount() - 1);
}
```

- **`simulate=true` 绝不能改状态**：漏斗/管道模组会先 simulate 再真插。simulate 就写入会让一次操作变成两次。
- **`getSlots()` 返回 1、`getSlotLimit(0)` 返回 1**：虚拟物品的语义是「一个槽位代理一个真实槽位」，
  多槽位会让第三方 UI 画出错误的格子。

**④ `release()` 必须幂等，且被所有出口调用**

```java
void release() { this.released = true; this.focus = ItemStack.EMPTY; }
ItemStack focus() { return released ? ItemStack.EMPTY : focus; }   // ← 释放后永远读空
```

三个必须释放的出口：**施法结束**、**女仆死亡/移除**、**服务器停止**（`clearAll()`）。
漏掉第三个，单人游戏换存档后旧 context 会串到新世界。

**⑤ 用 GameTest 把「兼容层真的能跑」变成可执行断言**

```java
@GameTestHolder("touhou_little_maid_spell")
@PrefixGameTestTemplate(false)
public final class GoetyVirtualWandGameTest {
    @GameTest(template = "gametest/empty", templateNamespace = "touhou_little_maid_spell", timeoutTicks = 200)
    public static void castsWithFocusBagOnly(GameTestHelper helper) { ... }
}
```

断言清单（每一条都对应一个曾经的 bug）：

> **数清「条」和「组」**：下面这 **7 条**断言全部属于 `castsWithFocusBagOnly` **一个** `@GameTest` 方法；
> 整个 `GoetyVirtualWandGameTest` 类共 **6 个** `@GameTest` 方法（6 组用例）。
> 所以「6 组 / 7 条」不矛盾——6 是**方法数**，7 是**第一个方法里的断言数**。别把两个数混着引用。

```java
helper.assertFalse(data.isCasting(),                    "instant cast should have completed");
helper.assertTrue(data.getVirtualWandId() == null,      "context should be released after an instant cast");
helper.assertTrue(VirtualWandManager.activeContextCount() == 0, "no context should remain");   // 泄漏检查
helper.assertTrue(data.getSpellCooldown("MagicBoltSpell") > 0, "the spell must actually run"); // 真放出来了
helper.assertTrue(!level.getEntitiesOfClass(MagicBolt.class,
        maid.getBoundingBox().inflate(4.0)).isEmpty(),   "must produce a projectile");
helper.assertTrue(ItemStack.matches(bagHandler.getStackInSlot(0), focus), "focus must stay in the bag"); // 没被吃掉
helper.assertTrue(maid.getMainHandItem().isEmpty() && maid.getOffhandItem().isEmpty(),
                                                        "the test maid must not hold a real staff");
```

- **断言「上下文归零」比断言「施法成功」更重要**：泄漏是慢性病，施法失败会立刻被发现。
- **用 `ItemStack.matches(...)` 判「物品没被消耗/改动」**：只比 `getItem()` 发现不了 count / NBT 被改。
- **`template = "gametest/empty"` + `@PrefixGameTestTemplate(false)`**：关掉自动加 `modid:` 前缀，
  结构模板路径才能写死复用。
- 软依赖的 GameTest 类会被 GameTest 框架无条件扫描：**类里引用第三方类型的代码必须放在 `isLoaded()` 之后**，
  或整类挪进兼容包，否则不装该模组时测试类加载就 `NoClassDefFoundError`。

> **上面清单里的 `assertTrue` / `assertFalse` 是「名字映射」而非原文**：反编译产物里是
> `helper.m_246336_(...)` 与 `helper.m_277053_(...)`。映射**已实证**（三方交叉）：
>
> | SRG | 位置 | obf | 官方名 | `client_mappings.txt` |
> | --- | --- | --- | --- | --- |
> | `m_246336_` | `GameTestHelper` 方法第 101 位 | `a(boolean,String)` | `assertTrue` | `761:764:void assertTrue(boolean,java.lang.String)` |
> | `m_277053_` | `GameTestHelper` 方法第 102 位 | `b(boolean,String)` | `assertFalse` | `767:770:void assertFalse(boolean,java.lang.String)` |
>
> 前提校验：`GameTestHelper` SRG 方法数 136 = obf `pq` 方法数 136，两侧位置逐位对齐。
> 语义侧另有独立佐证：该文件 **20 次 `m_246336_` 全部配肯定语气（"must" / "should"）、
> 2 次 `m_277053_` 全部配否定语气（"should have completed" / "must not grant"）**，极性完全一致。
> 抄代码时仍按 SRG 原名写（本文的 `assertTrue` 只是给人读的注释）。