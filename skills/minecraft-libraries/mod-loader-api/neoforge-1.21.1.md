# NeoForge 1.21.1 模组 API 参考

NeoForge 1.21.1 使用 Java 21、Mojang 官方映射（Mojmap），所有 API 包名以 `net.neoforged` 开头，游戏类以 `net.minecraft` 开头。它是 1.21.x 的主流 Forge 分支，与 1.20.1 Forge 存在大量不兼容改动：`net.minecraftforge.*` 全部改名、注册系统重写为 `DeferredRegister`、网络改为 `CustomPacketPayload`、Capability 改为 `RegisterCapabilitiesEvent` + `AttachmentType`。不要混用两个版本的代码。

本文所有类名、方法签名均对照 NeoForge 21.1.264 源码与 Minecraft 1.21.1 + NeoForge 补丁源码核对过。

## 1. 版本矩阵与坐标

### 1.1 固定版本

| 组件 | 值 | 说明 |
| --- | --- | --- |
| Minecraft | `1.21.1` | 数据包目录用单数（`recipe`、`loot_table`） |
| NeoForge | `21.1.264` | 21.1.x 系列，patch 号可升不可降 |
| Java | `21` | toolchain 必须锁 21，不能用 17 |
| ModDevGradle | `2.0.148` | 插件 id：`net.neoforged.moddev` |
| FML（fancymodloader） | `4.0.45` | 决定 `loaderVersion` 的可接受范围 |
| 映射 | Mojmap + 可选 Parchment | 参数名来自 Parchment |

版本兼容规则：
- `minecraft_version` 必须是 `1.21.1`；`21.1.x` 的 NeoForge 只对 1.21.1 打补丁。
- `neo_version` 与 `minecraft_version` 不匹配时，启动阶段会在 mod 加载器直接抛 `ModLoadingException`，不会进到主菜单。
- 不要拿 1.21 或 1.21.2/1.21.3 的 NeoForge 版本硬套 1.21.1，接口差异很大（例如 1.21.2 起 `BlockEntityType` 与数据包目录结构都变了）。

### 1.2 `gradle.properties` 全字段

```properties
# ---- Gradle 自身 ----
org.gradle.jvmargs=-Xmx3G
org.gradle.daemon=false
org.gradle.parallel=true
org.gradle.caching=true

# ---- Minecraft / NeoForge ----
minecraft_version=1.21.1
minecraft_version_range=[1.21.1,1.22)
neo_version=21.1.264
neo_version_range=[21.1.0,)
loader_version_range=[4,)

# ---- Parchment（可选，提供可读参数名）----
parchment_minecraft_version=1.21.1
parchment_mappings_version=2024.07.28

# ---- 模组元信息（会被 processResources 注入到 neoforge.mods.toml）----
mod_id=examplemod
mod_name=Example Mod
mod_license=MIT
mod_version=1.0.0
mod_group_id=com.example.examplemod
mod_authors=YourName
mod_description=Example NeoForge mod.
```

逐字段说明：

| 字段 | 作用 | 常见错误 |
| --- | --- | --- |
| `org.gradle.jvmargs` | Gradle 守护进程堆大小 | 低于 `-Xmx2G` 时 `compileJava` 容易 OOM |
| `org.gradle.daemon` | 是否常驻守护进程 | 设为 `false` 时每次构建都冷启动，很慢但内存占用低 |
| `minecraft_version` | 传给 ModDevGradle 的 MC 版本 | 写成 `1.21` 会找不到对应 neoform |
| `minecraft_version_range` | 写进 `neoforge.mods.toml` 的依赖范围 | 写成 `1.21.1`（无方括号）会被当作精确版本，启动器拒绝 |
| `neo_version` | NeoForge 构件版本，即 `net.neoforged:neoforge:<ver>` | 拼错会在依赖解析阶段 404 |
| `neo_version_range` | 对 `neoforge` 的依赖范围 | 建议 `[21.1.0,)`，允许玩家用更高 patch |
| `loader_version_range` | 对 `javafml` 加载器的范围 | FML 版本是 `4.x`，所以 `[4,)` 合理；写 `[1,)` 也能过，但语义不精确 |
| `parchment_minecraft_version` | Parchment 的 MC 版本键 | 必须与 `minecraft_version` 一致 |
| `parchment_mappings_version` | Parchment 发布号 | 不存在时会 404；不确定就去 parchmentmc.org 查当期号 |
| `mod_id` | 全局命名空间，必须全小写、只含 `a-z0-9_` | 大写或中划线会导致资源路径非法 |
| `mod_group_id` | Maven group，也决定包名前缀 | 与 `package` 声明不一致不影响运行，但很乱 |
| `mod_description` | 展示在模组列表 | 含 `$` 或 `\` 时要转义，否则 `expand` 阶段炸 |

### 1.3 `build.gradle`

```groovy
plugins {
    id 'java-library'
    id 'net.neoforged.moddev' version '2.0.148'
}

version = mod_version
group = mod_group_id
base { archivesName = mod_id }

java {
    toolchain { languageVersion = JavaLanguageVersion.of(21) }
}

repositories {
    mavenLocal()
}

neoForge {
    // 必需：NeoForge 版本
    version = project.neo_version

    // 可选：Parchment 参数名
    parchment {
        mappingsVersion = project.parchment_mappings_version
        minecraftVersion = project.parchment_minecraft_version
    }

    // 运行配置：每个块都会生成一个 Gradle 任务
    runs {
        client {
            client()
            systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id
        }
        server {
            server()
            programArgument '--nogui'
            systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id
        }
        data {
            data()
            programArguments.addAll '--mod', project.mod_id, '--all',
                '--output', file('src/generated/resources/').getAbsolutePath(),
                '--existing', file('src/main/resources/').getAbsolutePath()
        }
        configureEach {
            systemProperty 'forge.logging.markers', 'REGISTRIES'
            logLevel = org.slf4j.event.Level.DEBUG
        }
    }

    // 告诉 ModDevGradle 哪些源集属于这个模组
    mods {
        "${project.mod_id}" {
            sourceSet(sourceSets.main)
        }
    }
}

// 把生成的资源也当作资源目录（runData 的产物直接进 jar）
sourceSets.main.resources { srcDir 'src/generated/resources' }

// 让 ${...} 占位符在 neoforge.mods.toml 中被替换
tasks.named('processResources', ProcessResources).configure {
    var replaceProperties = [
        minecraft_version      : minecraft_version,
        minecraft_version_range: minecraft_version_range,
        neo_version            : neo_version,
        neo_version_range      : neo_version_range,
        loader_version_range   : loader_version_range,
        mod_id                 : mod_id,
        mod_name               : mod_name,
        mod_license            : mod_license,
        mod_version            : mod_version,
        mod_authors            : mod_authors,
        mod_description        : mod_description
    ]
    inputs.properties replaceProperties
    filesMatching(['META-INF/neoforge.mods.toml']) {
        expand replaceProperties
    }
}
```

常用任务：

| 命令 | 作用 |
| --- | --- |
| `./gradlew build` | 编译 + 打 jar（输出 `build/libs/<mod_id>-<version>.jar`） |
| `./gradlew runClient` | 启动带模组的客户端 |
| `./gradlew runServer` | 启动专用服务器（需先同意 eula） |
| `./gradlew runData` | 运行数据生成器，写入 `src/generated/resources` |
| `./gradlew runGameTestServer` | 只跑 GameTest（需要在 runs 里配 `gameTestServer()`） |

Parchment 说明：它只改参数名和 javadoc，不影响二进制兼容；开 `parchment` 后源码里能看到 `p_123456_` 变成 `level`、`pos` 之类。关掉它不影响编译，只是反编译可读性差。

## 2. 工程结构

### 2.1 默认目录树

```text
examplemod/
├── build.gradle
├── gradle.properties
├── settings.gradle
├── gradle/wrapper/...
└── src/
    ├── main/
    │   ├── java/com/example/examplemod/
    │   │   ├── ExampleMod.java           # @Mod 主类
    │   │   ├── blocks/ExampleBlocks.java
    │   │   ├── items/ExampleItems.java
    │   │   ├── Config.java
    │   │   └── ...
    │   └── resources/
    │       ├── META-INF/neoforge.mods.toml
    │       ├── examplemod.mixins.json
    │       ├── assets/examplemod/...
    │       └── data/examplemod/...
    ├── client/java/com/example/examplemod/client/   # 可选：客户端代码
    └── generated/resources/                          # runData 产物（commit 进仓库）
```

要点：
- `neoforge.mods.toml` 必须位于 `src/main/resources/META-INF/`，且文件名是 `neoforge.mods.toml`（1.21 起从 `mods.toml` 改名）。旧名会导致 “Mod file ... missing neoforge.mods.toml”。
- 资源/数据都以 `mod_id` 作为命名空间目录名，必须与 `@Mod` 里的 id 完全一致。
- 不需要自己写 `pack.mcmeta`：NeoForge 会为模组资源自动提供，只在你确实要控制 `pack_format` 时才加。

### 2.2 `runs` 块详解

`neoForge.runs` 里每个子块对应一个可执行任务，块名即任务名（`client` → `runClient`）。

```groovy
neoForge {
    version = project.neo_version

    runs {
        // 生成 runClient
        client {
            client()
            // 指定客户端运行的目录，默认是 ./run
            gameDirectory = file('run')
            // JVM 参数
            jvmArgument '-Xmx2G'
            // 传给游戏的参数
            programArgument '--username=Dev'
        }

        // 生成 runServer
        server {
            server()
            programArgument '--nogui'
        }

        // 生成 runData（数据生成器）
        data {
            data()
            programArguments.addAll '--mod', project.mod_id, '--all',
                '--output', file('src/generated/resources/').getAbsolutePath(),
                '--existing', file('src/main/resources/').getAbsolutePath()
        }

        // 生成 runGameTestServer
        gameTestServer {
            type = "gameTestServer"
        }
    }
}
```

`data()` 生成的 `runData` 会自动带上 `-existing` 与 `-output`，但 MDK 习惯显式再写一遍，避免 IDE 里手动跑 main 时路径不对。

### 2.3 客户端源集（可选）

最省事的做法是：客户端代码也放 `src/main/java`，用 `@Mod(dist = Dist.CLIENT)` 与 `@EventBusSubscriber(value = Dist.CLIENT)` 做隔离。这样零额外 Gradle 配置。

如果确实要物理分离：

```groovy
sourceSets {
    main {
        // 把 client 目录并入主源集：既分离文件，又不用改 runs
        java.srcDir 'src/client/java'
    }
}
```

这是最安全的写法——`src/client/java` 里的类会与主源集一起编译，`runClient` 能加载，专用服务器因为 `Dist.CLIENT` 注解而不会实例化它们（但仍会被类加载器扫描，所以类里**不能**在静态初始化阶段触碰 `Minecraft.getInstance()`）。

真正的双源集（`sourceSets.client` + `neoForge.mods.<id>.sourceSet(sourceSets.client)` + 独立 run 配置）在 ModDevGradle 2.0.x 中可行，但字段随小版本变化，务必以 MDK 2.0.148 的模板为准，不要照抄旧教程。

## 3. `neoforge.mods.toml` 全字段

### 3.1 完整示例

```toml
# 加载器：Java 模组固定 javafml
modLoader = "javafml"
# FML 版本范围，来自 gradle.properties 的 loader_version_range
loaderVersion = "${loader_version_range}"
# 许可证，展示在模组列表；也可以用 license = "MIT"
license = "${mod_license}"
# 问题追踪地址，可省略
issueTrackerURL = "https://github.com/example/examplemod/issues"
# 是否作为资源包出现在资源包列表（一般 false，省略即可）
showAsResourcePack = false

[[mods]]
modId = "examplemod"
version = "${mod_version}"
displayName = "${mod_name}"
# 支持 markdown 子集；''' 三引号可跨行
description = '''Example NeoForge mod.'''
# 位于 resources 根目录下的图片文件名
logoFile = "examplemod.png"
authors = "YourName"
# 展示用链接
displayURL = "https://example.com"
# 版本不匹配时客户端行为
displayTest = "MATCH_VERSION"

# ---- 依赖 ----
[[dependencies.examplemod]]
modId = "neoforge"
type = "required"
versionRange = "${neo_version_range}"
ordering = "NONE"
side = "BOTH"

[[dependencies.examplemod]]
modId = "minecraft"
type = "required"
versionRange = "${minecraft_version_range}"
ordering = "NONE"
side = "BOTH"

[[dependencies.examplemod]]
modId = "jei"
type = "optional"
versionRange = "[19,)"
ordering = "AFTER"
side = "CLIENT"

# ---- Mixin ----
[[mixins]]
config = "examplemod.mixins.json"

# ---- Access Transformer ----
[[accessTransformers]]
file = "META-INF/accesstransformer.cfg"

# ---- 特性声明（可选，极少用）----
[features.examplemod]
java_version = "21"
```

### 3.2 顶层字段

| 字段 | 必填 | 取值 | 说明 |
| --- | --- | --- | --- |
| `modLoader` | 是 | `"javafml"` / `"lowcodefml"` | Java 模组一律 `javafml` |
| `loaderVersion` | 是 | 版本范围字符串 | 对应 FML 版本（本栈为 `4.x`），写 `"[4,)"` |
| `license` | 是 | 任意字符串 | 展示用，不校验合法性 |
| `issueTrackerURL` | 否 | URL | 出现在崩溃报告里 |
| `showAsResourcePack` | 否 | `true`/`false` | 默认 false |
| `[[mods]]` | 是 | 表数组 | 一个 jar 可以有多个 `[[mods]]`，但一般只有一个 |
| `[[mixins]]` | 否 | 表数组 | 每项 `config = "<file>"` |
| `[[accessTransformers]]` | 否 | 表数组 | 每项 `file = "<path>"` |
| `[features.<modid>]` | 否 | 表 | 声明运行特性；`java_version` 是唯一常用键 |

### 3.3 `[[mods]]` 子字段

| 字段 | 说明 |
| --- | --- |
| `modId` | 必填，全局唯一，必须与 `@Mod` 值一致 |
| `version` | 必填，通常 `${mod_version}` |
| `displayName` | 展示名，可含空格 |
| `description` | 长描述，支持 `'''...'''` 多行 |
| `logoFile` | 相对 `resources` 根的图片路径，如 `examplemod.png` |
| `authors` | 字符串，多人用逗号分隔 |
| `credits` | 鸣谢 |
| `displayURL` | “主页”按钮链接 |
| `displayTest` | 见下表 |
| `enumExtensions` | 内嵌的枚举扩展声明（高级用法） |

`displayTest` 取值：

| 值 | 含义 |
| --- | --- |
| `MATCH_VERSION`（默认） | 客户端/服务端版本号不同就拒绝连接 |
| `IGNORE_SERVER_VERSION` | 客户端不校验服务端是否有该模组（纯客户端模组常用） |
| `IGNORE_ALL_VERSION` | 完全不校验 |
| `NONE` | 不做任何展示性校验（等同忽略） |

### 3.4 `[[dependencies.<modid>]]` 与 versionRange 语义

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `modId` | 字符串 | 被依赖的 mod（也可是 `minecraft`、`neoforge`、`java`） |
| `type` | `required` / `optional` / `incompatible` / `discouraged` | 取代旧 Forge 的 `mandatory=true/false` |
| `versionRange` | Maven 风格范围 | 见下表 |
| `ordering` | `NONE` / `BEFORE` / `AFTER` | 影响加载顺序，不是强约束 |
| `side` | `BOTH` / `CLIENT` / `SERVER` | 依赖生效的物理侧 |
| `referralUrl` | URL | 缺失时给玩家的指引链接 |

`versionRange` 语义（Maven version range）：

| 写法 | 含义 |
| --- | --- |
| `[21.1.0,)` | 大于等于 21.1.0，无上界 |
| `[1.21.1,1.22)` | 含 1.21.1，不含 1.22 |
| `[1.21.1]` | 精确等于 1.21.1 |
| `(,1.21.1]` | 小于等于 1.21.1 |
| `[21.1,21.2)` | 含 21.1，不含 21.2（`21.1` 等价 `21.1.0`） |
| `*` | 任意版本（不推荐） |

坑：`versionRange = "1.21.1"` 不是“1.21.1 及以上”，而是“必须恰好 1.21.1”。要兼容小版本就写 `[1.21.1,1.22)`。

### 3.5 Mixin 配置

`examplemod.mixins.json`（放 `src/main/resources` 根）：

```json
{
  "required": true,
  "package": "com.example.examplemod.mixin",
  "compatibilityLevel": "JAVA_21",
  "mixins": [
    "ExampleMixin"
  ],
  "client": [
    "client.ExampleClientMixin"
  ],
  "injectors": {
    "defaultRequire": 1
  }
}
```

- `mixins` 段在两侧都应用；`client` 段只在客户端应用；`server` 段只在服务端应用。
- 引用了不存在的 mixin 类会在启动时直接崩，`required: true` 时尤其严格。
- NeoForge 不再需要单独声明 mixin 的 `refmap`（Gradle 插件处理），但如果用 `@Shadow`/`@Accessor` 且本地能编译，仍需 `--tweakClass` 之外无配置。

## 4. `@Mod` 主类与两条事件总线

### 4.1 完整主类

```java
package com.example.examplemod;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.neoforge.client.gui.ConfigurationScreen;
import net.neoforged.neoforge.client.gui.IConfigScreenFactory;

@Mod(ExampleMod.MOD_ID)
public final class ExampleMod {

    public static final String MOD_ID = "examplemod";

    public ExampleMod(IEventBus modBus, ModContainer container, Dist dist) {
        // 1) 所有 DeferredRegister 必须挂到 mod 总线，且要在构造函数里完成
        ExampleBlocks.BLOCKS.register(modBus);
        ExampleItems.ITEMS.register(modBus);
        ExampleBlockEntities.BLOCK_ENTITIES.register(modBus);
        ExampleMenus.MENUS.register(modBus);
        ExampleTabs.CREATIVE_TABS.register(modBus);
        ExampleDataComponents.DATA_COMPONENTS.register(modBus);
        ExampleAttachments.ATTACHMENT_TYPES.register(modBus);
        ExampleParticles.PARTICLE_TYPES.register(modBus);

        // 2) 配置注册（必须是 registerConfig，不是 addListener）
        container.registerConfig(ModConfig.Type.COMMON, Config.SPEC);

        // 3) 客户端专属扩展点，必须按 Dist 隔离，否则专用服务器会加载客户端类
        if (dist == Dist.CLIENT) {
            container.registerExtensionPoint(IConfigScreenFactory.class, ConfigurationScreen::new);
        }

        // 4) 生命周期监听
        modBus.addListener(this::commonSetup);
    }

    private void commonSetup(FMLCommonSetupEvent event) {
        // 该阶段在并行线程池执行，需要主线程的操作必须 enqueueWork
        event.enqueueWork(() -> {
            // 例如 CompostableRegistry、BrewingRecipeRegistry 之类的注册
        });
    }
}
```

### 4.2 构造函数可注入类型

| 参数类型 | 用途 |
| --- | --- |
| `net.neoforged.bus.api.IEventBus` | mod 总线，注册 `DeferredRegister` 与 mod 事件监听器 |
| `net.neoforged.fml.ModContainer` | 注册配置、扩展点；`getModInfo()` 拿元数据 |
| `net.neoforged.api.distmarker.Dist` | 判断 `CLIENT`/`DEDICATED_SERVER`，用于隔离客户端代码 |

`ModLoadingContext.get()` 仍然存在（`javap` 可见 `get()` / `getActiveContainer()`），但在 1.21 已不推荐；用构造注入 `ModContainer` 更明确，且不会在错误线程拿到别的模组的容器。

`@Mod` 注解本身只有两个属性：`value()`（mod id）与 `dist()`（数组，可写 `dist = Dist.CLIENT`）。写 `dist = Dist.CLIENT` 时该主类只在客户端被实例化。

### 4.3 mod 总线 vs game 总线

| 项目 | mod 总线 | game 总线 |
| --- | --- | --- |
| 实例 | 构造函数的 `IEventBus` 参数 / `ModContainer#getEventBus()` | `NeoForge.EVENT_BUS` |
| 判定 | 事件类型 `implements IModBusEvent` | 其余所有事件 |
| 时机 | 加载期（注册、配置、初始化、数据生成、网络声明、客户端资源注册） | 运行期（世界/玩家/实体/方块逻辑） |
| 线程 | 多数在并行派发线程池（`ParallelDispatchEvent#enqueueWork`） | 主线程（服务端线程 / 渲染线程） |
| 注册方式 | `@EventBusSubscriber(bus = Bus.MOD)` 或 `modBus.addListener(...)` | `@EventBusSubscriber`（默认）或 `NeoForge.EVENT_BUS.addListener(...)` |

必须走 **mod 总线** 的典型事件：

`FMLCommonSetupEvent`、`FMLClientSetupEvent`、`FMLDedicatedServerSetupEvent`、`FMLLoadCompleteEvent`、`InterModEnqueueEvent`、`InterModProcessEvent`、`RegisterEvent`、`NewRegistryEvent`、`ModifyRegistriesEvent`、`RegisterCapabilitiesEvent`、`RegisterPayloadHandlersEvent`、`RegisterConfigurationTasksEvent`、`RegisterDataMapTypesEvent`、`GatherDataEvent`、`BuildCreativeModeTabContentsEvent`、`ModifyDefaultComponentsEvent`、`EntityAttributeCreationEvent`、`RegisterSpawnPlacementsEvent`、`RegisterMenuScreensEvent`、`RegisterKeyMappingsEvent`、`RegisterGuiLayersEvent`、`RegisterParticleProvidersEvent`、`RegisterShadersEvent`、`RegisterClientExtensionsEvent`、`EntityRenderersEvent.*`、`ModelEvent.*`、`RegisterColorHandlersEvent`、`RegisterBrewingRecipesEvent`、`ModConfigEvent.*`、`AddPackFindersEvent`。

必须走 **game 总线** 的典型事件：

`ServerAboutToStartEvent`、`ServerStartingEvent`、`ServerStartedEvent`、`ServerStoppingEvent`、`ServerStoppedEvent`、`PlayerEvent.*`、`PlayerInteractEvent.*`、`LivingIncomingDamageEvent`、`LivingDamageEvent.*`、`LivingDeathEvent`、`BlockEvent.BreakEvent`、`BlockEvent.EntityPlaceEvent`、`EntityJoinLevelEvent`、`LevelTickEvent.*`、`PlayerTickEvent.*`、`ServerTickEvent.*`、`RegisterCommandsEvent`、`AddReloadListenerEvent`、`OnDatapackSyncEvent`、`LevelEvent.Load/Unload`、`ExplosionEvent.Detonate`、`TagsUpdatedEvent`、`ItemTooltipEvent`。

> 判断方法：看事件类是否 `implements IModBusEvent`。若不实现，挂到 mod 总线永远不会触发，且**不会报错**——这是最常见的静默失败。

## 5. 注册体系

### 5.1 `DeferredRegister` 基础

```java
import net.minecraft.core.registries.Registries;
import net.neoforged.neoforge.registries.DeferredRegister;

// 1) 用 Registry 实例（BuiltInRegistries 里的）
public static final DeferredRegister<Item> ITEMS_GENERIC =
    DeferredRegister.create(Registries.ITEM, ExampleMod.MOD_ID);

// 2) 用 ResourceKey（推荐，NeoForge 与 MC 均支持）
public static final DeferredRegister<Item> ITEMS =
    DeferredRegister.create(net.minecraft.core.registries.Registries.ITEM, ExampleMod.MOD_ID);

// 3) 便捷工厂（返回带泛型增强的子类）
public static final DeferredRegister.Items ITEMS_EASY =
    DeferredRegister.createItems(ExampleMod.MOD_ID);
public static final DeferredRegister.Blocks BLOCKS_EASY =
    DeferredRegister.createBlocks(ExampleMod.MOD_ID);
public static final DeferredRegister.DataComponents DATA_COMPONENTS =
    DeferredRegister.createDataComponents(ExampleMod.MOD_ID);
```

核对过的 `DeferredRegister` 关键方法：

| 方法 | 签名要点 |
| --- | --- |
| `create(Registry<T>, String)` | 用注册表实例 + 命名空间 |
| `create(ResourceKey<? extends Registry<T>>, String)` | 用 `ResourceKey`，推荐 |
| `createItems(String)` | 返回 `DeferredRegister.Items` |
| `createBlocks(String)` | 返回 `DeferredRegister.Blocks` |
| `createDataComponents(String)` | 返回 `DeferredRegister.DataComponents` |
| `register(String, Supplier<? extends I>)` | 返回 `DeferredHolder<T, I>` |
| `register(String, Function<ResourceLocation, ? extends I>)` | 工厂能拿到自身 id（用于自定义 `Item` 需要 id 时） |
| `register(IEventBus)` | 挂到总线；不调用则全部不注册 |
| `createTagKey(String)` | 生成本模组命名空间的 `TagKey<T>` |
| `addAlias(ResourceLocation, ResourceLocation)` | 注册别名（数据包兼容用） |
| `getEntries()` | 拿到所有 `DeferredHolder` |

`DeferredHolder` 关键方法：`get()`、`value()`、`getId()`、`getKey()`、`isBound()`、`asOptional()`、`getData(DataMapType)`、`tags()`、`unwrapKey()`。它同时实现 `Holder<R>` 与 `Supplier<T>`，所以能直接传给需要 `Holder`/`Supplier` 的 API。

### 5.2 方块

```java
package com.example.examplemod.blocks;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;
import net.neoforged.neoforge.registries.DeferredBlock;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ExampleBlocks {

    public static final DeferredRegister.Blocks BLOCKS =
        DeferredRegister.createBlocks(ExampleMod.MOD_ID);

    // 最简：直接产出 Block
    public static final DeferredBlock<Block> RUBY_BLOCK =
        BLOCKS.registerSimpleBlock("ruby_block", BlockBehaviour.Properties.of()
            .mapColor(MapColor.CRIMSON_HYPHAE)
            .strength(3.0F, 6.0F)          // 挖掘时间 / 爆炸抗性
            .sound(SoundType.METAL)
            .requiresCorrectToolForDrops());

    // 自定义子类：函数拿得到 Properties
    public static final DeferredBlock<RubyOreBlock> RUBY_ORE =
        BLOCKS.registerBlock("ruby_ore", RubyOreBlock::new,
            BlockBehaviour.Properties.of()
                .mapColor(MapColor.STONE)
                .strength(3.0F, 3.0F)
                .requiresCorrectToolForDrops());
}
```

`DeferredRegister.Blocks` 的核对结果：

| 方法 | 说明 |
| --- | --- |
| `registerSimpleBlock(String, Properties)` | 直接 `new Block(props)` |
| `registerSimpleBlock(String)` | 用默认 `Properties.of()` |
| `registerBlock(String, Function<Properties, ? extends B>, Properties)` | 自定义方块类 |
| `register(String, Function<ResourceLocation, ? extends B>)` | 需要 id 的方块 |
| `register(String, Supplier<? extends B>)` | 完全自定义构造 |

> 不要用 `BlockBehaviour.Properties.of()` 之外的构造器；1.21 已删除 `Material`。`Properties#strength(t, r)` 与 `#strength(t)` 都存在，`requiresCorrectToolForDrops()` 在 1.21 取代了 `harvestTool/harvestLevel`。

### 5.3 物品

```java
package com.example.examplemod.items;

import net.minecraft.world.food.FoodProperties;
import net.minecraft.world.item.*;
import net.neoforged.neoforge.common.SimpleTier;
import net.neoforged.neoforge.registries.DeferredItem;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ExampleItems {

    public static final DeferredRegister.Items ITEMS =
        DeferredRegister.createItems(ExampleMod.MOD_ID);

    // 普通物品
    public static final DeferredItem<Item> RUBY =
        ITEMS.registerSimpleItem("ruby", new Item.Properties());

    // 方块物品：第二个参数是 Supplier<Block>，DeferredBlock 本身就是 Supplier
    public static final DeferredItem<BlockItem> RUBY_BLOCK =
        ITEMS.registerSimpleBlockItem("ruby_block", ExampleBlocks.RUBY_BLOCK);

    // 食物
    public static final DeferredItem<Item> RUBY_APPLE =
        ITEMS.registerSimpleItem("ruby_apple", new Item.Properties()
            .food(new FoodProperties.Builder()
                .nutrition(4)
                .saturationModifier(0.3F)
                .build()));

    // 自定义工具材料
    public static final Tier RUBY_TIER = new SimpleTier(
        BlockTags.INCORRECT_FOR_DIAMOND_TOOL,   // 挖不动时用的标签
        1561,                                   // 耐久
        8.0F,                                   // 挖掘速度
        3.0F,                                   // 攻击伤害加成
        10,                                     // 附魔能力
        () -> Ingredient.of(RUBY.get()));        // 修复材料

    // 工具：SwordItem 会自动带上属性组件
    public static final DeferredItem<SwordItem> RUBY_SWORD =
        ITEMS.registerItem("ruby_sword", p -> new SwordItem(RUBY_TIER, p), new Item.Properties());

    // 自定义物品（需要 id 时用这个重载）
    public static final DeferredItem<RubyWandItem> RUBY_WAND =
        ITEMS.register("ruby_wand", id -> new RubyWandItem(new Item.Properties(), id));
}
```

`DeferredRegister.Items` 核对结果：

| 方法 | 说明 |
| --- | --- |
| `registerSimpleItem(String, Item.Properties)` | `new Item(props)` |
| `registerItem(String, Function<Item.Properties, ? extends I>, Item.Properties)` | 自定义物品子类 |
| `registerSimpleBlockItem(String, Supplier<? extends Block>)` | 自动建 `BlockItem` |
| `registerSimpleBlockItem(String, Supplier<? extends Block>, Item.Properties)` | 带属性 |
| `registerSimpleBlockItem(Holder<Block>)` | 用 `Holder` 版本 |
| `register(String, Function<ResourceLocation, ? extends I>)` | 需要自身 id |

`Item.Properties` 常用方法（均已核对存在）：`food(FoodProperties)`、`stacksTo(int)`、`durability(int)`、`rarity(Rarity)`、`fireResistant()`、`component(DataComponentType<T>, T)`。

护甲（1.21 的 `ArmorMaterial` 是数据包注册表，必须注册）：

```java
import net.minecraft.core.registries.Registries;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.item.ArmorItem;
import net.minecraft.world.item.ArmorMaterial;
import net.minecraft.world.item.crafting.Ingredient;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public static final DeferredRegister<ArmorMaterial> ARMOR_MATERIALS =
    DeferredRegister.create(Registries.ARMOR_MATERIAL, ExampleMod.MOD_ID);

public static final DeferredHolder<ArmorMaterial, ArmorMaterial> RUBY_ARMOR_MATERIAL =
    ARMOR_MATERIALS.register("ruby", () -> new ArmorMaterial(
        java.util.Map.of(
            ArmorItem.Type.HELMET, 2,
            ArmorItem.Type.CHESTPLATE, 6,
            ArmorItem.Type.LEGGINGS, 5,
            ArmorItem.Type.BOOTS, 2),
        15,                                             // 附魔能力
        SoundEvents.ARMOR_EQUIP_DIAMOND,                // Holder<SoundEvent>
        () -> Ingredient.of(ExampleItems.RUBY.get()),   // 修复材料
        java.util.List.of(new ArmorMaterial.Layer(      // 贴图层
            ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "ruby"))),
        2.0F,                                           // toughness
        0.0F));                                         // knockbackResistance

public static final DeferredItem<ArmorItem> RUBY_HELMET =
    ITEMS.registerItem("ruby_helmet",
        p -> new ArmorItem(RUBY_ARMOR_MATERIAL, ArmorItem.Type.HELMET, p),
        new Item.Properties().durability(ArmorItem.Type.HELMET.getDurability(15)));
```

工具能力（1.21 用 `ItemAbility` 取代旧的 `Item#canPerformAction(String)`）：

```java
import net.neoforged.neoforge.common.ItemAbilities;
import net.neoforged.neoforge.common.ItemAbility;

public class RubyWandItem extends Item {
    public RubyWandItem(Item.Properties props, ResourceLocation id) {
        super(props);
    }

    @Override
    public boolean canPerformAction(ItemStack stack, ItemAbility ability) {
        // 让这把“魔杖”能做斧头的所有动作
        return ItemAbilities.DEFAULT_AXE_ACTIONS.contains(ability);
    }
}
```

可用常量：`AXE_DIG`、`PICKAXE_DIG`、`SHOVEL_DIG`、`HOE_DIG`、`SWORD_DIG`、`SHEARS_DIG`、`AXE_STRIP`、`AXE_SCRAPE`、`AXE_WAX_OFF`、`SHOVEL_FLATTEN`、`SHOVEL_DOUSE`、`SWORD_SWEEP`、`SHEARS_HARVEST`、`SHEARS_REMOVE_ARMOR`、`SHEARS_CARVE`、`SHEARS_DISARM`、`SHEARS_TRIM`、`HOE_TILL`、`SHIELD_BLOCK`、`FISHING_ROD_CAST`、`TRIDENT_THROW`、`BRUSH_BRUSH`、`FIRESTARTER_LIGHT`、`SPYGLASS_SCOPE`，以及集合 `DEFAULT_AXE_ACTIONS` / `DEFAULT_HOE_ACTIONS` / `DEFAULT_SHOVEL_ACTIONS` / `DEFAULT_PICKAXE_ACTIONS` / `DEFAULT_SWORD_ACTIONS` / `DEFAULT_SHEARS_ACTIONS`。

### 5.4 方块实体

```java
package com.example.examplemod.blockentity;

import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public class RubyBlockEntity extends BlockEntity {

    public RubyBlockEntity(BlockPos pos, BlockState state) {
        // 引用自己的 DeferredHolder 是安全的：此时注册已完成
        super(ExampleBlockEntities.RUBY_BE.get(), pos, state);
    }
}

public final class ExampleBlockEntities {

    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
        DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, ExampleMod.MOD_ID);

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<RubyBlockEntity>> RUBY_BE =
        BLOCK_ENTITIES.register("ruby_block_entity",
            () -> BlockEntityType.Builder
                .of(RubyBlockEntity::new, ExampleBlocks.RUBY_BLOCK.get())
                .build(null));   // 1.21.1 的参数是 Type<?>（数据固定器），一般传 null
}
```

Ticker 挂在方块上（`BlockEntityType` 本身没有 ticker 注册入口）：

```java
import net.minecraft.world.level.block.EntityBlock;
import net.minecraft.world.level.block.entity.BlockEntityTicker;
import net.minecraft.world.level.block.entity.BlockEntityType;
import org.jetbrains.annotations.Nullable;

public class RubyBlock extends Block implements EntityBlock {

    public RubyBlock(BlockBehaviour.Properties props) {
        super(props);
    }

    @Nullable
    @Override
    public <T extends BlockEntity> BlockEntityTicker<T> getTicker(
            Level level, BlockState state, BlockEntityType<T> type) {
        // 只在服务端 tick，避免客户端跑逻辑
        if (level.isClientSide()) {
            return null;
        }
        return type == ExampleBlockEntities.RUBY_BE.get() ? RubyBlockEntity::serverTick : null;
    }
}
```

`BlockEntityTicker<T>` 的方法签名是 `void tick(Level level, BlockPos pos, BlockState state, T blockEntity)`，所以静态方法可以写成：

```java
public static void serverTick(Level level, BlockPos pos, BlockState state, RubyBlockEntity be) {
    // 每秒（20 tick）加 1 点能量
    if (level.getGameTime() % 20 == 0) {
        be.energy++;
        be.setChanged();                 // 标记需要保存
        level.sendBlockUpdated(pos, state, state, Block.UPDATE_CLIENTS);
    }
}
```

### 5.5 菜单（`MenuType` + `AbstractContainerMenu` + `ContainerData`）

```java
package com.example.examplemod.menu;

import net.minecraft.world.SimpleContainer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.ContainerData;
import net.minecraft.world.inventory.MenuType;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;

public class RubyMenu extends AbstractContainerMenu {

    private final SimpleContainer container;
    private final ContainerData data;

    // 客户端/服务端共用的构造器（MenuType.MenuSupplier 需要它）
    public RubyMenu(int containerId, Inventory playerInventory) {
        this(containerId, playerInventory, new SimpleContainer(9), new RubyData());
    }

    public RubyMenu(int containerId, Inventory playerInventory, SimpleContainer container, ContainerData data) {
        super(ExampleMenus.RUBY_MENU.get(), containerId);
        this.container = container;
        this.data = data;

        // 9 个机器槽位
        for (int i = 0; i < 9; i++) {
            this.addSlot(new Slot(container, i, 8 + (i % 3) * 18, 18 + (i / 3) * 18));
        }

        // 玩家背包 3x9
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 9; col++) {
                this.addSlot(new Slot(playerInventory, col + row * 9 + 9, 8 + col * 18, 84 + row * 18));
            }
        }
        // 快捷栏
        for (int col = 0; col < 9; col++) {
            this.addSlot(new Slot(playerInventory, col, 8 + col * 18, 142));
        }

        this.addDataSlots(data);
    }

    @Override
    public boolean stillValid(Player player) {
        return true;   // 演示用；真实机器应判断距离
    }

    @Override
    public ItemStack quickMoveStack(Player player, int index) {
        // 省略具体实现，但必须返回 ItemStack.EMPTY 而不是 null
        return ItemStack.EMPTY;
    }

    public int getEnergy() {
        return this.data.get(0);
    }

    /** 用 ContainerData 把 int 数组同步到客户端 */
    public static class RubyData implements ContainerData {
        private final int[] values = new int[2];

        @Override public int get(int index) { return this.values[index]; }
        @Override public void set(int index, int value) { this.values[index] = value; }
        @Override public int getCount() { return this.values.length; }
    }
}
```

注册与打开界面：

```java
public static final DeferredRegister<MenuType<?>> MENUS =
    DeferredRegister.create(Registries.MENU, ExampleMod.MOD_ID);

public static final DeferredHolder<MenuType<?>, MenuType<RubyMenu>> RUBY_MENU =
    MENUS.register("ruby_menu", () -> new MenuType<>(RubyMenu::new, FeatureFlags.DEFAULT_FLAGS));
```

```java
// 服务端打开（player 必须是 ServerPlayer）
player.openMenu(new SimpleMenuProvider(
    (id, inv, p) -> new RubyMenu(id, inv),
    Component.translatable("container.examplemod.ruby")));
```

`MenuType` 的构造器是 `MenuType(MenuSupplier<T>, FeatureFlagSet)`，`FeatureFlags.DEFAULT_FLAGS` 即可。若菜单需要额外数据（如方块坐标），要用 `IMenuTypeExtension.create(StreamCodec)` 扩展，而不是重载 `MenuSupplier`。

### 5.6 创造模式标签页

```java
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ExampleTabs {

    public static final DeferredRegister<CreativeModeTab> CREATIVE_TABS =
        DeferredRegister.create(Registries.CREATIVE_MODE_TAB, ExampleMod.MOD_ID);

    public static final DeferredHolder<CreativeModeTab, CreativeModeTab> RUBY_TAB =
        CREATIVE_TABS.register("ruby_tab", () -> CreativeModeTab.builder()
            .title(Component.translatable("itemGroup.examplemod.ruby"))
            .icon(() -> new ItemStack(ExampleItems.RUBY.get()))
            .displayItems((params, output) -> {
                output.accept(ExampleItems.RUBY.get());
                output.accept(ExampleItems.RUBY_BLOCK.get());
                output.accept(ExampleItems.RUBY_SWORD.get());
            })
            .withTabsBefore(net.minecraft.resources.ResourceKey.create(
                Registries.CREATIVE_MODE_TAB,
                ResourceLocation.fromNamespaceAndPath("minecraft", "ingredients")))
            .build());
}
```

往**原版**标签页里追加物品，用 `BuildCreativeModeTabContentsEvent`（mod 总线）：

```java
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;

@SubscribeEvent
public static void buildTabContents(BuildCreativeModeTabContentsEvent event) {
    if (event.getTabKey() == CreativeModeTabs.INGREDIENTS) {
        event.accept(new ItemStack(ExampleItems.RUBY.get()),
            CreativeModeTab.TabVisibility.PARENT_AND_SEARCH_TABS);
    }
}
```

该事件同时是 `CreativeModeTab.Output`，因此还提供 `insertFirst`、`insertBefore`、`insertAfter`、`remove`；`getTab()`、`getTabKey()`、`getFlags()`、`hasPermissions()` 可用于按权限过滤。

### 5.7 数据组件（`DataComponentType`）

1.21 的 NBT 已被数据组件取代。自定义组件用于给物品附加结构化数据：

```java
import com.mojang.serialization.Codec;
import net.minecraft.core.component.DataComponentType;
import net.minecraft.network.codec.ByteBufCodecs;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ExampleDataComponents {

    public static final DeferredRegister.DataComponents DATA_COMPONENTS =
        DeferredRegister.createDataComponents(ExampleMod.MOD_ID);

    // 一个简单的整数“充能值”
    public static final DeferredHolder<DataComponentType<?>, DataComponentType<Integer>> CHARGE =
        DATA_COMPONENTS.registerComponentType("charge",
            builder -> builder
                .persistent(Codec.INT)                       // 存档用
                .networkSynchronized(ByteBufCodecs.VAR_INT)); // 同步用
}
```

使用：

```java
ItemStack stack = new ItemStack(ExampleItems.RUBY.get());
stack.set(ExampleDataComponents.CHARGE.get(), 7);
int charge = stack.getOrDefault(ExampleDataComponents.CHARGE.get(), 0);
```

`DataComponentType.Builder` 只有三个方法：`persistent(Codec<T>)`、`networkSynchronized(StreamCodec<? super RegistryFriendlyByteBuf, T>)`、`cacheEncoding()`，最后 `build()`。只写 `persistent` 的组件不会同步到客户端。

批量修改原版物品的默认组件，用 `ModifyDefaultComponentsEvent`（mod 总线）：

```java
@SubscribeEvent
public static void modifyComponents(ModifyDefaultComponentsEvent event) {
    event.modify(Items.DIAMOND_SWORD, builder ->
        builder.set(ExampleDataComponents.CHARGE.get(), 3));
}
```

### 5.8 数据附件（`AttachmentType`，替代 Capability 的“给已有对象加数据”）

```java
import com.mojang.serialization.Codec;
import net.minecraft.network.codec.ByteBufCodecs;
import net.neoforged.neoforge.attachment.AttachmentType;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;
import net.neoforged.neoforge.registries.NeoForgeRegistries;

public final class ExampleAttachments {

    public static final DeferredRegister<AttachmentType<?>> ATTACHMENT_TYPES =
        DeferredRegister.create(NeoForgeRegistries.Keys.ATTACHMENT_TYPES, ExampleMod.MOD_ID);

    // 玩家法力值：默认 0，存档保存，死亡保留，并同步给客户端
    public static final DeferredHolder<AttachmentType<?>, AttachmentType<Integer>> MANA =
        ATTACHMENT_TYPES.register("mana", () -> AttachmentType.builder(() -> 0)
            .serialize(Codec.INT)                 // 写入 NBT
            .copyOnDeath()                        // 死亡不掉
            .sync(ByteBufCodecs.VAR_INT)          // 自动同步
            .build());
}
```

使用（仅 `Level`、`Entity`、`ChunkAccess`、`BlockEntity` 实现了 `IAttachmentHolder`；`ItemStack` 不在其中，物品数据请用数据组件）：

```java
int mana = player.getData(ExampleAttachments.MANA.get());   // 取不到时返回默认值
player.setData(ExampleAttachments.MANA.get(), mana + 1);
Integer existing = player.getExistingDataOrNull(ExampleAttachments.MANA.get()); // 可能为 null
player.removeData(ExampleAttachments.MANA.get());
```

`AttachmentType.Builder` 核对过的方法：`serialize(IAttachmentSerializer)`、`serialize(Codec<T>)`、`serialize(Codec<T>, Predicate<? super T>)`、`copyOnDeath()`、`copyHandler(IAttachmentCopyHandler<T>)`、`sync(AttachmentSyncHandler<T>)`、`sync(StreamCodec<? super RegistryFriendlyByteBuf, T>)`、`sync(BiPredicate<IAttachmentHolder, ServerPlayer>, StreamCodec)`、`build()`。

自定义同步逻辑实现 `AttachmentSyncHandler<T>`（三个方法）：

```java
public class ManaSyncHandler implements AttachmentSyncHandler<Integer> {
    @Override
    public boolean sendToPlayer(IAttachmentHolder holder, ServerPlayer to) {
        return true;   // 默认实现即“所有能看到 holder 的玩家”
    }

    @Override
    public void write(RegistryFriendlyByteBuf buf, Integer mana, boolean initialSync) {
        buf.writeVarInt(mana);
    }

    @Override
    public Integer read(IAttachmentHolder holder, RegistryFriendlyByteBuf buf, Integer previousValue) {
        return buf.readVarInt();
    }
}
```

### 5.9 实体类型、状态效果、粒子、配方（简例）

```java
// 实体类型
public static final DeferredRegister<EntityType<?>> ENTITY_TYPES =
    DeferredRegister.create(Registries.ENTITY_TYPE, ExampleMod.MOD_ID);

public static final DeferredHolder<EntityType<?>, EntityType<RubyGolem>> RUBY_GOLEM =
    ENTITY_TYPES.register("ruby_golem", () -> EntityType.Builder
        .of(RubyGolem::new, MobCategory.MISC)
        .sized(0.6F, 1.8F)
        .clientTrackingRange(10)
        .build("examplemod:ruby_golem"));

// 状态效果：MobEffect 的构造器是 protected，必须写子类
public static final DeferredRegister<MobEffect> MOB_EFFECTS =
    DeferredRegister.create(Registries.MOB_EFFECT, ExampleMod.MOD_ID);

public static final DeferredHolder<MobEffect, MobEffect> RUBY_SHIELD =
    MOB_EFFECTS.register("ruby_shield", RubyShieldEffect::new);

public class RubyShieldEffect extends MobEffect {
    public RubyShieldEffect() {
        super(MobEffectCategory.BENEFICIAL, 0xC0121A);
    }
}

// 粒子
public static final DeferredRegister<ParticleType<?>> PARTICLE_TYPES =
    DeferredRegister.create(Registries.PARTICLE_TYPE, ExampleMod.MOD_ID);

public static final DeferredHolder<ParticleType<?>, SimpleParticleType> RUBY_SPARK =
    PARTICLE_TYPES.register("ruby_spark", () -> new SimpleParticleType(false));

// 配方序列化器 + 配方类型
public static final DeferredRegister<RecipeSerializer<?>> RECIPE_SERIALIZERS =
    DeferredRegister.create(Registries.RECIPE_SERIALIZER, ExampleMod.MOD_ID);

public static final DeferredHolder<RecipeSerializer<?>, RecipeSerializer<RubyRecipe>> RUBY_RECIPE_SERIALIZER =
    RECIPE_SERIALIZERS.register("ruby_crafting", RubyRecipe.Serializer::new);

public static final DeferredRegister<RecipeType<?>> RECIPE_TYPES =
    DeferredRegister.create(Registries.RECIPE_TYPE, ExampleMod.MOD_ID);

public static final DeferredHolder<RecipeType<?>, RecipeType<RubyRecipe>> RUBY_RECIPE_TYPE =
    RECIPE_TYPES.register("ruby_crafting", () -> new RecipeType<>() {
        @Override
        public String toString() {
            return ExampleMod.MOD_ID + ":ruby_crafting";
        }
    });
```

`Feature` / `PlacementModifierType` 简述：
- `Registries.FEATURE` 注册 `Feature<XxxConfig>`，`codec` 用 `RecordCodecBuilder` 组合；世界生成 JSON 里再按 id 引用。
- `Registries.PLACEMENT_MODIFIER_TYPE` 注册 `PlacementModifierType<C>`，实现类继承 `PlacementModifier` 并返回一个 `PlacementModifierType`。
- 两者都属世界生成数据包注册表，属于进阶内容；注册语法与上面完全一致，只是泛型参数不同。

## 6. 事件

### 6.1 注解自动注册规则

```java
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;

@EventBusSubscriber(modid = ExampleMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class ModEvents {

    @SubscribeEvent
    public static void onCommonSetup(FMLCommonSetupEvent event) {
        event.enqueueWork(() -> { /* 主线程初始化 */ });
    }
}
```

规则（写错任何一条都静默失效）：
1. 类必须是 `public`（包私有也能被扫到，但建议 public）。
2. 监听方法必须是 `public static`，返回 `void`，参数恰好一个事件类型。
3. 方法必须带 `@SubscribeEvent`。
4. `@EventBusSubscriber` 的 `modid` 用于限定“仅当该模组加载时才注册”。
5. `bus` 默认 `Bus.GAME`；mod 事件**必须**写 `bus = Bus.MOD`。
6. `value = Dist.CLIENT` 限定只在客户端注册（用于 `FMLClientSetupEvent` 等）。
7. `@Mod(dist = Dist.CLIENT)` 的主类只会在客户端实例化，适合放客户端入口。

手动注册（实例方法也行）：

```java
NeoForge.EVENT_BUS.addListener(ExampleMod::onPlayerJoin);
modBus.addListener(EventPriority.HIGH, this::onRegister);
```

`IEventBus` 的重载：`addListener(Consumer<T>)`、`addListener(EventHandlerPriority, Consumer<T>)`、`addListener(boolean receiveCanceled, Consumer<T>)`，以及带 `Class<T>` 的显式类型版本（用于泛型推断失败时）。

### 6.2 优先级与取消

`EventPriority` 只有五档：`HIGHEST` → `HIGH` → `NORMAL` → `LOW` → `LOWEST`（`HIGHEST` 最先执行）。

1.21 的事件**没有** `Event.Result`（1.20.1 Forge 才有）。取消统一用 `ICancellableEvent`：

```java
public class BlockEvent.BreakEvent extends BlockEvent implements ICancellableEvent { ... }
```

```java
@SubscribeEvent
public static void onBreak(BlockEvent.BreakEvent event) {
    // getPlayer() 在“非玩家破坏”场景（如活塞、爆炸）下可能为 null，必须先判空
    Player player = event.getPlayer();
    if (player == null) {
        return;
    }
    if (!player.hasPermissions(2)) {
        event.setCanceled(true);
    }
}
```

部分交互事件不用布尔取消，而用三态 `net.neoforged.neoforge.common.util.TriState`：

```java
@SubscribeEvent
public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
    // TRUE = 强制允许，FALSE = 强制拒绝，DEFAULT = 交给原逻辑
    event.setUseBlock(TriState.FALSE);
    event.setUseItem(TriState.FALSE);
    event.setCancellationResult(InteractionResult.SUCCESS);
}
```

### 6.3 生命周期事件表（mod 总线）

| 事件 | 时机 | 常见用途 |
| --- | --- | --- |
| `FMLConstructModEvent` | 主类构造后立即 | 极早期初始化（少用） |
| `FMLCommonSetupEvent` | 两侧通用初始化，**并行线程池** | 原版注册表后处理；必须 `enqueueWork` 才安全 |
| `FMLClientSetupEvent` | 客户端初始化，并行 | 客户端注册表后处理 |
| `FMLDedicatedServerSetupEvent` | 专用服务器初始化，并行 | 服务器专属初始化 |
| `InterModEnqueueEvent` | 模组间通信入队 | 给别的模组发 `IMessage` |
| `InterModProcessEvent` | 模组间通信处理 | 收别的模组的消息 |
| `FMLLoadCompleteEvent` | 加载完成 | 最终校验 |
| `RegisterEvent` | 每个注册表填充时触发一次 | 手动注册（`event.register(Registries.X, ...)`） |
| `NewRegistryEvent` | 自定义注册表创建时 | `event.create(new RegistryBuilder<>()...)` |
| `ModifyRegistriesEvent` | 注册表填充完后 | 删除/替换已有条目（慎用） |
| `EntityAttributeCreationEvent` | 实体属性注册 | `event.put(ENTITY_TYPE, Supplier<AttributeSupplier>)` |
| `RegisterSpawnPlacementsEvent` | 生成规则注册 | `event.register(type, predicate, Operation.ADD)` |
| `BuildCreativeModeTabContentsEvent` | 标签页内容构建 | 往原版页追加物品 |
| `ModifyDefaultComponentsEvent` | 物品默认组件 | `event.modify(item, builder -> ...)` |
| `RegisterCapabilitiesEvent` | Capability 注册 | 见第 11 章 |
| `RegisterPayloadHandlersEvent` | 网络载荷注册 | 见第 8 章 |
| `GatherDataEvent` | 数据生成 | 见第 9 章 |
| `ModConfigEvent.Loading` / `.Reloading` | 配置加载/重载 | 缓存配置值 |

`RegisterEvent` 的用法（不通过 `DeferredRegister` 时）：

```java
@SubscribeEvent
public static void onRegister(RegisterEvent event) {
    event.register(Registries.BLOCK, helper ->
        helper.register(ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "legacy_block"),
            new Block(BlockBehaviour.Properties.of())));
}
```

### 6.4 运行期事件表（game 总线）

| 事件 | 时机 | 备注 |
| --- | --- | --- |
| `ServerAboutToStartEvent` | 服务器对象已建、世界未加载 | 可改服务器配置 |
| `ServerStartingEvent` | 世界已加载、命令注册前 | `event.getServer()` |
| `ServerStartedEvent` | 启动完成 | 服务器已可接受连接 |
| `ServerStoppingEvent` | 开始停止 | 保存数据 |
| `ServerStoppedEvent` | 已停止 | 清理静态引用 |
| `PlayerEvent.PlayerLoggedInEvent` | 玩家登录 | 发欢迎语、同步数据 |
| `PlayerEvent.PlayerLoggedOutEvent` | 玩家登出 | 清理缓存 |
| `PlayerEvent.PlayerRespawnEvent` / `.Clone` | 重生 / 跨维度复制 | 复制自定义数据 |
| `PlayerEvent.BreakSpeed` | 计算挖掘速度（可取消） | 改挖掘速度 |
| `PlayerInteractEvent.RightClickBlock` / `.LeftClickBlock` / `.RightClickItem` / `.EntityInteract` | 交互 | 三态 + 可取消 |
| `LivingIncomingDamageEvent` | 伤害**进入**实体前（可取消，可加减免） | 护甲/药水减免阶段 |
| `LivingDamageEvent.Pre` | 伤害已结算、即将扣血 | `setNewDamage` 改最终值 |
| `LivingDamageEvent.Post` | 扣血之后 | 只读统计，改不了 |
| `LivingDeathEvent` | 死亡前（可取消） | 阻止死亡 |
| `BlockEvent.BreakEvent` | 方块被破坏前（可取消） | `getPlayer()` 可能为 `null` |
| `BlockEvent.EntityPlaceEvent` | 实体放置方块 | |
| `EntityJoinLevelEvent` | 实体加入世界 | 可取消加入 |
| `LevelTickEvent.Pre` / `.Post` | 世界 tick | 每 tick 两次，注意性能 |
| `PlayerTickEvent.Pre` / `.Post` | 玩家 tick | |
| `ServerTickEvent.Pre` / `.Post` | 服务器 tick | 全局调度 |
| `RegisterCommandsEvent` | 命令树构建 | `event.getDispatcher()` |
| `AddReloadListenerEvent` | 数据包重载监听器注册 | `event.addListener(PreparableReloadListener)` |
| `OnDatapackSyncEvent` | 数据包同步给玩家 | `getPlayer()` 为 null 表示同步给所有人 |
| `TagsUpdatedEvent` | 标签重载完成 | 重建标签缓存 |
| `ExplosionEvent.Detonate` | 爆炸影响列表已算 | 修改受影响方块/实体 |

`LivingDamageEvent` 与 `LivingIncomingDamageEvent` 的区别（重点）：

| | `LivingIncomingDamageEvent` | `LivingDamageEvent.Pre/Post` |
| --- | --- | --- |
| 位置 | 伤害管线最前端（护甲、附魔、药水减免之前） | 所有减免结算之后 |
| 可取消 | 是（`ICancellableEvent`） | `Pre` 不可取消，只能 `setNewDamage`；`Post` 只读 |
| 改数值 | `setAmount(float)` | `Pre#setNewDamage(float)` |
| 减免 | `addReductionModifier(DamageContainer.Reduction, IReductionFunction)` | 只能看 `getReduction(...)` |
| 无敌帧 | `setInvulnerabilityTicks(int)` | `Post#getPostAttackInvulnerabilityTicks()` |

```java
// 想让“红宝石护甲”减伤，应该用 Incoming
@SubscribeEvent
public static void reduceDamage(LivingIncomingDamageEvent event) {
    if (event.getEntity() instanceof Player player
            && player.getItemBySlot(EquipmentSlot.CHEST).is(ExampleItems.RUBY_BLOCK.get())) {
        event.addReductionModifier(DamageContainer.Reduction.ARMOR,
            (container, amount) -> amount * 0.5F);
    }
}

// 想改最终扣血量，用 Pre
@SubscribeEvent
public static void finalDamage(LivingDamageEvent.Pre event) {
    if (event.getSource().is(DamageTypeTags.IS_FIRE)) {
        event.setNewDamage(event.getNewDamage() * 0.5F);
    }
}
```

`OnDatapackSyncEvent` 用法：

```java
@SubscribeEvent
public static void onSync(OnDatapackSyncEvent event) {
    if (event.getPlayer() == null) {
        // 全量同步（玩家刚进服时）
        event.getRelevantPlayers().forEach(p -> PacketDistributor.sendToPlayer(p, new RubySyncPayload(...)));
    } else {
        PacketDistributor.sendToPlayer(event.getPlayer(), new RubySyncPayload(...));
    }
}
```

### 6.5 生命周期事件里的线程模型

`FMLCommonSetupEvent` / `FMLClientSetupEvent` / `FMLDedicatedServerSetupEvent` 都继承 `ParallelDispatchEvent`，方法为：

```java
public CompletableFuture<Void> enqueueWork(Runnable task);
public <T> CompletableFuture<T> enqueueWork(Supplier<T> task);
```

它们本身在并行派发线程上执行。任何触碰原版注册表内部状态（`CompostableRegistry`、`BrewingRecipeRegistry`、`FurnaceFuels`、`SpawnPlacements` 等）的操作都必须放进 `enqueueWork`，否则会出现偶发 `ConcurrentModificationException` 或“注册表已冻结”异常。

## 7. 配置

### 7.1 完整配置类

```java
package com.example.examplemod;

import java.util.List;
import net.neoforged.neoforge.common.ModConfigSpec;

public final class Config {

    public static final ModConfigSpec SPEC;
    public static final ModConfigSpec.BooleanValue RUBY_ENABLED;
    public static final ModConfigSpec.IntValue RUBY_DROP_CHANCE;
    public static final ModConfigSpec.DoubleValue RUBY_SPEED;
    public static final ModConfigSpec.EnumValue<Difficulty> DIFFICULTY;
    public static final ModConfigSpec.ConfigValue<List<? extends String>> DIMENSION_WHITELIST;
    public static final ModConfigSpec.IntValue MAX_MANA;

    public enum Difficulty { EASY, NORMAL, HARD }

    static {
        ModConfigSpec.Builder builder = new ModConfigSpec.Builder();

        builder.comment("通用设置").push("general");
        RUBY_ENABLED = builder
            .comment("是否启用红宝石相关内容")
            .define("rubyEnabled", true);
        RUBY_DROP_CHANCE = builder
            .comment("矿石掉落概率，0-100")
            .defineInRange("rubyDropChance", 5, 0, 100);
        RUBY_SPEED = builder
            .defineInRange("rubySpeed", 1.0D, 0.0D, 10.0D);
        builder.pop();

        builder.comment("平衡性").push("balance");
        DIFFICULTY = builder
            .defineEnum("difficulty", Difficulty.NORMAL);
        MAX_MANA = builder
            .comment("法力上限")
            .worldRestart()                    // 改动后需要重开世界
            .defineInRange("maxMana", 100, 1, 10000);
        builder.pop();

        builder.push("filters");
        DIMENSION_WHITELIST = builder
            .comment("允许生成红宝石的维度")
            .defineList("dimensionWhitelist",
                List.of("minecraft:overworld"),
                o -> o instanceof String s && !s.isBlank());
        builder.pop();

        SPEC = builder.build();
    }

    private Config() {}
}
```

### 7.2 API 表

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `push(String)` / `push(List<String>)` | `Builder` | 进入子分类，写进 TOML 时表现为表 |
| `pop()` / `pop(int)` | `Builder` | 退出 1 层 / N 层 |
| `comment(String...)` | `Builder` | 下一项/下一段的注释 |
| `translation(String)` | `Builder` | 给该项一个翻译键（供 `ConfigurationScreen` 用） |
| `worldRestart()` | `Builder` | 标记“改动需重开世界” |
| `define(String, T)` | `ConfigValue<T>` | 默认值 + 类型推断 |
| `define(String, boolean)` | `BooleanValue` | |
| `defineInRange(String, int, int, int)` | `IntValue` | 值、最小值、最大值 |
| `defineInRange(String, double, double, double)` | `DoubleValue` | |
| `defineInRange(String, long, long, long)` | `LongValue` | |
| `defineInRange(String, V, V, V, Class<V>)` | `ConfigValue<V>` | 自定义 `Comparable` 类型 |
| `defineEnum(String, V)` | `EnumValue<V>` | 也可传可变参数限定集合 |
| `defineList(String, List, Predicate<Object>)` | `ConfigValue<List<? extends T>>` | 元素校验器 |
| `defineListAllowEmpty(...)` | 同上 | 允许空列表 |
| `defineInList(String, T, Collection<? extends T>)` | `ConfigValue<T>` | 限定取值集合 |
| `build()` | `ModConfigSpec` | 收尾，必须最后调用 |

> 没有 `defineMap`。需要键值对时用 `defineList` + `"k=v"` 字符串自行解析，或用 `ConfigValue<List<? extends String>>`。

读取与写入：

```java
boolean enabled = Config.RUBY_ENABLED.get();
int chance = Config.RUBY_DROP_CHANCE.get();
Config.RUBY_DROP_CHANCE.set(10);          // 仅内存生效，不会写盘
```

`ConfigValue<T>` 实现了 `Supplier<T>`，所以 `Config.RUBY_ENABLED` 可以直接当作 `BooleanSupplier`（`BooleanValue` 实现了 `BooleanSupplier`）。

### 7.3 注册与类型

```java
container.registerConfig(ModConfig.Type.COMMON, Config.SPEC);
// 可选：自定义文件名（默认 <modid>-common.toml）
container.registerConfig(ModConfig.Type.COMMON, Config.SPEC, "examplemod-custom.toml");
```

| 类型 | 文件（默认） | 位置 | 同步 |
| --- | --- | --- | --- |
| `STARTUP` | `<modid>-startup.toml` | `config/` | 不参与世界，加载最早 |
| `COMMON` | `<modid>-common.toml` | `config/` | 服务端读取，不同步到客户端 |
| `SERVER` | `<modid>-server.toml` | 世界存档的 `serverconfig/` | 随世界走，服务端向客户端同步 |
| `CLIENT` | `<modid>-client.toml` | `config/` | 仅客户端 |

### 7.4 加载/重载事件与缓存

配置在 `ModConfigEvent.Loading` 之后才可用；在此之前访问 `get()` 会抛 `IllegalStateException`（值未加载）。

```java
public final class ConfigCache {

    private static boolean enabled = true;
    private static int dropChance = 5;

    @SubscribeEvent
    public static void onLoading(ModConfigEvent.Loading event) {
        if (event.getConfig().getSpec() == Config.SPEC) {
            reload();
        }
    }

    @SubscribeEvent
    public static void onReloading(ModConfigEvent.Reloading event) {
        if (event.getConfig().getSpec() == Config.SPEC) {
            reload();
        }
    }

    private static void reload() {
        enabled = Config.RUBY_ENABLED.get();
        dropChance = Config.RUBY_DROP_CHANCE.get();
    }

    public static boolean enabled() { return enabled; }
    public static int dropChance() { return dropChance; }
}
```

这两个事件都在 **mod 总线**（`ModConfigEvent implements IModBusEvent`）。热路径（每 tick 调用）读缓存字段，不要每次 `get()`。

### 7.5 配置界面

```java
import net.neoforged.neoforge.client.gui.ConfigurationScreen;
import net.neoforged.neoforge.client.gui.IConfigScreenFactory;

// 在 @Mod 构造函数里，且必须限客户端
if (dist == Dist.CLIENT) {
    container.registerExtensionPoint(IConfigScreenFactory.class, ConfigurationScreen::new);
}
```

`IConfigScreenFactory` 是函数式接口，唯一方法 `Screen createScreen(ModContainer container, Screen modListScreen)`；`ConfigurationScreen(ModContainer, Screen)` 的签名正好匹配，所以可以直接用构造器引用。`ConfigurationScreen` 还有两个重载：带 `ConfigurationSectionScreen.Filter`、带自定义 section 工厂，用于过滤或替换子页面。

想让配置项显示中文，给 `define` 前的 `Builder` 加 `translation("examplemod.config.rubyEnabled")`，然后在 `lang/zh_cn.json` 里给该键做翻译。

## 8. 网络

### 8.1 核心概念

1.21.1 完全移除 `SimpleChannel` / `NetworkRegistry`。现在：
- 载荷实现 `CustomPacketPayload`，并自带 `Type<T>` 与 `StreamCodec`。
- 在 `RegisterPayloadHandlersEvent`（mod 总线）里通过 `PayloadRegistrar` 注册。
- 用 `PacketDistributor` 发送。

`RegistryFriendlyByteBuf` vs `FriendlyByteBuf`：

| | `FriendlyByteBuf` | `RegistryFriendlyByteBuf` |
| --- | --- | --- |
| 位置 | `net.minecraft.network` | `net.minecraft.network` |
| 是否带注册表访问 | 否 | 是（`registryAccess()`） |
| 用途 | 配置阶段（configuration）载荷、纯基础类型 | 游戏阶段（play）载荷，可读写 `Holder`/`ItemStack`/`BlockState` 等需要注册表的数据 |
| 注册器对应方法 | `configurationToClient/Server/Bidirectional` | `playToClient/Server/Bidirectional` |

写 play 阶段载荷时，`StreamCodec` 泛型必须是 `RegistryFriendlyByteBuf`（或其父类型），否则用 `ByteBufCodecs.holderRegistry(...)` 这类需要注册表的编解码器会编译失败。

### 8.2 载荷定义

```java
package com.example.examplemod.network;

import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.network.codec.NeoForgeStreamCodecs;

public record RubySyncPayload(String name, int amount) implements net.minecraft.network.protocol.common.custom.CustomPacketPayload {

    public static final CustomPacketPayload.Type<RubySyncPayload> TYPE =
        new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
            "examplemod", "ruby_sync"));

    // 组合编解码器：顺序必须与 record 组件一致
    public static final StreamCodec<RegistryFriendlyByteBuf, RubySyncPayload> STREAM_CODEC =
        StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, RubySyncPayload::name,
            ByteBufCodecs.VAR_INT, RubySyncPayload::amount,
            RubySyncPayload::new);

    @Override
    public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
        return TYPE;
    }
}
```

要点：
- `Type` 的 id 必须全局唯一，建议 `<modid>:<name>`。
- `StreamCodec.composite` 最多支持 6 组“编解码器 + getter”，最后一参是构造器。
- `record` 是最省事的写法；用普通类时注意 `type()` 必须返回同一个常量实例。
- `NeoForgeStreamCodecs` 提供了一些原版没有的组合（如 `Optional`、`Either` 的便捷版本），需要时可用。

### 8.3 处理器类

```java
package com.example.examplemod.network;

import net.minecraft.world.entity.player.Player;
import net.neoforged.neoforge.network.handling.IPayloadContext;

public final class RubySyncHandler {

    // 服务端收到（客户端发来的）
    public static void handleFromClient(RubySyncPayload payload, IPayloadContext context) {
        // 默认在 MAIN 线程执行，但显式 enqueueWork 更稳，尤其是要访问世界状态时
        context.enqueueWork(() -> {
            Player player = context.player();   // 服务端侧返回发送者 ServerPlayer
            player.sendSystemMessage(net.minecraft.network.chat.Component.literal(
                "收到 " + payload.name() + " x" + payload.amount()));
        });
    }

    // 客户端收到（服务端发来的）
    public static void handleFromServer(RubySyncPayload payload, IPayloadContext context) {
        context.enqueueWork(() -> {
            Player player = context.player();   // 客户端侧返回 LocalPlayer
            // 只做客户端表现：更新 HUD、播放音效等
        });
    }
}
```

`IPayloadContext` 核对结果：`player()`、`connection()`、`protocol()`、`enqueueWork(Runnable)`、`enqueueWork(Supplier<T>)`、`reply(CustomPacketPayload)`、`disconnect(Component)`、`handle(Packet<?>)`、`channelHandlerContext()`。

- `enqueueWork` 返回 `CompletableFuture`，异常会被记录到日志而不会静默丢弃（但仍建议自己 try/catch）。
- `player()` 只在 PLAY 阶段可用；配置阶段返回会抛异常。

### 8.4 注册

```java
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.registration.HandlerThread;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

@SubscribeEvent
public static void registerPayloads(RegisterPayloadHandlersEvent event) {
    // 参数是“网络版本号”，两端不一致时会话在配置阶段失败
    PayloadRegistrar registrar = event.registrar("1");

    registrar
        // 双向：同一个 type + codec，两个方向各一个处理器
        .playBidirectional(RubySyncPayload.TYPE, RubySyncPayload.STREAM_CODEC,
            RubySyncHandler::handleFromServer)
        .optional()                       // 该载荷允许对端缺失（不强制两端都装）
        .versioned("1.0.1");              // 单独给这个载荷设置版本

    // 单向示例
    registrar.playToServer(RubySyncPayload.TYPE, RubySyncPayload.STREAM_CODEC,
        RubySyncHandler::handleFromClient);

    // 配置阶段载荷（用 FriendlyByteBuf）
    registrar.configurationToClient(RubyConfigPayload.TYPE, RubyConfigPayload.STREAM_CODEC,
        RubyConfigHandler::handle);
}
```

注意：`playBidirectional` 的第三个参数是 **`IPayloadHandler<T>`**，即 `(payload, context) -> void`。双向注册只提供一个处理器，因此若两个方向逻辑不同，应该分别调用 `playToClient` 与 `playToServer`，而不是用 `playBidirectional`。

`PayloadRegistrar` 核对过的方法：

| 方法 | 阶段 | 说明 |
| --- | --- | --- |
| `playToClient(Type<T>, StreamCodec<? super RegistryFriendlyByteBuf, T>, IPayloadHandler<T>)` | play | 服务端 → 客户端 |
| `playToServer(...)` | play | 客户端 → 服务端 |
| `playBidirectional(...)` | play | 双向，单一处理器 |
| `configurationToClient(...)` | configuration | 用 `FriendlyByteBuf` |
| `configurationToServer(...)` | configuration | |
| `configurationBidirectional(...)` | configuration | |
| `commonToClient(...)` | play + configuration | 两阶段都注册 |
| `commonToServer(...)` | 同上 | |
| `commonBidirectional(...)` | 同上 | |
| `executesOn(HandlerThread)` | — | 后续注册的默认执行线程，`HandlerThread.MAIN`（默认）或 `HandlerThread.NETWORK` |
| `versioned(String)` | — | 后续注册的载荷版本 |
| `optional()` | — | 后续注册的载荷允许对端缺失 |

`HandlerThread` 只有两个枚举值：`MAIN`（客户端渲染线程 / 服务端主线程）与 `NETWORK`（网络线程）。设成 `NETWORK` 时**必须**自己 `enqueueWork` 才能访问游戏状态。

### 8.5 发送

```java
import net.neoforged.neoforge.network.PacketDistributor;

// 客户端 → 服务端（只能在客户端调用）
PacketDistributor.sendToServer(new RubySyncPayload("ruby", 3));

// 服务端 → 单个玩家
PacketDistributor.sendToPlayer(serverPlayer, new RubySyncPayload("ruby", 1));

// 服务端 → 所有玩家
PacketDistributor.sendToAllPlayers(new RubySyncPayload("ruby", 1));

// 服务端 → 某维度内所有玩家
PacketDistributor.sendToPlayersInDimension(serverLevel, new RubySyncPayload("ruby", 1));

// 服务端 → 某坐标附近的玩家
PacketDistributor.sendToPlayersNear(serverLevel, /* 排除的玩家 */ null, x, y, z, radius, payload);

// 服务端 → 追踪某实体的玩家（不含实体本身）
PacketDistributor.sendToPlayersTrackingEntity(entity, payload);

// 服务端 → 追踪某实体的玩家 + 实体本身（若实体是玩家）
PacketDistributor.sendToPlayersTrackingEntityAndSelf(entity, payload);

// 服务端 → 某区块的追踪者
PacketDistributor.sendToPlayersTrackingChunk(serverLevel, chunkPos, payload);
```

方法名核对结果：是 `sendToPlayersInDimension`（不是 `sendToAllPlayersInDimension`），参数是 `ServerLevel`。

### 8.6 大小限制与常见错误

| 限制 | 值 |
| --- | --- |
| 客户端发出的单个自定义载荷 | 1 MiB |
| 服务端发出的单个自定义载荷 | 32 KiB |
| 超额行为 | 连接被断开，日志有 `Payload may not be larger than ...` |

排查：
- **注册了但收不到**：检查是否 `event.registrar(...)` 返回的 registrar 链式调用被丢弃（`registrar.playToClient(...)` 有返回值，但注册是副作用，不会丢）。真正的问题多是 `RegisterPayloadHandlersEvent` 挂错总线。
- **`Unknown payload id`**：两端 mod 版本不同，或 `optional()` 用在了必须存在的载荷上。
- **`ClassCastException: RegistryFriendlyByteBuf cannot be cast to FriendlyByteBuf`**：`configuration*` 系列用了 `RegistryFriendlyByteBuf` 的 codec，或反之。

## 9. 数据生成

### 9.1 入口

```java
import net.minecraft.data.DataGenerator;
import net.minecraft.data.PackOutput;
import net.neoforged.neoforge.common.data.ExistingFileHelper;
import net.neoforged.neoforge.data.event.GatherDataEvent;

@SubscribeEvent
public static void gatherData(GatherDataEvent event) {
    DataGenerator generator = event.getGenerator();
    PackOutput output = generator.getPackOutput();
    ExistingFileHelper helper = event.getExistingFileHelper();
    java.util.concurrent.CompletableFuture<HolderLookup.Provider> lookup = event.getLookupProvider();

    // 客户端资源（assets/）
    generator.addProvider(event.includeClient(), new ExampleItemModels(output, helper));
    generator.addProvider(event.includeClient(), new ExampleBlockStates(output, helper));
    generator.addProvider(event.includeClient(), new ExampleChineseLang(output, "zh_cn"));
    generator.addProvider(event.includeClient(), new ExampleEnglishLang(output, "en_us"));

    // 服务端数据（data/）
    BlockTagsProvider blockTags = new BlockTagsProvider(output, lookup, ExampleMod.MOD_ID, helper);
    generator.addProvider(event.includeServer(), blockTags);
    generator.addProvider(event.includeServer(), new ItemTagsProvider(
        output, lookup, blockTags.contentsGetter(), ExampleMod.MOD_ID, helper));
    generator.addProvider(event.includeServer(), new ExampleRecipes(output, lookup));
    generator.addProvider(event.includeServer(), new ExampleLootTables(output, lookup));
    generator.addProvider(event.includeServer(), new ExampleDataMaps(output, lookup));
}
```

`GatherDataEvent` 核对过的 API：`getGenerator()`、`getExistingFileHelper()`、`getLookupProvider()`、`includeClient()`、`includeServer()`、`includeDev()`、`includeReports()`、`getModContainer()`、`getMods()`、`getInputs()`。

`DataGenerator` 的方法：`getPackOutput()`、`getPackOutput(String path)`、`addProvider(boolean run, T provider)`、`addProvider(boolean run, DataProvider.Factory<T>)`。

### 9.2 各 Provider 示例

**物品模型**

```java
public class ExampleItemModels extends ItemModelProvider {

    public ExampleItemModels(PackOutput output, ExistingFileHelper helper) {
        super(output, ExampleMod.MOD_ID, helper);
    }

    @Override
    protected void registerModels() {
        basicItem(ExampleItems.RUBY.get());          // 自动生成 item/ruby.json
        basicItem(ExampleItems.RUBY_APPLE.get());
        // 手持物品用自定义父模型
        withExistingParent("ruby_wand", mcLoc("item/handheld"))
            .texture("layer0", modLoc("item/ruby_wand"));
    }
}
```

**方块状态与方块模型**

```java
public class ExampleBlockStates extends BlockStateProvider {

    public ExampleBlockStates(PackOutput output, ExistingFileHelper helper) {
        super(output, ExampleMod.MOD_ID, helper);
    }

    @Override
    protected void registerStatesAndModels() {
        // 生成 blockstates/ruby_block.json + models/block/ruby_block.json + item 模型
        simpleBlockWithItem(ExampleBlocks.RUBY_BLOCK.get(),
            models().cubeAll("ruby_block", modLoc("block/ruby_block")));

        // 水平朝向方块（熔炉式）
        horizontalBlock(ExampleBlocks.RUBY_ORE.get(),
            models().orientable("ruby_ore",
                modLoc("block/ruby_ore_side"),
                modLoc("block/ruby_ore_front"),
                modLoc("block/ruby_ore_top")));
    }
}
```

**语言文件**

```java
public class ExampleEnglishLang extends LanguageProvider {

    public ExampleEnglishLang(PackOutput output, String locale) {
        super(output, ExampleMod.MOD_ID, locale);
    }

    @Override
    protected void addTranslations() {
        add(ExampleBlocks.RUBY_BLOCK.get(), "Ruby Block");
        add(ExampleItems.RUBY.get(), "Ruby");
        add("itemGroup.examplemod.ruby", "Ruby");
        add("container.examplemod.ruby", "Ruby Machine");
        add("config.examplemod.rubyEnabled", "Enable Ruby");
    }
}
```

`LanguageProvider(PackOutput, String modid, String locale)`；便捷方法：`addBlock`、`addItem`、`addItemStack`、`addEntityType`、`addEffect`、`addBiome`、`addTag`、`add(Block/Item/... key, String)`、`add(String key, String value)`、`addDimension`。

**方块/物品标签**

```java
public class ExampleBlockTags extends BlockTagsProvider {

    public ExampleBlockTags(PackOutput output, CompletableFuture<HolderLookup.Provider> lookup,
                            ExistingFileHelper helper) {
        super(output, lookup, ExampleMod.MOD_ID, helper);
    }

    @Override
    protected void addTags(HolderLookup.Provider provider) {
        tag(BlockTags.MINEABLE_WITH_PICKAXE).add(ExampleBlocks.RUBY_BLOCK.get());
        tag(BlockTags.NEEDS_IRON_TOOL).add(ExampleBlocks.RUBY_BLOCK.get());
        // 自定义标签
        tag(net.minecraft.tags.TagKey.create(Registries.BLOCK,
            ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "ruby_ores")))
            .add(ExampleBlocks.RUBY_ORE.get());
    }
}
```

`ItemTagsProvider` 在 NeoForge 下的构造器是 `(PackOutput, CompletableFuture<HolderLookup.Provider>, CompletableFuture<TagLookup<Block>>, String modId, ExistingFileHelper)`——注意第三个参数是 `blockTags.contentsGetter()`，而不是 `blockTags` 本身。

**配方**

```java
public class ExampleRecipes extends RecipeProvider {

    public ExampleRecipes(PackOutput output, CompletableFuture<HolderLookup.Provider> lookup) {
        super(output, lookup);
    }

    @Override
    protected void buildRecipes(RecipeOutput output) {
        // 有序合成：9 个红宝石 → 1 个红宝石块
        ShapedRecipeBuilder.shaped(RecipeCategory.BUILDING_BLOCKS, ExampleBlocks.RUBY_BLOCK.get())
            .pattern("###").pattern("###").pattern("###")
            .define('#', ExampleItems.RUBY.get())
            .unlockedBy("has_ruby", has(ExampleItems.RUBY.get()))
            .save(output);

        // 无序合成：1 个红宝石块 → 9 个红宝石
        ShapelessRecipeBuilder.shapeless(RecipeCategory.MISC, ExampleItems.RUBY.get(), 9)
            .requires(ExampleBlocks.RUBY_BLOCK.get())
            .unlockedBy("has_ruby_block", has(ExampleBlocks.RUBY_BLOCK.get()))
            .save(output, "examplemod:ruby_from_block");
    }
}
```

**战利品表**

```java
public class ExampleLootTables extends LootTableProvider {

    public ExampleLootTables(PackOutput output, CompletableFuture<HolderLookup.Provider> lookup) {
        super(output, java.util.Set.of(), java.util.List.of(
            new LootTableProvider.SubProviderEntry(ExampleBlockLoot::new, LootContextParamSets.BLOCK)),
            lookup);
    }

    public static class ExampleBlockLoot extends BlockLootSubProvider {

        protected ExampleBlockLoot(HolderLookup.Provider registries) {
            super(java.util.Set.of(), FeatureFlags.DEFAULT_FLAGS, registries);
        }

        @Override
        protected void generate() {
            dropSelf(ExampleBlocks.RUBY_BLOCK.get());
            // 矿物需要掉落物品，用 createOreDrop
            add(ExampleBlocks.RUBY_ORE.get(), b -> createOreDrop(b, ExampleItems.RUBY.get()));
        }

        @Override
        protected Iterable<Block> getKnownBlocks() {
            return ExampleBlocks.BLOCKS.getEntries().stream().map(holder -> (Block) holder.get())::iterator;
        }
    }
}
```

**数据驱动注册表（`DatapackBuiltinEntriesProvider`）**

```java
public class ExampleDatapackEntries extends DatapackBuiltinEntriesProvider {

    public static final RegistrySetBuilder BUILDER = new RegistrySetBuilder()
        .add(Registries.CONFIGURED_FEATURE, bootstrap -> { /* 注册 feature */ })
        .add(Registries.DAMAGE_TYPE, bootstrap -> { /* 注册伤害类型 */ });

    public ExampleDatapackEntries(PackOutput output, CompletableFuture<HolderLookup.Provider> lookup) {
        super(output, lookup, BUILDER, java.util.Set.of(ExampleMod.MOD_ID));
    }
}
```

第三个参数是 `Set<String> modIds`，决定生成的 JSON 放在哪个命名空间目录。

**数据映射（`DataMapProvider`）** 见第 13 章。

### 9.3 输出目录与源集

`runData` 的产物落到 `src/generated/resources`（由 `runs.data` 的 `--output` 决定）。必须把它声明为资源目录，否则打出的 jar 里没有这些文件：

```groovy
sourceSets.main.resources { srcDir 'src/generated/resources' }
```

`--existing src/main/resources` 让生成器能读到手工维护的文件（如手写模型、已有的 lang）。

`neoForge.ideSyncTask`：ModDevGradle 2.0.148 的 `ModDevExtension` 上有 `ideSyncTask(TaskProvider<?>)` 与 `ideSyncTask(Task)` 两个重载（对应 `getIdeSyncTasks()` 返回 `ListProperty<TaskProvider<?>>`）。作用是告诉插件在 IDE 同步（IDEA/Eclipse）之前先跑哪些任务，通常是下载资源与生成 Minecraft 构件，否则 IDEA 里运行 `Main` 会报找不到 `net.neoforged.devlaunch`：

```groovy
neoForge {
    ideSyncTask tasks.named('createMinecraftArtifacts')
    ideSyncTask tasks.named('downloadAssets')
}
```

这两个任务名是插件自己注册的（`./gradlew tasks` 里可见，分组为 `neoForge`）。

排查 `runData` 找不到 provider：
- `GatherDataEvent` 挂在 game 总线 → 永远不触发。
- `generator.addProvider(event.includeClient(), ...)` 但跑的是 `--server` → provider 被跳过。
- 数据生成器崩溃会打印 `Data generator crashed` 与实际异常栈，看栈顶的那个 provider 类。

## 10. 客户端

### 10.1 客户端入口与隔离

```java
import net.neoforged.api.distmarker.Dist;
import net.neoforged.fml.common.EventBusSubscriber;

@EventBusSubscriber(modid = ExampleMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD, value = Dist.CLIENT)
public final class ClientModEvents {
    // 这里的每个方法只在客户端执行
}
```

或者单独一个客户端主类：

```java
@Mod(value = ExampleMod.MOD_ID, dist = Dist.CLIENT)
public final class ExampleModClient {
    public ExampleModClient(IEventBus modBus, ModContainer container) {
        modBus.addListener(this::clientSetup);
    }

    private void clientSetup(FMLClientSetupEvent event) {
        event.enqueueWork(() -> {
            // 菜单界面、按键等（也可以直接用 Register*Event）
        });
    }
}
```

铁律：任何引用 `net.minecraft.client.*` 的类，只能出现在 `Dist.CLIENT` 限定的主类/事件订阅类里，不能在通用代码里 `new` 或静态引用，否则专用服务器启动即 `NoClassDefFoundError`。

### 10.2 菜单界面

```java
import net.neoforged.neoforge.client.event.RegisterMenuScreensEvent;

@SubscribeEvent
public static void registerScreens(RegisterMenuScreensEvent event) {
    event.register(ExampleMenus.RUBY_MENU.get(), RubyScreen::new);
}
```

`RegisterMenuScreensEvent#register(MenuType<M>, ScreenConstructor<M, U>)`，`U` 必须同时是 `Screen` 与 `MenuAccess<M>`。

### 10.3 按键

```java
import com.mojang.blaze3d.platform.InputConstants;
import net.minecraft.client.KeyMapping;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import org.lwjgl.glfw.GLFW;

public static final KeyMapping RUBY_KEY = new KeyMapping(
    "key.examplemod.ruby",                 // 翻译键
    InputConstants.Type.KEYSYM,
    GLFW.GLFW_KEY_R,
    "key.categories.examplemod");          // 分类翻译键

@SubscribeEvent
public static void registerKeys(RegisterKeyMappingsEvent event) {
    event.register(RUBY_KEY);
}
```

按键的“按下”判定要自己在 `ClientTickEvent.Post` 里 `while (RUBY_KEY.consumeClick())` 处理，没有专门事件。

### 10.4 HUD 图层

```java
import net.minecraft.client.gui.LayeredDraw;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

@SubscribeEvent
public static void registerGuiLayers(RegisterGuiLayersEvent event) {
    // 在“玩家血量”之上插入自己的图层
    event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH,
        ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "mana_bar"),
        (guiGraphics, deltaTracker) -> {
            // 直接画：guiGraphics.fill(...)、guiGraphics.drawString(...)
        });
}
```

`RegisterGuiLayersEvent` 的方法：`registerAboveAll`、`registerBelowAll`、`registerAbove(ResourceLocation other, ResourceLocation id, LayeredDraw.Layer)`、`registerBelow(...)`、`replaceLayer(...)`、`wrapLayer(...)`。

`LayeredDraw.Layer` 是函数式接口：`void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker)`。`VanillaGuiLayers` 提供全部原版图层 id：`CROSSHAIR`、`HOTBAR`、`PLAYER_HEALTH`、`ARMOR_LEVEL`、`FOOD_LEVEL`、`EXPERIENCE_BAR`、`EXPERIENCE_LEVEL`、`EFFECTS`、`BOSS_OVERLAY`、`CHAT`、`TAB_LIST`、`TITLE`、`SLEEP_OVERLAY`、`DEBUG_OVERLAY`、`SCOREBOARD_SIDEBAR`、`OVERLAY_MESSAGE`、`SELECTED_ITEM_NAME`、`SPECTATOR_TOOLTIP`、`AIR_LEVEL`、`VEHICLE_HEALTH`、`JUMP_METER`、`CAMERA_OVERLAYS`、`DEMO_OVERLAY`。

### 10.5 客户端扩展（物品/方块）

```java
import net.neoforged.neoforge.client.extensions.common.IClientItemExtensions;
import net.neoforged.neoforge.client.extensions.common.RegisterClientExtensionsEvent;

@SubscribeEvent
public static void registerClientExtensions(RegisterClientExtensionsEvent event) {
    event.registerItem(new IClientItemExtensions() {
        @Override
        public boolean shouldRenderOffHand() {
            return true;
        }
    }, ExampleItems.RUBY.get());

    event.registerBlock(new IClientBlockExtensions() {
        @Override
        public boolean addDestroyEffects(BlockState state, Level level, BlockPos pos, ParticleEngine manager) {
            return true;   // 自己接管破坏粒子
        }
    }, ExampleBlocks.RUBY_BLOCK.get());
}
```

该事件位于 `net.neoforged.neoforge.client.extensions.common`（不是 `client.event`）。还有 `registerMobEffect(IClientMobEffectExtensions, MobEffect...)` 与 `registerFluidType(IClientFluidTypeExtensions, FluidType...)`。

`IClientItemExtensions` 常用方法：`getFont`、`getArmPose`、`getArmTransform`、`shouldRenderOffHand`、`getModels`、`getCustomRenderer`、`getRenderLayers`、`applyCustomSkin`。

### 10.6 实体/方块实体渲染器

```java
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.blockentity.BlockEntityRendererProvider;

@SubscribeEvent
public static void registerRenderers(EntityRenderersEvent.RegisterRenderers event) {
    event.registerEntityRenderer(ExampleEntities.RUBY_GOLEM.get(), RubyGolemRenderer::new);
    event.registerBlockEntityRenderer(ExampleBlockEntities.RUBY_BE.get(), RubyBlockEntityRenderer::new);
}

@SubscribeEvent
public static void registerLayers(EntityRenderersEvent.RegisterLayerDefinitions event) {
    event.registerLayerDefinition(RubyGolemModel.LAYER_LOCATION, RubyGolemModel::createBodyLayer);
}

@SubscribeEvent
public static void registerSkullModels(EntityRenderersEvent.CreateSkullModels event) {
    // 自定义头颅模型（1.21 需要显式注册）
    event.registerSkullModel(/* SkullBlock.Type */, /* SkullModelBase 实例 */);
}
```

`EntityRenderersEvent` 的嵌套类：`RegisterRenderers`、`RegisterLayerDefinitions`、`AddLayers`、`CreateSkullModels`。全部只在客户端触发、走 mod 总线。

### 10.7 粒子

```java
import net.neoforged.neoforge.client.event.RegisterParticleProvidersEvent;

@SubscribeEvent
public static void registerParticles(RegisterParticleProvidersEvent event) {
    event.registerSpecial(ExampleParticles.RUBY_SPARK.get(), new RubySparkParticle.Provider());
    // 或者：event.registerSprite / event.registerSpriteSet
}
```

三个方法：`registerSpecial(ParticleType<T>, ParticleProvider<T>)`、`registerSprite(ParticleType<T>, ParticleProvider.Sprite<T>)`、`registerSpriteSet(ParticleType<T>, ParticleEngine.SpriteParticleRegistration<T>)`。

### 10.8 着色器

```java
import net.neoforged.neoforge.client.event.RegisterShadersEvent;

@SubscribeEvent
public static void registerShaders(RegisterShadersEvent event) throws IOException {
    event.registerShader(
        new ShaderInstance(event.getResourceProvider(),
            ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "ruby_glow"),
            DefaultVertexFormat.POSITION_TEX),
        shader -> RUBY_GLOW_SHADER = shader);   // 回调在着色器编译完成后触发
}
```

`RegisterShadersEvent#registerShader(ShaderInstance, Consumer<ShaderInstance>)`，`getResourceProvider()` 返回 `ResourceProvider`。着色器资源放在 `assets/<modid>/shaders/core/` 下（`.json` + `.vsh`/`.fsh`）。

### 10.9 渲染与界面事件

| 事件 | 总线 | 用途 |
| --- | --- | --- |
| `RenderLevelStageEvent` | game | 在世界渲染的指定阶段插入绘制；`getStage()` 配合 `RenderLevelStageEvent.Stage` 常量过滤 |
| `RenderLevelStageEvent.RegisterStageEvent` | mod | 注册自定义渲染阶段 |
| `RenderGuiEvent.Pre` / `.Post` | game | 整个 HUD 绘制前后；`Pre` 可取消 |
| `RenderGuiLayerEvent.Pre` / `.Post` | game | 单个 HUD 图层前后 |
| `ScreenEvent.Init.Pre/Post` | game | Screen 初始化 |
| `ScreenEvent.Render.Pre/Post` | game | Screen 渲染 |
| `ScreenEvent.MouseButtonPressed.Pre/Post`、`MouseScrolled.Pre/Post`、`KeyPressed.Pre/Post` | game | 输入拦截 |
| `ScreenEvent.Opening` / `.Closing` | game | 界面打开/关闭（`Opening` 可取消） |
| `ClientTickEvent.Pre` / `.Post` | game | 客户端 tick；按键轮询放这里 |
| `RenderHandEvent`、`RenderPlayerEvent`、`RenderLivingEvent`、`RenderNameTagEvent`、`RenderTooltipEvent` | game | 具体渲染替换 |
| `RecipesUpdatedEvent` | game | 客户端配方同步完成 |

`RenderLevelStageEvent` 的 `Stage` 常量包括：`AFTER_SKY`、`AFTER_SOLID_BLOCKS`、`AFTER_CUTOUT_MIPPED_BLOCKS_BLOCKS`、`AFTER_CUTOUT_BLOCKS`、`AFTER_ENTITIES`、`AFTER_BLOCK_ENTITIES`、`AFTER_TRANSLUCENT_BLOCKS`、`AFTER_PARTICLES`、`AFTER_WEATHER`、`AFTER_LEVEL`。渲染时用 `getPoseStack()`、`getCamera()`、`getProjectionMatrix()`、`getPartialTick()`。

```java
@SubscribeEvent
public static void onRenderLevel(RenderLevelStageEvent event) {
    if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_ENTITIES) {
        return;
    }
    PoseStack pose = event.getPoseStack();
    pose.pushPose();
    // 在这里画线框/自定义几何
    pose.popPose();
}
```

### 10.10 客户端 tick

```java
import net.neoforged.neoforge.client.event.ClientTickEvent;

@SubscribeEvent
public static void onClientTick(ClientTickEvent.Post event) {
    while (ClientModEvents.RUBY_KEY.consumeClick()) {
        // 处理按键
    }
}
```

`ClientTickEvent` 只有 `Pre` / `Post` 两个嵌套类，都是 game 总线事件。

### 10.11 `src/client/java` 源集

Minimal（推荐）方案：把 `src/client/java` 并入 `main` 源集（见 2.3），用注解隔离。这样：
- `runClient` 能加载客户端类。
- `runServer` 不会实例化它们。
- 代价：客户端类会被打进同一个 jar（本来也是同一个 jar）。

若要真正分离编译，需要在 `build.gradle` 里声明独立 sourceSet 并在 `neoForge.mods` 中同时加入；不同 ModDevGradle 小版本的字段差异较大，务必对照 2.0.148 的 MDK 模板。

## 11. 数据附件与 Capability

### 11.1 概念划分

| 需求 | 用什么 |
| --- | --- |
| 给实体/方块实体/世界/区块加自定义数据 | `AttachmentType` |
| 给物品加自定义数据 | `DataComponentType` |
| 给方块实体/物品/实体提供“能力”（物品栏、流体、能量） | `RegisterCapabilitiesEvent` + `Capabilities.*` |
| 查询某位置/某物品的能力 | `level.getCapability(...)` / `stack.getCapability(...)` |

`IAttachmentHolder` 的实际实现类只有 `Level`、`Entity`、`ChunkAccess`、`BlockEntity`（`ChunkAccess` 通过内部 `AttachmentHolder.AsField` 委托）。

### 11.2 Attachment 完整流程

注册（见 5.8）：

```java
public static final DeferredRegister<AttachmentType<?>> ATTACHMENT_TYPES =
    DeferredRegister.create(NeoForgeRegistries.Keys.ATTACHMENT_TYPES, ExampleMod.MOD_ID);

public static final DeferredHolder<AttachmentType<?>, AttachmentType<RubyData>> RUBY_DATA =
    ATTACHMENT_TYPES.register("ruby_data", () -> AttachmentType.builder(RubyData::new)
        .serialize(RubyData.CODEC)     // Codec<RubyData>
        .copyOnDeath()
        .build());
```

读写：

```java
// BlockEntity 内
RubyData data = this.getData(ExampleAttachments.RUBY_DATA.get());
this.setData(ExampleAttachments.RUBY_DATA.get(), data.withAmount(5));
this.setChanged();

// Entity 内
RubyData d = entity.getData(ExampleAttachments.RUBY_DATA.get());
```

要点：
- `getData` 在不存在时**自动创建**默认值（`builder(Supplier)` 传入的供应商），所以永远不会返回 null。
- `getExistingDataOrNull` 不会创建，返回 `@Nullable`，适合“只在有数据时做某事”。
- `setData` 返回旧值（`@Nullable`）；`removeData` 也返回旧值。
- 变更后要自己调用 `setChanged()`（方块实体）或让实体同步，否则不会存盘。
- 存档键是 `neoforge:attachments`，不要和别的模组手动写这个键。
- 同步：`sync(...)` 之后服务端改数据会自动下发；`sync` 只在服务端生效，客户端不需要重复注册逻辑（但类型必须两端都注册）。

### 11.3 Capability 注册

```java
import net.neoforged.neoforge.capabilities.Capabilities;
import net.neoforged.neoforge.capabilities.RegisterCapabilitiesEvent;
import net.neoforged.neoforge.items.IItemHandler;
import net.neoforged.neoforge.items.ItemStackHandler;
import net.neoforged.neoforge.energy.IEnergyStorage;
import net.neoforged.neoforge.energy.EnergyStorage;
import net.neoforged.neoforge.fluids.capability.IFluidHandler;
import net.neoforged.neoforge.fluids.capability.templates.FluidTank;

@SubscribeEvent
public static void registerCapabilities(RegisterCapabilitiesEvent event) {
    // ---- 方块实体：物品栏（按方向区分）----
    event.registerBlockEntity(
        Capabilities.ItemHandler.BLOCK,
        ExampleBlockEntities.RUBY_BE.get(),
        (be, side) -> be.inventory);        // side 为 null 表示“无方向上下文”

    // ---- 方块：没有方块实体也能提供能力 ----
    event.registerBlock(
        Capabilities.ItemHandler.BLOCK,
        (level, pos, state, blockEntity, side) -> {
            if (blockEntity instanceof RubyBlockEntity be) {
                return be.inventory;
            }
            return null;
        },
        ExampleBlocks.RUBY_BLOCK.get());

    // ---- 方块实体：能量 ----
    event.registerBlockEntity(
        Capabilities.EnergyStorage.BLOCK,
        ExampleBlockEntities.RUBY_BE.get(),
        (be, side) -> be.energyStorage);

    // ---- 方块实体：流体 ----
    event.registerBlockEntity(
        Capabilities.FluidHandler.BLOCK,
        ExampleBlockEntities.RUBY_BE.get(),
        (be, side) -> be.tank);

    // ---- 物品：给 ItemStack 提供物品栏 ----
    event.registerItem(
        Capabilities.ItemHandler.ITEM,
        (stack, ctx) -> new ItemStackHandler(9),
        ExampleItems.RUBY_WAND.get());

    // ---- 实体：给实体提供物品栏 ----
    event.registerEntity(
        Capabilities.ItemHandler.ENTITY,
        ExampleEntities.RUBY_GOLEM.get(),
        (entity, ctx) -> entity.inventory);
}
```

方块实体里的字段实现：

```java
public class RubyBlockEntity extends BlockEntity {

    public final ItemStackHandler inventory = new ItemStackHandler(9) {
        @Override
        protected void onContentsChanged(int slot) {
            setChanged();
        }
    };

    public final EnergyStorage energyStorage = new EnergyStorage(1000, 100, 100);
    public final FluidTank tank = new FluidTank(1000);
}
```

核对过的构造器：`ItemStackHandler(int size)`、`EnergyStorage(int capacity, int maxReceive, int maxExtract)`、`FluidTank(int capacity)`。

`Capabilities` 的常量（`net.neoforged.neoforge.capabilities.Capabilities`）：

| 内部类 | 常量 | 泛型 |
| --- | --- | --- |
| `ItemHandler` | `BLOCK` / `ENTITY` / `ENTITY_AUTOMATION` / `ITEM` | `IItemHandler` |
| `FluidHandler` | `BLOCK` / `ENTITY` / `ITEM` | `IFluidHandler` / `IFluidHandlerItem` |
| `EnergyStorage` | `BLOCK` / `ENTITY` / `ITEM` | `IEnergyStorage` |

`RegisterCapabilitiesEvent` 的方法：`registerBlock`、`registerBlockEntity`、`registerEntity`、`registerItem`、`isBlockRegistered`、`isEntityRegistered`、`isItemRegistered`、`setProxyable`、`setNonProxyable`。

### 11.4 获取 Capability

```java
// 方块能力：上下文是 Direction（可为 null）
IItemHandler handler = level.getCapability(Capabilities.ItemHandler.BLOCK, pos, null);
IItemHandler upHandler = level.getCapability(Capabilities.ItemHandler.BLOCK, pos, Direction.UP);

// 已知方块状态与方块实体时，避免重复查询
IItemHandler fast = level.getCapability(Capabilities.ItemHandler.BLOCK, pos, state, blockEntity, null);

// 无上下文（Void）的能力
IEnergyStorage energy = level.getCapability(Capabilities.EnergyStorage.BLOCK, pos, null);

// 物品能力：上下文是 Void
IItemHandler stackHandler = stack.getCapability(Capabilities.ItemHandler.ITEM);

// 实体能力
IItemHandler golemInv = golem.getCapability(Capabilities.ItemHandler.ENTITY, null);
```

`IItemHandler` 的方法：`getSlots()`、`getStackInSlot(int)`、`insertItem(int, ItemStack, boolean simulate)`、`extractItem(int, int, boolean simulate)`、`getSlotLimit(int)`、`isItemValid(int, ItemStack)`。

缓存能力查询（性能敏感路径）：

```java
import net.neoforged.neoforge.capabilities.BlockCapabilityCache;

// 每个方块实体持有一个缓存，避免每 tick 重新查询
BlockCapabilityCache<IItemHandler, Direction> cache =
    BlockCapabilityCache.create(Capabilities.ItemHandler.BLOCK, level, pos, Direction.UP,
        () -> true,                // 是否仍有效
        handler -> { /* 能力变化回调 */ });
```

注意：
- `registerBlockEntity` 的 provider 在**每次查询**时调用，不要在里面做重活；返回字段即可。
- 若能力可用性会变化（例如机器关机），必须调用 `level.invalidateCapabilities(pos)` 通知缓存。
- 只有 `BLOCK`/`ENTITY` 才带方向上下文；`ITEM` 的上下文是 `Void`，不能传方向。

## 12. 资源与数据路径

### 12.1 目录约定

```text
src/main/resources/
├── META-INF/
│   ├── neoforge.mods.toml
│   └── accesstransformer.cfg
├── examplemod.mixins.json
├── examplemod.png                       # logoFile 指向这里
├── assets/examplemod/
│   ├── lang/en_us.json
│   ├── lang/zh_cn.json
│   ├── blockstates/ruby_block.json
│   ├── models/block/ruby_block.json
│   ├── models/item/ruby.json
│   ├── textures/block/ruby_block.png
│   ├── textures/item/ruby.png
│   ├── sounds.json
│   └── shaders/core/ruby_glow.json
└── data/examplemod/
    ├── recipe/ruby_block.json            # 1.21.1 是单数
    ├── advancement/ruby.json
    ├── loot_table/blocks/ruby_block.json
    ├── tags/block/ruby_ores.json
    ├── tags/item/ruby.json
    ├── damage_type/ruby_burn.json
    └── neoforge/data_maps/item/ruby.json  # 数据映射
```

1.21.1 的**单数目录**（重要，用复数会静默失效）：

| 正确 | 错误（1.20 及以前） |
| --- | --- |
| `data/<id>/recipe/` | `recipes/` |
| `data/<id>/loot_table/` | `loot_tables/` |
| `data/<id>/advancement/` | `advancements/` |
| `data/<id>/tags/block/` | `tags/blocks/` |
| `data/<id>/tags/item/` | `tags/items/` |
| `data/<id>/damage_type/` | `damage_types/` |
| `data/<id>/enchantment/` | `enchantments/` |

对应注册表键（`Registries` 里能查到同样的名字）：`Registries.RECIPE` → `recipe`，`Registries.LOOT_TABLE` → `loot_table`，`Registries.ADVANCEMENT` → `advancement`。

### 12.2 `pack.mcmeta`

模组**不需要**提供 `pack.mcmeta`。NeoForge 在加载时会给每个模组资源生成 `pack.mcmeta` 等价物（`pack_format` 由加载器注入）。只有以下情况才需要自己写：
- 你在 `data/` 下要放自定义 datapack 覆盖层，并声明 `pack_format` 与 `supported_formats`；
- 你需要 `filter` 段来屏蔽其他模组的文件。

自写时最小内容：

```json
{
  "pack": {
    "description": "Example Mod Resources",
    "pack_format": 34
  }
}
```

`pack_format` 与 1.21.1 对应的是 34；不确定就不要写，交给加载器。

### 12.3 翻译键

| 内容 | 键格式 |
| --- | --- |
| 物品 | `item.examplemod.ruby` |
| 方块 | `block.examplemod.ruby_block` |
| 创造标签页 | `itemGroup.examplemod.ruby` |
| 容器界面 | `container.examplemod.ruby` |
| 实体 | `entity.examplemod.ruby_golem` |
| 状态效果 | `effect.examplemod.ruby_shield` |
| 按键 | `key.examplemod.ruby` / `key.categories.examplemod` |
| 配置项 | 由 `translation(...)` 指定，如 `examplemod.config.rubyEnabled` |

`lang` 文件必须是合法 JSON，且**不能**有尾逗号；`zh_cn.json` 必须用 UTF-8（无 BOM）。

### 12.4 `displayTest` 与资源包的交互

- 纯客户端模组（如小地图、HUD）：`displayTest = "IGNORE_SERVER_VERSION"`，否则进不了没装该模组的服务器。
- 双端必需模组：保持默认 `MATCH_VERSION`。
- 只影响“客户端能否连接”，不影响服务端加载。

## 13. 常用工具类

| 类 / 方法 | 包 | 用途 |
| --- | --- | --- |
| `ModList.get()` | `net.neoforged.fml` | `isLoaded(String)`、`getModContainerById(String)`、`getMods()`、`size()` |
| `ModLoader` | `net.neoforged.fml` | `getLoadingIssues()`、`hasErrors()`；一般只在调试用 |
| `NeoForge.EVENT_BUS` | `net.neoforged.neoforge.common` | game 总线单例 |
| `NeoForgeMod` | `net.neoforged.neoforge.common` | 内置属性（`SWIM_SPEED`、`NAMETAG_DISTANCE`、`CREATIVE_FLIGHT`）、内置 biome/structure modifier 类型 |
| `SimpleTier` | `net.neoforged.neoforge.common` | 快速构造 `Tier`（见 5.3） |
| `ItemAbilities` | `net.neoforged.neoforge.common` | 工具行为常量集合 |
| `NeoForgeRegistries.Keys` | `net.neoforged.neoforge.registries` | 自定义注册表键：`ATTACHMENT_TYPES`、`FLUID_TYPES`、`ENTITY_DATA_SERIALIZERS`、`HOLDER_SET_TYPES`、`INGREDIENT_TYPES`、`FLUID_INGREDIENT_TYPES`、`CONDITION_CODECS`、`BIOME_MODIFIERS`、`STRUCTURE_MODIFIERS`、`GLOBAL_LOOT_MODIFIER_SERIALIZERS`、`BIOME_MODIFIER_SERIALIZERS`、`STRUCTURE_MODIFIER_SERIALIZERS` |
| `Tags` | `net.neoforged.neoforge.common` | NeoForge 约定的标签，按注册表分类：`Tags.Blocks`、`Tags.Items`、`Tags.Entities`、`Tags.Fluids`、`Tags.Enchantments`、`Tags.Biomes`、`Tags.Structures`、`Tags.DamageTypes` 等 |
| `CreativeModeTabRegistry` | `net.neoforged.neoforge.common` | `getSortedCreativeModeTabs()`、`getTab(ResourceLocation)`、`getName(CreativeModeTab)` |
| `ModConfigSpec` | `net.neoforged.neoforge.common` | 配置 DSL |
| `TriState` | `net.neoforged.neoforge.common.util` | 交互事件三态 |
| `ItemStackHandler` / `ItemHandlerHelper` | `net.neoforged.neoforge.items` | 物品栏实现与工具（`insertItem`、`extractItem`） |
| `EnergyStorage` / `IEnergyStorage` | `net.neoforged.neoforge.energy` | 能量 |
| `FluidTank` / `FluidUtil` | `net.neoforged.neoforge.fluids.capability.templates` / `net.neoforged.neoforge.fluids` | 流体 |

### 13.1 `DataMapType`（数据驱动映射）

数据映射用 JSON 给**已存在**的注册表条目附加数据，无需 Java 代码逐个注册。

```java
import net.neoforged.neoforge.registries.datamaps.DataMapType;
import net.neoforged.neoforge.registries.datamaps.RegisterDataMapTypesEvent;
import com.mojang.serialization.Codec;

public final class ExampleDataMaps {

    // 每个物品的“燃料值”，注册表是 ITEM
    public static final DataMapType<Item, Integer> RUBY_FUEL = DataMapType.builder(
            ResourceLocation.fromNamespaceAndPath(ExampleMod.MOD_ID, "ruby_fuel"),
            Registries.ITEM,
            Codec.INT)
        .synced(Codec.INT, false)      // 第二个参数：是否强制同步
        .build();

    @SubscribeEvent
    public static void registerDataMaps(RegisterDataMapTypesEvent event) {
        event.register(RUBY_FUEL);
    }
}
```

JSON 放在 `data/<modid>/neoforge/data_maps/item/ruby_fuel.json`：

```json
{
  "values": {
    "examplemod:ruby": 200,
    "minecraft:coal": 100
  }
}
```

读取：

```java
Integer fuel = stack.getItemHolder().getData(ExampleDataMaps.RUBY_FUEL);
// DeferredHolder 也实现了 getData
```

`DataMapType.Builder` 的方法：`synced(Codec<T> networkCodec, boolean mandatory)`、`build()`；`DataMapType` 的访问器：`registryKey()`、`id()`、`codec()`、`networkCodec()`、`mandatorySync()`。

服务端数据映射在重载后可能有变化，监听 `DataMapsUpdatedEvent` 可刷新缓存。

基于数据映射生成 JSON 的 provider：

```java
public class ExampleDataMapsProvider extends DataMapProvider {

    public ExampleDataMapsProvider(PackOutput output, CompletableFuture<HolderLookup.Provider> lookup) {
        super(output, lookup);
    }

    @Override
    protected void gather(HolderLookup.Provider provider) {
        builder(ExampleDataMaps.RUBY_FUEL)
            .add(ExampleItems.RUBY.get().builtInRegistryHolder(), 200, false);
    }
}
```

## 14. 坑与排查表

| 症状 | 原因 | 修复 |
| --- | --- | --- |
| 注册的东西在游戏里完全看不到 | `DeferredRegister` 创建了但没 `.register(modBus)` | 在 `@Mod` 构造函数里挂到 mod 总线 |
| 同上，且没有任何报错 | 事件监听器挂错总线（mod 事件挂到了 `NeoForge.EVENT_BUS`） | 看事件是否 `implements IModBusEvent`，是则改用 `bus = Bus.MOD` |
| `NullPointerException` 在 `DeferredXxx.get()` | 在注册完成前（静态初始化或构造函数里）调用了 `get()` | 只在 `RegisterEvent` 之后、或运行期调用；需要早期引用就用 `DeferredHolder` 本身 |
| `IllegalStateException: Registry is already frozen` | 在注册表冻结后（`FMLCommonSetupEvent` 之后）再注册 | 全部注册放构造函数 + `DeferredRegister` |
| `ConcurrentModificationException` 在 setup 阶段 | 在 `FMLCommonSetupEvent` 里直接改原版注册表，没 `enqueueWork` | `event.enqueueWork(() -> {...})` |
| 服务端崩 `NoClassDefFoundError: net/minecraft/client/...` | 通用代码静态引用客户端类，或 `ConfigurationScreen::new` 没按 `Dist` 隔离 | 用 `Dist.CLIENT` 限定主类/订阅类，或 `if (dist == Dist.CLIENT)` |
| 客户端收不到包 / `Unknown payload id` | `RegisterPayloadHandlersEvent` 挂 game 总线；或 `optional()` 用错；或两端版本不同 | 改挂 mod 总线，去掉 `optional()`，统一 `registrar("1")` 版本号 |
| `ClassCastException` 涉及 `RegistryFriendlyByteBuf` | `configuration*` 用了 play 阶段的 codec，或反之 | configuration → `FriendlyByteBuf`，play → `RegistryFriendlyByteBuf` |
| 处理器里访问世界崩 / 数据竞争 | `executesOn(HandlerThread.NETWORK)` 后没 `enqueueWork` | 用默认 `MAIN`，或显式 `context.enqueueWork(...)` |
| 配置项读出来是默认值 / 抛“not loaded” | 在 `ModConfigEvent.Loading` 之前访问 `get()` | 用 `Loading`/`Reloading` 事件缓存，热路径读缓存字段 |
| 配置改了不生效 | 改的是 `SERVER` 类型但文件在世界存档里；或只改了内存没写盘 | `SERVER` 配置在 `<world>/serverconfig/`；写盘用 `ConfigValue#set` 后由框架在关服时保存 |
| `runData` 报 “No provider found” / 不产出 | `GatherDataEvent` 挂 game 总线；或 `includeClient/includeServer` 与运行参数不匹配 | 挂 mod 总线；确认 `runs.data` 的 `--client/--server` 参数 |
| `runData` 产出不在 jar 里 | 没把 `src/generated/resources` 加进 resources | `sourceSets.main.resources { srcDir 'src/generated/resources' }` |
| 启动报 “missing neoforge.mods.toml” | 文件放错目录或仍叫 `mods.toml` | 放 `src/main/resources/META-INF/neoforge.mods.toml` |
| 启动报依赖不满足 | `[[dependencies]]` 缺 `versionRange`，或写成裸版本号 | 补 `versionRange = "[21.1.0,)"` 这类范围 |
| 客户端连不上“缺少模组” | `displayTest` 设成默认且是纯客户端模组 | `displayTest = "IGNORE_SERVER_VERSION"` |
| 数据包 JSON 不生效 | 用了复数目录（`recipes/`、`loot_tables/`） | 1.21.1 用单数（`recipe/`、`loot_table/`） |
| `mixin` 不生效 | `neoforge.mods.toml` 缺 `[[mixins]]`，或 json 里包名/类名错 | 补齐声明；`package` 与 `mixins` 条目要能拼出真实类名 |
| 参数名全是 `p_123456_` | 没开 Parchment | 配 `parchment { }` 并重新生成 |
| `compileJava` OOM / 卡死 | Gradle 堆太小 | `org.gradle.jvmargs=-Xmx3G`（或 4G），必要时关 `org.gradle.parallel` |
| IDE 运行报 `net.neoforged.devlaunch` 找不到 | IDE 没同步 Gradle 运行配置 | 重新 import Gradle 项目，或运行 `./gradlew ideSync` |
| 用了 `net.minecraftforge.*` 导入 | 1.20.1 代码残留 | 全部替换为 `net.neoforged.*`；`ResourceLocation` 构造器已私有化，改 `fromNamespaceAndPath` / `parse` |

### 14.1 `ResourceLocation` 在 1.21 的写法

```java
// 旧（1.20 及以前，现在私有）
// new ResourceLocation("examplemod", "ruby")

ResourceLocation id = ResourceLocation.fromNamespaceAndPath("examplemod", "ruby");
ResourceLocation parsed = ResourceLocation.parse("examplemod:ruby");
ResourceLocation vanilla = ResourceLocation.withDefaultNamespace("ruby"); // -> minecraft:ruby
```

### 14.2 注册顺序与类加载

`DeferredRegister` 的注册动作发生在 `RegisterEvent` 期间，而不是 `new` 的那一刻。因此：
- 在 `ExampleItems` 里引用 `ExampleBlocks.RUBY_BLOCK` 只是引用 `DeferredBlock` 对象，不会触发 `get()`，安全。
- 但若在 `ExampleItems` 的静态块里写 `ExampleBlocks.RUBY_BLOCK.get()`，就会在类初始化阶段拿到未绑定 holder → `NullPointerException`。
- `BlockEntityType.Builder.of(RubyBlockEntity::new, ExampleBlocks.RUBY_BLOCK.get())` 写在 `Supplier` 里（延迟到注册时执行），安全；写在静态字段初始化里则会炸。

### 14.3 调试建议

| 手段 | 用法 |
| --- | --- |
| `-Dforge.logging.markers=REGISTRIES` | 打印注册表填充细节，定位“没注册上” |
| `-Dneoforge.enabledGameTestNamespaces=<modid>` | 启用 GameTest |
| `ModList.get().isLoaded("jei")` | 软依赖判断 |
| `./gradlew runData --stacktrace` | 数据生成崩溃时看完整栈 |
| `build/` 下 `compileJava` 报错先看第一个 | 后续错误多是连锁 |

## 15. 本文核对范围

已对照 NeoForge 21.1.264 源码（`neoforge-21.1.264-sources.jar`）与 Minecraft 1.21.1 + NeoForge 补丁源码逐条核对的关键类型（方法签名以源码为准）：

`net.neoforged.neoforge.registries.DeferredRegister`（含内部类 `Blocks` / `Items` / `DataComponents`）、`DeferredHolder`、`net.neoforged.neoforge.common.ModConfigSpec`（含 `Builder`、`ConfigValue`、`IntValue`、`BooleanValue`、`EnumValue`）、`net.neoforged.neoforge.network.registration.PayloadRegistrar`、`net.neoforged.neoforge.network.registration.HandlerThread`、`net.neoforged.neoforge.network.handling.IPayloadContext`、`net.neoforged.neoforge.network.PacketDistributor`、`net.neoforged.neoforge.attachment.AttachmentType`、`AttachmentSyncHandler`、`AttachmentHolder`、`net.neoforged.neoforge.capabilities.Capabilities`、`RegisterCapabilitiesEvent`、`net.neoforged.neoforge.data.event.GatherDataEvent`、`net.neoforged.neoforge.common.data.DatapackBuiltinEntriesProvider`、`LanguageProvider`、`BlockTagsProvider`、`net.neoforged.neoforge.client.event.RegisterGuiLayersEvent`、`EntityRenderersEvent`、`RegisterParticleProvidersEvent`、`RegisterMenuScreensEvent`、`RegisterKeyMappingsEvent`、`RegisterClientExtensionsEvent`、`RegisterShadersEvent`、`RenderLevelStageEvent`、`ScreenEvent`、`RenderGuiEvent`、`ClientTickEvent`、`net.neoforged.neoforge.registries.datamaps.DataMapType`、`net.neoforged.neoforge.common.SimpleTier`、`ItemAbilities`、`NeoForgeRegistries`，以及 `net.neoforged.bus.api` 的 `Event`、`ICancellableEvent`、`EventPriority`、`IEventBus`、`net.neoforged.fml.common.Mod`、`EventBusSubscriber`、`net.neoforged.fml.config.ModConfig.Type`、`net.neoforged.fml.ModContainer`、`net.neoforged.fml.ModList`、`net.neoforged.fml.event.lifecycle.ParallelDispatchEvent`、`net.neoforged.fml.event.config.ModConfigEvent`。

游戏侧核对：`BlockEntityType.Builder.of(...)#build(Type<?>)`、`MenuType(MenuSupplier, FeatureFlagSet)`、`CreativeModeTab.builder()` 及 `Builder` 方法、`Item.Properties`、`FoodProperties.Builder`、`SwordItem`、`ArmorItem`、`ArmorMaterial`（record）、`EntityType.Builder`、`MobEffect`（构造器 protected）、`DataComponentType.Builder`、`BlockBehaviour.Properties.of()`、`DataGenerator#addProvider`、`RecipeProvider#buildRecipes(RecipeOutput)`、`LootTableProvider` 构造器与 `SubProviderEntry`、`BlockLootSubProvider`、`ItemTagsProvider` 的 NeoForge 重载、`LayeredDraw.Layer`、`ContainerData`、`BlockEntityTicker`。

未纳入本文的内容（避免臆测）：`defineMap`（`ModConfigSpec` 中不存在）、`EnUsLanguageProvider`（NeoForge 无此类，语言文件用 `LanguageProvider`）、`src/client/java` 独立源集在 ModDevGradle 2.0.148 下的完整 DSL（建议并入 `main` 源集）。

另外核对过 ModDevGradle 2.0.148 自身的 API（`moddev-gradle-2.0.148.jar`）：`ModDevExtension` 的 `version`、`parchment(Action<Parchment>)`、`runs(Action<...>)`、`mods(Action<...>)`、`ideSyncTask(TaskProvider<?>)` / `ideSyncTask(Task)`、`accessTransformers`、`interfaceInjectionData`、`validateAccessTransformers`、`addModdingDependenciesTo(SourceSet)`，以及插件注册的任务 `createMinecraftArtifacts`、`downloadAssets`。
