# Forge 1.20.1 模组 API

Forge 1.20.1 使用 Java 17、Mojang 官方映射（Mojmap / `official`），包名以 `net.minecraftforge` 开头。1.21.1 请改用 NeoForge；本文件只覆盖 1.20.1（Forge 47.x）。

本文的类名、方法签名均已在本机 Forge 47.4.10 源码 jar（`forge-1.20.1-47.4.10-sources.jar`）、映射后二进制 jar（`*_mapped_official_1.20.1.jar`）以及 ForgeGradle 6.0.54 插件类中核对过；标注「实测」的条目来自反编译验证，不是记忆。凡本文未出现的 API，默认按「不存在」处理。

---

## 1. 版本矩阵与运行环境

### 1.1 版本组合（唯一可用组合）

| 项 | 值 | 说明 |
|---|---|---|
| Minecraft | `1.20.1` | 1.20.1 是 Forge 47 线唯一主力版本 |
| Forge | `1.20.1-47.4.10`（47.x 任意） | 依赖坐标 `net.minecraftforge:forge:1.20.1-47.4.10` |
| Java | **17** | 必须；见 1.4 |
| ForgeGradle | 6（本机 6.0.54，声明区间 `[6.0.24,6.1)`） | 插件 id `net.minecraftforge.gradle` |
| Gradle | **8.8**（wrapper） | `gradle-8.8-bin.zip`，实测 MDK 用的就是这个 |
| 映射 | `channel = official`, `version = 1.20.1` | Mojang 官方名，`ItemStack#getOrCreateTag` 这类名字 |
| 资源/数据包 | `pack_format = 15` | 1.20.1 资源包与数据包同为 15 |

源码与二进制都在 `GRADLE_USER_HOME` 下，不要写死盘符。先定位（未设置时默认 `~/.gradle`）：

```powershell
$g = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { "$env:USERPROFILE\.gradle" }
Get-ChildItem $g -Recurse -Filter 'forge-1.20.1-*-sources.jar'            | Select-Object -First 1 -ExpandProperty FullName
Get-ChildItem $g -Recurse -Filter 'forge-1.20.1-*_mapped_official_*.jar' | Select-Object -First 1 -ExpandProperty FullName
Get-ChildItem $g -Recurse -Filter 'fmlcore-1.20.1-*.jar'                 | Select-Object -First 1 -ExpandProperty FullName
Get-ChildItem $g -Recurse -Filter 'ForgeGradle-6.0.*.jar'                | Select-Object -First 1 -ExpandProperty FullName
```

定位失败时按 `$g` 下的固定相对路径找：

```text
caches/forge_gradle/maven_downloader/net/minecraftforge/forge/1.20.1-47.4.10/forge-1.20.1-47.4.10-sources.jar
caches/forge_gradle/minecraft_user_repo/net/minecraftforge/forge/1.20.1-47.4.10_mapped_official_1.20.1/forge-1.20.1-47.4.10_mapped_official_1.20.1.jar
caches/modules-2/files-2.1/net.minecraftforge/fmlcore/1.20.1-47.4.10/<hash>/fmlcore-1.20.1-47.4.10.jar
caches/modules-2/files-2.1/net.minecraftforge.gradle/ForgeGradle/6.0.54/<hash>/ForgeGradle-6.0.54.jar
```

注意：`SimpleChannel` 在 `net.minecraftforge.network.simple`（不是 `net.minecraftforge.network`），本文所有网络示例已按真实包名书写。

### 1.2 `gradle.properties` 逐字段

```properties
# Gradle 守护进程的 JVM 参数。3G 是反编译/映射的最低舒适值，
# -Dnet.minecraftforge.gradle.check.certs=false 关闭 ForgeGradle 的证书校验（MDK 默认，见本机 MDK）
org.gradle.jvmargs=-Xmx3G -Dnet.minecraftforge.gradle.check.certs=false
# 关闭守护进程：改 build.gradle 后下次一定生效，代价是每次构建重新起 JVM
org.gradle.daemon=false

## 环境属性
minecraft_version=1.20.1
# 允许的 MC 版本区间（写进 mods.toml 的 minecraft 依赖）
minecraft_version_range=[1.20.1,1.21)
# Forge 版本：不带 MC 前缀，前缀在 build.gradle 里拼
forge_version=47.4.10
forge_version_range=[47,)
# loader 版本只能用 Forge/FML 主版本作为边界
loader_version_range=[47,)
# 映射通道：official / snapshot / snapshot_nodoc / stable / stable_nodoc / parchment
mapping_channel=official
# official 通道下必须填 MC 版本；parchment 通道要填 YYYY.MM.DD-MCVersion
mapping_version=1.20.1

## 模组属性（会被 processResources 展开进 mods.toml）
mod_id=examplemod
mod_name=Example Mod
mod_license=MIT
mod_version=1.0.0
mod_group_id=com.example.examplemod
mod_authors=YourName
mod_description=Example Forge 1.20.1 mod.
```

字段作用要点：

- `org.gradle.jvmargs` 只影响 **Gradle 守护进程**，不影响 `runClient` 启动的游戏 JVM；游戏内存用 `runs.configureEach { jvmArguments '-Xmx2G' }` 调。
- `org.gradle.daemon=false` 让每次构建都新建 JVM；CI 与「改脚本后行为不一致」排查时建议保持 `false`。
- `net.minecraftforge.gradle.check.certs` 是 ForgeGradle 的系统属性，不是 Gradle 官方属性；关掉可绕过企业代理替换证书导致的 `SSLHandshakeException`。
- `mod_group_id` 只影响发布到 Maven 时的坐标，同时约定源码根包名。
- `mod_id` 必须匹配 `[a-z][a-z0-9_]{1,63}`，且与 `@Mod` 常量、`assets/<modid>`、`data/<modid>` 目录名完全一致。

### 1.3 Gradle wrapper

```properties
# gradle/wrapper/gradle-wrapper.properties（实测 MDK 内容）
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.8-bin.zip
networkTimeout=10000
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

不要手动把 `distributionUrl` 升到 9.x：ForgeGradle 6 只验证到 Gradle 8.x。

### 1.4 为什么必须 Java 17（JDK 21+ 会失败）

1. **Gradle 版本上限**：Gradle 8.8 不支持 JDK 23+，用 JDK 23 及以上连 `gradlew` 都起不来（`Unsupported class file major version`）。
2. **ForgeGradle 6 的补丁与 AT 工具**：userdev 补丁、`ForgeAutoRenamingTool`、`binarypatcher` 是按 Java 17 字节码校验的；JDK 21 编译出 class 65 的文件会被部分工具拒绝。
3. **强封装参数**：Forge 1.20.1 的启动脚本与 ForgeGradle 生成的 run 配置只带针对 17 的一组 `--add-opens` / `--add-exports`；在 21 上会出现 `InaccessibleObjectException`、`IllegalAccessError`，且 `mixin.env` 的反射重映射会失效。
4. **工具链与运行时不一致**：`java.toolchain.languageVersion = 17` 只保证编译用 17，`runClient` 仍会挑 `JAVA_HOME`；两者不一致时表现为「编译通过、启动即崩」。

正确做法：

```powershell
$env:JAVA_HOME = '<JDK 17 安装目录>'   # 必须是 17
.\gradlew.bat build
```

命令行里的 `java` 可能不是 17（系统默认常指向更新的 JDK），**这些 JDK 都不能**用于本项目；查 jar 也不要调用系统默认 JDK 的 `jar`，统一用 JDK 17 自带的 `<JDK17>/bin/jar.exe`（只读 jar，不参与编译）。

### 1.5 常用 Gradle 任务

| 任务 | 用途 |
|---|---|
| `build` | 编译 + 打包 + 触发下载 userdev 与映射（首次跑一次即可） |
| `runClient` | 启动带模组的客户端（`run/` 工作目录） |
| `runServer` | 启动专用服务端（默认 `--nogui`） |
| `runData` | 跑数据生成，输出到 `src/generated/resources` |
| `reobfJar` | 把 `jar` 产物从 official 名重映射为发布用的 SRG 名（1.20.1 必须） |
| `genIntellijRuns` / `genEclipseRuns` | 生成 IDE 运行配置 |
| `--refresh-dependencies` | 依赖被代理污染时强制重下 |

ForgeGradle 6 **没有 `genSources`**（那是 NeoGradle/ModDevGradle 的概念）。要看 MC 源码只能用 Vineflower 反编译映射后的二进制 jar。

---

## 2. 项目结构

```text
examplemod/
├── build.gradle
├── settings.gradle
├── gradle.properties
├── gradlew / gradlew.bat
├── gradle/wrapper/
│   ├── gradle-wrapper.jar
│   └── gradle-wrapper.properties
├── src/
│   ├── main/
│   │   ├── java/com/example/examplemod/            # 源码根包 = mod_group_id
│   │   └── resources/
│   │       ├── META-INF/mods.toml                   # 必须存在，路径不能错
│   │       ├── pack.mcmeta                          # 1.20.1 仍需要
│   │       ├── examplemod.mixins.json               # 仅用 mixin 时
│   │       ├── assets/examplemod/
│   │       │   ├── lang/en_us.json  lang/zh_cn.json
│   │       │   ├── models/item/*.json  models/block/*.json
│   │       │   ├── blockstates/*.json
│   │       │   └── textures/item/*.png  textures/block/*.png
│   │       └── data/examplemod/
│   │           ├── recipes/
│   │           ├── advancements/
│   │           ├── loot_tables/blocks/
│   │           ├── tags/blocks/  tags/items/
│   │           └── forge/biome_modifier/            # 可选
│   ├── generated/resources/                          # runData 输出，被 sourceSets 引入
│   └── test/                                        # 可选
└── run/  run-data/                                  # 运行时工作目录，不要提交
```

目录规则（1.20.1 专属，写错即静默失效）：

| 内容 | 位置 | 备注 |
|---|---|---|
| 模组元数据 | `src/main/resources/META-INF/mods.toml` | 少 `META-INF` 启动直接失败 |
| 资源包元数据 | `src/main/resources/pack.mcmeta` | `pack_format: 15` |
| 客户端资源 | `assets/<modid>/…` | 目录名必须等于 modId |
| 服务端数据 | `data/<modid>/…` | **复数**：`recipes`、`advancements`、`loot_tables`、`tags`、`functions`、`predicates`、`item_modifiers`、`structures` |
| 贴图引用 | `assets/<modid>/textures/item/ruby.png` → `examplemod:item/ruby` | 模型里写命名空间:路径，不带 `.png` |
| 语言文件 | `assets/<modid>/lang/en_us.json` | 键为 `item.examplemod.ruby` 之类 |

`pack.mcmeta`（1.20.1 资源包与数据包共用一个文件）：

```json
{
  "pack": {
    "pack_format": 15,
    "description": "Example Mod resources"
  }
}
```

`pack_format` 对照：1.19.4 = 13，1.20/1.20.1 = 15，1.20.2 = 18，1.21 = 34，1.21.1 = 34。写错版本号，资源包会被标记「不兼容」但仍能加载，模型缺失时先查这里。

---

## 3. `build.gradle` 完整示例

### 3.1 主写法（`plugins` 块，MDK 默认）

```gradle
plugins {
    id 'eclipse'
    id 'idea'
    id 'maven-publish'
    id 'net.minecraftforge.gradle' version '[6.0.24,6.1)'
}

version = mod_version
group = mod_group_id

base {
    archivesName = mod_id
}

// MC 1.20.1 面向 Java 17
java.toolchain.languageVersion = JavaLanguageVersion.of(17)

println "Java: ${System.getProperty 'java.version'}, JVM: ${System.getProperty 'java.vm.version'} " +
        "(${System.getProperty 'java.vendor'}), Arch: ${System.getProperty 'os.arch'}"

minecraft {
    // official = Mojang 官方名；也可填 parchment，版本形如 2023.09.03-1.20.1
    mappings channel: mapping_channel, version: mapping_version

    // 让 IDE 启动前先跑 processResources，否则 IDE 里读不到展开后的 mods.toml
    copyIdeResources = true

    // 访问转换器（可选）：文件最终必须在 jar 内的 META-INF/accesstransformer.cfg
    // accessTransformer = file('src/main/resources/META-INF/accesstransformer.cfg')

    runs {
        // 所有 run 配置的公共部分
        configureEach {
            workingDirectory project.file('run')
            property 'forge.logging.markers', 'REGISTRIES'
            property 'forge.logging.console.level', 'debug'
            mods {
                "${mod_id}" {
                    source sourceSets.main
                }
            }
        }

        client {
            property 'forge.enabledGameTestNamespaces', mod_id
        }

        server {
            property 'forge.enabledGameTestNamespaces', mod_id
            args '--nogui'
        }

        // GameTest 专用服务端：没有注册 gametest 会主动崩溃
        gameTestServer {
            property 'forge.enabledGameTestNamespaces', mod_id
        }

        data {
            workingDirectory project.file('run-data')
            args '--mod', mod_id, '--all',
                 '--output', file('src/generated/resources/'),
                 '--existing', file('src/main/resources/')
        }
    }
}

// 把生成的资源当作主资源集的一部分
sourceSets.main.resources { srcDir 'src/generated/resources' }

repositories {
    // ForgeGradle 已自动加入 Forge maven 与 Maven Central，这里只补额外仓库
    maven { name = 'MinecraftForge'; url = 'https://maven.minecraftforge.net/' }
    flatDir { dir 'libs' }        // 本地 mod jar
}

dependencies {
    minecraft "net.minecraftforge:forge:${minecraft_version}-${forge_version}"

    // 第三方 mod 依赖：必须 fg.deobf()，把发布版 SRG 引用重映射到开发映射
    // compileOnly fg.deobf("mezz.jei:jei-1.20.1-forge-api:15.2.0.27")
    // runtimeOnly fg.deobf("mezz.jei:jei-1.20.1-forge:15.2.0.27")
}

// 把 gradle.properties 的占位符展开进 mods.toml / pack.mcmeta
tasks.named('processResources', ProcessResources).configure {
    var replaceProperties = [
            minecraft_version      : minecraft_version,
            minecraft_version_range: minecraft_version_range,
            forge_version          : forge_version,
            forge_version_range    : forge_version_range,
            loader_version_range   : loader_version_range,
            mod_id                 : mod_id,
            mod_name               : mod_name,
            mod_license            : mod_license,
            mod_version            : mod_version,
            mod_authors            : mod_authors,
            mod_description        : mod_description,
    ]
    inputs.properties replaceProperties

    filesMatching(['META-INF/mods.toml', 'pack.mcmeta']) {
        expand replaceProperties + [project: project]
    }
}

// jar 清单，方便运行时排查（不含敏感信息）
tasks.named('jar', Jar).configure {
    manifest {
        attributes([
                'Specification-Title'     : mod_id,
                'Specification-Vendor'    : mod_authors,
                'Specification-Version'   : '1',
                'Implementation-Title'    : project.name,
                'Implementation-Version'  : project.jar.archiveVersion,
                'Implementation-Vendor'   : mod_authors,
                'Implementation-Timestamp': new Date().format("yyyy-MM-dd'T'HH:mm:ssZ")
        ])
    }
    // ForgeGradle 6：这一句替代老版手写 reobf 任务
    finalizedBy 'reobfJar'
}

tasks.withType(JavaCompile).configureEach {
    options.encoding = 'UTF-8'
}

publishing {
    publications {
        register('mavenJava', MavenPublication) { artifact jar }
    }
    repositories {
        maven { url "file://${project.projectDir}/mcmodsrepo" }
    }
}
```

### 3.2 旧写法（`buildscript` + `apply plugin`）

只在不支持 `plugins {}` 的旧构建脚本里用，语义等价：

```gradle
buildscript {
    repositories {
        maven { url = 'https://maven.minecraftforge.net/' }
        maven { url = 'https://repo.spongepowered.org/repository/maven-public/' }
        mavenCentral()
    }
    dependencies {
        classpath group: 'net.minecraftforge.gradle', name: 'ForgeGradle', version: '6.0.+', changing: true
    }
}
apply plugin: 'net.minecraftforge.gradle'
apply plugin: 'eclipse'

minecraft {
    mappings channel: 'official', version: '1.20.1'
    runs {
        client { workingDirectory project.file('run') }
        server { workingDirectory project.file('run'); args '--nogui' }
    }
}
```

`settings.gradle` 必须给插件仓库与工程名，否则插件解析失败：

```gradle
pluginManagement {
    repositories {
        gradlePluginPortal()
        maven { name = 'MinecraftForge'; url = 'https://maven.minecraftforge.net/' }
    }
}
plugins {
    id 'org.gradle.toolchains.foojay-resolver-convention' version '0.7.0'
}
rootProject.name = mod_id
```

### 3.3 `reobf` / `reobfJar` 的真实含义

- 1.20.1 的**生产运行时**仍是 SRG 名（`m_xxxxx_` / `f_xxxxx_`）。在 `official` 映射下编译出的 class 引用的是 Mojang 官方名，**发布 jar 必须重映射**，所以 `finalizedBy 'reobfJar'` 不能删。

```gradle
tasks.named('jar', Jar).configure { finalizedBy 'reobfJar' }
```

- 不要手写 `reobf { jar {} }`：ForgeGradle 6 会自动为 `jar` 创建对应 reobf 任务；只有自定义 `Jar` 任务（多 sourceSet 打独立 jar）才需要显式声明：

```gradle
reobf {
    myAddonJar { }
}
```

- `runClient`/`runServer` 用的是 named（official）环境，不需要 reobf；只有给别人用的发布 jar 需要。

### 3.4 `jarJar`（嵌套依赖）

Forge 1.20.1 具备 JarJar。ForgeGradle 6 提供 `jarJar` 扩展（实测 `JarJarProjectExtension`，扩展名常量 `"jarJar"`）：

```gradle
jarJar.enable()                        // 开启嵌入；jarJar.disable() 关闭
jarJar.fromRuntimeConfiguration()      // 把 runtime 依赖也纳入
jarJar.pin(dependency, '2.4')          // 固定被嵌入依赖的版本
```

依赖声明用 `jarJar` 配置，被嵌入的 jar 及其 `META-INF/jarjar/metadata.json` 由插件生成，不要手写 metadata。嵌入后必须能在游戏里正常读到，否则启动时报 `Missing or unsupported mandatory dependencies`。

---

## 4. `mods.toml` 全字段

路径固定为 `src/main/resources/META-INF/mods.toml`。1.20.1 用 **`mods.toml`**，不是 `neoforge.mods.toml`（后者是 NeoForge 1.20.5+）。

```toml
# 语言加载器：Java 模组固定 javafml
modLoader = "javafml"
# FML/Forge 主版本区间，必须是 loaderVersion 而不是 forge 版本
loaderVersion = "[47,)"
# 必填，发布合规信息
license = "MIT"
# 可选：问题追踪地址
issueTrackerURL = "https://github.com/you/examplemod/issues"

[[mods]]
modId = "${mod_id}"
version = "${mod_version}"
displayName = "${mod_name}"
# 多行描述用 '''，单行用 "。会被模组列表渲染
description = '''Example Forge 1.20.1 mod.'''
# 可选：logo，放在 resources 根目录，写文件名不写路径
logoFile = "examplemod.png"
authors = "${mod_authors}"
# 可选：鸣谢
credits = "Thanks to ..."
# 可选：展示链接
displayURL = "https://example.com"

# 每条依赖一个 [[dependencies.<你的modid>]] 表；字段是 mandatory，不是 type
[[dependencies.${mod_id}]]
modId = "forge"
mandatory = true
versionRange = "[${forge_version},)"
ordering = "NONE"
side = "BOTH"

[[dependencies.${mod_id}]]
modId = "minecraft"
mandatory = true
versionRange = "[1.20.1,1.21)"
ordering = "NONE"
side = "BOTH"

# 软依赖：不装也能跑，装了要排在我的模组之后
[[dependencies.${mod_id}]]
modId = "jei"
mandatory = false
versionRange = "[15,)"
ordering = "AFTER"
side = "CLIENT"

# 可选：自定义模组属性，供其它模组读取
[modproperties.${mod_id}]
catalogueItemIcon = "examplemod:ruby"
```

字段清单：

| 字段 | 位置 | 取值 / 说明 |
|---|---|---|
| `modLoader` | 顶层 | `javafml`（Java 模组）；`lowcodefml` 用于 JS/其它语言 |
| `loaderVersion` | 顶层 | `[47,)`；只能是 FML 主版本边界 |
| `license` | 顶层 | 必填，任意字符串 |
| `issueTrackerURL` | 顶层 | 可选 |
| `modId` | `[[mods]]` | 必填，小写，和 `@Mod`、目录名一致 |
| `version` | `[[mods]]` | 必填；打包时用 `${file.jarVersion}` 可替换为清单版本 |
| `displayName` | `[[mods]]` | 必填，UI 显示名 |
| `description` | `[[mods]]` | 必填，`'''` 多行 |
| `logoFile` | `[[mods]]` | 可选，resources 根下的图片名 |
| `authors` / `credits` / `displayURL` | `[[mods]]` | 可选 |
| `modId` | `[[dependencies.*]]` | 必填，`forge`/`minecraft`/其它 modid |
| `mandatory` | `[[dependencies.*]]` | 必填，`true`/`false`（NeoForge 才用 `type`） |
| `versionRange` | `[[dependencies.*]]` | Maven 版本区间语法，如 `[1.20.1,1.21)` |
| `ordering` | `[[dependencies.*]]` | `NONE`/`BEFORE`/`AFTER` |
| `side` | `[[dependencies.*]]` | `BOTH`/`CLIENT`/`SERVER` |
| `[modproperties.<modid>]` | 自定义表 | 键值对随 `IModInfo#getModProperties()` 暴露 |

### 4.1 `displayTest` 的正确做法

1.20.1 的 `mods.toml` **不要依赖 `displayTest` 字段**：实测 `fmlloader` 的 `ModInfo` / `DefaultModFileInfo` 中没有任何 `displayTest` 解析代码（`ModFileParser` 里连 "mixin" 字样都没有）。要做版本协商，走 API：

```java
import net.minecraftforge.fml.IExtensionPoint.DisplayTest;
import net.minecraftforge.fml.ModLoadingContext;

// 放在主类构造器里：任意版本的客户端都能连本服
ModLoadingContext.get().registerDisplayTest(DisplayTest.IGNORE_ALL_VERSION);
// 或：忽略服务器版本，但保留客户端版本
// ModLoadingContext.get().registerDisplayTest(DisplayTest.IGNORE_SERVER_VERSION);
```

（`IExtensionPoint.DisplayTest` 的 `IGNORE_SERVER_VERSION` / `IGNORE_ALL_VERSION` 两个常量实测存在。）

### 4.2 `mods.toml` vs `neoforge.mods.toml`

| 项 | Forge 1.20.1 | NeoForge 1.20.5+ |
|---|---|---|
| 文件名 | `META-INF/mods.toml` | `META-INF/neoforge.mods.toml` |
| 依赖表字段 | `mandatory = true` | `type = "required"` |
| 加载器 | `modLoader = "javafml"` | 同上，但 `loaderVersion = "[4,)"` |
| mixin 声明 | 清单 `MixinConfigs`（见 §15） | `[[mixins]] config="x.mixins.json"` |
| 包名 | `net.minecraftforge.*` | `net.neoforged.*` |

### 4.3 常见 TOML 语法错误

- 表名必须带完整 modid：`[[dependencies.${mod_id}]]`，写成 `[[dependencies]]` 直接解析失败。
- TOML 字符串不要用反斜杠转义以外的多余引号；`description` 用 `'''…'''`。
- 缩进不影响解析，但 `[[mods]]` 与后续 `[[dependencies.*]]` 之间不能嵌套在别的表里。

---

## 5. 主类与加载

### 5.1 完整主类（含注册、监听、配置、网络）

```java
package com.example.examplemod;

import net.minecraftforge.eventbus.api.IEventBus;
import net.minecraftforge.fml.IExtensionPoint.DisplayTest;
import net.minecraftforge.fml.ModLoadingContext;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.config.ModConfig;
import net.minecraftforge.fml.event.lifecycle.FMLCommonSetupEvent;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;

@Mod(ExampleMod.MOD_ID)
public final class ExampleMod {

    public static final String MOD_ID = "examplemod";

    public ExampleMod() {
        // mod 总线：注册、初始化、数据生成都在这里
        IEventBus modBus = FMLJavaModLoadingContext.get().getModEventBus();

        // 注册顺序影响不大，但方块类必须先于物品类被初始化（BlockItem 要拿 Block）
        ExampleBlocks.BLOCKS.register(modBus);
        ExampleItems.ITEMS.register(modBus);
        ExampleBlockEntities.BLOCK_ENTITIES.register(modBus);
        ExampleMenus.MENUS.register(modBus);
        ExampleTabs.TABS.register(modBus);
        ExampleSounds.SOUNDS.register(modBus);

        modBus.addListener(this::commonSetup);

        // 配置文件：类型 + spec + 可选文件名
        ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, Config.SPEC, "examplemod-common.toml");
        ModLoadingContext.get().registerDisplayTest(DisplayTest.IGNORE_ALL_VERSION);
    }

    private void commonSetup(final FMLCommonSetupEvent event) {
        // FMLCommonSetupEvent 是并行触发的，操作游戏全局状态必须 enqueueWork
        event.enqueueWork(() -> {
            ModNetwork.init();
        });
    }
}
```

要点：

- `@Mod` 的 value 必须与 `mods.toml` 的 `modId` 一致，否则模组被判定为不完整。
- 主类必须有**无参构造器**（FML 反射实例化）。构造器执行时 Registry 尚未填充，不能 `RegistryObject#get()`。
- `ModLoadingContext.get()` 在 1.20.1 能编译、能运行，但 Forge 47.4.10 的 `fmlcore` 已给它加上 `@Deprecated(forRemoval = true, since = "1.21.1")`（`javap -v` 实测），javac 默认就会打 `[removal]` 警告（实测编译）。警告不影响运行；NeoForge 1.21.1 仍保留 `get()`，但配置注册改用 `ModContainer#registerConfig`（1.21.1 起推荐构造器注入 `IEventBus` / `ModContainer`，见 `references/neoforge-1.21.1.md` §4）。

### 5.2 两套总线对照

| 维度 | mod 总线 | Forge 总线 |
|---|---|---|
| 获取 | `FMLJavaModLoadingContext.get().getModEventBus()` | `MinecraftForge.EVENT_BUS` |
| 类型 | `net.minecraftforge.eventbus.api.IEventBus` | 同上 |
| 触发时机 | 加载期：构造、注册、setup、数据生成 | 游戏期：登录、tick、交互、伤害 |
| 监听方式 | `modBus.addListener(this::method)` 或 `@Mod.EventBusSubscriber(bus = Bus.MOD)` | `MinecraftForge.EVENT_BUS.addListener(...)` 或默认 `Bus.FORGE` |
| 典型事件 | `FMLCommonSetupEvent`、`RegisterEvent`、`GatherDataEvent`、`BuildCreativeModeTabContentsEvent`、`RegisterCapabilitiesEvent`、`RegisterKeyMappingsEvent` | `PlayerEvent.*`、`TickEvent.*`、`BlockEvent.*`、`LivingDamageEvent`、`ServerStartingEvent` |

实测：`@Mod.EventBusSubscriber` 的 `bus()` 默认值就是 `Bus.FORGE`，所以游戏期事件监听器可以只写 `@Mod.EventBusSubscriber(modid = MOD_ID)`。

### 5.3 客户端/服务端隔离

```java
import net.minecraftforge.api.distmarker.Dist;
import net.minecraftforge.api.distmarker.OnlyIn;
import net.minecraftforge.fml.DistExecutor;
```

1.20.1 的 `Dist` 与 `OnlyIn` 在 **`net.minecraftforge.api.distmarker`**（实测 `DistExecutor` 内部 switch 用的是 `net.minecraftforge.api.distmarker.Dist`），不是 `net.minecraftforge.fml.Dist`。

```java
// 推荐：延迟类加载，服务端不会碰客户端类
DistExecutor.unsafeRunWhenOn(Dist.CLIENT, () -> () -> ClientOnlyThing.init());

// 不推荐：@OnlyIn 只做删除标记，仍可能触发客户端类加载
@OnlyIn(Dist.CLIENT)
public void doClientStuff() { }
```

`DistExecutor.runWhenOn` / `runForDist` 已被标记 `@Deprecated`，新代码用 `unsafeRunWhenOn`（已核对签名 `unsafeRunWhenOn(Dist, Supplier<Runnable>)`）。

---

## 6. 注册

### 6.1 `DeferredRegister` 与 `RegistryObject`

1.20.1 **只有 `RegistryObject`**，没有 NeoForge 的 `DeferredItem` / `DeferredBlock` / `DeferredHolder`。

```java
DeferredRegister.create(ForgeRegistries.ITEMS, MOD_ID);          // IForgeRegistry 重载
DeferredRegister.create(Registries.CREATIVE_MODE_TAB, MOD_ID);   // ResourceKey 重载
```

`DeferredRegister.create` 的三种重载（实测）：`create(IForgeRegistry<B>, String)`、`create(ResourceKey<? extends Registry<B>>, String)`、`create(ResourceLocation, String)`，另有 `createOptional(...)` 用于可缺省注册表。

注册表入口（`ForgeRegistries` 实测字段）：

| 目标 | DeferredRegister 泛型 | 注册表常量 |
|---|---|---|
| 物品 | `Item` | `ForgeRegistries.ITEMS` |
| 方块 | `Block` | `ForgeRegistries.BLOCKS` |
| 方块实体类型 | `BlockEntityType<?>` | `ForgeRegistries.BLOCK_ENTITY_TYPES` |
| 实体类型 | `EntityType<?>` | `ForgeRegistries.ENTITY_TYPES` |
| 菜单 | `MenuType<?>` | `ForgeRegistries.MENU_TYPES` |
| 药水效果 | `MobEffect` | `ForgeRegistries.MOB_EFFECTS` |
| 粒子类型 | `ParticleType<?>` | `ForgeRegistries.PARTICLE_TYPES` |
| 配方序列化器 | `RecipeSerializer<?>` | `ForgeRegistries.RECIPE_SERIALIZERS` |
| 声音事件 | `SoundEvent` | `ForgeRegistries.SOUND_EVENTS` |
| 属性 | `Attribute` | `ForgeRegistries.ATTRIBUTES` |
| 创造模式标签页 | `CreativeModeTab` | `Registries.CREATIVE_MODE_TAB`（**不在 ForgeRegistries**） |
| 流体 | `Fluid` | `ForgeRegistries.FLUIDS` |

`DeferredRegister` 必须 `.register(modBus)` 才会真正注册；`.register(String, Supplier)` 返回 `RegistryObject<I>`，`getEntries()` 返回 `Collection<RegistryObject<T>>`（实测）。

`.register(modBus)` 只能写在 `@Mod` 构造器（或构造器直接调用的方法）里，不能写进任何 `@SubscribeEvent` 回调：监听器必须在 `RegisterEvent` 之前挂上，晚挂等于静默不注册；若 `RegisterEvent` 之后再调 `register(name, supplier)`，`DeferredRegister` 会抛 `IllegalStateException("Cannot register new entries to DeferredRegister after RegisterEvent has been fired.")`（源码实测）。

### 6.2 物品

```java
package com.example.examplemod;

import net.minecraft.world.food.FoodProperties;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class ExampleItems {

    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(ForgeRegistries.ITEMS, ExampleMod.MOD_ID);

    public static final RegistryObject<Item> RUBY =
            ITEMS.register("ruby", () -> new Item(new Item.Properties()));

    // 1.20.1 物品堆叠/耐久/稀有度都在 Item.Properties 上；创造模式标签页不在这里指定
    public static final RegistryObject<Item> RUBY_SWORD =
            ITEMS.register("ruby_sword", () -> new SwordItem(
                    ExampleTiers.RUBY, 3, -2.4F, new Item.Properties()));

    public static final RegistryObject<Item> RUBY_APPLE =
            ITEMS.register("ruby_apple", () -> new Item(new Item.Properties()
                    .food(new FoodProperties.Builder()
                            .nutrition(6)
                            .saturationMod(0.6F)
                            .alwaysEat()
                            .build())));

    public static final RegistryObject<Item> RUBY_STAFF =
            ITEMS.register("ruby_staff", () -> new Item(new Item.Properties()
                    .stacksTo(1)
                    .durability(120)
                    .rarity(Rarity.UNCOMMON)
                    .fireResistant()));

    // BlockItem 必须在 lambda 内取方块，注册时才求值
    public static final RegistryObject<Item> RUBY_BLOCK_ITEM =
            ITEMS.register("ruby_block", () -> new BlockItem(ExampleBlocks.RUBY_BLOCK.get(),
                    new Item.Properties()));
}
```

`Item.Properties` 实测方法：`food(FoodProperties)`、`stacksTo(int)`、`durability(int)`、`defaultDurability(int)`、`rarity(Rarity)`、`fireResistant()`、`craftRemainder(Item)`。**没有 `tab(...)`**（1.19.3 起移除，改用创造模式标签页）。

`FoodProperties` 在 **`net.minecraft.world.food`**（不是 `world.item`），`Builder` 方法实测：`nutrition(int)`、`saturationMod(float)`、`meat()`、`alwaysEat()`、`fast()`、`effect(Supplier<MobEffectInstance>, float)`、`build()`。

### 6.3 方块与 BlockItem

```java
package com.example.examplemod;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class ExampleBlocks {

    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(ForgeRegistries.BLOCKS, ExampleMod.MOD_ID);

    public static final RegistryObject<Block> RUBY_BLOCK =
            BLOCKS.register("ruby_block", () -> new Block(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_RED)
                    .strength(3.0F, 6.0F)          // 硬度, 抗爆
                    .sound(SoundType.STONE)
                    .requiresCorrectToolForDrops()));

    // 复制 vanilla 方块属性再改，比从零拼更稳
    public static final RegistryObject<Block> RUBY_ORE =
            BLOCKS.register("ruby_ore", () -> new Block(
                    BlockBehaviour.Properties.copy(Blocks.IRON_ORE)));
}
```

`BlockBehaviour.Properties` 实测：`of()`、`copy(BlockBehaviour)`、`strength(float, float)`、`strength(float)`、`instabreak()`、`requiresCorrectToolForDrops()`、`noOcclusion()`、`randomTicks()`、`lightLevel(ToIntFunction<BlockState>)`、`sound(SoundType)`、`mapColor(DyeColor/MapColor/Function)`、`dynamicShape()`。

### 6.4 方块实体与 ticker

```java
package com.example.examplemod;

import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

public class RubyBlockEntity extends BlockEntity {

    private int counter;

    // 这里用 .get() 是安全的：构造发生在注册完成之后
    public RubyBlockEntity(BlockPos pos, BlockState state) {
        super(ExampleBlockEntities.RUBY_BLOCK_ENTITY.get(), pos, state);
    }

    public static void tick(net.minecraft.world.level.Level level, BlockPos pos,
                            BlockState state, RubyBlockEntity be) {
        if (level.isClientSide) return;
        be.counter++;
        if (be.counter % 20 == 0) be.setChanged();
    }

    @Override
    protected void saveAdditional(CompoundTag tag) {
        super.saveAdditional(tag);
        tag.putInt("Counter", counter);
    }

    @Override
    public void load(CompoundTag tag) {
        super.load(tag);
        counter = tag.getInt("Counter");
    }

    // 需要把数据同步到客户端时再加：getUpdateTag / getUpdatePacket / onDataPacket
}

// ---- 注册 ----
public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
        DeferredRegister.create(ForgeRegistries.BLOCK_ENTITY_TYPES, ExampleMod.MOD_ID);

public static final RegistryObject<BlockEntityType<RubyBlockEntity>> RUBY_BLOCK_ENTITY =
        BLOCK_ENTITIES.register("ruby_block_entity",
                () -> BlockEntityType.Builder.of(RubyBlockEntity::new, ExampleBlocks.RUBY_BLOCK.get())
                        .build(null));
```

`BlockEntityType.Builder` 实测：`of(BlockEntitySupplier<? extends T>, Block...)`、`build(Type<?>)`（`null` 表示无 DataFixer 类型）。

ticker 绑定在方块上，不在方块实体类型上：

```java
public class RubyBlock extends Block {
    public RubyBlock(Properties props) { super(props); }

    @Override
    public <T extends BlockEntity> net.minecraft.world.level.block.entity.BlockEntityTicker<T> getTicker(
            net.minecraft.world.level.Level level, BlockState state, BlockEntityType<T> type) {
        return type == ExampleBlockEntities.RUBY_BLOCK_ENTITY.get()
                ? (lvl, pos, st, be) -> RubyBlockEntity.tick(lvl, pos, st, (RubyBlockEntity) be)
                : null;
    }
}
```

### 6.5 菜单：`MenuType` + `AbstractContainerMenu` + `ContainerData`

```java
package com.example.examplemod;

import net.minecraft.world.SimpleContainer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.ContainerData;
import net.minecraft.world.inventory.SimpleContainerData;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.flag.FeatureFlags;
import net.minecraft.world.inventory.MenuType;
import net.minecraftforge.common.extensions.IForgeMenuType;

public class RubyMenu extends AbstractContainerMenu {

    private final ContainerData data;
    private final net.minecraft.world.Container container;

    // 服务端构造：MenuType.MenuSupplier 是 (int, Inventory) -> T
    public RubyMenu(int id, Inventory playerInv) {
        this(id, playerInv, new SimpleContainer(1), new SimpleContainerData(2));
    }

    // 客户端构造（带额外同步数据时用 IForgeMenuType）
    public RubyMenu(int id, Inventory playerInv, net.minecraft.world.Container container, ContainerData data) {
        super(ExampleMenus.RUBY_MENU.get(), id);
        this.container = container;
        this.data = data;

        this.addSlot(new Slot(container, 0, 80, 20));
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 9; col++) {
                this.addSlot(new Slot(playerInv, col + row * 9 + 9, 8 + col * 18, 84 + row * 18));
            }
        }
        for (int col = 0; col < 9; col++) {
            this.addSlot(new Slot(playerInv, col, 8 + col * 18, 142));
        }
        this.addDataSlots(data);   // 让 data 走 ContainerSynchronizer 同步
    }

    public int getProgress() { return data.get(0); }
    public int getMaxProgress() { return data.get(1); }

    @Override
    public boolean stillValid(Player player) {
        return container.stillValid(player);
    }
}

// ---- 注册 ----
public static final DeferredRegister<MenuType<?>> MENUS =
        DeferredRegister.create(ForgeRegistries.MENU_TYPES, ExampleMod.MOD_ID);

// 方式 A：普通 MenuSupplier（(int, Inventory) -> T）
public static final RegistryObject<MenuType<RubyMenu>> RUBY_MENU =
        MENUS.register("ruby_menu", () -> new MenuType<>(RubyMenu::new, FeatureFlags.VANILLA_SET));

// 方式 B：需要从 FriendlyByteBuf 读额外数据时用 IForgeMenuType.create
// public static final RegistryObject<MenuType<RubyMenu>> RUBY_MENU_B =
//         MENUS.register("ruby_menu_b", () -> IForgeMenuType.create(
//                 (id, inv, buf) -> new RubyMenu(id, inv, new SimpleContainer(1), new SimpleContainerData(2))));
```

`MenuType` 构造器实测为 `MenuType(MenuSupplier<T>, FeatureFlagSet)`，`FeatureFlags.VANILLA_SET` 可用；`IForgeMenuType.create(IContainerFactory<T>)` 是 Forge 便利工厂（`(int, Inventory, FriendlyByteBuf)`）。

`ContainerData`（实测三方法）：

```java
public interface ContainerData {
    int get(int index);
    void set(int index, int value);
    int getCount();
}
```

用 `SimpleContainerData(n)` 即可；服务端改数据后客户端在菜单同步包里读到 `Slot`/`DataSlot` 的镜像值。

### 6.6 创造模式标签页

```java
public static final DeferredRegister<CreativeModeTab> TABS =
        DeferredRegister.create(net.minecraft.core.registries.Registries.CREATIVE_MODE_TAB,
                ExampleMod.MOD_ID);

public static final RegistryObject<CreativeModeTab> RUBY_TAB = TABS.register("ruby_tab",
        () -> CreativeModeTab.builder()
                .title(Component.translatable("itemGroup.examplemod.ruby"))
                .icon(() -> new ItemStack(ExampleItems.RUBY.get()))
                .displayItems((params, output) -> {
                    output.accept(ExampleItems.RUBY.get());
                    output.accept(ExampleItems.RUBY_SWORD.get());
                })
                .withTabsBefore(CreativeModeTabs.INGREDIENTS)   // 排到原版「材料」页之前
                .build());
```

`CreativeModeTab.builder()` 实测存在（另有 `builder(Row, int)`），Builder 方法实测：`title(Component)`、`icon(Supplier<ItemStack>)`、`displayItems(DisplayItemsGenerator)`、`withTabsBefore(ResourceLocation...)` / `(ResourceKey...)`、`withTabsAfter(...)`、`alignedRight()`、`hideTitle()`、`noScrollBar()`、`withBackgroundLocation(ResourceLocation)`、`withSearchBar()`、`build()`。

把物品追加到**别人的**标签页（含原版页）用 `BuildCreativeModeTabContentsEvent`（mod 总线、仅客户端，实测 `final class`，`getTab()`/`getTabKey()`/`getEntries()`/`accept(...)`）：

```java
@SubscribeEvent
public static void onBuildTab(BuildCreativeModeTabContentsEvent event) {
    if (event.getTabKey() == CreativeModeTabs.INGREDIENTS) {
        event.accept(ExampleItems.RUBY.get());
    }
}
```

注意：1.20.1 **没有** `CreativeModeTabEvent`（那是 1.19.3 过渡期的类名，已删除并被本事件取代）。

### 6.7 工具材质：1.20.1 没有 `SimpleTier`

`net.minecraft.world.item.Tier` 是接口（实测方法）：

```java
public interface Tier {
    int getUses();
    float getSpeed();
    float getAttackDamageBonus();
    @Deprecated int getLevel();
    int getEnchantmentValue();
    Ingredient getRepairIngredient();
    default TagKey<Block> getTag() { return null; }
}
```

自己实现一个（`SimpleTier` 是 NeoForge 1.21 才有的便利类，1.20.1 不存在）：

```java
public final class RubyTier implements Tier {
    public static final RubyTier INSTANCE = new RubyTier();

    @Override public int getUses() { return 250; }
    @Override public float getSpeed() { return 7.0F; }
    @Override public float getAttackDamageBonus() { return 2.5F; }
    @Override public int getLevel() { return 3; }              // 已废弃但必须实现
    @Override public int getEnchantmentValue() { return 18; }
    @Override public Ingredient getRepairIngredient() {
        return Ingredient.of(ExampleItems.RUBY.get());
    }
}
```

若要让自定义材质参与「正确挖掘等级」判定与排序，注册到 `TierSortingRegistry`（`net.minecraftforge.common.TierSortingRegistry`，实测静态方法 `registerTier(Tier, ResourceLocation, List<Object> after, List<Object> before)`、`isCorrectTierForDrops(Tier, BlockState)`、`getTiersLowerThan(Tier)`）：

```java
TierSortingRegistry.registerTier(RubyTier.INSTANCE,
        new ResourceLocation(ExampleMod.MOD_ID, "ruby"),
        List.of(Tiers.IRON), List.of(Tiers.DIAMOND));
```

### 6.8 `IForgeItem` / `IForgeBlock` 扩展点

`Item` 通过 `IForgeItem` 增加了一批 ItemStack 敏感的钩子（实测默认方法）：

| 方法 | 用途 |
|---|---|
| `getBurnTime(ItemStack, RecipeType<?>)` | 燃料时长（tick） |
| `onEntitySwing(ItemStack, LivingEntity)` | 挥动时（返回 `true` 表示已处理） |
| `onLeftClickEntity(ItemStack, Player, Entity)` | 攻击实体前 |
| `onItemUseFirst(ItemStack, UseOnContext)` | 先于方块交互执行 |
| `getFoodProperties(ItemStack, LivingEntity)` | ItemStack 敏感的食物属性 |
| `getAttributeModifiers(EquipmentSlot, ItemStack)` | 按槽位返回属性修饰符 |
| `onInventoryTick(ItemStack, Level, Player, int, int)` | 背包内 tick（替代已废弃的 `onArmorTick`） |
| `getShareTag(ItemStack)` / `readShareTag(ItemStack, CompoundTag)` | 客户端同步 NBT 裁剪 |
| `isBookEnchantable(ItemStack, ItemStack)` | 附魔书能否打在物品上 |
| `getEntityLifespan(ItemStack, Level)` | 掉落物存活时长 |
| `doesSneakBypassUse(ItemStack, LevelReader, BlockPos, Player)` | 潜行是否绕过方块交互 |

`IForgeBlock` 提供 `getExplosionResistance`、`onBlockExploded`、`isFragile`、`getAppearance` 等；`IForgeBlockEntity` 提供跨区块 tick 与 capability 相关的默认实现。这些是**接口默认方法**，在自定义类里 `@Override` 即可，不需要实现接口。

### 6.9 其它注册项

下面按「注册表项类型」逐个给最小写法。用到的类型都在 `net.minecraft.world.effect`（`MobEffect`、`MobEffectInstance`、`MobEffects`、`MobEffectCategory`）、`net.minecraft.world.entity`（`LivingEntity`）与 `net.minecraft.core.particles`（`SimpleParticleType`、`ParticleType`）中。

```java
// 药水效果：MobEffect 的构造器实测是 protected MobEffect(MobEffectCategory, int color)
// 以及 protected MobEffect(MobEffectCategory, int, ParticleOptions)，所以**不能**在模组包里
// 直接 new MobEffect(...)，必须继承（或写成匿名子类）。override 的方法名实测为
// applyEffectTick(LivingEntity, int) -> boolean 与 shouldApplyEffectTickThisTick(int, int) -> boolean。
public class RubyShieldEffect extends MobEffect {
    public RubyShieldEffect() {
        super(MobEffectCategory.BENEFICIAL, 0xCC3344);   // 被子类调用 protected 构造器，合法
    }

    @Override
    public boolean applyEffectTick(LivingEntity living, int amplifier) {
        living.addEffect(new MobEffectInstance(MobEffects.DAMAGE_RESISTANCE, 60, amplifier));
        return true;
    }

    // 返回 true 才会每 tick 调 applyEffectTick
    @Override
    public boolean shouldApplyEffectTickThisTick(int duration, int amplifier) {
        return true;
    }
}

public static final DeferredRegister<MobEffect> EFFECTS =
        DeferredRegister.create(ForgeRegistries.MOB_EFFECTS, MOD_ID);
public static final RegistryObject<MobEffect> RUBY_SHIELD =
        EFFECTS.register("ruby_shield", RubyShieldEffect::new);

// 粒子：SimpleParticleType(boolean overrideLimiter)
public static final DeferredRegister<ParticleType<?>> PARTICLES =
        DeferredRegister.create(ForgeRegistries.PARTICLE_TYPES, MOD_ID);
public static final RegistryObject<SimpleParticleType> RUBY_SPARK =
        PARTICLES.register("ruby_spark", () -> new SimpleParticleType(true));

// 声音事件：可变距离，避免硬编码 range
public static final DeferredRegister<SoundEvent> SOUNDS =
        DeferredRegister.create(ForgeRegistries.SOUND_EVENTS, MOD_ID);
public static final RegistryObject<SoundEvent> RUBY_CHIME = SOUNDS.register("ruby_chime",
        () -> SoundEvent.createVariableRangeEvent(new ResourceLocation(MOD_ID, "ruby_chime")));

// 配方序列化器
public static final DeferredRegister<RecipeSerializer<?>> RECIPE_SERIALIZERS =
        DeferredRegister.create(ForgeRegistries.RECIPE_SERIALIZERS, MOD_ID);
public static final RegistryObject<SimpleCraftingRecipeSerializer<RubyRecipe>> RUBY_RECIPE =
        RECIPE_SERIALIZERS.register("ruby_crafting",
                () -> new SimpleCraftingRecipeSerializer<>(RubyRecipe::new));

// 实体类型
public static final DeferredRegister<EntityType<?>> ENTITIES =
        DeferredRegister.create(ForgeRegistries.ENTITY_TYPES, MOD_ID);
public static final RegistryObject<EntityType<RubyGolem>> RUBY_GOLEM = ENTITIES.register("ruby_golem",
        () -> EntityType.Builder.of(RubyGolem::new, MobCategory.MISC)
                .sized(0.6F, 1.8F)
                .clientTrackingRange(8)
                .build("ruby_golem"));

// 属性（自定义属性用 RangedAttribute，翻译键写在 lang 里）
public static final DeferredRegister<Attribute> ATTRIBUTES =
        DeferredRegister.create(ForgeRegistries.ATTRIBUTES, MOD_ID);
public static final RegistryObject<Attribute> RUBY_LUCK = ATTRIBUTES.register("ruby_luck",
        () -> new RangedAttribute("attribute.examplemod.ruby_luck", 0.0D, 0.0D, 1024.0D)
                .setSyncable(true));
```

实体属性必须在 mod 总线事件里挂：

```java
@SubscribeEvent
public static void onEntityAttributes(EntityAttributeCreationEvent event) {
    // 实测：put(EntityType<? extends LivingEntity>, AttributeSupplier)
    event.put(ExampleEntities.RUBY_GOLEM.get(),
            RubyGolem.createAttributes().build());
}
```

---

## 7. 事件

### 7.1 订阅器声明

```java
@Mod.EventBusSubscriber(modid = ExampleMod.MOD_ID, bus = Mod.EventBusSubscriber.Bus.MOD)
public final class ModEvents {
    @SubscribeEvent
    public static void onCommonSetup(FMLCommonSetupEvent event) { /* … */ }
}
```

实测 `@Mod.EventBusSubscriber` 的三个成员：`Dist[] value()`（默认 `{CLIENT, DEDICATED_SERVER}`）、`String modid()`（默认空）、`Bus bus()`（默认 `Bus.FORGE`）。`Bus` 只有 `FORGE` 与 `MOD` 两个值。

- 监听方法必须 `public static`（自动订阅扫描只认静态方法）。
- 手动注册用 `modBus.addListener(this::method)`，此时方法可以是实例方法。

### 7.2 优先级与取消

```java
import net.minecraftforge.eventbus.api.EventPriority;

@SubscribeEvent(priority = EventPriority.HIGHEST, receiveCanceled = true)
public static void onLivingDamage(LivingDamageEvent event) { /* … */ }
```

- 优先级顺序（从先到后）：`HIGHEST` → `HIGH` → `NORMAL` → `LOW` → `LOWEST`。
- 同一优先级内，注册/扫描顺序决定调用顺序，**不要依赖**扫描顺序做业务（用 `ordering = AFTER/BEFORE` 的模组依赖来保证跨模组顺序）。
- 取消：事件类带 `@Cancelable`（如 `BlockEvent.BreakEvent`、`LivingHurtEvent`）才能 `event.setCanceled(true)`；取消后同一优先级后续监听器与所有低优先级监听器默认被跳过，除非 `receiveCanceled = true`。
- `@HasResult` 的事件（如 `PlayerInteractEvent`）需要 `event.setResult(Result.ALLOW/DENY/DEFAULT)`，不是 `setCanceled`。

### 7.3 mod 总线（加载期）常用事件

| 事件 | 时机 | 典型用途 |
|---|---|---|
| `FMLConstructModEvent` | 模组类刚被构造 | 早期初始化，极少用 |
| `RegisterEvent` | 每次某个注册表开始填充（**按注册表分别触发**） | 需要按注册表批量注册的第三方体系（如 `RegisterEvent` 里再注册） |
| `EntityAttributeCreationEvent` | 实体属性构建 | `event.put(type, supplier)` |
| `EntityAttributeModificationEvent` | 给已存在实体追加属性 | 给原版实体加自定义属性 |
| `FMLCommonSetupEvent` | 全局 setup（并行） | 网络通道、跨注册表逻辑，必须 `enqueueWork` |
| `FMLClientSetupEvent` | 客户端 setup（并行） | `MenuScreens.register`、按键以外的客户端注册 |
| `FMLDedicatedServerSetupEvent` | 专用服务端 setup（并行） | 仅服务端需要的初始化 |
| `BuildCreativeModeTabContentsEvent` | 标签页填充（客户端、可能多次触发） | 追加/移除标签页条目 |
| `RegisterCapabilitiesEvent` | capability 注册 | `event.register(IItemHandler.class)` |
| `RegisterKeyMappingsEvent` | 客户端按键注册 | `event.register(new KeyMapping(...))` |
| `GatherDataEvent` | `runData` | 注册 DataProvider |
| `InterModEnqueueEvent` / `InterModProcessEvent` | 模组间通信 | 向其它模组发 `InterModComms` |
| `FMLLoadCompleteEvent` | 加载完全结束 | 最后收尾 |

### 7.4 Forge 总线（游戏期）常用事件

| 事件 | 说明 |
|---|---|
| `ServerStartingEvent` / `ServerStartedEvent` / `ServerStoppingEvent` / `ServerStoppedEvent` | 服务端生命周期（`net.minecraftforge.event.server.*`）；`getServer()` 来自父类 `ServerLifecycleEvent` |
| `PlayerEvent.PlayerLoggedInEvent` / `PlayerLoggedOutEvent` / `PlayerRespawnEvent` / `PlayerChangedDimensionEvent` | 玩家生命周期 |
| `PlayerEvent.Clone` | 死亡克隆（复制数据的地方） |
| `PlayerInteractEvent.RightClickBlock` / `RightClickItem` / `LeftClickBlock` / `EntityInteract` / `EntityInteractSpecific` | 交互 |
| `LivingHurtEvent` | 伤害计算阶段（可改 `getAmount()`），1.20.1 仍存在 |
| `LivingDamageEvent` | 伤害已确定、即将扣血（常用于减免/加成） |
| `LivingDeathEvent` / `LivingDropsEvent` / `LivingExperienceDropEvent` | 死亡与掉落 |
| `BlockEvent.BreakEvent` | 方块被破坏（可取消）；`BlockEvent.EntityPlaceEvent` 放置 |
| `TickEvent.ServerTickEvent` / `TickEvent.ClientTickEvent` / `TickEvent.LevelTickEvent` / `TickEvent.PlayerTickEvent` / `TickEvent.RenderTickEvent` | 各类 tick；**都是嵌套在 `TickEvent` 里的静态类**，写 `ServerTickEvent` 单独 import 会编译失败 |
| `EntityJoinLevelEvent` | 实体进入世界（含区块加载回放） |
| `RegisterCommandsEvent` | 注册 `/yourcmd`；`getDispatcher()` 实测存在 |
| `AddReloadListenerEvent` | 数据包 reload 时挂自定义 listener；`addListener(PreparableReloadListener)` 实测 |
| `OnDatapackSyncEvent` | 数据包同步给玩家；`getPlayer()`（可能为 `null` 表示全量同步）、`getPlayers()`、`getPlayerList()` 实测 |
| `AttachCapabilitiesEvent<ItemStack/BlockEntity/Entity>` | 给对象挂 capability |
| `ExplosionEvent.Detonate` | 爆炸影响列表 |
| `LevelEvent.Load` / `LevelEvent.Unload` | 维度加载/卸载 |

### 7.5 事件代码示例

```java
@Mod.EventBusSubscriber(modid = ExampleMod.MOD_ID)   // 默认 FORGE 总线
public final class GameEvents {

    @SubscribeEvent
    public static void onLogin(PlayerEvent.PlayerLoggedInEvent event) {
        event.getEntity().sendSystemMessage(Component.literal("Welcome"));
    }

    @SubscribeEvent
    public static void onPlayerTick(TickEvent.PlayerTickEvent event) {
        // PlayerTickEvent 每 tick 触发两次（START/END），必须判 phase
        if (event.phase != TickEvent.Phase.END) return;
        if (event.player.level().isClientSide) return;
    }

    @SubscribeEvent
    public static void onLevelTick(TickEvent.LevelTickEvent event) {
        if (event.phase != TickEvent.Phase.END) return;
    }

    @SubscribeEvent
    public static void onBreak(BlockEvent.BreakEvent event) {
        if (event.getPlayer().isCreative()) return;
        // 取消方块破坏
        event.setCanceled(event.getState().is(ExampleBlocks.RUBY_BLOCK.get()));
    }

    @SubscribeEvent
    public static void onServerStarting(ServerStartingEvent event) {
        // 此时 Registry 已就绪，可以安全 get()
        event.getServer().setMotd("Ruby Server");
    }

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(
                Commands.literal("ruby")
                        .executes(ctx -> {
                            ctx.getSource().sendSuccess(() -> Component.literal("ruby!"), false);
                            return 1;
                        }));
    }
}
```

`ServerStartingEvent` 的 `getServer()` 来自 `ServerLifecycleEvent`；`RegisterCommandsEvent` 实测有 `getDispatcher()`、`getCommandSelection()`、`getBuildContext()`（1.20.1 的注册命令要用 `getBuildContext()` 而不是旧的 `getRegistryAccess()`）。

---

## 8. 配置

### 8.1 完整的 `ForgeConfigSpec`

`ForgeConfigSpec` 在 `net.minecraftforge.common`。

```java
package com.example.examplemod;

import net.minecraftforge.common.ForgeConfigSpec;

public final class Config {

    public static final ForgeConfigSpec SPEC;
    public static final ForgeConfigSpec.BooleanValue RUBY_ENABLED;
    public static final ForgeConfigSpec.IntValue RUBY_DROP_CHANCE;
    public static final ForgeConfigSpec.DoubleValue RUBY_SPEED;
    public static final ForgeConfigSpec.ConfigValue<String> RUBY_GREETING;
    public static final ForgeConfigSpec.EnumValue<Difficulty> RUBY_DIFFICULTY;
    public static final ForgeConfigSpec.ConfigValue<java.util.List<? extends String>> RUBY_DIMENSIONS;

    public enum Difficulty { EASY, NORMAL, HARD }

    static {
        ForgeConfigSpec.Builder builder = new ForgeConfigSpec.Builder();

        builder.comment("General settings").push("general");
        RUBY_ENABLED = builder
                .comment("是否启用红宝石内容")
                .define("rubyEnabled", true);
        RUBY_DROP_CHANCE = builder
                .comment("矿石掉落几率（百分比）")
                .defineInRange("rubyDropChance", 5, 0, 100);
        RUBY_SPEED = builder
                .defineInRange("rubySpeed", 1.0D, 0.0D, 10.0D);
        RUBY_GREETING = builder
                .define("rubyGreeting", "Hello, ruby!");
        RUBY_DIFFICULTY = builder
                .defineEnum("rubyDifficulty", Difficulty.NORMAL);
        RUBY_DIMENSIONS = builder
                .comment("生效维度 ID 列表")
                .defineList("rubyDimensions",
                        java.util.List.of("minecraft:overworld"),
                        o -> o instanceof String);
        builder.pop();

        builder.comment("Client only").push("client");
        builder.define("showRubyHud", true);
        builder.pop();

        SPEC = builder.build();
    }
}
```

`Builder` 实测方法：`comment(String)` / `comment(String...)`、`push(String)` / `push(List<String>)`、`pop()` / `pop(int)`、`define(String, boolean)`、`defineInRange(String, double|int|long, min, max)`、`defineEnum(String, V)` / `defineEnum(String, V, V...)` / `defineEnum(String, V, Collection<V>)`、`defineList(String, List<? extends T>, Predicate<Object>)`、`defineListAllowEmpty(...)`、`build()`。

注意 `defineList` 的默认值不能是空列表（空列表会被判为「需要修正」，Forge 直接提示改用 `defineListAllowEmpty`）。

### 8.2 注册与类型

```java
ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, Config.SPEC, "examplemod-common.toml");
ModLoadingContext.get().registerConfig(ModConfig.Type.CLIENT, ClientConfig.SPEC);
ModLoadingContext.get().registerConfig(ModConfig.Type.SERVER, ServerConfig.SPEC);
```

| 类型 | 文件位置 | 同步行为 |
|---|---|---|
| `COMMON` | `config/<modid>-common.toml` | 不随服务器下发，客户端与服务端各自读本地 |
| `CLIENT` | `config/<modid>-client.toml` | 仅客户端 |
| `SERVER` | `world/serverconfig/<modid>-server.toml` | 存于世界存档，服务端启动/切换世界时加载 |

`ForgeConfigSpec` 实现了 `IConfigSpec`，因此可直接传给 `registerConfig(Type, IConfigSpec<?>, String)`（实测重载存在）。

### 8.3 读写的正确姿势

- **缓存**：`ConfigValue#get()` 每次都会走 TOML 查找，热路径（tick、渲染）应在首次使用时缓存到字段，并在 `ModConfigEvent.Reloading` 时刷新。
- 修改：`value.set(x)` 只改内存；写盘用 `value.save()`（或 `Spec.save()`）。服务端配置修改后要 `SPEC.save()` 才会落到 `serverconfig`。

```java
private static boolean cachedRubyEnabled = true;

@Mod.EventBusSubscriber(modid = ExampleMod.MOD_ID, bus = Mod.EventBusSubscriber.Bus.MOD)
public final class ConfigEvents {

    @SubscribeEvent
    public static void onLoading(ModConfigEvent.Loading event) {
        cachedRubyEnabled = Config.RUBY_ENABLED.get();
    }

    @SubscribeEvent
    public static void onReloading(ModConfigEvent.Reloading event) {
        // 文件被改后重读并刷新缓存
        cachedRubyEnabled = Config.RUBY_ENABLED.get();
    }
}
```

`ModConfigEvent` 的 `Loading` / `Reloading` / `Unloading` 三个子类实测存在（`net.minecraftforge.fml.event.config`，mod 总线）。早期版本用 `ModConfigEvent` 本身，1.20.1 必须订阅具体子类。

---

## 9. 网络

### 9.1 通道与消息（1.20.1 完整可编译示例）

```java
package com.example.examplemod.network;

import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraftforge.network.NetworkDirection;
import net.minecraftforge.network.NetworkEvent;
import net.minecraftforge.network.NetworkRegistry;
import net.minecraftforge.network.PacketDistributor;
import net.minecraftforge.network.simple.SimpleChannel;

import java.util.Optional;
import java.util.function.Supplier;

public final class ModNetwork {

    private static final String PROTOCOL = "1";

    // 通道名必须是 资源位置；协议版本不匹配会拒绝连接
    public static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
            new ResourceLocation(ExampleMod.MOD_ID, "main"),
            () -> PROTOCOL,
            PROTOCOL::equals,   // 客户端接受的服务端版本
            PROTOCOL::equals    // 服务端接受的客户端版本
    );

    private ModNetwork() { }

    public static void init() {
        int id = 0;
        CHANNEL.registerMessage(id++, RubyMessage.class,
                RubyMessage::encode,
                RubyMessage::decode,
                RubyMessage::handle,
                Optional.of(NetworkDirection.PLAY_TO_SERVER));

        CHANNEL.registerMessage(id++, RubySyncMessage.class,
                RubySyncMessage::encode,
                RubySyncMessage::decode,
                RubySyncMessage::handle,
                Optional.of(NetworkDirection.PLAY_TO_CLIENT));
    }

    // ---- 发送辅助 ----
    public static void sendToServer(Object msg) {
        CHANNEL.sendToServer(msg);
    }

    public static void sendToPlayer(Object msg, ServerPlayer player) {
        CHANNEL.send(PacketDistributor.PLAYER.with(() -> player), msg);
    }

    public static void sendToAll(Object msg) {
        CHANNEL.send(PacketDistributor.ALL.noArg(), msg);
    }

    public static void sendToDimension(Object msg, net.minecraft.resources.ResourceKey<net.minecraft.world.level.Level> dim) {
        CHANNEL.send(PacketDistributor.DIMENSION.with(() -> dim), msg);
    }
}
```

实测签名：

- `NetworkRegistry.newSimpleChannel(ResourceLocation, Supplier<String>, Predicate<String>, Predicate<String>)`。
- `SimpleChannel#registerMessage(int, Class<MSG>, BiConsumer<MSG, FriendlyByteBuf>, Function<FriendlyByteBuf, MSG>, BiConsumer<MSG, Supplier<NetworkEvent.Context>>)` —— 5 参数版；6 参数版第 6 个参数是 `Optional<NetworkDirection>`（**不是** `NetworkDirection` 本身）。
- `SimpleChannel#sendToServer(MSG)`、`SimpleChannel#send(PacketDistributor.PacketTarget, MSG)`、`SimpleChannel#sendTo(MSG, Connection, NetworkDirection)`。

### 9.2 `PacketDistributor`（真实形态）

**1.20.1 没有 `PacketDistributor.sendToPlayer/sendToServer/sendToAllPlayers/sendToAllPlayersInDimension` 这些静态方法**（那是 NeoForge 1.20.5+ 的写法）。1.20.1 是「静态分发器实例 + `with(Supplier)` + `channel.send(target, msg)`」：

| 分发器 | 目标 | 方向 |
|---|---|---|
| `PacketDistributor.PLAYER` | 单个 `ServerPlayer` | PLAY_TO_CLIENT |
| `PacketDistributor.ALL` | 所有在线玩家（`.noArg()`） | PLAY_TO_CLIENT |
| `PacketDistributor.DIMENSION` | 指定维度的所有玩家 | PLAY_TO_CLIENT |
| `PacketDistributor.NEAR` | `TargetPoint`（中心 + 半径） | PLAY_TO_CLIENT |
| `PacketDistributor.TRACKING_ENTITY` | 跟踪该实体的玩家 | PLAY_TO_CLIENT |
| `PacketDistributor.TRACKING_ENTITY_AND_SELF` | 跟踪者 + 实体本身（玩家实体必用） | PLAY_TO_CLIENT |
| `PacketDistributor.TRACKING_CHUNK` | 该区块的观察者 | PLAY_TO_CLIENT |
| `PacketDistributor.SERVER` | 发给服务端（等价 `sendToServer`） | PLAY_TO_SERVER |
| `PacketDistributor.NMLIST` | 直接给 `List<Connection>` | PLAY_TO_CLIENT |

### 9.3 自定义消息类

```java
public class RubyMessage {

    private final int amount;

    public RubyMessage(int amount) { this.amount = amount; }

    // 解码构造器：Function<FriendlyByteBuf, RubyMessage>
    public RubyMessage(FriendlyByteBuf buf) { this.amount = buf.readVarInt(); }

    public void encode(FriendlyByteBuf buf) { buf.writeVarInt(amount); }

    public static void handle(RubyMessage msg, Supplier<NetworkEvent.Context> ctxSupplier) {
        NetworkEvent.Context ctx = ctxSupplier.get();
        // 解码在网络线程，改游戏状态必须回主线程
        ctx.enqueueWork(() -> {
            ServerPlayer sender = ctx.getSender();   // 客户端→服务端时非空
            if (sender == null) return;
            // 服务端业务逻辑
        });
        ctx.setPacketHandled(true);   // 忘记调用会触发「未处理包」警告并可能断连
    }
}
```

`NetworkEvent.Context` 实测方法：`enqueueWork(Runnable)`（返回 `CompletableFuture<Void>`）、`setPacketHandled(boolean)`、`getSender()`（`ServerPlayer`，仅 PLAY_TO_SERVER 有值）、`getDirection()`、`getNetworkManager()`。

### 9.4 「IntArrayPacket」式极简包

原版有 `ClientboundContainerSetDataPacket` 之类的内置包；自定义最小包直接复用 `int[]`：

```java
public record IntArrayPacket(int[] values) {

    public IntArrayPacket(FriendlyByteBuf buf) { this(buf.readVarIntArray()); }

    public void encode(FriendlyByteBuf buf) { buf.writeVarIntArray(values); }

    public static void handle(IntArrayPacket msg, Supplier<NetworkEvent.Context> ctxSupplier) {
        NetworkEvent.Context ctx = ctxSupplier.get();
        ctx.enqueueWork(() -> {
            // 举例：把数组里的值套到本地玩家某个同步状态上
        });
        ctx.setPacketHandled(true);
    }
}
```

注意数组需要防御性拷贝（`values.clone()`），否则发送端后续修改会影响已编码内容。

### 9.5 注册时机

`registerMessage` 必须在任何发包之前执行，且只在 `FMLCommonSetupEvent#enqueueWork` 里注册（见 §5.1）。不要放进主类构造器：构造期早于注册表就绪，消息类或编解码器一旦在静态初始化里访问 `RegistryObject#get()`（例如引用 `ItemStack` 编解码），就可能在该时机提前触发类加载并 NPE。

---

## 10. Capability

### 10.1 概念与注册

1.20.1 用 `CapabilityManager` + `CapabilityToken` + `ForgeCapabilities`：

```java
// 自定义 capability 的令牌（匿名子类，类型参数决定 Capability<T>）
public static final Capability<IRubyStorage> RUBY_STORAGE =
        CapabilityManager.get(new CapabilityToken<>() { });

// 在 mod 总线上声明，否则别人 getCapability 永远拿不到
@SubscribeEvent
public static void onRegisterCaps(RegisterCapabilitiesEvent event) {
    event.register(IRubyStorage.class);
}
```

Forge 内置四件套（实测常量）：

```java
ForgeCapabilities.ITEM_HANDLER        // IItemHandler
ForgeCapabilities.FLUID_HANDLER       // IFluidHandler
ForgeCapabilities.FLUID_HANDLER_ITEM  // IFluidHandlerItem
ForgeCapabilities.ENERGY              // IEnergyStorage
```

包名是 `net.minecraftforge.common.capabilities.ForgeCapabilities`。1.20.1 **没有** `Capabilities.ItemHandler.BLOCK` 这种嵌套写法（那是 NeoForge 1.20.5+）。

### 10.2 给方块实体挂 capability（完整示例）

```java
import net.minecraft.core.Direction;
import net.minecraft.nbt.CompoundTag;
import net.minecraftforge.common.capabilities.Capability;
import net.minecraftforge.common.capabilities.CapabilityManager;
import net.minecraftforge.common.capabilities.CapabilityToken;
import net.minecraftforge.common.capabilities.ICapabilityProvider;
import net.minecraftforge.common.util.LazyOptional;
import net.minecraftforge.items.ItemStackHandler;

public class RubyBlockEntity extends BlockEntity implements ICapabilityProvider {

    public static final Capability<IRubyStorage> RUBY_STORAGE =
            CapabilityManager.get(new CapabilityToken<>() { });

    private final ItemStackHandler inventory = new ItemStackHandler(9) {
        @Override
        protected void onContentsChanged(int slot) {
            setChanged();
        }
    };
    private LazyOptional<ItemStackHandler> inventoryOptional = LazyOptional.of(() -> inventory);

    public RubyBlockEntity(BlockPos pos, BlockState state) {
        super(ExampleBlockEntities.RUBY_BLOCK_ENTITY.get(), pos, state);
    }

    @Override
    public <T> LazyOptional<T> getCapability(Capability<T> cap, Direction side) {
        if (cap == ForgeCapabilities.ITEM_HANDLER) {
            return inventoryOptional.cast();
        }
        return super.getCapability(cap, side);   // BlockEntity 本身实现了 ICapabilityProvider
    }

    @Override
    public void invalidateCaps() {
        super.invalidateCaps();
        inventoryOptional.invalidate();   // 必须，否则残留 LazyOptional 造成内存/状态泄漏
    }

    @Override
    protected void saveAdditional(CompoundTag tag) {
        super.saveAdditional(tag);
        tag.put("Inventory", inventory.serializeNBT());
    }

    @Override
    public void load(CompoundTag tag) {
        super.load(tag);
        inventory.deserializeNBT(tag.getCompound("Inventory"));
    }
}
```

`ICapabilityProvider` 实测只有一个抽象方法 `getCapability(Capability<T>, Direction)`，外加默认 `getCapability(Capability<T>)` 转发 `side = null`。

### 10.3 给 ItemStack / Entity 挂 capability

```java
@SubscribeEvent
public static void onAttachItemCaps(AttachCapabilitiesEvent<ItemStack> event) {
    // 实测：getObject()、addCapability(ResourceLocation, ICapabilityProvider)、getCapabilities()
    if (!event.getObject().is(ExampleItems.RUBY.get())) return;
    event.addCapability(new ResourceLocation(ExampleMod.MOD_ID, "ruby_storage"),
            new RubyItemStorageProvider());
}

@SubscribeEvent
public static void onAttachEntityCaps(AttachCapabilitiesEvent<Entity> event) {
    if (!(event.getObject() instanceof Player)) return;
    event.addCapability(new ResourceLocation(ExampleMod.MOD_ID, "ruby_data"),
            new RubyPlayerDataProvider());
}
```

`AttachCapabilitiesEvent` 的泛型参数必须写精确类型（`ItemStack` / `BlockEntity` / `Entity`），Forge 按泛型分发；写成 `AttachCapabilitiesEvent<Object>` 收不到事件。

### 10.4 读取 capability

```java
import net.minecraftforge.common.capabilities.ForgeCapabilities;
import net.minecraftforge.items.IItemHandler;

// 方块实体（level 侧查询，side 为 null 表示不区分面）
IItemHandler handler = level.getCapability(ForgeCapabilities.ITEM_HANDLER, pos, null)
        .orElse(null);

// 物品堆
handler = stack.getCapability(ForgeCapabilities.ITEM_HANDLER).orElse(null);

// 实体
handler = entity.getCapability(ForgeCapabilities.ENERGY).orElse(null);
```

`LazyOptional#orElse` / `orElseThrow` / `ifPresent` / `map` / `cast`；**不要**把 `LazyOptional` 长期缓存到静态字段而不 `invalidate()`。

### 10.5 三种内置实现的构造与要点

```java
// 物品槽：ItemStackHandler(int size) 或 ()；重写 onContentsChanged 存档/同步
new ItemStackHandler(9);

// 流体罐：FluidTank(int capacity) 或 (capacity, Predicate<FluidStack> validator)
new FluidTank(4000);

// 能量：EnergyStorage(int capacity) 或 (capacity, maxReceive, maxExtract)
new EnergyStorage(10000, 1000, 1000);
```

`ItemStackHandler` 默认每槽 64、拒绝不合法物品；`FluidTank` 默认 `FluidStack.EMPTY`；`EnergyStorage` 的 `receiveEnergy/extractEnergy` 自带上限检查。三者都需要自己接 `IFluidHandler` / `IEnergyStorage` 的 capability 类型（`FluidTank` 已实现 `IFluidHandler`，`EnergyStorage` 已实现 `IEnergyStorage`，`ItemStackHandler` 已实现 `IItemHandler`）。

---

## 11. 数据生成

### 11.1 `GatherDataEvent` 接线

```java
@Mod.EventBusSubscriber(modid = ExampleMod.MOD_ID, bus = Mod.EventBusSubscriber.Bus.MOD)
public final class DataGen {

    @SubscribeEvent
    public static void gatherData(GatherDataEvent event) {
        DataGenerator generator = event.getGenerator();
        PackOutput output = generator.getPackOutput();
        ExistingFileHelper helper = event.getExistingFileHelper();
        CompletableFuture<HolderLookup.Provider> lookup = event.getLookupProvider();

        // 客户端资源：模型、方块状态、语言
        generator.addProvider(event.includeClient(),
                new ItemModels(output, helper));
        generator.addProvider(event.includeClient(),
                new BlockStates(output, helper));
        generator.addProvider(event.includeClient(),
                new EnUsLang(output));

        // 服务端数据：配方、战利品表、标签
        generator.addProvider(event.includeServer(),
                new Recipes(output));
        generator.addProvider(event.includeServer(),
                new LootTables(output));
        BlockTags blockTags = new BlockTags(output, lookup, helper);
        generator.addProvider(event.includeServer(), blockTags);
        generator.addProvider(event.includeServer(),
                new ItemTags(output, lookup, blockTags.contentsGetter(), helper));
    }
}
```

`GatherDataEvent` 实测 getter：`getGenerator()`、`getExistingFileHelper()`、`getLookupProvider()`、`includeClient()`、`includeServer()`、`includeDev()`、`includeReports()`、`validate()`、`getModContainer()`、`getInputs()`。`generator.getPackOutput()` 由 MC 的 `DataGenerator` 提供。

`DataGenerator#addProvider(boolean run, DataProvider provider)` —— 第一个参数是「是否在本次运行启用」，直接传 `event.includeClient()` / `includeServer()`。

### 11.2 常用 Provider

| Provider | 包 | 构造器 |
|---|---|---|
| `BlockStateProvider` | `net.minecraftforge.client.model.generators` | `(PackOutput, String modid, ExistingFileHelper)` |
| `ItemModelProvider` | `net.minecraftforge.client.model.generators` | `(PackOutput, String modid, ExistingFileHelper)` |
| `LanguageProvider` | `net.minecraftforge.common.data` | `(PackOutput, String modid, String locale)` |
| `BlockTagsProvider` | `net.minecraft.data.tags`（Forge 另有 `common.data.BlockTagsProvider` 基类） | `(PackOutput, CompletableFuture<HolderLookup.Provider>, String modid, ExistingFileHelper)` |
| `ItemTagsProvider` | `net.minecraft.data.tags` | `(PackOutput, CompletableFuture<HolderLookup.Provider>, BlockTagsProvider, String modid, ExistingFileHelper)` |
| `RecipeProvider` | `net.minecraft.data.recipes` | `(PackOutput)` |
| `LootTableProvider` | `net.minecraft.data.loot` | `(PackOutput, Set<ResourceLocation>, List<SubProviderEntry>)` |

`ItemModelProvider` 示例：

```java
public final class ItemModels extends ItemModelProvider {

    public ItemModels(PackOutput output, ExistingFileHelper helper) {
        super(output, ExampleMod.MOD_ID, helper);
    }

    @Override
    protected void registerModels() {
        // 生成 assets/examplemod/models/item/ruby.json（parent=item/generated）
        singleTexture("ruby", new ResourceLocation("item/generated"),
                "layer0", new ResourceLocation(ExampleMod.MOD_ID, "item/ruby"));
        // 方块物品直接借方块模型的 parent
        withExistingParent("ruby_block", new ResourceLocation(ExampleMod.MOD_ID, "block/ruby_block"));
    }
}
```

`singleTexture(String name, ResourceLocation parent, String textureKey, ResourceLocation texture)` 与 `withExistingParent(String name, ResourceLocation parent)` 实测存在（在 `ModelProvider` 上）。

`BlockStateProvider` 示例：

```java
public final class BlockStates extends BlockStateProvider {

    public BlockStates(PackOutput output, ExistingFileHelper helper) {
        super(output, ExampleMod.MOD_ID, helper);
    }

    @Override
    protected void registerStatesAndModels() {
        // 实测方法：simpleBlock / simpleBlockWithItem / cubeAll / horizontalBlock
        simpleBlockWithItem(ExampleBlocks.RUBY_BLOCK.get(),
                cubeAll(ExampleBlocks.RUBY_BLOCK.get()));
    }
}
```

`LanguageProvider` 示例：

```java
public final class EnUsLang extends LanguageProvider {

    public EnUsLang(PackOutput output) {
        super(output, ExampleMod.MOD_ID, "en_us");
    }

    @Override
    protected void addTranslations() {
        add(ExampleItems.RUBY.get(), "Ruby");
        add(ExampleBlocks.RUBY_BLOCK.get(), "Block of Ruby");
        add("itemGroup.examplemod.ruby", "Ruby Tab");
    }
}
```

`LanguageProvider` 实测：抽象方法 `addTranslations()`，`add(String key, String value)`、`add(Block, String)`、`addItem(Supplier<? extends Item>, String)`、`addEntityType(...)`、`addEffect(...)`。

### 11.3 `runData` 与输出目录

```gradle
data {
    workingDirectory project.file('run-data')
    args '--mod', mod_id, '--all',
         '--output', file('src/generated/resources/'),
         '--existing', file('src/main/resources/')
}
```

- `--output` 是生成目录，`--existing` 让生成器能看到手写资源（否则报「纹理不存在」）。
- `sourceSets.main.resources { srcDir 'src/generated/resources' }` 让生成结果进 jar。
- 生成目录不要提交冲突文件：`src/generated` 里应只有生成的 json。
- 只跑某一个模组（多模组工作区）：`--mod examplemod --client` 或 `--server`。

---

## 12. 客户端

### 12.1 订阅器与 `Dist`

```java
@Mod.EventBusSubscriber(modid = ExampleMod.MOD_ID, value = Dist.CLIENT,
        bus = Mod.EventBusSubscriber.Bus.MOD)
public final class ClientSetup { /* … */ }
```

`value = Dist.CLIENT` 让该类只在物理客户端加载。`Dist` 用 `net.minecraftforge.api.distmarker.Dist`。

### 12.2 屏幕注册：1.20.1 没有 `RegisterMenuScreensEvent`

实测 Forge 1.20.1 客户端事件里**没有** `RegisterMenuScreensEvent`（那是 NeoForge 1.20.2+ 的类）。正确做法是在 `FMLClientSetupEvent` 的 `enqueueWork` 里调 `MenuScreens.register`：

```java
import net.minecraft.client.gui.screens.MenuScreens;

@SubscribeEvent
public static void onClientSetup(FMLClientSetupEvent event) {
    event.enqueueWork(() ->
            MenuScreens.register(ExampleMenus.RUBY_MENU.get(), RubyScreen::new));
}
```

`MenuScreens.register(MenuType<M>, MenuScreens.ScreenConstructor<M, U>)`；`RubyScreen` 构造器签名固定为 `(RubyMenu menu, Inventory inv, Component title)`，继承 `AbstractContainerScreen<RubyMenu>`。

### 12.3 按键：`RegisterKeyMappingsEvent`（1.20.1 确实存在）

实测 `net.minecraftforge.client.event.RegisterKeyMappingsEvent`（mod 总线、仅客户端、不可取消），唯一方法 `register(KeyMapping)`。

```java
public final class KeyBindings {
    public static final KeyMapping OPEN_MENU = new KeyMapping(
            "key.examplemod.open_menu",
            InputConstants.Type.KEYSYM,
            GLFW.GLFW_KEY_R,
            "key.categories.examplemod");
}

@SubscribeEvent
public static void onRegisterKeys(RegisterKeyMappingsEvent event) {
    event.register(KeyBindings.OPEN_MENU);
}
```

`KeyMapping` 实测构造器：`(String, int, String)`、`(String, InputConstants.Type, int, String)`、以及带 `IKeyConflictContext` / `KeyModifier` 的重载。`GLFW` 来自 `org.lwjgl.glfw.GLFW`，LWJGL 由 Forge 提供，无需额外依赖。

按键按下检测在 `TickEvent.ClientTickEvent` 里 `while (OPEN_MENU.consumeClick()) { … }`。

### 12.4 实体/方块实体渲染器

```java
@SubscribeEvent
public static void onRenderers(EntityRenderersEvent.RegisterRenderers event) {
    // 实测签名
    event.registerEntityRenderer(ExampleEntities.RUBY_GOLEM.get(), RubyGolemRenderer::new);
    event.registerBlockEntityRenderer(ExampleBlockEntities.RUBY_BLOCK_ENTITY.get(),
            RubyBlockEntityRenderer::new);
}
```

`EntityRenderersEvent.RegisterRenderers` 的方法：`registerEntityRenderer(EntityType<? extends T>, EntityRendererProvider<T>)`、`registerBlockEntityRenderer(BlockEntityType<? extends T>, BlockEntityRendererProvider<T>)`（另有 `registerLayerDefinition` 等）。

### 12.5 粒子

```java
@SubscribeEvent
public static void onParticles(RegisterParticleProvidersEvent event) {
    // 实测：registerSpriteSet / registerSpecial / registerSprite
    event.registerSpriteSet(ExampleParticles.RUBY_SPARK.get(), RubyParticle.Provider::new);
    // 自定义 ParticleOptions：
    // event.registerSpecial(ExampleParticles.RUBY_CUSTOM.get(), RubyCustomParticle.Provider::new);
}
```

`ParticleEngine.SpriteParticleRegistration<T>` 是 `(SpriteSet) -> ParticleProvider<T>`；`registerSprite` 用固定 sprite。

### 12.6 着色器与渲染阶段

```java
@SubscribeEvent
public static void onShaders(RegisterShadersEvent event) throws IOException {
    // 实测构造器：ShaderInstance(ResourceProvider, String, VertexFormat) 或 (…, ResourceLocation, VertexFormat)
    ShaderInstance shader = new ShaderInstance(event.getResourceProvider(),
            "examplemod_ruby", DefaultVertexFormat.POSITION_TEX);
    // registerShader(ShaderInstance, Consumer<ShaderInstance>)：第二个参数在编译完成后回调
    event.registerShader(shader, s -> RUBY_SHADER = s);
}
```

`RenderLevelStageEvent`（Forge 总线、客户端）按阶段渲染，实测阶段常量：

`AFTER_SKY`、`AFTER_SOLID_BLOCKS`、`AFTER_CUTOUT_MIPPED_BLOCKS_BLOCKS`（注意 Forge 里确实拼了两次 BLOCKS）、`AFTER_CUTOUT_BLOCKS`、`AFTER_ENTITIES`、`AFTER_BLOCK_ENTITIES`、`AFTER_TRANSLUCENT_BLOCKS`、`AFTER_TRIPWIRE_BLOCKS`、`AFTER_PARTICLES`、`AFTER_WEATHER`、`AFTER_LEVEL`。

```java
@SubscribeEvent
public static void onRenderLevel(RenderLevelStageEvent event) {
    if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_TRANSLUCENT_BLOCKS) return;
    PoseStack pose = event.getPoseStack();
    // 用 event.getCamera() / getPartialTick() / getFrustum() 做可见性裁剪
}
```

`RenderLevelStageEvent` 实测 getter：`getStage()`、`getLevelRenderer()`、`getPoseStack()`、`getProjectionMatrix()`、`getRenderTick()`、`getPartialTick()`、`getCamera()`、`getFrustum()`；另有 `RenderLevelStageEvent.RegisterStageEvent`（mod 总线）用于注册自定义阶段。

### 12.7 `ScreenEvent` 与 `InputEvent`

```java
@SubscribeEvent
public static void onScreenInit(ScreenEvent.Init.Post event) {
    // 屏幕初始化完成
}

@SubscribeEvent
public static void onKey(InputEvent.Key event) {
    // event.getKey() / getScanCode() / getAction() / getModifiers()
}
```

`ScreenEvent` 实测子类结构：`Init.Pre/Post`、`Render.Pre/Post`、`BackgroundRendered`、`MouseButtonPressed.Pre/Post`、`MouseButtonReleased.Pre/Post`、`MouseDragged.Pre/Post`、`MouseScrolled.Pre/Post`、`KeyPressed.Pre/Post`、`KeyReleased.Pre/Post`、`CharacterTyped.Pre/Post`、`Opening`、`Closing`、`RenderInventoryMobEffects`。

### 12.8 `IClientItemExtensions` / `IClientBlockExtensions`

```java
public class RubyItem extends Item implements IClientItemExtensions {
    @Override
    public Font getFont(ItemStack stack, IClientItemExtensions.FontContext context) {
        return null;   // 返回 null 表示用默认字体
    }
}
```

`IClientItemExtensions`（`net.minecraftforge.client.extensions.common.IClientItemExtensions`）用于给物品自定义字体、手持渲染、护甲模型、第一人称变换等；`IClientBlockExtensions`（同包）用于方块的自定义破坏粒子、渲染类型。二者都是客户端注解之外的分发点，实现类会随物品进入客户端。

### 12.9 `BakedModel` 简述

自定义物品/方块外观的最低成本路径是**数据生成模型 json**；需要动态外观时才实现 `BakedModel`（`net.minecraft.client.resources.model.BakedModel`）。

- 包装现有模型：继承 `net.minecraftforge.client.model.BakedModelWrapper<BakedModel>`，只重写需要的方法。
- 动态数据：用 `ModelData` / `ModelProperty`（`net.minecraftforge.client.model.data`）+ 方块实体实现 `getModelData(BlockAndTintGetter, BlockPos, BlockState, ModelData)` 回报。
- 注册自定义加载器（`.obj`、多材质）走 `ModelEvent.RegisterLoaders`（`net.minecraftforge.client.event.ModelEvent`）。

---

## 13. 资源与数据路径

### 13.1 完整清单

```text
src/main/resources/
├── META-INF/mods.toml
├── pack.mcmeta                                   {"pack":{"pack_format":15,...}}
├── examplemod.mixins.json                        （仅用 mixin）
├── assets/examplemod/
│   ├── lang/en_us.json
│   ├── lang/zh_cn.json
│   ├── blockstates/ruby_block.json
│   ├── models/block/ruby_block.json
│   ├── models/item/ruby.json
│   ├── models/item/ruby_block.json
│   ├── textures/block/ruby_block.png
│   ├── textures/item/ruby.png
│   └── sounds.json                               （可选）
└── data/examplemod/
    ├── recipes/ruby_block.json
    ├── advancements/ruby.json
    ├── loot_tables/blocks/ruby_block.json
    ├── loot_tables/entities/ruby_golem.json
    ├── tags/blocks/ruby_ores.json
    ├── tags/items/ruby_gems.json
    └── forge/biome_modifier/add_ruby_ore.json     （可选）
```

1.20.1 数据目录是**复数**：`recipes`、`advancements`、`loot_tables`、`tags`、`functions`、`predicates`、`item_modifiers`、`structures`、`worldgen`。1.21 起改成单数，迁移时目录要重命名。

### 13.2 语言文件

```json
{
  "item.examplemod.ruby": "Ruby",
  "block.examplemod.ruby_block": "Block of Ruby",
  "itemGroup.examplemod.ruby": "Ruby Tab",
  "attribute.examplemod.ruby_luck": "Ruby Luck",
  "key.examplemod.open_menu": "Open Ruby Menu",
  "key.categories.examplemod": "Example Mod"
}
```

键名规则：物品 `item.<modid>.<name>`，方块 `block.<modid>.<name>`，标签页 `itemGroup.<modid>.<name>`，属性 `attribute.<modid>.<name>`。

### 13.3 模型与方块状态

`assets/examplemod/models/item/ruby.json`：

```json
{
  "parent": "item/generated",
  "textures": { "layer0": "examplemod:item/ruby" }
}
```

`assets/examplemod/blockstates/ruby_block.json`：

```json
{
  "variants": {
    "": { "model": "examplemod:block/ruby_block" }
  }
}
```

`assets/examplemod/models/block/ruby_block.json`：

```json
{
  "parent": "block/cube_all",
  "textures": { "all": "examplemod:block/ruby_block" }
}
```

方块物品模型（`models/item/ruby_block.json`）通常 `{"parent": "examplemod:block/ruby_block"}`。

### 13.4 配方与战利品表

`data/examplemod/recipes/ruby_block.json`（1.20.1 格式）：

```json
{
  "type": "minecraft:crafting_shaped",
  "pattern": ["###", "###", "###"],
  "key": { "#": { "item": "examplemod:ruby" } },
  "result": { "item": "examplemod:ruby_block", "count": 1 }
}
```

`data/examplemod/loot_tables/blocks/ruby_block.json`（最小方块掉落）：

```json
{
  "type": "minecraft:block",
  "pools": [
    {
      "rolls": 1,
      "entries": [{ "type": "minecraft:item", "name": "examplemod:ruby_block" }],
      "conditions": [
        { "condition": "minecraft:survives_explosion" }
      ]
    }
  ]
}
```

### 13.5 标签

`data/examplemod/tags/items/ruby_gems.json`：

```json
{
  "replace": false,
  "values": ["examplemod:ruby"]
}
```

引用原版标签用 `#minecraft:...`；Forge 通用标签在 `data/forge/tags/...`，跨模组识别（如 `forge:ores`）必须挂到 `forge` 命名空间下（`data/forge/tags/blocks/ores.json`）。

### 13.6 `displayTest` 与资源加载顺序

资源包在 `pack.mcmeta` 的 `pack_format` 匹配后才不会报「不兼容」；`mods.toml` 的展示信息与资源无关，只在模组列表生效。二者的展开都靠 `processResources`，IDE 里若改了 `gradle.properties` 而没重新处理资源，看到的仍是旧值——先跑一次 `processResources` 或 `build`。

---

## 14. 物品 NBT（1.20.1）

1.20.1 **没有 DataComponents**（那是 1.20.5+），物品附加数据全部走 `CompoundTag`。

### 14.1 API 清单（实测）

```java
import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.item.ItemStack;

ItemStack stack = new ItemStack(Items.DIAMOND_SWORD);

// 写：没有 tag 时创建
CompoundTag tag = stack.getOrCreateTag();
tag.putString("owner", "steve");
tag.putInt("ruby_count", 3);
tag.putBoolean("charged", true);
tag.putDouble("power", 1.5D);

// 读：getTag() 可能为 null
CompoundTag read = stack.getTag();
if (read != null && read.contains("owner")) {
    String owner = read.getString("owner");
    int count = read.getInt("ruby_count");       // 缺失返回 0
    boolean charged = read.getBoolean("charged");
}

// 只判断有没有
if (stack.hasTag()) { /* … */ }

// 子标签：getOrCreateTagElement(name) / getTagElement(name)（后者可能返回 null）
CompoundTag sub = stack.getOrCreateTagElement("examplemod");
sub.putInt("level", 2);

// 整体替换（慎用，会丢掉原有数据）
stack.setTag(null);        // 清空
if (!stack.hasTag()) { CompoundTag fresh = new CompoundTag(); stack.setTag(fresh); }
```

方法签名（实测）：

| 方法 | 返回 | 说明 |
|---|---|---|
| `getOrCreateTag()` | `CompoundTag` | 无 tag 时创建并挂上 |
| `getTag()` | `@Nullable CompoundTag` | 只读，可能 null |
| `setTag(@Nullable CompoundTag)` | `void` | 整体替换 |
| `hasTag()` | `boolean` | 判断是否存在 tag |
| `getOrCreateTagElement(String)` | `CompoundTag` | 子标签，不存在则创建 |
| `getTagElement(String)` | `@Nullable CompoundTag` | 子标签，可能 null |

读取注意：`getInt` / `getString` / `getBoolean` 在键不存在时返回类型零值，容易掩盖 bug；用 `contains(key, Tag.TAG_INT)` 严格判断。

### 14.2 与 capability 的分工

- **纯展示/缓存数据**（计数、名称、等级）写 NBT 即可。
- **需要跨模组访问的能力**（物品槽、能量、流体）用 capability（见 §10）；capability 数据默认随 `ItemStack` 的 NBT 序列化（`ICapabilitySerializable`）。
- **客户端同步**：物品 NBT 全量同步代价高，用 `IForgeItem#getShareTag` / `readShareTag` 裁剪。

### 14.3 常见误区

- `ItemStack#setTag` 之后 `stack.getTag()` 仍可能是 null（若写入 `null`）。
- 复制 `ItemStack` 用 `stack.copy()`，`new ItemStack(stack.getItem())` 会丢 NBT。
- 1.20.1 **没有** `PersistentDataHolder` / PDC（那是 Bukkit/Paper 的 API），不要混用。

---

## 15. 坑与排查表

| 现象 | 根因 | 处理 |
|---|---|---|
| `Unsupported class file major version 65/69` | 用了 JDK 21+ 跑 Gradle | `JAVA_HOME` 指向 JDK 17；Gradle 保持 8.8 |
| `runClient` 立即崩、报 `InaccessibleObjectException` | JDK 版本与 `--add-opens` 参数不匹配 | 同上；不要自己改 run 参数列表 |
| 启动报「Mod file … missing mods.toml」 | 文件不在 `META-INF/` 或文件名写成 `neoforge.mods.toml` | 放 `src/main/resources/META-INF/mods.toml` |
| `Mod … requires minecraft [1.20.1,1.21)` 但版本匹配 | TOML 表名写成 `[[dependencies]]`、字段用 `type` | 用 `[[dependencies.<modid>]]` + `mandatory = true` |
| 模组加载成功，`/give` 也拿不到物品 | `DeferredRegister` 忘记 `.register(modBus)`；或 `.register(modBus)` 写在 `RegisterEvent` 之后，监听器晚挂 | 主类构造器里逐个 `register`（见 §6.1） |
| `/give` 能拿到，但创造模式标签页搜不到 | 物品没加进自定义 `CreativeModeTab.displayItems`，也没监听 `BuildCreativeModeTabContentsEvent` | 在标签页 generator 里 `output.accept(...)`，或在事件里 `event.accept(...)`（见 §6.6） |
| `RegistryObject#get()` 返回 null / 抛异常 | 在注册完成前调用（构造器、静态初始化、`FMLConstructModEvent`） | 推迟到 `FMLCommonSetupEvent#enqueueWork` 或 `ServerStartingEvent` |
| `NoClassDefFoundError: net/minecraft/client/...`（服务端） | 客户端类被服务端加载 | 用 `DistExecutor.unsafeRunWhenOn` 或 `@Mod.EventBusSubscriber(value = Dist.CLIENT)` |
| 发包无反应，日志「Unknown message id」 | `SimpleChannel` 的 `registerMessage` 索引重复或未 `init()` | 索引从 0 递增且唯一；`init()` 在 `FMLCommonSetupEvent` 里调 |
| 收包后世界状态错乱、偶发崩溃 | 在 `handle` 里直接改游戏状态 | `ctx.enqueueWork(...)`，末尾 `ctx.setPacketHandled(true)` |
| 找不到 `RegisterMenuScreensEvent` | 那是 NeoForge 的类 | 1.20.1 用 `FMLClientSetupEvent#enqueueWork` + `MenuScreens.register` |
| 找不到 `SimpleTier` / `DeferredItem` / `CreativeModeTabEvent` | 均为 NeoForge 或已删除的类 | 1.20.1 用 `Tier` 实现、`RegistryObject`、`BuildCreativeModeTabContentsEvent` |
| `level.getCapability(Capabilities.ItemHandler.BLOCK, …)` 编译失败 | 1.20.1 没有 `Capabilities` 嵌套类 | 用 `ForgeCapabilities.ITEM_HANDLER` + `getCapability(cap, pos, side)` |
| capability 永远为空 | 没订阅 `RegisterCapabilitiesEvent`，或 `AttachCapabilitiesEvent` 泛型写错 | `event.register(MyCap.class)`；泛型写 `ItemStack`/`Entity`/`BlockEntity` |
| 模型紫黑方块 | 缺 `blockstates/`、`models/` 或缺纹理；或路径不是 `assets/<modid>/` | 对照 §13 的目录；`pack_format` 必须是 15 |
| 资源包提示「不兼容」 | `pack.mcmeta` 的 `pack_format` 不是 15 | 改成 15 |
| `runData` 跑完 `src/generated` 仍为空 | 缺少 `--output` / `--existing`，或 provider 传了 `false` | 检查 `runs.data.args` 与 `addProvider(event.includeClient(), …)` |
| `runData` 报「texture not found」 | 缺 `--existing src/main/resources` | 加 `--existing`，或先 `processResources` |
| 发布 jar 进游戏后 `NoSuchMethodError` | 没跑 `reobfJar` | `jar` 任务加 `finalizedBy 'reobfJar'`；不要手写 `reobf { jar {} }` |
| `jarJar` 嵌入后启动报缺依赖 | 未 `jarJar.enable()`，或 metadata 缺失 | 开启扩展；不要手写 `META-INF/jarjar/metadata.json` |
| mixin 不生效 | 1.20.1 的 `mods.toml` 不解析 `[[mixins]]`（实测 `ModFileParser` 无此键） | 在 jar 清单里声明 `MixinConfigs: examplemod.mixins.json`，文件放 resources 根 |
| 开发环境 mixin 生效，发布 jar 后完全不生效且无报错 | refmap 没打进 jar；`mixins.json` 的 `refmap` 字段与实际文件名不一致；清单 `MixinConfigs` 与 jar 内路径不一致 | `gradlew build` 后解包 jar：根目录要有与 `mixins.json` 中 `refmap` 同名的 `.refmap.json`，清单里的配置路径与 jar 内文件一致 |
| `@Shadow field <字段名> was not located in the target class <类名>.`（尾部还有 refmap 状态与动态信息，可能为空）；grep 用 `was not located in the target class`（不带字段名、类名、句点） | refmap 与运行时命名不一致 | 配 `mixin.env.remapRefMap=true` 与 `mixin.env.refMapRemappingFile`（见本机 MDK） |
| `@SubscribeEvent` 方法不被调用 | 方法非 `static`，或类没被 `@Mod.EventBusSubscriber` 标注/未 `addListener` | 改成 `public static`，并确认 `bus` 选对（默认 FORGE） |
| tick 逻辑每 tick 跑两次 | `TickEvent.*TickEvent` 有 `START`/`END` 两相 | 判 `event.phase == TickEvent.Phase.END` |
| `ResourceLocation` 构造器报废弃警告 | Forge 47.4.x 把 1.21 的废弃标记回移植进了 1.20.1：`@Deprecated(forRemoval = true, since = "1.20.6")`（`javap -v` 实测） | `new ResourceLocation(ns, path)` 仍可用，只是有 `[removal]` 警告；替代方法也已一并回移植：`ResourceLocation.fromNamespaceAndPath(ns, path)`、`ResourceLocation.parse(String)` |
| 服务端配置改了不生效 | 改的是 `serverconfig`，需同步/重启 | `SERVER` 类型配置存于世界存档，改后需重启或 `SPEC.save()`；或改用 `COMMON` |

### 15.1 环境相关的两条

1. 系统默认 `java` 不保证是 17，**直接 `./gradlew` 可能失败**；必须先设 `JAVA_HOME`。
2. `jar` 与 `java` 都不在 PATH 的 JDK 里时，用绝对路径；查看 API 时按 `references/local-decompile.md` 的流程解压单个 `.java` 再读，不要整包反编译进项目目录。

### 15.2 迁移到 NeoForge 1.21 时的高频断裂点

| 1.20.1（Forge 47） | 1.21.1（NeoForge） |
|---|---|
| `net.minecraftforge.*` | `net.neoforged.*` |
| `mods.toml` | `neoforge.mods.toml`，依赖用 `type` |
| `FMLJavaModLoadingContext.get()` | 构造函数注入 `IEventBus` / `ModContainer` |
| `RegistryObject` | `DeferredItem` / `DeferredBlock` / `DeferredHolder` |
| `BuildCreativeModeTabContentsEvent` | 保留，另有 `RegisterMenuScreensEvent` 等新事件 |
| `PacketDistributor.PLAYER.with(...)` + `channel.send` | `PacketDistributor.sendToPlayer(...)` 等静态方法 |
| `ForgeCapabilities.ITEM_HANDLER` | `Capabilities.ItemHandler.BLOCK` |
| `CompoundTag` + `getOrCreateTag` | `DataComponents` + `DataComponentType` |
| `reobfJar` | 不需要（运行时即 Mojmap） |