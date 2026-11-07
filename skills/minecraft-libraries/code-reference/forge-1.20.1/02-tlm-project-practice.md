# 车万女仆扩展 API / 跨模组合成 / 崩溃排查 / 物品与配方实证

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

## 7. 车万女仆（Touhou Little Maid）扩展 API

- 软依赖接入：构造器查 `ModList.get().isLoaded("touhou_little_maid")`，未装则静默，不引用任何女仆类。
- 通过 `@LittleMaidExtension` 注解的扩展类被女仆模组加载时自动实例化（注意构造器里不要 `new` 任何引用女仆类的对象）。
- 扩展点：`registerAIChatSerializer`（AI 对话站点）、`ILittleMaid` 工厂、女仆任务（Behavior/Task）、饰品/餐食兜底。
- `mods.toml` 中把 `touhou_little_maid` 依赖设 `mandatory=false` 保持软依赖；错误标注 `mandatory=true` 会导致无 TLM 时拒绝加载，与代码“静默运行”矛盾。

## 8. 开发期跨模组合成要点

- named/parchment 版 jar 替换发布版 jar 的做法与原理见 §3（`@Shadow` + SRG refmap 冲突及其两种规避），此处不重复。
- 缺失运行时库时，从 Gradle 缓存（`~/.gradle/caches/modules-2/...`）定位 jar，把其真实包前缀（如 `javazoom/`、`org/tritonus/`、`org/yaml/`）注入目标 jar；不要用无关前缀否则注入无效。

## 9. 崩溃与映射排查清单

构建产物与配方的验收、退出码判读统一见 §13「验收闭环」，此处只留崩溃与映射。

- 启动崩溃优先看 `run/logs/latest.log` 的 `Caused by:` 与 `FATAL`。
- 混淆 / “找不到类/字段”多与映射命名空间或模块类加载器隔离有关，先定位是哪个 jar 的类、哪个命名空间。

## 10. 资料核实与来源

- 独立联网核实有效（批次日期见文首「最后校准」）：
  - **mojmap/dev 可读映射 vs SRG 生产**：Forge 官方配置文档（fg-6.x）确认生产运行用 SRG，ForgeGradle 在其上加人类可读映射集。
  - **Mixins dev 重映射**：真实 dev 运行配置含 `mixin.env.refMapRemappingFile = ${projectDir}/build/createSrgToMcp/output.srg`（“srg to mcp 映射文件，用于 mixin 兼容”），佐证 §3 的 srg→mcp refmap 链路。
  - **`@Shadow field ... was not located` 是普遍真实错误**：Forge 论坛多起同款崩溃（含 Sodium/Epic Fight/JEI 相关 mod），机制与 §3 一致。
  - **车万女仆扩展 API**：DeepWiki（TartaricAcid/TouhouLittleMaid）佐证 `ILittleMaid` 扩展点、任务/装备/AI/渲染扩展注册、AI 聊天与 token 同步消息。
  - **SimpleChannel 早期创建**：社区 mod 均采用 `@Mod` 构造器/静态块创建频道的标准模式。
- **本项目实测（未在公开检索复现原文）**：
  - 报错串 `Registration of impl channels is locked` 为本工程 runClient 实测观察，用作诊断线索而非 Forge 规范错误串；根治手段（提前到构造期建频道）符合标准模式。
  - `jar uf` 会破坏第三方 SecureJar 结构、`runtimeOnly` 对第三方模组的 `ModuleClassLoader` 不可见等，为本次开发实证结论。

## 11. 自定义武器/物品交互实证（Forge 1.20.1，本项目）

核心原则：**决定在客户端、执行在服务端**。客户端可靠的本地状态（如 `isShiftKeyDown`、按键/长按）经 SimpleChannel 发 C2S 包，由服务端真正改变世界；据此规避 Item 方法覆写在 SRG 生产空间的命名失配。

- **覆写 vs 事件**：`Item#use`/`getUseAnimation`/`getUseDuration` 等方法有 SRG 别名，ForgeGradle 正确 remap、生产环境稳定（另见 §9）；多帧逻辑用 `TickEvent.PlayerTickEvent` + `@SubscribeEvent`，事件处理器不受 SRG 覆写失配影响。能用事件就别依赖高层交互事件（如 `RightClickEmpty`）的触发时序。
- **右键长按＝自动攻击模型**：非潜行右键 `player.startUsingItem(hand)` 进入长按；每 tick 在 `PlayerTickEvent`(Phase.END，服务端) 用 `player.isUsingItem() && player.getUseItem().equals(主手) && getUseItemRemainingTicks()>0` 判定“正在按住”。松开右键由客户端释放包驱动，服务端 `isUsingItem` 自然置 false，自动攻击随之停止。
- **`UseAnim.BLOCK` 减速陷阱**：返回 BLOCK 会被判成 `isBlocking()`，举起 5 tick 后玩家移速减半——凡冲锋/突进依赖视线速度阈值（如 >4.6 m/s）都会被卡死伤害。需要“举起姿态但不格挡”时用 `UseAnim.NONE`（姿态由持举动作维持）。
- **守卫防递归**：服务端范围攻击若对命中目标 `player.attack()` 会再次进入自身攻击处理器 → 用 `ThreadLocal<Boolean> SWEEP_IN_PROGRESS` 嵌套守卫（先 set，finally 里 remove）防递归。
- **状态机先取后移**：每 tick 先 `get` 冲锋/冲刺状态再判是否 `remove`，切勿“先 remove 再 get”——否则状态永远取不到、对应效果永久失效（实测冲刺碰撞伤害失效根因）。
- **冲锋/冲刺伤害随相对速度**：伤害 = 基础攻击力 + `⌈相对速度 × 材料/蓄力倍率⌉`，随两实体相对速度提升而增加；不要用 `rel>阈值` 整体短路（站桩右键判不上、打不出），也不要硬编码“固定最低伤害”。直接 `target.hurt()`、不触碰玩家攻击冷却 → 冷却期间仍能发动冲锋（基岩版对齐）。
- **第三方长矛库（`ConfiguredSpearItem`）**：用 `SpearStats.Stats` 参数化配置（伤害倍率/击落阈值/各阶段时长/接触冷却/命中框边距/范围），`SpearStats.Stats.of(基底, ...)` 派生新档位；`/give` 走 `new ItemStack(item)` 不经 `getDefaultInstance`，对 ItemStack 注入附魔不可靠 → 改覆写 `performStabAttack` 手动实现“空挥突进”。
- **自定义 sourceSet 独立附属 jar**：多模块模组可建独立 sourceSet 产出独立附属 jar（如 `reobfAddonJar` 产出混淆可发布 jar），单模块编译用 `compileXxxJava`，部署前必跑 reobf，否则正式 Forge 环境 `NoSuchFieldError`。
- **自动化稳定验证**：可用 WebSocket bridge + Python 验收脚本驱动游戏（input: key/look/hold/attack + 读实体 NBT/血量/坐标）做服务端权威回归，缩短“改码→进游戏手测”回路。

## 12. 物品/武器覆写入口速查与维护纪律（编辑代码实证）

**交互链路分工**：左键命中与右键举起是两条独立路径，职责分离更稳——
- 右键：`use()`（唯一可靠入口，SRG 别名 `use_`）做客户端本地决策（`isShiftKeyDown` 是否按下）→ 发 C2S 包 → 服务端进入长按；多帧自动攻击放 `PlayerTickEvent` 按模式分支。
- 左键命中：`hurtEnemy(stack, target, attacker)` 对不同模式做差异化附加效果（如重锤命中额外触发风暴）；长矛/三叉戟左键需“与普通攻击无区别”时不加额外动作即可。

**常用覆写入口**：

| 入口 | 用途 | 备注 |
|------|------|------|
| `use()` | 右键总入口：切模式(shift)/举起(长按) C2S | 客户端决策，服务端发 `pass` 避免重复 |
| `getUseDuration()` | 返回大值(如 72000)支撑 `startUsingItem` 长按 | 靠释放包收尾 |
| `getUseAnimation()` | 举起姿态 | 用 `NONE` 防 `isBlocking()` 减速（见 §11） |
| `onUseTick()` | 长按期间每 tick | 也可放事件总线统一处理 |
| `releaseUsing()` | 松手收尾 | 长按自动攻击一般由 `isUsingItem=false` 自然停止 |
| `hurtEnemy()` | 左键命中差异化附加效果 | 与服务端权威、事件驱动不冲突 |
| `aoeRadius()`/`getDamageMultiplier()` | 范围/伤害参数抽成方法 | 便于统一施加全局约束 |

**维护纪律**（本项目实测反复踩坑）：
- 改交互逻辑**必须同步更新 javadoc**——旧注释会误导后续维护（多处出现 javadoc 与实现脱节）。
- 单通道多动作用**动作枚举**（`SWITCH/USE/THRUST/…`），C2S 只发动作码，避免每动作单独建通道。
- 半径/范围/伤害这类全局规则抽成方法并在**一处**加约束（如 `Math.max(5.0, ...)` 保证范围下限），勿在各模式各处硬编码。
- 冲锋/冲刺等跨 tick 状态用 `record` + `UUID→state` Map 在事件间共享，天然带不可变快照，配 `ThreadLocal` 守卫防递归。
- 加“应与普通攻击一致”的克制型规则时，直接让处理器在对应模式下**返回/不发文**即可（如中和空挥突进），保留注册但清空副作用，比删事件更易回溯。

## 13. 配方链与物品注册（数据驱动实证，本项目）

**升级链范式（3×3 围一圈）**

```json
{"type":"minecraft:crafting_shaped","pattern":["III","IFI","III"],
 "key":{"I":{"item":"<本档材料>"},"F":{"item":"<上一档成品>"}},
 "result":{"item":"<本档成品>"}}
```

- 每档中心放**上一档成品**、外圈 8 格填**本档材料** → 档位天然递进，无法跳级。与 mod 内既有 `AAA/ABA/AAA` 升级配方（工作台/箱子/铁砧等）同构，风格统一。
- 链头（首档无上一档）：用「底座件 + 基础材料」2 格配方起链。例：1.20.1 无原版重锤 → `heavy_core + netherite_ingot` 造 `mace` 作为全链底座，其余档再逐级围锭。
- **反例（本项目原始 bug）**：所有档位复用同一条「沉重核心 + 下界合金锭」2 格配方 → 各档无递进关系，玩家一步拿满最高档，整条升级链形同虚设。**只要出现“多个等级物品配方完全相同”，就是设计事故**。

**跨模组引用纪律（最容易踩的坑）**

- 引用外部 mod 物品（`othermod:xxx`）前，必须确认**该物品真的完成注册**，不能只看贴图/模型在不在：
  - **有 png ≠ 有物品**。判据两条：① 解包 jar 看 `assets/<modid>/textures/item/*.png`、`models/item/*.json` 是否齐全；② 扫 `*.class` 常量池里是否有该注册 ID 字符串（`ITEMS.register("id", ...)` 的 id 会以字符串常量进 class）。
  - 只存在于资源层（有贴图无 class 注册）的物品，配方会因找不到 item 被 Forge **静默跳过**（仅记 warn），现象是「JEI 里这条配方根本不出现」，极易误判成配方 JSON 写错，浪费大量排查时间。
- 无法确认的外部物品，**在自己命名空间补齐同名物品**（`自己modid:ultimate_ingot`）即可让配方可用；日后对方正式注册时只改配方 JSON 里的 `item` 值，不动 Java 代码。
- 命名空间隔离：附属 sourceSet 的配方必须放 `data/<自己的modid>/recipes/`，不要写进主 mod 的 `data/<主modid>/` 污染其数据包。

**物品注册四件套（缺一即露馅）**

| 项 | 位置 | 缺失表现 |
|---|---|---|
| 物品注册 | `init/*Items.java`：`ITEMS.register("id", ...)` | 物品不存在 → 引用它的配方全部失效 |
| 创造栏 | `displayItems` 内 `output.accept(XXX.get())` | 创造栏搜不到（但 `/give` 与配方仍可用） |
| 模型 | `assets/<modid>/models/item/<id>.json` | 紫黑格（缺模型贴图占位） |
| 贴图 | `assets/<modid>/textures/item/<id>.png` | 紫黑格 |
| 本地化 | `lang/{zh_cn,en_us}.json` | 显示裸键 `item.<modid>.<id>` |

- 模型 `parent` 选择：手持类（武器/工具）用 `item/handheld`，普通材料/锭用 `item/generated`。
- 新增物品后**同时**补这五项；只注册不补资源，游戏里就是紫黑方块，且 `build` 不会报任何错。

**JSON 批量写入的 PowerShell 陷阱**

- 写配方 JSON 必须用无 BOM 的 UTF-8：
  `[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))`
  `Set-Content` / `Out-File` 默认带 BOM，带 BOM 的 recipe JSON 在部分环境解析失败。
- Windows PowerShell 5.1 **不支持 `??` 空合并运算符**（报 `ParserError: 意外的标记“??”`），一律改 `if($x){...}else{...}`。
- 终端中文乱码（如 `瓒呯骇X鍏夐敾閫犲彴`）是 GBK 解码 UTF-8 的显示假象，**文件本身没坏**；必须用 `Get-Content -Raw | ConvertFrom-Json` 校验才算真验证（见 §6 同款结论）。

**验收闭环（不启动游戏即可查掉 90% 问题）**

1. `.\gradlew build -x test --console=plain` → 用 `Tee-Object` 落盘日志再 `Select-String` 过滤，避免终端输出被截断看不到真正报错；以 `$LASTEXITCODE` 判成败（`UP-TO-DATE` 行不代表任务没跑）：`exit 1` = BUILD FAILED；`exit 0` 且日志出现 `Setting user` = 已过模组加载，此时运行失败的锅在环境/映射/运行时类装配，不在编译。
2. 解包产物 jar 核对条目：配方总数、每个新增 recipe 文件、`models/item/*.json`、`textures/item/*.png` 是否齐全。
3. 扫 `init/*Items.class` 常量池，确认新注册 ID 字符串存在——**验证编译产物比看源码可靠**（源码改了但没重新编译时尤其重要）。
4. 逐个核对配方里引用的**每一个外部 item id** 在其来源 jar 中有对应资源（用上面「跨模组引用纪律」的两条判据）。
5. 全部 recipe JSON 过一遍 `ConvertFrom-Json`，排除语法错。
6. 最后才 `runClient` 进 JEI 逐条看配方图，确认无“同结果多配方冲突”与“配方不显示”。