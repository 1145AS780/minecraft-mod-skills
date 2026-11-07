---
name: minecraft-mod-autopilot
description: Minecraft Forge 1.20.1 mod development autopilot — write mod code, add enchantments, items, blocks and entities, build with Gradle, launch runClient or a real PCL2 instance, read latest.log and crash-reports, auto-fix compile errors and startup crashes, and loop until verified. Also drives Minecraft over a WebSocket bridge (<bridge-modid>) for commands, state queries, key simulation, mining and placing, screenshot capture, perception text sensing, auto-combat, and automated acceptance tests. Use when asked to write a mod, fix a mod, debug a Forge mod, fix a crash, or run the client to see errors. 中文触发：Minecraft Forge 1.20.1 模组全自动开发与自修复。当用户要求“写模组/加附魔、物品、方块、实体/修模组/跑客户端看报错/自动修复崩溃/自动调试 Forge 模组/打开PCL2我的世界/启动PCL2游戏实例”时使用。也用于让 AI 或脚本通过 WebSocket 操控 Minecraft（<bridge-modid>：执行命令、查询状态、模拟按键/挖掘/放置、截图回传、perception 文本感知、自动战斗、多文件脚本、任务队列、触发器、弹道投掷、建造采矿、安全白名单）与自动化验收。流程为编写代码 → Gradle 构建 → 启动 runClient 或 PCL2 真实实例 → 采集 latest.log 与 crash-reports → 定位并修复 → 循环验证；内置 Forge API、注册、事件、数据生成、第三方 jar 字节码补丁与常见错误知识。
---

# Minecraft Mod Autopilot

面向 Forge 1.20.1 工程的“写 → 构建 → 跑 → 读日志 → 修”闭环技能。默认工作目录为工程根目录。

## 何时使用

- 在 Forge 1.20.1 工程中新增或修改附魔、物品、方块、实体、事件、配置、数据生成。
- `compileJava` / `build` 失败，需要定位并修复。
- `runClient` 崩溃或卡在加载界面，需要从日志/崩溃报告定位原因。
- 用户要求“自动写模组”“自动修复模组”“自己跑起来看报错”。
- 需要通过 `<bridge-modid>` 的 WebSocket 通道驱动游戏（执行命令、查询状态、模拟输入、截图、perception 文本感知、自动战斗）或跑自动化验收。

不适用：Fabric / NeoForge / 其它 MC 版本（需先替换 `references/forge-1.20.1-api.md` 中的 API 说明）；Bukkit/Paper 服务端插件。

## 核心原则

1. **先读后写**：动手前确认 `build.gradle`、`gradle.properties`、主类、现有包结构和命名约定。
2. **单一入口**：只保留一个 `@Mod` 类；所有注册走 `DeferredRegister`。
3. **服务端权威**：生成实体、结算伤害、修改世界状态只在 `!level.isClientSide` 执行；客户端只做渲染。
4. **小步循环**：一轮只改一个可验证的点，每轮都重新编译，不攒大批改动。
5. **证据优先**：修复依据必须是编译器输出、`latest.log` 或 `crash-reports` 的真实堆栈，不靠猜测。
6. **可回滚**：改动前把原文件复制到 `.autopilot/backups/<时间戳>/`；不删除用户未要求删除的代码。
7. **有预算**：最多 5 轮“构建 → 运行”循环；同类错误连续 2 次未解决就停止并汇报，不无限重试。
8. **不隐瞒**：无法复现或无法修复时，明确说明证据、已尝试方案和剩余风险。

## 环境前置检查

```powershell
java -version
Test-Path .\gradlew.bat
Get-Content gradle.properties | Select-String 'minecraft_version|forge_version|mod_id'
```

要求：JDK 17、Gradle Wrapper 可用、`build.gradle` 中的 ForgeGradle 带版本号（例如 `version '[6.0.24,6.1)'`）。首次构建需能访问 Minecraft Forge Maven。若工程对第三方库有软依赖，需确认 `libs/` 下对应 jar 已就位。

## 工作循环

### 第 1 步：计划

1. 阅读主类与目标包，列出要新增/修改的文件。
2. 明确验收标准，例如：`compileJava` 通过；`runClient` 到达主菜单且无 crash；游戏内执行某命令能看到效果。
3. 把计划写入 `.autopilot/plan.md`（目标、文件清单、验收标准、回滚点）。

### 第 2 步：实现

- 注册链路：`DeferredRegister` → 主类构造器 `register(modBus)` → 资源文件（`mods.toml`、`lang`、模型、纹理、`damage_type` 等）。
- API 细节与代码模板见 [references/forge-1.20.1-api.md](references/forge-1.20.1-api.md)。
- 改文件前先备份到 `.autopilot/backups/<时间戳>/`。

### 第 3 步：构建

```powershell
powershell -ExecutionPolicy Bypass -File <skills-root>/minecraft-mod-autopilot/scripts/build.ps1 -Task compileJava
```

- 失败：读脚本输出的 `error:` 摘要与 `.autopilot/logs/build-*.log`，进入第 6 步。
- 通过：继续第 4 步。需要完整打包时用 `-Task build`，重跑数据生成用 `-Task runData`。

### 第 3b 步：构建独立 sourceSet 子 mod 的发布 jar（必须 reobf）

当仓库有第二 sourceSet（如 `addon`，产出独立 mod jar，`build.gradle` 里的 `reobf { addonJar { } }` 会对应生成一个 reobf 任务）时：

```powershell
gradlew :addonJar                             # 产出 dev 版（mojmap/可读字段名）——只用于本机构建与检查
gradlew :reobfAddonJar                        # 产出 SRG 混淆可发布版——部署到 mods 必须用它
```

- `reobf` 任务会**覆盖写回同一个** `build/libs/<jar>`，记得以"最近执行的是 reobf 任务"为准，而不是时间戳相近的普通构建。
- 只跑 `addonJar` 不跑 reobf 时，jar 里 MC 字段/方法名仍是开发映射名（mojmap，如 `Items.GOLD_INGOT`）。把它部署到真实运行环境（SRG 字段空间）会抛运行时错误：
  ```text
  java.lang.NoSuchFieldError: GOLD_INGOT
      at <pkg>.init.AddonItems.<clinit>(AddonItems.java:53)
  ```
- 判定：部署前确认产物出自 `reobfAddonJar`。若报 `NoSuchFieldError: <全大写成员>`，即为"未 reobf 的 dev jar 进了 SRG 运行空间"。

### 第 4 步：运行客户端

```powershell
powershell -ExecutionPolicy Bypass -File <skills-root>/minecraft-mod-autopilot/scripts/run-client.ps1 -TimeoutSeconds 240
```

- 脚本会启动 `gradlew runClient`，轮询 `run/logs/latest.log`，检测崩溃标记或到达主菜单。
- 默认超时后结束进程；需要保留窗口时加 `-KeepRunning`。
- 只检查命令拼写、不启动游戏时加 `-PlanOnly`。`-PlanOnly` 只打印将要执行的命令，不落日志。
- 首次运行会先跑 `:downloadAssets`，资源 CDN 不通时以 `exited-error`（退出码 4）结束并在 `.autopilot/logs/client-*.err.log` 报 `Failed to get asset: ...`；这是网络问题，重跑或配代理，不要改代码。

### 第 4b 步：启动 PCL2 真实实例（部署验证）

当修复对象是**部署到 PCL 真实实例的 jar**（例如 `<minecraft-dir>\versions\<版本>\mods\` 下的第三方/自建 mod），用 dev 的 `runClient` 无法验证，应改用本脚本启动 PCL2：

```powershell
powershell -ExecutionPolicy Bypass -File <skills-root>/minecraft-mod-autopilot/scripts/launch-pcl2.ps1 -InstancePath "<minecraft-dir>\versions\<版本>" -TimeoutSeconds 300
```

- 启动脚本按顺序解析：`-LaunchScript` 显式指定 → 实例目录 `启动*.bat` → 实例 `mods/启动*.bat` → `$env:PCL_LAUNCHER`（PCL2 最新导出的 `LatestLaunch.bat`）。默认实例目录为 `$env:APPDATA\.minecraft\versions\1.20.1-forge`，请用 `-InstancePath` 指定本机实际路径。
- 它监控**实例的** `logs/latest.log` 与 `crash-reports/`（不是 `run/` 下的 dev 日志）。
- 判定 `ready`（出现 `Sound engine started` 等并稳定 `ReadyGraceSeconds` 秒）、`crashed`（新崩溃报告或日志含崩溃标记）、`timeout`。
- 默认结束游戏进程；需要保留窗口加 `-KeepRunning`；只打印启动命令加 `-PlanOnly`。
- 使用前提：实例 mods 目录里已放入待验证 jar；若需从本仓库构建产物同步到实例，先完成构建再启动。
- 免手动进世界：在实例启动脚本的 java 命令行加 `--quickPlaySingleplayer "<世界文件夹名>"`（取 `versions/<版本>/saves/` 下的文件夹名，不是世界显示名；1.20 起才支持）。PCL2 重新导出启动脚本会覆盖该文件，若想让 PCL2 直接启动也自动进世界，把同样参数加到 PCL2「版本设置 → 高级 → 自定义启动参数」。该 bat 为无 BOM UTF-8 + `chcp 65001`，中文世界名可直接写。

### 第 4c 步：WebSocket 桥操控与截图验收

当验收目标是“AI 能通过 WebSocket 操控游戏”（而不是修崩溃）时，按 [references/ws-bridge.md](references/ws-bridge.md) 的 quickPlay 配方启动带 `<bridge-modid>` 的客户端，再跑脚本：

```powershell
java .autopilot\ws-test\InputScreenshotTest.java          # 基础 21 项
java .autopilot\ws-test\InputScreenshotScenarioTest.java  # 连续场景 45 项
java .autopilot\ws-test\PerceptionLoopTest.java           # 1 Hz 感知循环 28 项（文本+截图同包）
java .autopilot\ws-test\CombatPerceptionTest.java         # 1 Hz 自动化战斗 45 项（接近/瞄准/击杀/目标轮换/LOS）
java .autopilot\ws-test\HoldInputTest.java                # 长按组合键 21 项（疾跑/右键/连击/stop）

python .autopilot\ws-test\bridge_console.py               # 交互式控制台（零依赖，直接敲命令操控角色）
```

- 通过标准：`RESULT: N passed, 0 failed`，退出码 0；截图与 JSON 写入 `.autopilot/ws-test/out/<loop|combat|hold>/`。
- 想手动试指令用 Python 控制台：`sense`（一行文本感知）、`watch 5`（连感 5 秒）、`hold use sprint forward 1200`（长按组合键）、`hold attack 3000`（按住左键连击）、`fight 20`（自动战斗）、`detect threat`（单次条件检测，也可 `detect health<=10 block_below=air`）、`wait 800`（等世界同步）、`shot a.png`、`cmd time set night`、`raw {...}`；`--commands <文件>` 可批量执行后退出。token 默认读 `<bridge-dir>/run/config/<bridge-modid>.token`，也可 `--token`/`--port` 指定。给 AI/脚本用加 `--json`（stdout 纯 NDJSON，推送走 stderr）与 `--fail-fast`（首个失败即停）；批量模式有失败时退出码 1。
- 纯文本 AI 用 `perception` 请求：每 tick 一个响应同时给位置/朝向/准星/可视方块/背包方块/可攻击生物与同一帧截图，脚本另存 `tick-XXXX.json` + `tick-XXXX.png` 并写 `senses.log` 文本摘要。
- 连续操作（长按）用 `{"type":"input","op":"hold","keys":["use","sprint","forward"],"ms":1200}`：一次按下一组键、到点一起释放；`use` 会真按 `keyUse`（否则物品使用会被立刻取消），`attack` 按冷却自动连击准星实体；原版在使用物品时会取消疾跑，属正常语义。
- 战斗脚本只读 `attackableEntities`（`health/lineOfSight/aimYaw/aimPitch/hostile`）决策：距离 >2.9 先走近，准星指向目标 id 才出刀，每 tick 一个动作、1 s 一刀（铁剑满蓄力 6 伤害，僵尸 20 HP→4 刀）；preflight 会设 `difficulty easy`、夜间+停止昼夜循环、关刷怪、关自然回血、回满血、`doImmediateRespawn true`。
- 单次判断用 `detect`：`{"type":"detect","preset":"threat"}` 或 `{"type":"detect","conditions":["health<=10","block_below=air"]}`，返回逐条 `checks` + `context`；9 个预设（threat/low_health/fall_risk/night/lava/water/inventory_full/durability/target）与数值/关键字条件见 [references/ws-bridge.md](references/ws-bridge.md) 第 4 节。`ok` = 所有条件成立；`nearest_hostile` 无敌对时给 999，`durability` 空手为 -1 并附 note。
- 让 AI 直接做事用第 9 节客户端能力层：`keys`（列出含其它模组的按键映射，配合 `input.op=press` 驱动界面）、`scan`（视野锥 110°/16 格生物扫描，可按敌/中立/友过滤）、`block_search`（按方块 id 查位置）、`path`/`waypoint`（A* 寻路、跟随实体、记录坐标点）、`lock`/`combat`（锁定+自动瞄准连击，支持风筝/低血撤退/进食/盾牌/弓弩）、`hotbar`/`inventory`/`container`（换快捷栏、背包查询、开箱取放）、`fish`/`build`/`gather`/`farm`（自动钓鱼、搭桥搭塔、按方块或 tag 采集、收割种植施肥）、`explore`（群系/方块/实体搜索与区域缓存）、`craft`/`smelt`/`trade`/`anvil`（合成、冶炼、村民交易、铁砧改名附魔，阻塞到完成）、`macro`/`loop`（动作序列与定时循环，`await` 可等子系统结束）。控制台统一入口 `feat <type> k=v ...`（例 `feat scan radius=16 category=hostile`），细节见 [references/ws-bridge.md](references/ws-bridge.md) 第 9 节。
- 客户端必须已进入世界且窗口未暂停（单机窗口失焦会弹「游戏菜单」暂停世界，命令照执行但方块/时间不同步，`detect` 会读旧世界）；改世界后先 `wait 800` 再检测。测试期间不要动鼠标（会覆盖 yaw/pitch）。`command` 的 `asPlayer` 只换锚点不提权：非 OP 玩家下 `time set`/`summon`/`effect` 会被过滤成“未知或不完整的命令”，改世界时不要传 `asPlayer`（控制台权限 4）。专用服不具备 `input` / `screenshot` / `perception` / `detect` 能力。

### 第 4d 步：多文件指令层（任务/脚本/触发器/新能力）

2026-11 新增的一层，全部走同一个 `{"type":..., "action":...}` 入口，按功能拆成独立 Java 文件，客户端 tick 逐帧推进：

- **采矿与地形**：`mining`（`tunnel`/`strip`/`vein`/`quarry`，带危险方块预检与区域白名单）、`building`（`blueprint` 蓝图为 `blocks` 数组或 `layers`+`palette`、`flatten`、`demolish`、`fill`）。
- **仓储与物流**：`storage`（`index` 直接读容器方块实体建索引、`deposit`/`withdraw`/`sort` 走 `QUICK_MOVE` 点击队列）、`logistics`（`collect` 行走拾取掉落物、`store` 转仓储、`ride` 乘矿车）。
- **战斗与生存**：`hunt`/`guard`/`survive`/`recover`/`death_point`（狩猎、守卫、低血自动进食后撤、死亡点回收）；`combat` 仍走原 `ClientTargeting`，`{"type":"combat","action":"hunt"}` 才进入新战斗任务。
- **交易与附魔**：`trade_loop`（`ServerboundSelectTradePacket` 批量交易）、`enchant`（附魔台放物/青金石/按钮/取回）。
- **红石**：`redstone`/`signal`/`pulse`/`sequence`（读邻接信号、脉冲、按 `steps` 执行时序）。
- **弹道投掷**：`projectile` 的 `solve`/`aim`/`throw`/`shoot`/`status`，按逐 tick 积分（阻力+重力+`level.clip`）两轮搜索 pitch，移动目标按速度做提前量；箭/弩/三叉戟/雪球等参数不同。
- **指令系统**：`vars`（共享变量 + `config/<bridge-modid>_vars.json` 持久化）、`queue`（优先级 + 多 lane 并行 + `config/<bridge-modid>_task_queue.json` 持久化）、`scheduler`（定时投递）、`script_file`（脚本根 `config/<bridge-modid>_scripts/`，支持 `include`、`${expr}`、`if/unless`、`repeat`、`while`、`delayTicks`、`await`、`retry`、嵌套 `script_file`）、`triggers`（health/food/xp/inventory_full/item/entity/block/player_near/job_idle 触发脚本或 steps）。
- **状态与事件**：`status_board`（`show` 聚合玩家+各子系统、`hud` 常驻）、`stream`（`subscribe`/`unsubscribe` 主题 tick/position/health/food/inventory/near/block/job，异步 `broadcast` 推送 `{"type":"event"}`）。
- **安全层**：`safety`（区域白名单 `set`/`clear`、`protect` 资源保护、`hazard` 危险预检、`audit` 读 `logs/<bridge-modid>_actions.log`）。
- **技能库联动**：`skills`（只读浏览 `~/.<bridge-modid>/skills`，`list`/`show`/`files`/`read`/`search`/`status`，路径限制在根目录内）。
- 寻路跳跃上限 1 格（`VERTICAL_ORDER` 只允许 +1 向上），下落最多 3 格；宏步骤里的 `{"type":"input","op":"mine"}` 改为异步启动，不再阻塞客户端线程。

### 第 5 步：诊断

```powershell
powershell -ExecutionPolicy Bypass -File <skills-root>/minecraft-mod-autopilot/scripts/collect-diagnostics.ps1
```

输出 `.autopilot/logs/diagnosis-<时间戳>.md`，包含：运行摘要、错误分类、首个异常、涉及本模组的栈帧、修复建议。分类规则与修复方案见 [references/error-triage.md](references/error-triage.md)。

### 第 6 步：修复

1. 按诊断报告定位到具体文件与行号。
2. 一次只修一类问题；修复后回到第 3 步。
3. 若错误指向第三方/Forge 内部，先确认版本与映射（mojmap 名 vs SRG 名），再决定降级或绕行。
4. 部署到真实运行环境后的典型运行时症状与处理：
   - `NoSuchFieldError: <全大写成员>`（如 `GOLD_INGOT`）→ 未 reobf 的 dev jar 进了 SRG 空间，改用 `reobfAddonJar` 重建部署（见第 3b 步）。
   - `java.lang.module.ResolutionException: Modules <A> and <B> export package <pkg> to module <C>` → JPMS **拆分包冲突**：本 jar 自带类副本与所依赖库共用了同一个 `com.*` 包名。把本 jar 中与库同包的自带类移到自有命名空间（如 `cn.<modid>.mcb`），同步更新引用它的类 import、清理旧空包目录后重建。
   - `NoClassDefFoundError: <库里的类>` 而库已部署 → 运行 mods 缺该依赖库或引用了不含该类的副本 jar，核对 mods 目录里起作用的 jar 是否真是带该类的那份。

### 第 7 步：验证与交付

- `compileJava` 通过且无新增错误（弃用警告可接受）。
- `runClient` 到达主菜单，`run/logs/latest.log` 无 `ERROR`/`FATAL` 崩溃堆栈。
- 游戏内验收（按模组实际内容选择）：

```text
latest.log 应出现
[<modid>] 兼容自检: 车万女仆=<true|false>, Curios=<...>
装了车万女仆时，还应有 "[<modid>] 已连接车万女仆，物品桥接启用"。
```

- WebSocket 操控链路（如涉及 `<bridge-modid>`）：`InputScreenshotScenarioTest.java`、`PerceptionLoopTest.java`、`CombatPerceptionTest.java` 全部 `0 failed`，截图非空且场景有变化。
- 汇报：改了哪些文件、每轮错误根因、最终验证结果、未解决的问题。

## 停止条件

出现以下任一情况立即停止循环并汇报：

- 5 轮构建/运行仍未通过。
- 同一异常连续 2 轮修复无效。
- 需要删除或重写大量用户代码。
- 需要联网下载新依赖、修改 Gradle/Java 版本或系统环境。
- 日志显示问题来自显卡驱动、系统编码等外部环境。

## 资源

- [references/forge-1.20.1-api.md](references/forge-1.20.1-api.md)：Forge 1.20.1 API、注册、事件、实体、附魔、数据生成、本仓库约定。
- [references/error-triage.md](references/error-triage.md)：编译错误、启动崩溃、资源缺失、注册冲突的症状→原因→修复对照表。
- [references/automation-loop.md](references/automation-loop.md)：详细运行手册、日志位置、回滚与验收策略。
- [references/ws-bridge.md](references/ws-bridge.md)：`<bridge-modid>` 模组、WebSocket 协议、输入模拟（含 `hold` 长按组合键）/截图/`perception` 文本感知/自动战斗能力矩阵、验收脚本（21/45/28/45/21 项全部实测通过）、客户端 quickPlay 联调配方。
- [scripts/](scripts/)：`build.ps1` / `run-client.ps1` / `launch-pcl2.ps1` / `collect-diagnostics.ps1`。脚本自动从自身位置或当前目录向上查找含 `gradlew.bat` 的仓库根（可在任意目录位置调用），也可用 `$env:AUTOPILOT_ROOT` 显式指定。