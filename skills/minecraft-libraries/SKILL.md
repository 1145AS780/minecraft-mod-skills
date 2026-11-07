---
name: minecraft-libraries
description: "Unified code reference library for Minecraft mod development. Two layers — mod-loader-api (standard API references per loader) plus code-reference (project-tested code and gotchas organized by loader). Covers Forge 1.20.1, NeoForge 1.21.1, Fabric 1.21.1, Paper plugins, vanilla datapacks, and OptiFine/Iris shaderpacks. Use for registration, events, networking, Mixin/ASM, rendering, entity lifecycle, damage pipeline, boss AI, zone spells, maid-mod extensions, datapack and NBT work, and shaderpack development; the automation loop lives in the separate minecraft-mod-autopilot skill. 中文触发：Minecraft 模组开发统一代码参考库。两层结构：mod-loader-api（各加载器标准 API 参考）+ code-reference（按加载器名分类的项目实战代码与踩坑记录）。覆盖 Forge 1.20.1 / NeoForge 1.21.1 / Fabric 1.21.1 / Paper 插件 / 原版数据包 / 光影包。用于注册、事件、网络、Mixin/ASM、渲染、实体生命周期、伤害管线、Boss AI、区域法术、车万女仆扩展等全链路开发场景（自动化闭环见独立技能 minecraft-mod-autopilot）。另含 1.20.1 原版数据包与 OptiFine/Iris 光影包参考。"
---

# Minecraft 模组开发统一代码参考库

两层结构：`mod-loader-api/`（各加载器标准 API 参考）+ `code-reference/`（按加载器名分类的项目实战代码）。
覆盖 **Forge 1.20.1 / NeoForge 1.21.1 / Fabric 1.21.1 / Paper 插件 / 原版数据包 / 光影包**。

> 最后校准：2026-11-05 · 写入方：DeepSeek-V4.1-Flash+Trae｜改动前先读本行；若上次写入方不是自己，先重读全文再动手。
> 2026-11-03 变更：`code-reference/forge-1.20.1/autopilot/` 已拆出为独立技能 `minecraft-mod-autopilot`（本技能只保留 API 与实战代码，不再承载自动化闭环与 WebSocket 桥操控）。

## 目录结构

```text
minecraft-libraries/
├── SKILL.md                       # 本文件（路由表 + 硬纪律）
├── mod-loader-api/                # 通用模组加载器 API 参考
│   ├── forge-1.20.1.md           # Forge 1.20.1 标准 API（版本矩阵/构建/注册/事件/配置/网络/Capability/数据生成/资源/NBT）
│   ├── neoforge-1.21.1.md        # NeoForge 1.21.1 标准 API（含 StreamCodec 网络、neoforge.mods.toml）
│   ├── fabric.md                 # Fabric 1.21.1 标准 API（Yarn 映射，附 Mojmap 对照）
│   ├── paper-bukkit.md           # Paper/Bukkit 插件 API（plugin.yml、事件、命令、GUI、PDC）
│   ├── datapack-1.20.1.md        # 1.20.1 原版数据包（pack_format 15、functions/tags/recipes/loot/advancements/worldgen）
│   ├── vanilla-datapack-nbt.md   # 原版命令语法与 NBT 结构（1.20.1 / 1.21.1）
│   ├── version-migration.md      # 版本差异与迁移对照（1.20.1 → 1.21.1）
│   ├── local-decompile.md        # 本地反编译环境（核对真实 API 签名）
│   └── shaderpack-1.20.1.md      # 1.20.1 OptiFine/Iris 光影包（程序清单、uniforms、buffer、shaders.properties）
└── code-reference/                # 项目实战代码 + 踩坑记录（按加载器版本建子文件夹）
    └── forge-1.20.1/             # Forge 1.20.1 项目实战（15 章节 + 构建环境 + 模组制作器）
        ├── 01-env-build-mixin.md
        ├── 02-tlm-project-practice.md
        ├── 14a-decompile-reading.md
        ├── 14b-architecture.md
        ├── 14c-casting-entity.md
        ├── 14d-client-render.md
        ├── 14e-bauble-damage-asm.md
        ├── 14e2-authoritative-health.md
        ├── 14f-lifecycle-chunk.md
        ├── 14g-boss-ai.md
        ├── 14h-api-provider.md
        ├── 14i-network-mixin.md
        ├── 14j-worldgen.md
        ├── 14k-config-event.md
        ├── 14l-zone-spells.md
        ├── build-env.md          # 构建环境：JDK/Gradle/Maven 镜像/Wrapper/常见报错
        └── mod-maker.md          # 从 0 到 1 模组制作器：注册/模型/语言/打包
```

## 使用方式

1. **先定层级**：要查 Forge 1.20.1 标准 API（`DeferredRegister.toXxx` 签名、`ForgeConfigSpec.Builder` 用法）→ `mod-loader-api/forge-1.20.1.md`。要查本项目实战经验（Mixin 三层梯度、骨挂点渲染、Boss AI 拆分）→ `code-reference/forge-1.20.1/`。
2. **不要全读**：本文件只是路由表。按任务打开对应**一个或两个**文件即可。正文中的 `§N` 是稳定编号，可直接当引用锚点。
3. **先扫「跨领域组合」表**：任务里只要出现**伤害 / 渲染 / 生命周期 / 网络 / 存档**任一边界的交叉，先查下面的组合表。这张表不靠关键词命中——它按**边界**列组合，只命中一行路由也会被它捞住。
4. **再查路由表**：走完组合表后定位具体文件；两边指向同一份时只读一份，指向多份时**全部读**。
5. **每条结论标注来源等级**：**实证**（本项目反编译/编译验证）> 官方 API > 社区来源。冲突时以实证为准。

---

## 第一层：mod-loader-api（标准 API 参考）

| 平台 | 文件 | 内容 |
|---|---|---|
| Forge 1.20.1 | `mod-loader-api/forge-1.20.1.md` | 版本矩阵、`build.gradle`、`mods.toml`、`@Mod` 主类、注册（`DeferredRegister`）、事件总线、`ForgeConfigSpec` 配置、`SimpleChannel` 网络、Capability 能力、数据生成、客户端、资源路径、物品 NBT、坑与排查 |
| 数据包 1.20.1（原版） | `mod-loader-api/datapack-1.20.1.md` | **写/改 `data/<ns>/` 下的 JSON、`.mcfunction`、标签、配方、战利品表、进度、世界生成时读**。内容：版本与 `pack_format` 速查、`pack.mcmeta`、完整目录树、命名空间与 reload、标签、函数、配方、战利品表、进度、谓词与物品修饰器、世界生成、伤害类型与盔甲纹饰、调试与坑表 |
| 光影包 1.20.1（OptiFine/Iris） | `mod-loader-api/shaderpack-1.20.1.md` | **写/调 OptiFine/Iris shaderpack、排查 GLSL 编译错误、buffer/uniform 问题时读**。内容：概念速查、最小可运行包、渲染阶段与程序清单、着色器文件结构、uniforms 全表、缓冲区、`shaders.properties`、OptiFine 与 Iris 差异、PBR/labPBR、性能、调试与报错、与 Forge 交叉问题、坑表 |
| NeoForge 1.21.1 | mod-loader-api/neoforge-1.21.1.md | **写/改 NeoForge 1.21.1 模组时读**（2501 行）。版本矩阵与坐标、`build.gradle`、`neoforge.mods.toml`、`DeferredRegister`、事件总线、配置、`CustomPacketPayload`+`StreamCodec` 网络、Capability、数据生成、客户端与渲染 |
| Fabric 1.21.1 | mod-loader-api/fabric.md | **写/改 Fabric 1.21.1 模组时读**（1627 行，全部按 Yarn 映射写，附 Mojmap 名对照）。版本矩阵与 `gradle.properties`、`fabric.mod.json`、注册、事件、`CustomPayload`+`PacketCodec` 网络、mixin |
| Paper / Bukkit 插件 | mod-loader-api/paper-bukkit.md | **写/调 Paper 插件时读**（959 行，覆盖 1.21.1 与 1.20.1）。plugin.yml、事件、Brigadier 命令、调度器、物品、GUI、PDC、Adventure |
| 原版命令与 NBT | mod-loader-api/vanilla-datapack-nbt.md | **查 /execute、/data、/summon 等原版命令语法与 NBT 结构时读**（2003 行，覆盖 1.20.1 / 1.21.1） |
| 版本差异与迁移 | mod-loader-api/version-migration.md | **跨版本迁移、查某 API 在 1.20.1→1.21.1 之间改了什么时读**（513 行） |
| 本地反编译环境 | mod-loader-api/local-decompile.md | **需要核对真实 API 签名、搭本地反编译时读**（128 行）：两套 MDK 一览与反编译流程 |

### 章节跳转索引（mod-loader-api/forge-1.20.1.md · 2086 行）

[1 版本矩阵](mod-loader-api/forge-1.20.1.md#L9) · [2 项目结构](mod-loader-api/forge-1.20.1.md#L131) · [3 build.gradle](mod-loader-api/forge-1.20.1.md#L191) · [4 mods.toml](mod-loader-api/forge-1.20.1.md#L406) · [5 主类与加载](mod-loader-api/forge-1.20.1.md#L517) · [6 注册](mod-loader-api/forge-1.20.1.md#L606) · [7 事件](mod-loader-api/forge-1.20.1.md#L1051) · [8 配置](mod-loader-api/forge-1.20.1.md#L1173) · [9 网络](mod-loader-api/forge-1.20.1.md#L1276) · [10 Capability](mod-loader-api/forge-1.20.1.md#L1423) · [11 数据生成](mod-loader-api/forge-1.20.1.md#L1568) · [12 客户端](mod-loader-api/forge-1.20.1.md#L1698) · [13 资源路径](mod-loader-api/forge-1.20.1.md#L1844) · [14 物品 NBT](mod-loader-api/forge-1.20.1.md#L1971) · [15 坑与排查](mod-loader-api/forge-1.20.1.md#L2037)

### 章节跳转索引（mod-loader-api/datapack-1.20.1.md · 3322 行）

[0 版本与 pack_format 速查](mod-loader-api/datapack-1.20.1.md#L16) · [1 数据包是什么、与原版/模组的关系](mod-loader-api/datapack-1.20.1.md#L57) · [2 pack.mcmeta 全字段与最小示例](mod-loader-api/datapack-1.20.1.md#L102) · [3 完整目录树](mod-loader-api/datapack-1.20.1.md#L155) · [4 命名空间、加载顺序、reload 与 datapack 命令](mod-loader-api/datapack-1.20.1.md#L313) · [5 标签 tags](mod-loader-api/datapack-1.20.1.md#L384) · [6 函数 functions（.mcfunction）](mod-loader-api/datapack-1.20.1.md#L583) · [7 配方 recipes](mod-loader-api/datapack-1.20.1.md#L1205) · [8 战利品表 loot_tables](mod-loader-api/datapack-1.20.1.md#L1481) · [9 进度 advancements](mod-loader-api/datapack-1.20.1.md#L1936) · [10 谓词 predicates 与物品修饰器 item_modifiers](mod-loader-api/datapack-1.20.1.md#L2216) · [11 世界生成 worldgen](mod-loader-api/datapack-1.20.1.md#L2418) · [12 伤害类型与盔甲纹饰](mod-loader-api/datapack-1.20.1.md#L2943) · [13 调试与坑表](mod-loader-api/datapack-1.20.1.md#L3102) · [14 来源与核对](mod-loader-api/datapack-1.20.1.md#L3243)

### 章节跳转索引（mod-loader-api/shaderpack-1.20.1.md · 1478 行）

[0 概念速查](mod-loader-api/shaderpack-1.20.1.md#L11) · [1 最小可运行包](mod-loader-api/shaderpack-1.20.1.md#L86) · [2 渲染阶段与程序清单](mod-loader-api/shaderpack-1.20.1.md#L318) · [3 着色器文件结构](mod-loader-api/shaderpack-1.20.1.md#L424) · [4 uniforms 全表](mod-loader-api/shaderpack-1.20.1.md#L540) · [5 缓冲区（buffers）](mod-loader-api/shaderpack-1.20.1.md#L690) · [6 shaders.properties 全字段](mod-loader-api/shaderpack-1.20.1.md#L861) · [7 OptiFine 与 Iris 差异表](mod-loader-api/shaderpack-1.20.1.md#L1035) · [8 PBR / labPBR](mod-loader-api/shaderpack-1.20.1.md#L1072) · [9 性能](mod-loader-api/shaderpack-1.20.1.md#L1165) · [10 调试与报错](mod-loader-api/shaderpack-1.20.1.md#L1212) · [11 与 Forge 1.20.1 模组的交叉问题](mod-loader-api/shaderpack-1.20.1.md#L1289) · [12 坑表](mod-loader-api/shaderpack-1.20.1.md#L1360) · [13 来源](mod-loader-api/shaderpack-1.20.1.md#L1392) · [附录 A 未验证条目汇总](mod-loader-api/shaderpack-1.20.1.md#L1461)


---

## 第二层：code-reference/forge-1.20.1（项目实战代码参考）

### 跨领域组合（先扫这张表，再查路由表）

> **触发条件：出现跨边界信号就必查，与「命中几行路由」无关。**
> 本表 7 行都是实测会漏的组合，直接给「同时打开哪几份」。
> 只读一份就答 = 验收不通过（典型反例：饰品锁血只读 14e，漏掉 14g 的守卫拦截与 14e2 的权威值）。

| 组合任务 | 要同时读 |
|---|---|
| 饰品 + 致命伤害锁血（还要防第三方 `setHealth` 绕过） | 14e（§14.23 注册 · §14.24 闸门 · §14.26 血量改写）＋ **14e2（§14.49 权威值，第三方绕过时必读）** ＋ 14g（§14.50 守卫类） |
| 新 Boss + 多段技能阵型 + 客户端表现 | 14g ＋ 14b（§14.51 阵型）＋ 14c（§14.22 时间轴）＋ 14d（§14.38 客户端注册） |
| 女仆自定义任务 + 服务端校验 + 网络同步 | 14c（§14.40 任务）＋ 14i（§14.35 分道）＋ 14f（§14.27 归属） |
| 换存档 / 换世界后状态串味 | 14k（§14.48 清空）＋ 14h（§14.47 release 出口）＋ 14f（§14.29 状态位归零） |
| 装了我的模组后别人的 Boss 血条不对 / 打不死 | 14e2（§14.49 镜像与占位值）＋ 14a（§14.6 权威状态） |
| 结构或矿脉只生成一次，重进世界不再生成 | 14j（§14.41 SavedData vs 运行时状态）＋ 14k（§14.43 配置开关） |
| 大范围区域技能：冲击波打空 / 只有中心的人掉血 / 站在力场里不掉血 | **14l（§14.52 三形态：先数「一个目标被判几次」）** ＋ 14c（§14.22 时间轴）＋ 14b（§14.51 若为离散多点）＋ 14d（§14.38 大范围包围盒与剔除） |

### 路由表（code-reference/forge-1.20.1/）

| 你要做什么 | 打开 |
|---|---|
| 搭环境 / Gradle 报错 / 映射对不上 / Mixin refmap / 事件不触发 / 网络包不通 / 拉依赖 | `01-env-build-mixin.md` |
| 写车万女仆扩展 / 加物品方块配方 / 跨模组合成 / 启动崩溃排查 | `02-tlm-project-practice.md` |
| 第一次读陌生模组，不知道从哪下手 / 判 God Class / 诊断顺序 | `14a-decompile-reading.md` |
| 评估架构 / 选改造方案（官方 API → Mixin → ASM）/ **多点技能阵型（箭雨·地刺·符文阵）** | `14b-architecture.md` |
| 让非玩家实体施法 / 自定义法术实体 / 时间轴同步 / 女仆战斗任务 | `14c-casting-entity.md` |
| 客户端渲染复用 / 骨挂点 / 动画 Provider / BGM 独占 / HUD / 客户端注册 | `14d-client-render.md` |
| 女仆饰品 / **致命伤害锁血** / 伤害闸门 / 非致死决斗 / ASM 改血量 | `14e-bauble-damage-asm.md` |
| **权威血量 getter 插桩（防第三方 setHealth 绕过）** / 归因栈 / 镜像同步 / **L3 自挂 agent 与放弃条件** | `14e2-authoritative-health.md` |
| 实体被误杀、被卸载、停不下来 / 区块卸载造成的 tick 缺口 / 归属解析 | `14f-lifecycle-chunk.md` |
| Boss 与战斗 AI / 延迟任务链 / 复用第三方实体 / **非致死与退役守卫（`LivingChangeTarget`·`InteractMaid` 拦截）** / 4000 行 Boss 拆分 | `14g-boss-ai.md` |
| 对外 API 层 / 法术 Provider / 多法术模组适配 / **第三方软依赖与反射注册** / 虚拟第三方物品 / GameTest / **跨存档静态状态清理出口** | `14h-api-provider.md` |
| 网络层分道限流 / Mixin 拦截第三方频道消息 | `14i-network-mixin.md` |
| 世界生成 / 结构互斥 / **只生成一次（SavedData vs 运行时状态）** / 私有维度 / 分帧搜索 | `14j-worldgen.md` |
| 配置体系 / 事件层聚合 / 伤害管线 / 数据驱动预设 / **换存档后数据残留** | `14k-config-event.md` |
| 冲击波 / 环形冲击 / 波前扫掠 / 结界 / 领域 / 力场 / **区域只结算一次** / 站在区域里不掉血 / 只有中心的人掉血 / 绕过无敌帧 / 命中去重容器（位图 vs Set） / 区域时间源（`gameTime` vs `tickCount`） | `14l-zone-spells.md` |
| JDK/Gradle/Maven 镜像/Wrapper 复用/依赖缓存/build.gradle 常见报错 | `build-env.md` |
| 从 0 到 1 做模组：注册物品/方块/实体 → 创造组 → 合成表 → datagen 模型/语言文件 → runClient 测试 → reobf 打包 | `mod-maker.md` |

### 全量索引（code-reference/forge-1.20.1/）

| 文件 | 覆盖小节 | 行数 |
|---|---|---|
| `01-env-build-mixin.md` | §1 环境构建 · §2 命名映射（12 条三方交叉实证 SRG 表）· §3 Mixin/refmap · §4 事件总线 · §5 网络频道 · §6 数据包/资源包/标签 · §15 依赖获取与校验 | 126 |
| `02-tlm-project-practice.md` | §7 女仆扩展 API · §8 跨模组合成 · §9 崩溃与映射排查 · §10 资料核实与来源 · §11 武器/物品交互实证 · §12 覆写入口速查 · §13 配方链与注册 | 125 |
| `14a-decompile-reading.md` | §14.1 定位入口 · §14.2 软依赖范式 · §14.3 版本能力探测 · §14.4 世界生成防切坏 · §14.5 私有维度 · §14.6 权威状态 · §14.7 单体类判读 · §14.8 诊断顺序 | 177 |
| `14b-architecture.md` | §14.9 施法协议 · §14.10 Boss AI 七抄七避 · §14.11 枚举即数据表 · §14.12 三层改造梯度（L0/L2/L3，L1 跳号不适用） · **§14.51 阵型 = 布局 + 索引 + 位图 + 总量上限**（→ §14.52） | 476 |
| `14c-casting-entity.md` | §14.13 非玩家施法配方 · §14.14 default 覆盖陷阱 · §14.15 doSync 补发 · §14.16 Mixin 门控时序 · §14.21 法术实体六件套 · §14.22 时间轴纯函数（→ 阵型见 §14.51） · §14.40 女仆自定义任务 | 387 |
| `14d-client-render.md` | §14.17 渲染四级阶梯 · §14.18 骨挂点 · §14.19 动画 Provider · §14.20 BGM 独占 · §14.37 HUD · §14.38 客户端注册收口 | 440 |
| `14e-bauble-damage-asm.md` | §14.23 饰品 handler 注册表 · §14.24 伤害闸门重入 · §14.25 ASM 补丁细节 · §14.26 血量改写 | 279 |
| `14e2-authoritative-health.md` | §14.49 权威值容器 · 归因栈 · 白名单 · 写入统一入口 · 镜像同步 · getter 插桩 · **L0~L3 风险分级（含 L2.5 ModLauncher）与 6 条放弃条件** · 伤害数值三层收敛 | 242 |
| `14f-lifecycle-chunk.md` | §14.27 归属解析 · §14.28 生命周期保护 · §14.29 状态位归零（12 写入 + 21 处 SRG 符号全量三方交叉实证） · §14.30 区块加载 | 361 |
| `14g-boss-ai.md` | §14.31 Boss 契约前缀 · §14.32 候选池冷却 · §14.45 延迟任务链调度器 · §14.46 复用第三方实体 · §14.50 4000 行 Boss 拆分法 | 469 |
| `14h-api-provider.md` | §14.33 能力接口注入 · §14.34 Provider 模板方法 · §14.39 八 Provider 统一适配（含反射注册） · §14.47 虚拟第三方物品 + 假 Capability + GameTest | 546 |
| `14i-network-mixin.md` | §14.35 网络请求/响应分道 · §14.36 Mixin 拦截四手法 | 309 |
| `14j-worldgen.md` | §14.41 世界生成四范式 · §14.42 运行时私有维度与分帧搜索 | 286 |
| `14k-config-event.md` | §14.43 配置体系 · §14.44 事件层与伤害管线 · §14.48 数据驱动预设与 ReloadListener | 383 |
| `14l-zone-spells.md` | §14.52 持续区域三形态（A 离散多点→§14.51 · B 波前扫掠 · C 几何力场）· 命中去重容器 · 无敌帧绕过 · 区域时间源对比与修法 · 常量/字面量重复自查 · 选型判据 | 415 |
| `build-env.md` | JDK/Gradle/ForgeGradle 版本 · Wrapper 复用 · Maven 镜像 · 依赖缓存 · CI/publish · jar 重映射 | 74 |
| `mod-maker.md` | MVP 切片 · 注册（`DeferredRegister`）· 物品/方块/实体 · 创造组 · 合成表 · datagen 模型/语言文件 · runClient · reobf | 74 |

---

## 跨文件硬纪律（违反过就会出 bug）

1. **软依赖必须双层保护**：`mods.toml` 声明 optional + 类加载前用 `LoadingModList`/`ModList` 判定；缺一不可（§14.2、§14.16）。
2. **接口 `default` 方法不能覆盖父类具体方法**——零效果，javac 实测（§14.14）。
3. **客户端同步值不可作判定依据**：判定用服务端权威状态（§14.6）。
4. **`ServerTickEvent` 必须判 `phase == END`**，否则每 tick 跑两遍（§14.44）。
5. **伤害/状态改动要在每一层重入**，只在最外层加闸门会被内层绕过（§14.24）。
6. **注册与清理必须成对**（Join/Leave、PutOn/TakeOff、ToItem/ToMaid、AboutToStart/Stopped），清理挂 `EntityLeaveLevel` 而非 `EntityDeath`（§14.44）。
7. **热路径不 `sqrt`**：距离常量同时存值与平方值，命名标 `_SQR`（§14.46）。
8. **假 Capability 不落盘、`simulate` 不改状态、`release()` 幂等**（§14.47）。
9. **静态数据字段必须 `volatile` + 不可变，且挂 `ServerStoppedEvent` 清空**（§14.48）。
10. **第三方能绕过你的 `hurt()` 时，权威值必须做在 getter 上**（插桩返回 + 归因栈 + 镜像同步）；所有中间浮点必须 `Float.isFinite` 兜底（§14.49）。
11. **`switch` 状态转移表不写 `default`**，让 javac 在加枚举值时强制你补规则；`fromId` 越界回默认（§14.50）。
12. **服务端/客户端必须分道**：`tick()` 与各类 handler 先判 `isClientSide`；服务端不跑粒子音效，客户端不跑伤害与随机（§14.44、§14.51）。
13. **确定性重建优于状态同步**：能用 `(seed, 参数, 起始时间)` 重建的东西只同步 seed；轨迹/时间轴预计算成数组，运行时只查表（§14.22、§14.51）。
14. **大范围技能必须做预算**：伤害按固定间隔结算，粒子/音效每 tick 有总量上限 + **轮转起点**；且**单环/单批上限 ≠ 总量上限**（总量随环数与每环数相乘增长，必须另设总量上限并按「由内向外」截断）（§14.51）。
15. **多部件/大范围实体必须自己覆写包围盒与剔除距离**，默认 0.5 格包围盒会让远处整块被剔除、射线漏检（§14.51）。
16. **存档只存参数不存对象**，重建走 `onSyncedDataUpdated` 唯一入口；`CompoundTag` 入档一律 `copy()`（§14.51）。
17. **共享可变对象不能原地改**：`MerchantOffers` / `ItemStack` / `SynchedEntityData` 默认值一律 `copy()` / `copyWithCount`（§14.46、§14.47）。
18. **越界/异常输入一律降级回默认值，不抛异常**：`fromId` 越界回默认、`layout == null` 走 `discard()`、浮点先 `isFinite`（§14.49、§14.50、§14.51）。
19. **「L3」有两套无关分级，引用必须带前缀**：字节码/插桩 L3 见 §14.49（L0/L1/L2/L2.5/L3，ModLauncher agent），渲染 L3 见 §14.17（L0~L3，客户端表现）。只写「L3」会串台，必须写「字节码 L3」或「渲染 L3」。