# 反编译阅读法：定位入口、软依赖、诊断顺序、世界生成与私有维度初识

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.1 先找 mods.toml，找不到就去内层 jar

**双层嵌套 jar 的迹象**：外层 jar 的 entry 极少（实测仅 18 个），`META-INF` 里只有 `MANIFEST.MF`，
其余全是 `bootstrap/` 下的几个类，且存在：

- `META-INF/services/cpw.mods.modlauncher.api.ITransformationService`
- `META-INF/services/net.minecraftforge.forgespi.locating.IModLocator`

这说明**外层只是壳**，真模组在嵌套 jar 里（如 `META-INF/<name>/<name>-mod.jar`，实测内层 1593 个 entry）。
`mods.toml`、`mixins.json`、`assets/`、`data/` **全在内层**——软硬依赖、`mandatory`、版本范围只在内层能找到。

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[System.IO.Compression.ZipFile]::OpenRead($jar)
$e=$zip.Entries | Where-Object { $_.FullName -eq "META-INF/mods.toml" }
if($e){ $sr=New-Object System.IO.StreamReader($e.Open()); $sr.ReadToEnd(); $sr.Close() }
$zip.Dispose()
```

外层壳的用途通常是**抢在模组代码加载前做 ASM 改写**（实测类名 `HurtHeadTransformationService` +
`HurtMethodTransformer` + `ClassHeader`，即在类加载期重写 `LivingEntity.hurt` / `m_6469_`，共 514 行）。
看到 bootstrap 里出现 `*TransformationService` / `*ClassHeader` / `*MethodTransformer`，基本可判定它插了字节码钩子。

> **别按文件名 grep 这三个词，会扑空。** 本库 `src-bootstrap` 里**只有一个 .java 文件**——
> `HurtHeadTransformationService.java`（514 行），`ClassHeader`（L469）和 `HurtMethodTransformer`（L476）
> 都是它内部的 `private static final class`，不是独立文件。看到「类名存在但文件不存在」时先想到嵌套类，
> 再想到内部类/匿名类，最后才怀疑文档写错。

> **风险等级：这是 L2.5，不是 L3。** ModLauncher `ITransformationService` 是 Forge **官方支持**的 coremod 路径
> （Forge 自己的补丁就这么打），不需要 `-javaagent`、不绕 JDK 内部、不反射改 `Unsafe` 静态字段。
> 真正的高危 L3 是「运行时自挂 agent + `retransform`」——库内另有一处（改 `getHealth`），
> 完整分级与判据见 14e2 §14.49。**别把两者都叫「ASM 改写」**：失败模式与降级策略完全不同。

### 14.2 软依赖的两种注册范式（都能规避 NoClassDefFoundError）

**范式 A：反射 Provider 工厂**——适合「多个同类可插拔实现」

```java
private static void registerProviderFactory(String modId, String providerName, String providerClassName) {
   try {
      if (ModList.get().isLoaded(modId)) {              // 先判存在（缺这步 = 不装该模组时类加载就炸）
         Class<?> c = Class.forName(providerClassName); // 再反射取类
         ISpellBookProvider<?, ?> p = (ISpellBookProvider<?, ?>)c.getConstructor().newInstance();
         providerMap.put(modId, p);
      }
   } catch (Exception e) {                              // 单条异常隔离，别让一个模组拖垮其余 7 个
      LOGGER.error("Failed to register provider factory for mod {}: {}", modId, e.getMessage());
   }
}
```

> 第三个参数 `providerName` 只用于日志（`LOGGER.debug("Mod {} loaded, finished {} registration", ...)`）。
> 完整实现见 `SpellBookManager.java` L42-53，8 个调用点 L32-39。**别省成 2 参**——签名对不上时反射调用方全废。

要点：**类名以字符串传入**，编译期不产生符号引用，mod 未装时该类根本不会被加载。
因此公共接口必须抽到**不引用任何第三方类型**的 `api/` 包。

> **该包不是「8 个接口」，是「5 接口 + 3 类」**（`api/` 实测 8 个 .java）：
> 真接口 5 个（`IAuthoritativeHealth` 25 · `IBossDamageClamp` 7 · `IBossSyncedDataGuard` 10 ·
> `IPersistentEncounterEntity` 13 · `ITrueDamageRedirect` 11）；
> 非接口 3 个（`IMaidSpellData` 177 行 `abstract class`、`ISpellBookProvider` 145 行 `abstract class`、
> `AnchorCoreWhitelist` 95 行 `final class`）。**名字带 `I` 不代表是接口**——
> 前两个是模板方法基类（所以「子类实现 5 个抽象方法」成立），第三个是纯静态白名单。
> 详细拆分见 14h §14.33。

**范式 B：Mixin 门控**——适合「必须改第三方类内部」

```java
public class XxxMixinPlugin implements IMixinConfigPlugin {
   private boolean loaded;
   public void onLoad(String pkg) { loaded = LoadingModList.get().getModFileById(modId) != null; }
   public boolean shouldApplyMixin(String target, String mixin) {
      if (mixin.startsWith("...mixin.iss.")) return loaded;   // 按包前缀门控
      return true;
   }
}
```

要点：mixin 按模组**分子目录**（`mixin/iss/`、`mixin/goety/`、`mixin/psi/`…，实测 90 个 mixin 分 13 个目录），
`shouldApplyMixin` 里按包前缀判断。第三方未装时整批 mixin 不应用，不会因找不到目标类而崩。

### 14.3 用 `Class.forName` 探测「目标模组的版本能力」

软依赖不只是「装没装」，还有「装了但版本太老」：

```java
try { Class.forName("com.github.tartaricacid.touhoulittlemaid.api.animation.IMagicCastingAnimationProvider");
      isTlmMagicAnimationSupported = true; }
catch (ClassNotFoundException e) { /* 老版本没有这个接口 */ }
```

比在 `mods.toml` 里硬卡 `versionRange` 更灵活——**按接口存在性做能力开关**，避免因版本号格式差异误判。

### 14.4 世界生成：结构要自己防原版特征切坏

原版洞穴雕刻器、玄武岩石柱、三角洲等特征会在结构生成后**继续改写地形**。实测的防护层次：

- `CarverGuard` / `TerrainFeatureGuard` / `XxxPlacementGuard`：在结构范围内拦截雕刻与特征放置
- `ChunkGeneratorMixin` + `NoiseBasedChunkGeneratorCarverMixin`：直接改生成管线
- `StructureTemplateMixin`：结构模板落地时保护已有方块

判据：模组同时存在 `StructurePiece` 子类与上述 Guard/Mixin，说明它在**自己修原版地形的破坏性**。
这类问题的现象是「结构被切穿、方块悬空、岩浆灌入房间」。

### 14.5 按需私有维度 + 常加载 + 数据保留期

- **每玩家一个独立维度**：`ResourceKey.create(Registries.DIMENSION, new ResourceLocation(MODID, "the_retreat_" + uuid.toString().replace("-","_"))`，另配一个共享维度（同模组 ID 下的固定 location）。
- `ForgeChunkManager.setForcedChunkLoadingCallback` 在 `FMLCommonSetupEvent` 的 `enqueueWork` 里注册，
  **启动时先清空历史 ticket**（`ticketHelper.removeAllTickets(owner)`），防止上次会话的强加载残留。
- **实体卸载后的数据保留期**（实测 `UNLOAD_RETENTION_TICKS = 100`）：`onMaidLeave` 不立即清数据，
  而是记一个 deadline，超时才真删。用于防止区块边界来回横跳把运行时数据洗掉——
  凡「跨区块移动后数据丢失」的 bug，先查这里。

### 14.6 权威状态：别把客户端同步值当判定依据

软依赖模组常见的补丁型接口（实测一个 `api/` 包里就有 4 个）：

| 接口 | 作用 |
| --- | --- |
| `IAuthoritativeHealth` | 服务端权威存活/濒死判定 |
| `IBossDamageClamp` | 单次伤害上限钳制 |
| `ITrueDamageRedirect` | 真伤重定向 |
| `IBossSyncedDataGuard` | 同步数据保护 |

凡出现「Boss 血条与实际不符 / 没死却判死 / 单次扣血超上限」，优先怀疑**客户端同步值被当成了判定依据**。

### 14.7 超大单体类：先核对同包配套类，别急着判 God Class

实测 Boss 实体类 **3930 行 / 161KB**，第一反应是上帝类。但同包 `winefox/` 共 **24 个文件**，
除实体外 23 个配套类（战斗 Goal 1005 行、血量控制器 428 行、招式表 286 行、交易 260 行、对话 233 行、
非致死守卫 156 行……最细的只有 7 行），职责已充分外置，实体只做生命周期编排与状态持有。
**这是合理拆分，不是反模式。**

> **行数口径（重要，本节曾因此出过一次「同文件两个数」的事故）**：本节所有行数都是**总行数（含空行）**，
> 与 SKILL.md 索引、README 总规模的口径一致。
> 早期版本这里曾写 `3463 / 905 / 385 / 262 / 226 / 197 / 139 / 5`，那是**非空行**口径——
> 同一批文件换算后逐一吻合（3930-467=3463、1005-100=905、428-43=385、286-24=262、
> 260-34=226、233-36=197、156-17=139、7-2=5）。**两套数都对，只是口径不同；混着用就变成「矛盾」。**
> 全库统一：**报行数必须报总行数**，引用别处的数字前先确认口径。

注意：实体子类受 `@Override` 约束（`setHealth` / `tick` / `die` / `readAdditionalSaveData` 必须挂在实体上），
骨架代码天然集中在实体类，这个量级可以接受。

**判读纪律**：不要用「某层专业 / 某层稀烂」这种按层的结论给模组定性——**按文件看**。
先按行数列出业务包全部文件，再三看：

| 看哪个文件 | 判据 | 结论 |
| --- | --- | --- |
| **最长的** | 结构最平、只做编排与状态持有；同包有 10+ 个细粒度配套类 | 合理编排，**勿误判**；行数大 ≠ 坏设计 |
| **中等长度、嵌套最深** | 缩进 > 4 层 / 早退缺失 / 同文件多套冷却 | 反模式重灾区，优先改这里（见 §14.10） |
| **最短且最内聚** | 单一职责、命名清晰、无旁路状态 | 可抄的正例，照它的形状写新类 |
| 同包仅 1~2 个文件，招式/音效/粒子/同步全塞实体 | 无配套类可查 | 真上帝类，需拆 |

实测同一模组、同一作者、同一包内同时存在这四类：

- **教科书级**：`WinefoxSwordCombo`(60 行) / `WinefoxAction` / `WinefoxEncounterState` / 施法 Provider 基类 / 区块票据管理器
- **控制流灾难**：`WinefoxCombatGoal`(1005 行，七层嵌套 + 12 套冷却)
- **抄错教程**：`WinefoxHealthState`（`AtomicReference<Float>`）
- **反编译残留未清**：`describeTarget` 里的 `var10000`、空 `else if` 分支

**真正的反模式在同包别处**：一个 1005 行的 `WinefoxCombatGoal` 里 12 套独立冷却字段 + 七层嵌套 if（见 §14.10）。
结论修正：**行数大 ≠ 坏设计；控制流深 + 状态散落才是。**

### 14.8 诊断顺序（读一个陌生模组时）

1. **内层 jar 的 `mods.toml`** → 版本、软硬依赖、`mandatory`
2. **`mixins.json` + `MixinConfigPlugin`** → 它改了谁、门控条件
3. **主类构造器** → 注册顺序、配置分类、`isLoaded` 分支
4. **`api/` 包** → 它对外暴露什么抽象
5. **`compat/<模组>/` 目录文件数** → 哪家兼容最重（实测铁魔法 110 个文件，是主力目标）
6. **`lang/zh_cn.json` 的 key 数** → 内容量级（实测 608 keys / 113 个物品显示名）
7. **业务包的文件数与行数分布**（`Get-ChildItem -Filter *.java | ForEach-Object { 行数 }`）
   → 找出「控制流最深的那个文件」，反模式几乎总在那里，而不是在最长的那个