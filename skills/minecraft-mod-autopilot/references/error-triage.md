# 错误分类与自动修复手册

## 1. 读取顺序

1. `compileJava` 失败 → 只看 `.autopilot/logs/build-*.log` 的 `error:` 行。
2. 启动/运行失败 → 先看 `run/crash-reports/crash-*.txt` 的 `Description` 与 `-- Head --`。
3. 没有崩溃报告 → 看 `run/logs/latest.log` 末尾 200 行与 `ERROR`/`FATAL` 行。
4. 仍无线索 → 看 `.autopilot/logs/client-*.summary.txt` 的 `status`，区分 `crashed` / `exited-error` / `timeout`。

## 2. 编译期错误

| 症状（日志关键字） | 常见原因 | 修复 |
| --- | --- | --- |
| `cannot find symbol` | 缺 import、方法名/签名与 1.20.1 不符、拼写错误 | 用 `official` 映射核对方法名；检查 import |
| `package X does not exist` | 依赖未声明或 jar 不在 `libs/` | 确认 `build.gradle` 的 `compileOnly`/`implementation` 与文件存在 |
| `incompatible types` | `RegistryObject<T>` 当 `T` 用、泛型推断错误 | 取 `.get()`；显式写泛型 |
| `non-static method ... cannot be referenced` | 在静态上下文调用实例方法 | 改为实例字段/事件对象调用 |
| `duplicate class` / 两个 `@Mod` | 遗留入口类未删 | 只保留一个 `@Mod` 主类 |
| `UnsupportedClassVersionError` | 用 JDK 8/11 编译或运行 | 设 Toolchain/JAVA_HOME 为 17 |
| `unmappable character` | 源码编码非 UTF-8 | `build.gradle` 已有 `options.encoding = 'UTF-8'`，把文件另存为 UTF-8 |
| `Plugin [id: 'net.minecraftforge.gradle'] was not found` | 插件缺版本号 | `id 'net.minecraftforge.gradle' version '[6.0.24,6.1)'` |
| `Could not find or load main class GradleWrapperMain` | wrapper jar 缺失 | 重新生成 wrapper，或使用本机 Gradle |
| `Could not resolve net.minecraftforge:forge` | 网络/Maven 不可达 | 检查代理与 `settings.gradle` 仓库；不要改代码 |

修复编译错误时一次只改一类，改完立即 `build.ps1 -Task compileJava`。

## 3. 模组加载期错误

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| `Mod loading has failed` + `Failed to create mod` | 主类构造器抛异常（注册顺序、静态初始化、配置读取过早） | 把注册/网络/配置调用按依赖顺序排列；构造器内不访问未注册对象 |
| `NoClassDefFoundError: org/yaml/snakeyaml/...` | TLM named jar 未内置 SnakeYAML | 保留 `runtimeOnly 'org.yaml:snakeyaml:2.4'` |
| `NoClassDefFoundError: com/github/tartaricacid/...` | 缺 TLM named jar，或从主类直接引用 TLM 类 | `libs/` 放 named jar；把引用隔离到 `@LittleMaidExtension` 类 |
| `NoSuchMethodError` / `NoSuchFieldError` | 依赖版本不匹配或使用了错误映射的 jar | 核对 TLM/Forge 版本；dev 必须用 named jar，不能用发布版 SRG jar |
| `Registration of impl channels is locked` | 首个 tick 才创建 `SimpleChannel` | 在模组构造器调用 `LearnNetwork.init()` |
| Mixin `... refmap ...` / `@Shadow` 找不到 | TLM dev 需要 refmap 反映射 | 保留 `mixin.env.remapRefMap`、`refMapRemappingFile`、`GradleStart.srg.srg-mcp` 三个属性 |
| `Duplicate registry entry` / `already registered` | 同一注册名注册两次 | 删除重复 `DeferredRegister` 或重复 `register` |
| `Missing texture ...` / `FileNotFoundException: ...png` | 资源路径/文件名不匹配 | 检查 `assets/<modid>/textures/...` 与模型 json 的 `texture` 字段 |
| 模型加载失败 `Unable to load model` | 模型 json 语法或父模型路径错误 | 用 `minecraft:item/generated` 为父模型，纹理名与文件名一致 |
| 配置读取抛 `IllegalStateException: Cannot get config value before config is loaded` | 静态初始化里读配置 | 改为运行期读取，或加默认值兜底 |
| `NoSuchFieldError: <全大写成员>`（如 `GOLD_INGOT`） | 发布 jar 未 reobf：直接用 `<addon>Jar` 产出的 dev 版带 mojmap 字段名，进入 SRG 运行空间查不到字段 | 部署前用 `reobf<Addon>Jar` 产出 SRG 混淆版再同步到 mods（见 SKILL.md 第 3b 步） |
| `java.lang.module.ResolutionException: Modules <A> and <B> export package <pkg> to module <C>` | JPMS 拆分包冲突：本 jar 自带类副本与所依赖库共用同一个 `com.*` 包名 | 把与库同包的自带类改名到自有命名空间（如 `cn.<modid>.mcb`），同步更新 import、清理旧空包目录后重建 |
| `NoClassDefFoundError: <库里的类>` 且 `mods` 里确实有该库 | 运行 mods 里的现役 jar 不含该类（引用了不含该类的副本 jar），或缺对应依赖库 | 核对 mods 里真正加载的是哪个 jar、是否含该类 / 是否缺少依赖底座库 |

## 4. 运行期崩溃

| 症状 | 根因 | 修复 |
| --- | --- | --- |
| `NullPointerException`，栈顶在本模组 | 字段/注册对象为 null、目标实体已移除 | 加 `!= null`、`isAlive()`、`isRemoved()` 检查；确认注册完成 |
| `Exception in server tick loop` | tick 处理器抛异常 | 定位栈中的本模组帧；对实体集合做快照遍历，避免边遍历边删 |
| `ConcurrentModificationException` | 遍历中修改实体/列表 | 用 `new ArrayList<>(list)` 或收集后统一处理 |
| `OutOfMemoryError` | 单次生成实体过多 | 增加硬上限/分批生成；检查 tick 内生成数量 |
| `IllegalStateException: ... level is null` | 实体未加入世界就访问 `level()` | 延迟到 `tick` 或入世界事件后再处理 |
| `ClassCastException` | 未做 `instanceof` 判断 | 命中/交互入口先判类型 |
| `GLFW error` / `Failed to create window` / `Pixel format` | 显卡驱动、远程桌面、无显示环境 | 环境问题，不改模组逻辑；改用 `runServer` 验证服务端 |
| `java.lang.OutOfMemoryError: Metaspace` | 反复热重载/依赖过多 | 重启 Gradle daemon，必要时加大 `org.gradle.jvmargs` |

## 5. 崩溃报告怎么读

1. 顶部 `Description:` 是崩溃摘要（例如 `Mod loading has failed`）。
2. `-- Head --` 之后是**真正抛出点**的栈顶。
3. 从栈顶向下找第一个自有包帧（如 `<group>.<modid>.*`），那通常就是需要改的文件与行号。
4. `Caused by:` 链要读到最内层，外层往往只是包装。
5. `-- System Details --` 用于确认 Java/Forge/TLM 版本，不要用来定位代码。

## 6. 自动修复决策树

```text
构建失败?
├─ 是 → 有 error: 行?
│        ├─ 是 → 按文件/行修语法、import、签名 → 重新编译
│        └─ 否 → 看 FAILURE 段（依赖/网络/插件）→ 只修环境或配置
└─ 否 → 运行客户端
         ├─ crashed → 读 crash-report 的 Head → 找本模组帧 → 修 → 编译 → 重跑
         ├─ exited-error → 看 stdout 日志末尾 → 通常是 Gradle/Java 启动失败
         └─ ready/timeout → 查 latest.log 的 ERROR → 按上表分类
```

## 7. 修复后的回归验证

1. `build.ps1 -Task compileJava`：必须 exit 0。
2. `run-client.ps1 -TimeoutSeconds 240`：`status=ready` 或 `exited-ok`。
3. `collect-diagnostics.ps1`：`Status: clean`，且 `Frames In This Mod` 为空。
4. 功能验证：在日志中确认模组自检行；需要时进游戏执行对应命令（本仓库：`/ollama_maid`、`/maidlearn`）。
5. 服务端验证：`.\gradlew runServer`，确认无 `Exception in server tick loop`。

## 8. 不要自动改的东西

- 显卡/音频/输入法/系统编码导致的错误。
- `libs/` 下的第三方 named jar（除非用户明确要求升级）。
- `gradle.properties` 中的展开键（形如 `<archivesName>`，见 API 文档第 1 节）。
- 与当前错误无关的格式化、重构、依赖升级。