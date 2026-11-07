# 自动开发闭环运行手册

## 1. 工作产物

技能运行期间只写以下位置，避免污染源码：

```text
.autopilot/
├─ plan.md                  # 本轮目标、文件清单、验收标准
├─ backups/<yyyyMMdd-HHmmss>/  # 改动前的原文件副本
├─ logs/
│  ├─ build-<task>-<time>.log
│  ├─ client-<time>.summary.txt
│  ├─ client-<time>.out.log
│  └─ diagnosis-<time>.md
├─ ws-test/                 # <bridge-modid> WebSocket 验收脚本
│  └─ out/                  # 截图证据（scenario-*.png）
```

日志与备份目录可以随时删除，不参与构建。

## 2. 单轮流程

```powershell
# 0) 记录基线（首次运行时）
git status --short          # 若仓库不是 git，用文件时间/备份代替

# 1) 备份要改的文件
Copy-Item src\main\java\...\Foo.java .autopilot\backups\<stamp>\Foo.java

# 2) 实现修改（一次只做一类改动）

# 3) 编译
powershell -ExecutionPolicy Bypass -File skills/minecraft-mod-autopilot/scripts/build.ps1 -Task compileJava

# 4) 通过后启动客户端
powershell -ExecutionPolicy Bypass -File skills/minecraft-mod-autopilot/scripts/run-client.ps1 -TimeoutSeconds 240

# 5) 采集诊断
powershell -ExecutionPolicy Bypass -File skills/minecraft-mod-autopilot/scripts/collect-diagnostics.ps1

# 6) 修复 → 回到 3)
```

需要完整 jar 时用 `-Task build`；需要重跑数据生成时用 `-Task runData`；只验证服务端时直接 `.\gradlew runServer`（不要用客户端脚本）。

## 3. runClient 生命周期

- 脚本用 `cmd /c gradlew.bat runClient` 启动，游戏窗口会真实弹出。
- 判定为 **ready**：`latest.log` 出现 `Sound engine started` / `Narrator library for x64 successfully loaded` / `OpenAL initialized` 之一，并持续 `ReadyGraceSeconds` 秒无崩溃标记。
- 判定为 **crashed**：日志出现 `Crash report`、`Mod loading has failed`、`A fatal error has been detected`、`Exception in server tick loop` 等。
- 判定为 **timeout**：超时仍无 ready/crash 标记（常见于资源下载、卡在加载界面）。
- 默认结束进程；`-KeepRunning` 保留窗口供人工操作。`-PlanOnly` 只打印启动命令。
- 若机器没有显示环境，改用 `runServer`；客户端崩溃日志中的 `GLFW`/`OpenGL` 属于环境问题。

## 4. 迭代预算与回滚

- 每轮只修一个根因；修复后必须重新编译再运行。
- 最多 5 轮。达到上限或同类异常 2 轮无效 → 停止并汇报。
- 回滚：把 `.autopilot/backups/<stamp>/` 中对应文件复制回原路径，再重新编译确认回到基线。
- 不整目录回滚，避免覆盖用户在本轮之外做的改动。

## 5. 验收层级

| 层级 | 验证内容 | 命令 | 通过标准 |
| --- | --- | --- | --- |
| L0 | 编译 | `build.ps1 -Task compileJava` | exit 0 |
| L1 | 客户端启动 | `run-client.ps1` | `status=ready` 或 `exited-ok` |
| L2 | 模组自检 | 查 `latest.log` | 出现 `[<modid>]` 自检行，无 ERROR |
| L3 | 功能 | 进游戏执行命令/交互 | 行为符合目标，无新报错 |
| L3b | AI Bridge 操控 | `java .autopilot\ws-test\InputScreenshotScenarioTest.java` | `RESULT: N passed, 0 failed`，退出码 0，截图非空 |
| L3c | 文本感知循环 | `java .autopilot\ws-test\PerceptionLoopTest.java` | 每 tick 文本+截图同包，28 项全过 |
| L3d | 自动战斗 | `java .autopilot\ws-test\CombatPerceptionTest.java` | 接近/瞄准/4 刀击杀、反击治疗、目标轮换、LOS 阻断全过（45 项） |
| L3e | 长按组合键 | `java .autopilot\ws-test\HoldInputTest.java` | 疾跑+到点释放、盾牌右键 usingItem、左右键连击、stop 中断全过（21 项） |
| L3f | 交互式控制台 | `python .autopilot\ws-test\bridge_console.py` | `sense`/`hold`/`watch`/`fight`/`shot`/`raw` 可用；`--json` 输出全为合法 NDJSON、`--fail-fast` 与失败退出码 1 实测通过 |
| L3g | 单次条件检测 | `python .autopilot\ws-test\bridge_console.py --commands detect.txt` | `detect threat`/自定义条件/9 个预设均返回 `passed`+`total`+`context`；世界 tick 正常时条件随 `setblock`/`time set`/`summon` 变化 |
| L4 | 服务端 | `.\gradlew runServer` | 正常启动，无 tick 异常 |

## 6. 常见日志标记

```text
# 成功
[<modid>] 兼容自检: ...
[<modid>] 已连接车万女仆，物品桥接启用

# 需要关注
ERROR ... Exception
FATAL ... 
Mod loading has failed
Exception in server tick loop
Missing texture
```

## 7. 新增功能检查清单

- [ ] 注册类是否在模组构造器 `register(modBus)`。
- [ ] 注册名是否为小写合法字符。
- [ ] 资源文件路径是否与注册名一致。
- [ ] 是否只在服务端执行世界/伤害逻辑。
- [ ] 是否避免在静态初始化读取配置或 `RegistryObject.get()`。
- [ ] 是否对第三方类做了软依赖隔离。
- [ ] 是否需要数据生成（`runData`）。
- [ ] 是否需要网络包（构造期初始化频道）。
- [ ] 是否补充日志，便于下一轮脚本定位。
- [ ] 是否写入 `.autopilot/plan.md` 与备份。

## 8. 汇报模板

```text
目标：<一句话>
改动：<文件列表>
轮次：<第 N 轮>
错误：<分类 + 首个堆栈>
修复：<改了什么 + 为什么>
验证：L0 <通过/失败>；L1 <状态>；L2 <日志证据>
遗留：<未解决项与风险>
```

## 9. 本仓库特有问题

- `gradle.properties` 的展开键（形如 `<archivesName>=<modid>`）是 `mods.toml` 的 `modId` 来源，不能只改名。
- 发布 jar 名由 `archivesName` 决定，与 Mod ID 不一致属预期。
- TLM 必须用 `libs/touhou_little_maid-1.5.3-named.jar`；发布版 SRG jar 在 dev 会因 refmap 崩溃。
- 客户端首次启动可能较慢（资源/模型加载），超时默认 240 秒；网络慢时可加大。
- `<bridge-dir>/` 是自带 wrapper 的独立 Gradle 工程（`cd <bridge-dir> && gradlew build`），与主工程互不依赖；dev 运行目录是 `<bridge-dir>/run/`，日志在 `run/logs/latest.log`，token 在 `run/config/<bridge-modid>.token`。
- `latest.log` 会保留上一次运行的内容：判断“已就绪”必须结合日志时间戳或端口探测，不能只 grep 关键字。