# Fabric 模组 API 参考（Minecraft 1.21.1）

面向 Minecraft 1.21.1 + Fabric Loader + Fabric API + Fabric Loom 的模组开发参考。默认使用 **Yarn 映射**，涉及命名差异处会标注 Mojmap 名字。所有类名/方法名以 Fabric API `1.21.1` 分支源码为准；与本文件写出的签名不一致时，先查 Javadoc 再改代码。

> 重要前提：1.21.1 的网络类名有两套叫法，取决于映射而不是版本。Yarn（本项目默认）叫 `CustomPayload` / `CustomPayload.Id` / `PacketCodec`，Mojmap（NeoForge、官方新文档）叫 `CustomPacketPayload` / `CustomPacketPayload.Type` / `StreamCodec`；`MinecraftClient#level`（Mojmap 是 `Minecraft#level`）同理。网上大量教程按 Mojmap 写，**直接抄进 Yarn 工程会编译失败**。本文件全部按 Yarn 1.21.1 写，必要时附 Mojmap 名。

---

## 1. 版本矩阵与 gradle.properties

### 1.1 版本矩阵

| 组件 | 1.21.1 基线版本 | 说明 |
| --- | --- | --- |
| Minecraft | `1.21.1` | 1.21 的补丁版，协议 1.21.1 |
| Fabric Loader | `0.16.x` | 1.21.1 发布期基线；官方模板当前已用 `0.20.1`，都能加载 1.21.1 |
| Fabric API | `0.102.x+1.21.1` | 1.21.1 首发基线；该分支仍在更新（官方模板当前用 `0.116.x+1.21.1`） |
| Fabric Loom | `1.7` | 插件 id `fabric-loom`；更新版 Loom 使用 `net.fabricmc.fabric-loom-remap` |
| Java | `21` | 必须 21，`options.release = 21` |
| Yarn | `1.21.1+build.3` | `mappings "net.fabricmc:yarn:${yarn_mappings}:v2"` |
| Mojmap（可选） | 不写版本 | `mappings loom.officialMojangMappings()` |
| 资源包 `pack_format` | `34` | 1.21/1.21.1 资源包格式 |
| 数据包 `pack_format` | `48` | 1.21/1.21.1 数据包格式（1.21.2 变为 42/57） |

版本兼容性判断：`fabric.mod.json` 的 `depends.minecraft` 写 `~1.21.1`（允许 1.21.1 的补丁级），`fabric-api` 写 `*` 或 `>=0.102.0`。

### 1.2 gradle.properties 全字段

```properties
# Gradle 自身配置
org.gradle.jvmargs=-Xmx2G
org.gradle.parallel=true
org.gradle.configuration-cache=true

# Fabric 版本属性（改版本只改这里）
minecraft_version=1.21.1
yarn_mappings=1.21.1+build.3
loader_version=0.16.9
fabric_version=0.102.1+1.21.1
loom_version=1.7-SNAPSHOT

# 模组自身属性
mod_version=1.0.0
maven_group=com.example
archives_base_name=examplemod
```

字段用途：

| 字段 | 用途 |
| --- | --- |
| `minecraft_version` | `minecraft "com.mojang:minecraft:${...}"` 的版本号 |
| `yarn_mappings` | Yarn 映射版本，拼成 `net.fabricmc:yarn:<ver>:v2` |
| `loader_version` | Fabric Loader 依赖版本 |
| `fabric_version` | Fabric API 版本，形如 `<ver>+<mcver>`，加号前是 API 版本、加号后是适配的游戏版本 |
| `loom_version` | Loom 插件版本，在 `plugins {}` 里用作插件版本 |
| `mod_version` | `project.version`，会被 `processResources` 展开进 `fabric.mod.json` |
| `maven_group` | `project.group`，发布 Maven 时用 |
| `archives_base_name` | 产物 jar 名（`base { archivesName = ... }`） |

### 1.3 Yarn vs Mojmap 命名对照（只列高频）

| 概念 | Yarn（1.21.1） | Mojmap |
| --- | --- | --- |
| 标识符 | `Identifier`，`Identifier.of(...)` | `ResourceLocation` |
| 注册表 | `net.minecraft.registry.Registries` | `net.minecraft.core.registries.BuiltInRegistries` |
| 注册表键 | `RegistryKey` / `RegistryKeys` | `ResourceKey` / `Registries` 键集 |
| 玩家 | `PlayerEntity` / `ServerPlayerEntity` / `ClientPlayerEntity` | `Player` / `ServerPlayer` / `LocalPlayer` |
| 世界 | `World` / `ServerWorld` / `ClientWorld` | `Level` / `ServerLevel` / `ClientLevel` |
| 客户端 | `MinecraftClient` | `Minecraft` |
| 交互结果 | `ActionResult` | `InteractionResult` |
| 方块设置 | `AbstractBlock.Settings` | `BlockBehaviour.Properties` |
| 屏幕处理器 | `ScreenHandler` / `Registries.SCREEN_HANDLER` | `AbstractContainerMenu` / `Registries.MENU` |
| 状态效果 | `StatusEffect` / `Registries.STATUS_EFFECT` | `MobEffect` / `Registries.MOB_EFFECT` |
| 音效 | `SoundEvent` / `Registries.SOUND_EVENT` | 同名 |

规则：一个工程只能选一套。混用会出现「编译通过、Mixin 目标找不到、`Registry.register` 泛型不匹配」这类问题。

---

## 2. build.gradle 与 settings.gradle

### 2.1 settings.gradle

```gradle
pluginManagement {
    repositories {
        maven { name = 'Fabric'; url = 'https://maven.fabricmc.net/' }
        mavenCentral()
        gradlePluginPortal()
    }
}

rootProject.name = 'examplemod'
```

`pluginManagement` 必须在 `settings.gradle` 里声明 Fabric Maven，否则 `fabric-loom` 插件解析不到（`mavenCentral` 没有 Loom）。

### 2.2 build.gradle 完整示例（Yarn + 拆分 sourceSet）

```gradle
plugins {
    id 'fabric-loom' version "${loom_version}"
    id 'maven-publish'
}

version = project.mod_version
group = project.maven_group

base {
    archivesName = project.archives_base_name
}

repositories {
    // Loom 会自动加入 Minecraft / Fabric 仓库；这里只放第三方模组仓库
    maven { url = 'https://maven.terraformersmc.com/releases/' }   // 例：Mod Menu
}

loom {
    // 拆分 main（两端共用）/ client（仅客户端）两套源码集
    splitEnvironmentSourceSets()

    mods {
        "examplemod" {
            sourceSet sourceSets.main
            sourceSet sourceSets.client
        }
    }

    // 需要访问转换器时打开
    // accessWidenerPath = file("src/main/resources/examplemod.accesswidener")
}

dependencies {
    minecraft "com.mojang:minecraft:${project.minecraft_version}"
    mappings "net.fabricmc:yarn:${project.yarn_mappings}:v2"
    // 想用 Mojmap 就换成下面这行（二选一，不能同时写）
    // mappings loom.officialMojangMappings()

    modImplementation "net.fabricmc:fabric-loader:${project.loader_version}"
    modImplementation "net.fabricmc.fabric-api:fabric-api:${project.fabric_version}"
}

processResources {
    inputs.property "version", project.version
    filesMatching("fabric.mod.json") {
        expand "version": project.version
    }
}

tasks.withType(JavaCompile).configureEach {
    options.release = 21
    options.encoding = 'UTF-8'
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
    withSourcesJar()
}

jar {
    from("LICENSE") {
        rename { "${it}_${project.archives_base_name}" }
    }
}
```

要点：

- `mappings` 两种写法互斥；Yarn 需要 `:v2` 后缀（映射格式 v2）。
- `splitEnvironmentSourceSets()` 之后，客户端代码写进 `src/client/java`、客户端资源写进 `src/client/resources`；`loom { mods { ... } }` 里的 `sourceSet sourceSets.client` 是必需的，否则 Loom 不知道客户端源码属于哪个 mod，Mixin/AT 处理和 run config 都会出错。
- `options.release = 21` 与 toolchain 同时写是安全的：toolchain 决定用哪个 JDK，`release` 决定字节码目标。
- 不要把 Fabric API 写成 `implementation`，必须 `modImplementation`（Loom 需要做 remap）。

### 2.3 JiJ（Jar-in-Jar，把依赖打进自己的 mod）

`include` 是 Loom 提供的配置，被 include 的 jar 会被塞进 `META-INF/jars/`，并在 `fabric.mod.json` 里自动生成嵌套依赖声明（Loom 在构建时改写）。

```gradle
dependencies {
    modImplementation "com.example:ruby-lib:1.2.0"
    include "com.example:ruby-lib:1.2.0"
}
```

注意事项：

1. `include` 只嵌入**这一层** artifact。它的传递依赖（POM 里 `runtime` 的库）不会自动带上，要么把传递依赖逐一声明并 `include`，要么自己打 fat jar。
2. 需要重定位（relocate）第三方库时用 Gradle Shadow 插件产出 `shadowJar`，再 `include(project(path: ':sub', configuration: 'shadow'))`；单纯 `include` 不做重定位，命名冲突需自己规避。
3. 被 `include` 的模组/库必须是**已 remap** 的产物（对 Fabric 模组用 `modImplementation`），否则运行期映射不匹配。
4. 不要 include `fabric-api` 或 `fabric-loader`：它们是运行环境的一部分，写进 `fabric.mod.json` 的 `depends` 就行。
5. 用 `./gradlew dependencies` 看 `include` 配置里到底挂了什么；`jar` 任务产物用 `unzip -l` 检查 `META-INF/jars`。

### 2.4 验证任务

```text
./gradlew build        # 编译 + remap + 打 jar
./gradlew runClient    # 启动带 mod 的客户端
./gradlew runServer    # 启动专用服务器（先 eula=true）
./gradlew runDatagen   # 数据生成（见第 9 节）
./gradlew genSources   # 生成可读的反编译源码
./gradlew migrateMappings --mappings "1.21.1+build.3"   # 换映射后迁移源码
```

---

## 3. fabric.mod.json 全字段

路径：`src/main/resources/fabric.mod.json`（拆分 sourceSet 后客户端资源在 `src/client/resources/fabric.mod.json`？**不是**，元数据只有一份，永远在 `src/main/resources`）。

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schemaVersion` | 是 | 目前只能是 `1`，缺失或写错 Loader 直接拒绝加载 |
| `id` | 是 | 模组 ID，只能是小写字母、数字、`_`、`-`；与 `MOD_ID` 常量一致 |
| `version` | 是 | 语义化版本，通常写 `"${version}"` 交给 `processResources` 展开 |
| `name` | 是 | 显示名 |
| `description` | 否 | 模组列表里的描述 |
| `authors` | 否 | 字符串数组 |
| `contributors` | 否 | 字符串数组 |
| `contact` | 否 | 对象：`email`/`irc`/`homepage`/`issues`/`sources` |
| `license` | 否 | SPDX 标识符，如 `MIT`、`CC0-1.0` |
| `icon` | 否 | 相对 `resources` 的路径，如 `assets/examplemod/icon.png` |
| `environment` | 否 | `*`（默认）/ `client` / `server`；`client` 表示仅物理客户端加载 |
| `entrypoints` | 否 | 对象，key 是入口名，value 是类名数组 |
| `mixins` | 否 | 字符串数组，或带 `{"config": "...", "environment": "client"}` 的对象数组 |
| `accessWidener` | 否 | AW 文件路径，相对 `resources`，如 `examplemod.accesswidener` |
| `depends` | 否 | 对象，硬依赖；缺失则拒绝加载 |
| `breaks` | 否 | 对象，存在这些版本则拒绝加载 |
| `conflicts` | 否 | 对象，同上（语义上表示明确不兼容） |
| `recommends` | 否 | 对象，缺失只警告 |
| `suggests` | 否 | 对象，缺失不提示 |
| `jars` | 否 | 嵌套 jar 列表，Loom `include` 会自动生成，手写少见 |
| `languageAdapters` | 否 | 自定义 `LanguageAdapter`，极少用 |
| `custom` | 否 | 给别的模组读的任意元数据 |

完整示例：

```json
{
  "schemaVersion": 1,
  "id": "examplemod",
  "version": "${version}",
  "name": "Example Mod",
  "description": "A Fabric 1.21.1 example mod.",
  "authors": [ "YourName" ],
  "contributors": [ "Testers" ],
  "contact": {
    "homepage": "https://example.com",
    "sources": "https://github.com/you/examplemod",
    "issues": "https://github.com/you/examplemod/issues"
  },
  "license": "MIT",
  "icon": "assets/examplemod/icon.png",
  "environment": "*",
  "entrypoints": {
    "main": [ "com.example.examplemod.ExampleMod" ],
    "client": [ "com.example.examplemod.client.ExampleModClient" ],
    "server": [ "com.example.examplemod.ExampleModServer" ],
    "fabric-datagen": [ "com.example.examplemod.datagen.ExampleModDataGen" ]
  },
  "mixins": [
    "examplemod.mixins.json",
    {
      "config": "examplemod.client.mixins.json",
      "environment": "client"
    }
  ],
  "accessWidener": "examplemod.accesswidener",
  "depends": {
    "fabricloader": ">=0.16.0",
    "minecraft": "~1.21.1",
    "java": ">=21",
    "fabric-api": "*"
  },
  "recommends": {
    "modmenu": ">=11.0.0"
  },
  "breaks": {
    "optifabric": "*"
  }
}
```

版本范围语法（Loader 的 semver）：`*` 任意、`>=1.0.0`、`~1.21.1`（1.21.x）、`^0.16.0`（0.16.x 且 <0.17）、`1.2.3` 精确。`depends` 里不写 `fabric-api` 时，运行期调 Fabric API 会 `NoClassDefFoundError`。

---

## 4. 入口（Entrypoint）

### 4.1 三个入口接口

```java
package com.example.examplemod;

import net.fabricmc.api.ModInitializer;

public class ExampleMod implements ModInitializer {
    public static final String MOD_ID = "examplemod";

    @Override
    public void onInitialize() {
        ModRegistry.init();      // 注册物品/方块/实体
        ModEvents.register();    // 注册事件回调
        ModNetworking.register();// 注册 payload 与接收器
    }
}
```

```java
package com.example.examplemod;

import net.fabricmc.api.DedicatedServerModInitializer;

public class ExampleModServer implements DedicatedServerModInitializer {
    @Override
    public void onInitializeServer() {
        // 只在专用服务器执行
    }
}
```

```java
package com.example.examplemod.client;

import net.fabricmc.api.ClientModInitializer;

public class ExampleModClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        // 按键、渲染器、屏幕、客户端接收器
    }
}
```

三个接口的区别：

| 接口 | 入口 key | 运行环境 | 常见用途 |
| --- | --- | --- | --- |
| `ModInitializer` | `main` | 两端都跑 | 注册表注册、事件、网络注册 |
| `ClientModInitializer` | `client` | 仅物理客户端 | 渲染、按键、`Screen` |
| `DedicatedServerModInitializer` | `server` | 仅专用服务器 | 专用服务器专属逻辑（勿放通用注册） |

### 4.2 初始化顺序

1. Loader 解析所有 `fabric.mod.json`，按依赖拓扑排序。
2. `preLaunch` 入口（`PreLaunchEntrypoint`）。
3. `main` 入口的 `onInitialize()`：此时**注册表已经创建但还没冻结**，可以 `Registry.register`；但世界、玩家、服务器都还不存在。
4. `client` 入口的 `onInitializeClient()`：`MinecraftClient` 实例已创建，但资源/世界可能还没加载。
5. `server` 入口的 `onInitializeServer()`：专用服务器启动流程中。
6. `fabric-datagen` 入口只在 `runDatagen` 时执行。

所以：注册放在 `main`；需要 `ServerLifecycleEvents.SERVER_STARTING` 才能碰服务器对象；需要世界的东西放事件里。

### 4.3 环境判断与类加载边界

```java
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import net.fabricmc.loader.api.FabricLoader;

if (FabricLoader.getInstance().getEnvironmentType() == EnvType.CLIENT) {
    // 物理客户端
}
```

- `EnvType.CLIENT` / `EnvType.SERVER` 来自 `net.fabricmc.api`，判断的是**物理端**，不是逻辑端（单人游戏里逻辑服务端也跑在客户端进程）。
- 判断逻辑端用 `world.isClient()`。
- **客户端类绝不能在 `main` 入口里被直接引用**：专用服务器加载 `main` 入口时，如果该类的方法体里有 `MinecraftClient` 引用，只有在该方法真正执行（且 JVM 解析到那个符号）时才可能崩溃，但字段类型、`implements`、注解参数、静态初始化器会立即触发类加载。安全做法：
  - 客户端代码全部放 `src/client/java`（推荐，`splitEnvironmentSourceSets()` 后服务端 classpath 里根本没有这些类）；
  - 或者加 `@Environment(EnvType.CLIENT)`，并在调用前用 `getEnvironmentType()` 守卫。
- 混用 sourceSet 时，`main` 里的类**不能** import `src/client` 里的类；反过来可以（客户端能引用 common）。

---

## 5. 注册

### 5.1 原则

- 注册必须在**类加载期或 `onInitialize()` 内**完成，且早于注册表冻结。实践上就是：`public static final` 字段 + 在 `onInitialize()` 里触发那个类初始化。
- 静态字段注册的隐患：如果 A 类的静态字段引用 B 类的静态字段，而 B 类还没初始化，JVM 会保证初始化 B（合法），但**顺序不可控**。需要确定性顺序时，把注册集中在一个 `ModRegistry.init()` 里显式按序调用。
- 1.21 起 `Identifier` 的构造器是私有的，只能 `Identifier.of(namespace, path)`、`Identifier.of(path)`（默认 `minecraft`）、`Identifier.ofVanilla(path)`。

### 5.2 常用注册表常量（Yarn）

| 内容 | 注册表 | Mojmap |
| --- | --- | --- |
| 物品 | `Registries.ITEM` | `BuiltInRegistries.ITEM` |
| 方块 | `Registries.BLOCK` | `BLOCK` |
| 方块实体类型 | `Registries.BLOCK_ENTITY_TYPE` | `BLOCK_ENTITY_TYPE` |
| 实体类型 | `Registries.ENTITY_TYPE` | `ENTITY_TYPE` |
| 创造模式物品组 | `Registries.ITEM_GROUP` | `CREATIVE_MODE_TAB` |
| 屏幕处理器类型 | `Registries.SCREEN_HANDLER` | `MENU` |
| 粒子类型 | `Registries.PARTICLE_TYPE` | `PARTICLE_TYPE` |
| 音效 | `Registries.SOUND_EVENT` | `SOUND_EVENT` |
| 状态效果 | `Registries.STATUS_EFFECT` | `MOB_EFFECT` |
| 药水 | `Registries.POTION` | `POTION` |
| 配方序列化器 / 类型 | `Registries.RECIPE_SERIALIZER` / `Registries.RECIPE_TYPE` | `RECIPE_SERIALIZER` / `RECIPE_TYPE` |
| 数据组件类型 | `Registries.DATA_COMPONENT_TYPE` | `DATA_COMPONENT_TYPE` |
| 属性 | `Registries.ATTRIBUTE` | `ATTRIBUTE` |
| 流体 | `Registries.FLUID` | `FLUID` |
| 附魔 | `Registries.ENCHANTMENT` | `ENCHANTMENT` |

`RegistryKey` 用法：

```java
public static final RegistryKey<Item> RUBY_KEY =
    RegistryKey.of(RegistryKeys.ITEM, Identifier.of(MOD_ID, "ruby"));
```

### 5.3 物品

```java
package com.example.examplemod;

import net.minecraft.item.Item;
import net.minecraft.registry.Registries;
import net.minecraft.registry.Registry;
import net.minecraft.registry.RegistryKey;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.util.Identifier;

public final class ModItems {
    public static final RegistryKey<Item> RUBY_KEY =
        RegistryKey.of(RegistryKeys.ITEM, Identifier.of(ExampleMod.MOD_ID, "ruby"));

    public static final Item RUBY = Registry.register(
        Registries.ITEM,
        RUBY_KEY,
        new Item(new Item.Settings().registryKey(RUBY_KEY))
    );
}
```

- `Item.Settings#registryKey`：1.21.1 里推荐设置（物品默认组件与配方查找会用到物品 ID；1.21.2+ 变成强制）。
- 需要堆叠上限、食物、稀有度：`new Item.Settings().registryKey(RUBY_KEY).maxCount(64).rarity(Rarity.RARE)`。
- 不想写 `RegistryKey` 时也可 `Registry.register(Registries.ITEM, Identifier.of(MOD_ID, "ruby"), item)`，但此时 `Item.Settings` 就拿不到 key。

### 5.4 方块 + 方块物品

```java
package com.example.examplemod;

import net.minecraft.block.AbstractBlock;
import net.minecraft.block.Block;
import net.minecraft.item.BlockItem;
import net.minecraft.item.Item;
import net.minecraft.registry.Registries;
import net.minecraft.registry.Registry;
import net.minecraft.registry.RegistryKey;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.util.Identifier;

public final class ModBlocks {
    public static final RegistryKey<Block> RUBY_BLOCK_KEY =
        RegistryKey.of(RegistryKeys.BLOCK, Identifier.of(ExampleMod.MOD_ID, "ruby_block"));
    public static final RegistryKey<Item> RUBY_BLOCK_ITEM_KEY =
        RegistryKey.of(RegistryKeys.ITEM, Identifier.of(ExampleMod.MOD_ID, "ruby_block"));

    public static final Block RUBY_BLOCK = Registry.register(
        Registries.BLOCK,
        RUBY_BLOCK_KEY,
        new Block(AbstractBlock.Settings.copy(Blocks.IRON_BLOCK).strength(5.0f, 6.0f))
    );

    public static final Item RUBY_BLOCK_ITEM = Registry.register(
        Registries.ITEM,
        RUBY_BLOCK_ITEM_KEY,
        new BlockItem(RUBY_BLOCK, new Item.Settings().registryKey(RUBY_BLOCK_ITEM_KEY))
    );
}
```

- `AbstractBlock.Settings.copy(Blocks.X)` 是最稳的起点；也可以用 `.copy(Blocks.STONE).requiresTool()`。
- 方块与方块物品用**同名 ID** 是惯例（`ruby_block`、`ruby_block`），资源路径才能对上。
- 需要方块实体时，方块要实现 `BlockEntityProvider` 并覆写 `createBlockEntity(BlockPos, BlockState)`。

### 5.5 方块实体与 `BlockEntityType`

```java
package com.example.examplemod.block;

import net.minecraft.block.BlockState;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.block.entity.BlockEntityType;
import net.minecraft.registry.Registries;
import net.minecraft.registry.Registry;
import net.minecraft.util.Identifier;
import net.minecraft.util.math.BlockPos;
import com.example.examplemod.ExampleMod;
import com.example.examplemod.ModBlocks;

public class RubyBlockEntity extends BlockEntity {
    public RubyBlockEntity(BlockPos pos, BlockState state) {
        super(ModBlockEntities.RUBY, pos, state);
    }
}

public final class ModBlockEntities {
    public static final BlockEntityType<RubyBlockEntity> RUBY =
        Registry.register(
            Registries.BLOCK_ENTITY_TYPE,
            Identifier.of(ExampleMod.MOD_ID, "ruby_block"),
            BlockEntityType.Builder.create(RubyBlockEntity::new, ModBlocks.RUBY_BLOCK).build()
        );
}
```

1.21.1 的关键变化：**`FabricBlockEntityTypeBuilder` 已标记 `@Deprecated`**，直接用原版 `BlockEntityType.Builder.create(BlockEntityType.BlockEntityFactory, Block...)`。Fabric 通过 `fabric-transitive-access-wideners-v1` 公开了 `BlockEntityFactory`，所以不需要 AT。
注意 `BlockEntityType.Builder#build()` 在 1.21.1 不接受参数（旧版 `build(null)` 的写法只是兼容壳）。

### 5.6 实体类型与属性

```java
public static final EntityType<RubyGolemEntity> RUBY_GOLEM = Registry.register(
    Registries.ENTITY_TYPE,
    Identifier.of(MOD_ID, "ruby_golem"),
    EntityType.Builder.create(RubyGolemEntity::new, SpawnGroup.CREATURE)
        .dimensions(0.8f, 1.4f)
        .maxTrackingRange(8)
        .build()
);

// 服务端初始化时注册属性（必须早于实体生成）
FabricDefaultAttributeRegistry.register(RUBY_GOLEM, RubyGolemEntity.createRubyGolemAttributes());
```

`FabricDefaultAttributeRegistry` 在 `net.fabricmc.fabric.api.object.builder.v1.entity` 包；`FabricEntityTypeBuilder` 同样已废弃，不要再用。

### 5.7 创造模式物品组

```java
import net.fabricmc.fabric.api.itemgroup.v1.FabricItemGroup;
import net.minecraft.item.ItemGroup;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.registry.Registry;
import net.minecraft.registry.RegistryKey;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.text.Text;

public static final RegistryKey<ItemGroup> RUBY_GROUP_KEY =
    RegistryKey.of(RegistryKeys.ITEM_GROUP, Identifier.of(MOD_ID, "ruby_group"));

public static void registerItemGroup() {
    Registry.register(Registries.ITEM_GROUP, RUBY_GROUP_KEY, FabricItemGroup.builder()
        .displayName(Text.translatable("itemGroup.examplemod.ruby"))
        .icon(() -> new ItemStack(ModItems.RUBY))
        .entries((context, entries) -> {
            entries.add(ModItems.RUBY);
            entries.add(ModBlocks.RUBY_BLOCK_ITEM);
        })
        .build());
}
```

往原版物品组追加：

```java
import net.fabricmc.fabric.api.itemgroup.v1.ItemGroupEvents;
import net.minecraft.item.ItemGroups;

ItemGroupEvents.modifyEntriesEvent(ItemGroups.INGREDIENTS)
    .register(entries -> entries.add(ModItems.RUBY));
```

`displayName` 是必需的（不设会走空显示名），`FabricItemGroup.builder()` 返回原版 `ItemGroup.Builder`。

### 5.8 其他注册：粒子、状态效果、音效

```java
// 粒子类型（服务端注册类型，客户端另注册工厂）
import net.fabricmc.fabric.api.particle.v1.FabricParticleTypes;
import net.minecraft.particle.SimpleParticleType;

public static final SimpleParticleType RUBY_SPARKLE =
    Registry.register(Registries.PARTICLE_TYPE,
        Identifier.of(MOD_ID, "ruby_sparkle"),
        FabricParticleTypes.simple(true));   // 参数：是否强制渲染（overrideLimiter）

// 状态效果
public class RubyEffect extends StatusEffect {
    public RubyEffect() {
        super(StatusEffectCategory.BENEFICIAL, 0xB4003C); // 分类、颜色
    }
    @Override
    public boolean canApplyUpdateEffect(int duration, int amplifier) {
        return duration % 20 == 0;
    }
}

public static final StatusEffect RUBY_EFFECT = Registry.register(
    Registries.STATUS_EFFECT,
    Identifier.of(MOD_ID, "ruby_effect"),
    new RubyEffect());
```

音效：`Registry.register(Registries.SOUND_EVENT, id, SoundEvent.of(id))`，事件的 id 必须与注册 id 完全一致，否则 `sounds.json` 与代码对不上。

### 5.9 数据组件（`DataComponentType`）

```java
public static final DataComponentType<Integer> CHARGE = Registry.register(
    Registries.DATA_COMPONENT_TYPE,
    Identifier.of(MOD_ID, "charge"),
    DataComponentType.<Integer>builder()
        .codec(Codec.INT)
        .packetCodec(PacketCodecs.VAR_INT)
        .build()
);
```

组件的读取/写入在 1.21 走 `ItemStack` 上的 `get(...)`/`set(...)`。1.21.1 已有 `DataComponentType.Builder`；如果 Javadoc 显示方法名不同（例如需要 `PacketCodec` 而非 `PacketCodecs.VAR_INT`），以当前 API 版本为准。

### 5.10 附件 `AttachmentRegistry`（Fabric 的 “Capability”）

```java
import net.fabricmc.fabric.api.attachment.v1.AttachmentRegistry;
import net.fabricmc.fabric.api.attachment.v1.AttachmentType;
import net.fabricmc.fabric.api.attachment.v1.AttachmentTarget;

public static final AttachmentType<Integer> RUBY_CHARGE =
    AttachmentRegistry.createPersistent(Identifier.of(MOD_ID, "ruby_charge"), Codec.INT);

// 读：target 可以是 ItemStack / Entity / BlockEntity / Level / Chunk
int charge = stack.getAttachedOrCreate(RUBY_CHARGE);
stack.setAttached(RUBY_CHARGE, charge + 1);
```

`AttachmentRegistry` 的四种快捷方法：

| 方法 | 持久化 | 自动初始化 | 网络同步 |
| --- | --- | --- | --- |
| `create(id)` | 否 | 否 | 否 |
| `createDefaulted(id, supplier)` | 否 | 是 | 否 |
| `createPersistent(id, codec)` | 是 | 否 | 否 |
| `create(id, builderConsumer)` | 由 builder 定 | 由 builder 定 | 可 `syncWith(codec, predicate)` |

builder 还有 `copyOnDeath()`（玩家死亡保留）、`initializer(Supplier)`、`syncWith(PacketCodec, AttachmentSyncPredicate)`。附件不需要注册表条目，`create*` 内部完成注册，但仍要在 `onInitialize()` 阶段调用。

---

## 6. 事件

### 6.1 模型

Fabric 的事件**不是总线**，也没有 `@SubscribeEvent`。每个事件是 `net.fabricmc.fabric.api.event.Event<T>` 实例，通常放在回调接口的静态字段里，或直接放在工具类里（如 `ServerTickEvents.START_SERVER_TICK`）。注册方式：

```java
SomeEvents.SOME_EVENT.register(callback);
```

`Event<T>` 由 `EventFactory.createArrayBacked(...)` 创建，内部维持监听器数组，按注册顺序调用；返回值型事件用 `ActionResult` 协作（`PASS` 继续、`SUCCESS`/`FAIL` 终止）。

**注册必须在 `onInitialize()` 或类加载期完成**，在事件触发之后注册的监听器不会再被已发生的事件调到。

### 6.2 常用事件与函数式接口

| 事件 | 包 / 类 | 回调签名（Yarn） |
| --- | --- | --- |
| 服务端生命周期 | `net.fabricmc.fabric.api.event.lifecycle.v1.ServerLifecycleEvents` | `SERVER_STARTING`/`SERVER_STARTED`/`SERVER_STOPPING`/`SERVER_STOPPED`: `(MinecraftServer)`；还有 `BEFORE_SAVE`/`AFTER_SAVE`/`START_DATA_PACK_RELOAD`/`END_DATA_PACK_RELOAD`/`SYNC_DATA_PACK_CONTENTS` |
| 玩家进出服 | `net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents` | `INIT`: `(ServerPlayNetworkHandler, MinecraftServer)`；`JOIN`: `(ServerPlayNetworkHandler, PacketSender, MinecraftServer)`；`DISCONNECT`: `(ServerPlayNetworkHandler, MinecraftServer)` |
| 服务端 tick | `...event.lifecycle.v1.ServerTickEvents` | `START_SERVER_TICK`/`END_SERVER_TICK`: `(MinecraftServer)`；`START_WORLD_TICK`/`END_WORLD_TICK`: `(ServerWorld)` |
| 客户端 tick | `net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents` | `START_CLIENT_TICK`/`END_CLIENT_TICK`: `(MinecraftClient)` |
| 实体加/卸载 | `...event.lifecycle.v1.ServerEntityEvents` | `ENTITY_LOAD`/`ENTITY_UNLOAD`: `(Entity, ServerWorld)`；`EQUIPMENT_CHANGE`: `(LivingEntity, EquipmentSlot, ItemStack, ItemStack)` |
| 破坏方块 | `...event.player.PlayerBlockBreakEvents` | `BEFORE`: `boolean (World, PlayerEntity, BlockPos, BlockState, BlockEntity)`；`AFTER`/`CANCELED`: `void (...)` |
| 右键方块 | `...event.player.UseBlockCallback` | `ActionResult (PlayerEntity, World, Hand, BlockHitResult)` |
| 左键方块 | `...event.player.AttackBlockCallback` | `ActionResult (PlayerEntity, World, Hand, BlockPos, Direction)` |
| 使用物品 | `...event.player.UseItemCallback` | `ActionResult (PlayerEntity, World, Hand)` |
| 攻击实体 | `...event.player.AttackEntityCallback` | `ActionResult (PlayerEntity, World, Hand, Entity, EntityHitResult)` |
| 与实体交互 | `...event.player.UseEntityCallback` | `ActionResult (PlayerEntity, World, Hand, Entity, EntityHitResult)` |
| 命令注册 | `net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback` | `EVENT`: `(CommandDispatcher<ServerCommandSource>, CommandRegistryAccess, CommandManager.RegistrationEnvironment)` |
| 战利品表 | `net.fabricmc.fabric.api.loot.v3.LootTableEvents` | `MODIFY`: `(RegistryKey<LootTable>, LootTable.Builder, LootTableSource, RegistryWrapper.WrapperLookup)`；另有 `REPLACE`/`ALL_LOADED` |
| 资源重载 | `net.fabricmc.fabric.api.resource.ResourceManagerHelper` + `SimpleResourceReloadListener` | 见 6.4 |

**注意**：Fabric API **没有** `PlayerEvents.JOIN` / `PlayerEvents.QUIT`。玩家进服用 `ServerPlayConnectionEvents.JOIN`，退服用 `ServerPlayConnectionEvents.DISCONNECT`。

### 6.3 代码示例

```java
package com.example.examplemod;

import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerLifecycleEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.event.player.PlayerBlockBreakEvents;
import net.fabricmc.fabric.api.event.player.UseBlockCallback;
import net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.server.command.CommandManager;
import net.minecraft.text.Text;
import net.minecraft.util.ActionResult;

public final class ModEvents {

    public static void register() {
        ServerLifecycleEvents.SERVER_STARTING.register(server ->
            System.out.println("server starting: " + server.getSaveProperties().getLevelName()));

        ServerLifecycleEvents.SERVER_STARTED.register(server -> {
            // 此时所有维度已加载
        });

        ServerLifecycleEvents.SERVER_STOPPING.register(server -> {
            // 维度仍在，可安全保存数据
        });

        ServerPlayConnectionEvents.JOIN.register((handler, sender, server) -> {
            ServerPlayerEntity player = handler.player;
            player.sendMessage(Text.literal("欢迎"), false);
        });

        ServerPlayConnectionEvents.DISCONNECT.register((handler, server) -> {
            // 此事件中不要再发包
        });

        ServerTickEvents.END_SERVER_TICK.register(server -> {
            // 每秒 20 次；避免在这里做 O(chunk) 的重活
        });

        ServerTickEvents.END_WORLD_TICK.register(world -> {
            // 逐维度 tick
        });

        PlayerBlockBreakEvents.AFTER.register((world, player, pos, state, blockEntity) -> {
            // 服务端：方块已破坏，state 是破坏前的状态
        });

        PlayerBlockBreakEvents.BEFORE.register((world, player, pos, state, blockEntity) -> {
            return true; // 返回 false 取消破坏
        });

        UseBlockCallback.EVENT.register((player, world, hand, hitResult) -> {
            if (world.isClient()) return ActionResult.PASS;
            if (world.getBlockState(hitResult.getBlockPos()).isOf(ModBlocks.RUBY_BLOCK)) {
                return ActionResult.SUCCESS;
            }
            return ActionResult.PASS;
        });

        ServerEntityEvents.ENTITY_LOAD.register((entity, world) -> {
            // 实体已加入世界
        });

        CommandRegistrationCallback.EVENT.register((dispatcher, registryAccess, environment) -> {
            dispatcher.register(CommandManager.literal("ruby")
                .requires(source -> source.hasPermissionLevel(2))
                .executes(context -> {
                    context.getSource().sendFeedback(() -> Text.literal("ruby!"), false);
                    return 1;
                }));
        });
    }
}
```

`PlayerBlockBreakEvents` 的 `BEFORE` 只在逻辑服务端触发；客户端侧的破坏事件在 `net.fabricmc.fabric.api.event.client.player.ClientPlayerBlockBreakEvents`。

### 6.4 数据类注册辅助（不是事件，但常一起用）

```java
import net.fabricmc.fabric.api.registry.CompostingChanceRegistry;
import net.fabricmc.fabric.api.registry.FuelRegistry;
import net.fabricmc.fabric.api.registry.VillagerInteractionRegistries;
import net.fabricmc.fabric.api.object.builder.v1.trade.TradeOfferHelper;
import net.minecraft.village.VillagerProfession;

FuelRegistry.INSTANCE.add(ModItems.RUBY, 200);            // 燃烧 200 tick
CompostingChanceRegistry.INSTANCE.add(ModItems.RUBY, 0.5f);// 堆肥概率 50%
VillagerInteractionRegistries.registerCollectable(ModItems.RUBY); // 村民可拾取
VillagerInteractionRegistries.registerFood(ModItems.RUBY, 1);     // 可食用（繁殖值）
TradeOfferHelper.registerVillagerOffers(VillagerProfession.TOOLSMITH, 2, factories ->
    factories.add((entity, random) -> new TradeOffer(/* ... */)));
```

这些注册同样是“在 `onInitialize()` 里调用一次”的模型，没有事件。

### 6.5 战利品表修改

```java
LootTableEvents.MODIFY.register((key, tableBuilder, source, registries) -> {
    if (source.isBuiltin() && key.getValue().equals(Identifier.of("minecraft", "blocks/coal_ore"))) {
        tableBuilder.pool(LootPool.builder().with(ItemEntry.builder(ModItems.RUBY)));
    }
});
```

判定目标表时优先用 `Blocks.COAL_ORE.getLootTableKey()` 而不是手拼 `Identifier`，避免写错路径。

### 6.6 自定义资源重载

```java
ResourceManagerHelper.get(ResourceType.SERVER_DATA).registerReloadListener(
    new SimpleResourceReloadListener<MyConfig>() {
        @Override
        public Identifier getFabricId() { return Identifier.of(MOD_ID, "my_config"); }

        @Override
        public CompletableFuture<MyConfig> load(ResourceManager manager, Profiler profiler, Executor executor) {
            // 任意线程执行，不能改游戏状态
            return CompletableFuture.supplyAsync(MyConfig::load, executor);
        }

        @Override
        public CompletableFuture<Void> apply(MyConfig data, ResourceManager manager, Profiler profiler, Executor executor) {
            // 主线程执行
            return CompletableFuture.completedFuture(null);
        }
    });
```

`SimpleResourceReloadListener` 的 `load` 阶段可并发，`apply` 阶段保证在主线程。

### 6.7 线程规则

| 场景 | 线程 |
| --- | --- |
| `ServerPlayNetworking` 的接收器 | 服务端主线程（可直接改世界） |
| `ClientPlayNetworking` 的接收器 | 客户端渲染线程（可直接调客户端方法） |
| `ServerTickEvents`、`ServerLifecycleEvents` | 服务端主线程 |
| `ClientTickEvents` | 客户端主线程 |
| `SimpleResourceReloadListener#load` | 加载线程池（禁止改游戏状态） |
| 自己开的 `CompletableFuture` / 异步 IO | 未知线程，回到主线程用 `server.execute(...)` / `client.execute(...)` |

---

## 7. 网络（payload 制）

### 7.1 1.21.1 的命名（必须记住）

| 1.21.1（Yarn） | 1.21.2+ 曾用名 | 说明 |
| --- | --- | --- |
| `net.minecraft.network.packet.CustomPayload` | `CustomPacketPayload` | payload 接口 |
| `CustomPayload.Id<T>` | `CustomPacketPayload.Type<T>` | 类型标识（内含 `Identifier`） |
| `CustomPayload.Type<? super B, T>` | `Type<T>` | 注册后的类型（由 `PayloadTypeRegistry.register` 返回） |
| `net.minecraft.network.codec.PacketCodec` | `StreamCodec` | 编解码器 |
| `CustomPayload#getId()` | `type()` | 覆写方法名 |

1.21.1 还提供便捷工厂 `CustomPayload.codecOf(encoder, decoder)`，encoder 的签名是 `(payload, buf)`。

### 7.2 定义 payload

```java
package com.example.examplemod.network;

import net.minecraft.network.RegistryByteBuf;
import net.minecraft.network.codec.PacketCodec;
import net.minecraft.network.packet.CustomPayload;
import net.minecraft.util.Identifier;

public record RubySyncPayload(int value) implements CustomPayload {

    public static final CustomPayload.Id<RubySyncPayload> ID =
        new CustomPayload.Id<>(Identifier.of("examplemod", "ruby_sync"));

    public static final PacketCodec<RegistryByteBuf, RubySyncPayload> CODEC =
        CustomPayload.codecOf(
            (payload, buf) -> buf.writeVarInt(payload.value()),
            buf -> new RubySyncPayload(buf.readVarInt())
        );

    @Override
    public CustomPayload.Id<? extends CustomPayload> getId() {
        return ID;
    }
}
```

`RegistryByteBuf` 是 play 阶段的缓冲区类型（能带注册表上下文）；configuration 阶段用 `PacketByteBuf`。复杂字段也可用 `PacketCodecs.STRING.xmap(...).cast()` 组合。

### 7.3 注册类型（两端都要，且在收包之前）

```java
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;

// common 初始化阶段，客户端与服务端都会执行 onInitialize()
PayloadTypeRegistry.playC2S().register(RubySyncPayload.ID, RubySyncPayload.CODEC);
PayloadTypeRegistry.playS2C().register(RubySyncPayload.ID, RubySyncPayload.CODEC);
```

- 服务端**接收**的包注册到 `playC2S()`；服务端**发送**的包注册到 `playS2C()`。
- 两端都必须注册同一类型（发送端要编码、接收端要解码），所以放 common 初始化里最省事。
- 顺序：先 `register` 类型，再 `registerGlobalReceiver`；否则抛 `IllegalArgumentException`。
- 还有 `configurationC2S()` / `configurationS2C()`，用于 configuration 阶段（登录后、进服前）。

### 7.4 服务端接收 + 客户端接收

```java
// 服务端（common 初始化里）
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;

ServerPlayNetworking.registerGlobalReceiver(RubySyncPayload.ID, (payload, context) -> {
    // 已在服务端主线程，可直接操作 World / PlayerEntity
    ServerPlayerEntity player = context.player();
    MinecraftServer server = context.server();
    PacketSender sender = context.responseSender();   // 可直接回包
    player.sendMessage(net.minecraft.text.Text.literal("value=" + payload.value()), false);
});
```

```java
// 客户端（ClientModInitializer 里）
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;

ClientPlayNetworking.registerGlobalReceiver(RubySyncPayload.ID, (payload, context) -> {
    // 已在渲染线程，可直接改客户端状态
    MinecraftClient client = context.client();
    ClientPlayerEntity player = context.player();
});
```

两边的 `Context` 都提供 `responseSender()`；服务端是 `server()`+`player()`，客户端是 `client()`+`player()`。

### 7.5 发送

```java
// 服务端 → 某个玩家
ServerPlayNetworking.send(player, new RubySyncPayload(7));

// 服务端 → 全服（Fabric 提供 PlayerLookup）
for (ServerPlayerEntity p : PlayerLookup.all(server)) {
    ServerPlayNetworking.send(p, new RubySyncPayload(7));
}

// 客户端 → 服务端
ClientPlayNetworking.send(new RubySyncPayload(3));
```

`PlayerLookup` 在 `net.fabricmc.fabric.api.networking.v1`，常用 `all(server)`、`world(ServerWorld)`、`tracking(entity)`（只发给能看到该实体的玩家）。

### 7.6 线程与可用性检查

- `ClientPlayNetworking.send(...)` 只能在客户端主线程调用（内部用 `MinecraftClient#getNetworkHandler`），非主线程需 `client.execute(...)`。
- 发包前可 `ServerPlayNetworking.canSend(player, ID)` / `ClientPlayNetworking.canSend(ID)` 检查对端是否声明了该通道（对端没装 mod 时避免报错刷屏）。
- `ServerPlayNetworking.getSender(player).sendPacket(packet, callbacks)` 可用于自定义包和 bundle 发包。
- 服务端不要在 `DISCONNECT` 里发包。

---

## 8. Mixin

### 8.1 注解速查

| 注解 | 作用 |
| --- | --- |
| `@Mixin(Target.class)` | 声明目标类；多个目标用 `@Mixin({A.class, B.class})` |
| `@Inject(method=..., at=@At(...), cancellable=...)` | 在指定位置插入回调 |
| `@At("HEAD"/"TAIL"/"RETURN"/"INVOKE"/"FIELD"/"NEW"/"CONSTANT")` | 注入点 |
| `CallbackInfo` / `CallbackInfoReturnable<T>` | 无返回值 / 有返回值方法的回调信息；`cancellable = true` 后可用 `ci.cancel()`、`cir.setReturnValue(...)` |
| `@Redirect` | 替换一条方法调用或字段访问，签名必须与目标调用一致（实例调用第一个参数是接收者） |
| `@ModifyVariable` | 修改变量/参数；配合 `at = @At("HEAD")`、`argsOnly = true`、`index = n` |
| `@ModifyArg` | 修改某次调用的某个实参；`at = @At(value="INVOKE", target=..., ordinal=...)` + `index` |
| `@ModifyConstant` | 改常量（数字/字符串） |
| `@Accessor("fieldName")` / `@Invoker("methodName")` | 在 `@Mixin` 接口里生成 getter/setter / 调用器 |
| `@Shadow` | 声明目标类里存在的字段/方法，供注入代码使用（`@Shadow @Final` 表示 final 字段） |
| `@Unique` | 标记本 mixin 自己新增的成员，避免与方法重名冲突 |
| `@Final` | 配合 `@Shadow` 表示目标字段是 final |
| `@Overwrite` | 整体替换方法（**最后手段**，极易冲突，尽量不用） |

### 8.2 基础示例

```java
package com.example.examplemod.mixin;

import net.minecraft.server.MinecraftServer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(MinecraftServer.class)
public abstract class MinecraftServerMixin {

    @Inject(method = "tick", at = @At("HEAD"))
    private void examplemod$onTick(CallbackInfo ci) {
        // 每个服务端 tick 开始
    }
}
```

### 8.3 带返回值 / 可取消

```java
@Inject(method = "getMaxPlayerCount", at = @At("RETURN"), cancellable = true)
private void examplemod$maxPlayers(CallbackInfoReturnable<Integer> cir) {
    cir.setReturnValue(cir.getReturnValue() + 10);
}
```

### 8.4 `INVOKE` 注入与描述符

```java
@Inject(
    method = "tick",
    at = @At(value = "INVOKE",
             target = "Lnet/minecraft/server/world/ServerWorld;tick()V")
)
private void examplemod$beforeWorldTick(CallbackInfo ci) { }
```

`target` 格式：`L<内部类名>;<方法名>(<参数描述符>)<返回描述符>;`
- 内部类名用 `/`，例如 `net/minecraft/server/world/ServerWorld`；
- 基本类型：`Z`=boolean、`B`=byte、`C`=char、`S`=short、`I`=int、`J`=long、`F`=float、`D`=double、`V`=void；
- 引用类型 `L...;`，数组 `[`。

多候选方法时用 `ordinal = n` 指定第几个；条件匹配可用 `@At(value="INVOKE", target=..., ordinal=0)`。

### 8.5 `@Redirect`

```java
@Redirect(
    method = "tick",
    at = @At(value = "INVOKE", target = "Lnet/minecraft/server/world/ServerWorld;tick()V")
)
private void examplemod$redirect(ServerWorld world) {
    world.tick();          // 必现自己调用，否则世界不 tick
}
```

`@Redirect` 的钩子签名 = 目标调用的签名 + 接收者（实例方法时）。改字段访问时把方法调用换成 `value = "FIELD"`，钩子返回字段类型、参数为接收者。

### 8.6 `@ModifyVariable` / `@ModifyArg`

```java
// 改方法入参（argsOnly）
@ModifyVariable(method = "damage", at = @At("HEAD"), argsOnly = true)
private float examplemod$scaleDamage(float amount) {
    return amount * 2.0f;
}

// 改某次调用的第 1 个实参
@ModifyArg(
    method = "applyDamage",
    at = @At(value = "INVOKE", target = "Lnet/minecraft/entity/Entity;damage(Lnet/minecraft/entity/damage/DamageSource;F)Z"),
    index = 1
)
private float examplemod$modifyDamageArg(float amount) {
    return amount + 1.0f;
}
```

### 8.7 `@Accessor` / `@Invoker`

```java
@Mixin(PlayerEntity.class)
public interface PlayerEntityAccessor {
    @Accessor("abilities")
    PlayerAbilities getAbilities();

    @Invoker("getBlockPos")
    BlockPos invokeGetBlockPos();
}
```

访问器 mixin 用 `interface` 形式；调用侧 `((PlayerEntityAccessor) player).getAbilities()`。接口 mixin 不写进 `mixins` 数组也要写——**要写**，所有 mixin 类（含接口）都必须在配置里列出。

### 8.8 `@Shadow` 与 `@Unique`

```java
@Mixin(Block.class)
public abstract class BlockMixin {
    @Shadow @Final @Mutable   // @Mutable 允许改 final 字段
    private static Identifier[] BLOCK_IDS;   // 实际字段名以 Yarn 为准

    @Shadow
    protected abstract void onStateReplaced(BlockState state, World world, BlockPos pos, BlockState newState, boolean moved);

    @Unique
    private int examplemod$counter;
}
```

`@Shadow` 只声明，不给实现；`@Shadow @Final` 的字段在构造器里赋值会报错，需要 `@Mutable`。

### 8.9 mixins.json 结构

`src/main/resources/examplemod.mixins.json`：

```json
{
  "required": true,
  "package": "com.example.examplemod.mixin",
  "compatibilityLevel": "JAVA_21",
  "minVersion": "0.8",
  "mixins": [
    "MinecraftServerMixin",
    "BlockMixin",
    "PlayerEntityAccessor"
  ],
  "client": [
    "client.MinecraftClientMixin"
  ],
  "server": [],
  "injectors": {
    "defaultRequire": 1
  }
}
```

拆分 sourceSet 后，客户端 mixin 单独一个配置文件 `src/client/resources/examplemod.client.mixins.json`：

```json
{
  "required": true,
  "package": "com.example.examplemod.mixin.client",
  "compatibilityLevel": "JAVA_21",
  "client": [ "MinecraftClientMixin" ],
  "injectors": { "defaultRequire": 1 }
}
```

并在 `fabric.mod.json` 里以对象形式声明 `environment`（见第 3 节）。字段含义：

| 字段 | 说明 |
| --- | --- |
| `required` | true 时任一 mixin 应用失败即崩溃（开发期建议 true，发布可保持 true） |
| `package` | mixin 类所在包，**必须**与实际包一致，类名写相对包路径 |
| `compatibilityLevel` | Java 版本，1.21.1 用 `JAVA_21` |
| `minVersion` | Mixin 版本下限，一般 `0.8` |
| `mixins` | 两端都应用的 common mixin |
| `client` / `server` | 只在对应物理端应用 |
| `injectors.defaultRequire` | 默认注入次数，`1` 表示注入失败即报错；`0` 为尽力注入 |
| `refmap` | Loom 在 remap 时自动写入，**不要手写**（手写会与生成的 refmap 冲突） |
| `plugin` | 自定义 `IMixinConfigPlugin` 类名 |
| `overwrites.requireAnnotations` | 要求 `@Overwrite` 必须带注解（1.21.1 模板默认开启） |

### 8.10 Yarn / Mojmap 与运行时映射

- Loom 把 Yarn（或 Mojmap）名字 remap 成 intermediary 再上生产环境，运行时是 intermediary 名。
- 所以你写 `method = "tick"` 用的是 **Yarn 名字**，Loom 生成的 refmap 负责转换；换映射后必须重新构建，否则 refmap 与新名字对不上。
- 用 Mojmap 时 `tick` 仍是 `tick`，但 `PlayerEntity#getBlockPos` 会变成 `blockPosition()` 等，必须逐一核对。
- 目标方法是**私有/包私有**时照样能注入；方法名带 lambda 或混淆（`method_xxxx`）时，请用 `genSources` 生成的反编译源码确认名字。

### 8.11 Mixin 调试

```text
-Dmixin.debug.export=true                        # 导出改写后的字节码
-Dmixin.debug.verbose=true                       # 详细日志
-Dmixin.debug.countInjections=true               # 统计注入次数
-Dmixin.debug.verify=true                        # 校验注入结果
```

- 导出目录：`run/.mixin.out/class/<目标类>.class`（Gradle run 任务下），用 IDE 反编译对照。
- 注入失败常见原因：方法名/描述符不存在、`ordinal` 选错、目标方法在父类、`@Shadow` 字段名错、混用映射。
- 加进 `runClient` 的 VM 参数写法（`build.gradle`）：

```gradle
loom {
    runs {
        client {
            vmArgs "-Dmixin.debug.export=true"
        }
    }
}
```

---

## 9. 数据生成

### 9.1 入口与注册

`fabric.mod.json` 增加入口：

```json
"entrypoints": {
  "main": [ "com.example.examplemod.ExampleMod" ],
  "fabric-datagen": [ "com.example.examplemod.datagen.ExampleModDataGen" ]
}
```

实现 `DataGeneratorEntrypoint`：

```java
package com.example.examplemod.datagen;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;

public class ExampleModDataGen implements DataGeneratorEntrypoint {

    @Override
    public void onInitializeDataGenerator(FabricDataGenerator generator) {
        FabricDataGenerator.Pack pack = generator.createPack();

        // 只需要 FabricDataOutput 的 provider
        pack.addProvider(ExampleModelProvider::new);
        pack.addProvider(ExampleLootTableProvider::new);
        pack.addProvider(ExampleLangProvider::new);
        pack.addProvider(ExampleRecipeProvider::new);

        // 需要注册表查询的 provider（Tag / 语言里读注册表等）
        pack.addProvider((output, registries) -> new ExampleTagProvider(output, registries));
    }
}
```

`Pack` 有两个重载：
- `addProvider(Pack.Factory<T>)`：`T create(FabricDataOutput output)`；
- `addProvider(Pack.RegistryDependentFactory<T>)`：`T create(FabricDataOutput output, CompletableFuture<RegistryWrapper.WrapperLookup> registriesFuture)`。

还有 `generator.createBuiltinResourcePack(Identifier)` 用于生成内置资源包（配合 `ResourceManagerHelper.registerBuiltinResourcePack`）。

### 9.2 1.21.1 可用的 Provider（实测类清单）

| 类 | 输出 |
| --- | --- |
| `FabricModelProvider` | `models/`、`blockstates/`、物品模型 |
| `FabricBlockLootTableProvider` | `loot_table/blocks/` |
| `FabricLootTableProvider` / `SimpleFabricLootTableProvider` | 自定义战利品表 |
| `FabricRecipeProvider` | `recipe/` |
| `FabricAdvancementProvider` | `advancement/` |
| `FabricLanguageProvider` | `lang/` |
| `FabricTagProvider`（含嵌套 `BlockTagProvider`、`ItemTagProvider`、`EntityTypeTagProvider`、`FluidTagProvider` …） | `tags/` |
| `FabricCodecDataProvider` | codec 驱动的 json（`damage_type`、`enchantment` 等） |
| `FabricDynamicRegistryProvider` | 动态注册表内容 |

**1.21.1 没有 `FabricBlockStateModelProvider`**（那是 1.21.4+ 拆分出来的）；方块状态模型通过 `FabricModelProvider#generateBlockStateModels(BlockStateModelGenerator)` 输出。

### 9.3 模型 provider

```java
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;
import net.minecraft.data.client.BlockStateModelGenerator;
import net.minecraft.data.client.ItemModelGenerator;
import net.minecraft.data.client.Models;

public class ExampleModelProvider extends FabricModelProvider {

    public ExampleModelProvider(FabricDataOutput output) {
        super(output);
    }

    @Override
    public void generateBlockStateModels(BlockStateModelGenerator gen) {
        gen.registerSimpleCubeAll(ModBlocks.RUBY_BLOCK);
    }

    @Override
    public void generateItemModels(ItemModelGenerator gen) {
        gen.register(ModItems.RUBY, Models.GENERATED);
    }
}
```

### 9.4 语言 provider

```java
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;
import net.minecraft.registry.RegistryWrapper;
import java.util.concurrent.CompletableFuture;

public class ExampleLangProvider extends FabricLanguageProvider {

    public ExampleLangProvider(FabricDataOutput output,
                               CompletableFuture<RegistryWrapper.WrapperLookup> registries) {
        super(output, registries);        // 默认 en_us；要别的语言用三参构造
    }

    @Override
    public void generateTranslations(RegistryWrapper.WrapperLookup lookup,
                                     TranslationBuilder builder) {
        builder.add(ModItems.RUBY, "Ruby");
        builder.add(ModBlocks.RUBY_BLOCK, "Block of Ruby");
        builder.add("itemGroup.examplemod.ruby", "Ruby Items");
        builder.add("key.examplemod.ruby", "Ruby Key");
    }
}
```

1.21.1 的 `generateTranslations` 是两参（lookup + builder）；后续版本改成只传 builder。构造函数需要 `CompletableFuture<RegistryWrapper.WrapperLookup>`。

### 9.5 战利品表 provider

```java
import net.fabricmc.fabric.api.datagen.v1.provider.FabricBlockLootTableProvider;

public class ExampleLootTableProvider extends FabricBlockLootTableProvider {

    public ExampleLootTableProvider(FabricDataOutput output) { super(output); }

    @Override
    public void generate() {
        addDrop(ModBlocks.RUBY_BLOCK);
    }
}
```

### 9.6 标签 provider

```java
import net.fabricmc.fabric.api.datagen.v1.provider.FabricTagProvider;
import net.minecraft.registry.RegistryWrapper;
import net.minecraft.registry.tag.ItemTags;
import java.util.concurrent.CompletableFuture;

public class ExampleTagProvider extends FabricTagProvider.ItemTagProvider {

    public ExampleTagProvider(FabricDataOutput output,
                              CompletableFuture<RegistryWrapper.WrapperLookup> registries) {
        super(output, registries);
    }

    @Override
    protected void configure(RegistryWrapper.WrapperLookup lookup) {
        getOrCreateTagBuilder(ItemTags.SWORDS).add(ModItems.RUBY);
    }
}
```

- `FabricTagProvider<T>` 的抽象方法是 `configure(RegistryWrapper.WrapperLookup)`。
- 直接用 `FabricTagProvider<Item>` 时需要自己覆写 `reverseLookup(...)`，否则 `.add(对象)` 抛 `UnsupportedOperationException`；用嵌套的 `ItemTagProvider`/`BlockTagProvider` 就没这个问题。
- `getOrCreateTagBuilder` 返回 `FabricTagBuilder`，支持 `add(...)`、`addTag(...)`、`setReplace(true)`。

### 9.7 配方 / 进度

```java
public class ExampleRecipeProvider extends FabricRecipeProvider {

    public ExampleRecipeProvider(FabricDataOutput output,
                                 CompletableFuture<RegistryWrapper.WrapperLookup> registries) {
        super(output, registries);
    }

    @Override
    protected RecipeProvider generateRecipes(RecipeExporter exporter) {
        // 1.21.1 的 RecipeProvider 体系仍基于 RecipeExporter；
        // 具体型别（ShapedRecipe / ShapelessRecipe / StonecuttingRecipe）按需构造
        return new RecipeProvider(exporter);
    }
}
```

1.21 起配方开始 codec 化，不同 `Recipe` 子类的构造参数变化较大；实现时直接对照原版 `ShapedRecipe.Serializer` 与 `RecipeProvider` 的现有方法，不要照抄旧版教程。

### 9.8 Gradle 配置

```gradle
loom {
    runs {
        datagen {
            inherit client                 // 也可以继承 server
            name "Data Generation"
            vmArg "-Dfabric-api.datagen"
            vmArg "-Dfabric-api.datagen.output-dir=${file('src/main/generated')}"
            vmArg "-Dfabric-api.datagen.modid=examplemod"
            vmArg "-Dfabric-api.datagen.strict-validation"
            runDir "build/datagen"
        }
    }
}

sourceSets {
    main {
        resources {
            srcDirs += ['src/main/generated']
        }
    }
}
```

- 新版 Loom 可能自动生成 `runDatagen`；没有 `datagen` 任务时用上面的显式 `runs` 块。
- 输出目录 `src/main/generated` 必须加入 `main` 的 resources，否则生成的数据不会被打进 jar。
- 生成物是**源码树的一部分**：提交前 review 生成结果，不要手动改生成文件。
- 想强制所有条目都有数据：加 `-Dfabric-api.datagen.strict-validation`。

---

## 10. 资源与数据路径（1.21.1）

### 10.1 目录树

```text
src/main/resources/
├── fabric.mod.json
├── examplemod.mixins.json
├── examplemod.accesswidener
└── assets/examplemod/
    ├── icon.png
    ├── lang/en_us.json
    ├── blockstates/ruby_block.json
    ├── models/block/ruby_block.json
    ├── models/item/ruby.json
    ├── models/item/ruby_block.json
    ├── textures/block/ruby_block.png
    ├── textures/item/ruby.png
    └── sounds.json

src/main/resources/data/examplemod/
├── recipe/ruby_block.json          # 1.21.1 是单数
├── advancement/ruby.json
├── loot_table/blocks/ruby_block.json
├── tags/item/ruby.json
└── tags/block/ruby.json

src/client/resources/
├── fabric.mod.json?                # 不要：元数据只有一份
└── examplemod.client.mixins.json
```

### 10.2 1.21.1 的目录名（易错）

| 内容 | 1.21.1 路径 | 备注 |
| --- | --- | --- |
| 配方 | `data/<id>/recipe/` | 单数；1.21 之前是 `recipes/` |
| 进度 | `data/<id>/advancement/` | 单数 |
| 战利品表 | `data/<id>/loot_table/` | 单数；方块表放 `loot_table/blocks/` |
| 标签 | `data/<id>/tags/item|block|entity_type|fluid/` | 1.21 之前是 `tags/items/` 等复数 |
| 物品组 | 无需数据文件，代码注册 | — |

### 10.3 `pack.mcmeta`

Loom 会在构建时向 jar 注入一个 `pack.mcmeta`（包含 `pack_format`），一般不需要手写。需要自己控制时：

```json
{
  "pack": {
    "pack_format": 34,
    "description": "Example Mod Resources"
  }
}
```

`pack_format` 规则（1.21/1.21.1）：资源包 `34`，数据包 `48`。同一个 `pack.mcmeta` 会被资源包与数据包共用，Loom 按 `pack_format` 选值；写错会显示「不兼容的资源包」或数据包被跳过。1.21.2+ 改成 42/57，不要混用。

### 10.4 命名对应关系

- 物品 `examplemod:ruby` → `assets/examplemod/models/item/ruby.json` + `textures/item/ruby.png`。
- 方块 `examplemod:ruby_block` → `blockstates/ruby_block.json`、`models/block/ruby_block.json`、`textures/block/ruby_block.png`，另需物品模型 `models/item/ruby_block.json`（指向方块模型）。
- 翻译键默认由 ID 推导：`item.examplemod.ruby`、`block.examplemod.ruby_block`；物品组用自定义的 `itemGroup.examplemod.ruby`。

---

## 11. 客户端

### 11.1 客户端入口与按键

```java
package com.example.examplemod.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;
import com.example.examplemod.network.RubySyncPayload;

public class ExampleModClient implements ClientModInitializer {

    public static KeyBinding RUBY_KEY;

    @Override
    public void onInitializeClient() {
        RUBY_KEY = KeyBindingHelper.registerKeyBinding(new KeyBinding(
            "key.examplemod.ruby",       // 翻译键
            InputUtil.Type.KEYSYM,
            GLFW.GLFW_KEY_R,
            "category.examplemod"        // 分类翻译键
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (RUBY_KEY.wasPressed()) {
                if (client.player != null) {
                    ClientPlayNetworking.send(new RubySyncPayload(1));
                }
            }
        });
    }
}
```

客户端按键用 `wasPressed()` 的 `while` 循环消费（一 tick 内可能多次）；不要用 `isPressed()` 做边沿触发。

分类键 `category.examplemod` 必须存在于 lang 文件，否则按键设置里显示原始键名。

### 11.2 HUD 渲染（1.21.1）

```java
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;

HudRenderCallback.EVENT.register((drawContext, tickCounter) -> {
    // DrawContext 绘制；tickCounter 是 RenderTickCounter
    drawContext.drawText(
        net.minecraft.client.MinecraftClient.getInstance().textRenderer,
        "Ruby: " + 1, 10, 10, 0xFFFFFF, false);
});
```

**重要**：1.21.1 用 `HudRenderCallback`（`net.fabricmc.fabric.api.client.rendering.v1`），签名是 `onHudRender(DrawContext, RenderTickCounter)`。
`HudLayerRegistrationCallback` + `LayeredDraw` 是 **1.21.2+** 才引入的 API（对应原版 HUD 分层改造），1.21.1 里不存在，写了会 `NoClassDefFoundError`。

### 11.3 渲染注册

```java
import net.fabricmc.fabric.api.client.rendering.v1.ColorProviderRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.EntityRendererRegistry;
import net.fabricmc.fabric.api.blockrenderlayer.v1.BlockRenderLayerMap;
import net.minecraft.client.render.RenderLayer;

// 实体渲染器
EntityRendererRegistry.register(ModEntities.RUBY_GOLEM, RubyGolemRenderer::new);

// 方块渲染层（必须在客户端初始化阶段、世界渲染之前）
BlockRenderLayerMap.INSTANCE.putBlock(ModBlocks.RUBY_BLOCK, RenderLayer.getCutout());

// 方块/物品着色（tint）
ColorProviderRegistry.BLOCK.register(
    (state, world, pos, tintIndex) -> 0xB4003C, ModBlocks.RUBY_BLOCK);
```

- `BlockRenderLayerMap` 在 `net.fabricmc.fabric.api.blockrenderlayer.v1`，注意是 `.INSTANCE.putBlock(...)`，不是静态方法。
- `ColorProviderRegistry` 有 `BLOCK` 与 `ITEM` 两个注册器。
- 方块实体渲染器用 `BlockEntityRendererRegistry.register(type, factory)`。

### 11.4 `ScreenHandler` + `Screen`

服务端（common）：

```java
import net.fabricmc.fabric.api.screenhandler.v1.ExtendedScreenHandlerType;
import net.minecraft.screen.ScreenHandlerType;

public static final ExtendedScreenHandlerType<RubyScreenHandler, RubyScreenData> RUBY_SCREEN =
    new ExtendedScreenHandlerType<>(
        (syncId, inventory, data) -> new RubyScreenHandler(syncId, inventory, data),
        RubyScreenData.PACKET_CODEC);

Registry.register(Registries.SCREEN_HANDLER, Identifier.of(MOD_ID, "ruby"), RUBY_SCREEN);
```

```java
import net.minecraft.network.RegistryByteBuf;
import net.minecraft.network.codec.PacketCodec;
import net.minecraft.network.codec.PacketCodecs;

public record RubyScreenData(int value) {
    public static final PacketCodec<RegistryByteBuf, RubyScreenData> PACKET_CODEC =
        PacketCodec.tuple(PacketCodecs.VAR_INT, RubyScreenData::value, RubyScreenData::new);
}
```

开屏数据 record 需要一个 `PacketCodec<RegistryByteBuf, D>`；`PacketCodec.tuple(...)` 的用法就是「字段 codec + getter + 构造器」，与上例一致。**不要**用 `CustomPayload.codecOf` 给非 payload 类型做 codec，那个工厂只接受 `CustomPayload` 子类型。

`ScreenHandler` 构造器必须存在 `(int syncId, PlayerInventory inventory)`（给 `ScreenHandlerType` 用）以及扩展版的 `(int, PlayerInventory, D)`；客户端 `Screen` 通过 `HandledScreens.register(RUBY_SCREEN, RubyScreen::new)` 绑定。

打开界面：服务端用 `ExtendedScreenHandlerFactory<RubyScreenData>` + `player.openHandledScreen(factory)`（`openHandledScreen` 只在 `ServerPlayerEntity` 上有效）。

`ExtendedScreenHandlerType` 的核心用途就是把额外的开屏数据（如方块坐标、自定义配置）编码后同步到客户端。

---

## 12. 与 NeoForge / Forge 的差异

| 维度 | Fabric 1.21.1 | NeoForge 1.21.1 / Forge |
| --- | --- | --- |
| 元数据文件 | `fabric.mod.json` | `META-INF/neoforge.mods.toml` / `META-INF/mods.toml` |
| 入口 | `ModInitializer` / `ClientModInitializer`（入口点声明在 json） | `@Mod` 注解类 + 构造器注入 `IEventBus` / `ModContainer` |
| 注册 | `Registry.register(Registries.X, id, obj)`，静态字段或 `onInitialize` | `DeferredRegister` + `RegistryEvent`/`RegisterEvent`，`DeferredHolder` |
| 事件模型 | 回调注册（`SomeEvent.register(...)`），事件对象是普通类字段 | 事件总线（`@SubscribeEvent` + `IEventBus`，有 mod bus / game bus 之分），可取消事件用 `Event` 子类 |
| 网络 | payload 制：`CustomPayload` + `PayloadTypeRegistry` + `ServerPlayNetworking` | `CustomPacketPayload` + `PayloadRegistrar`（`RegisterPayloadHandlersEvent`）+ `PacketDistributor` |
| 数据附加 | `AttachmentRegistry`（`AttachmentType`） | `AttachmentType`（NeoForge 自带，`AttachmentRegistry.create`）/ Forge 用 Capability |
| 物品数据 | `DataComponentType` | 同名 `DataComponentType`（NeoForge 也走组件） |
| 访问拓宽 | `accessWidener`（`.accesswidener`）+ Loom | Access Transformer（`accesstransformer.cfg`）/ `@Accessors`? 实际是 AT 配置 |
| 配置系统 | **无内置**，用 Cloth Config / 自写 JSON + `SimpleResourceReloadListener` | `ModConfigSpec` / `ModConfig`（`ConfigScreenHandler` 等） |
| Mixin | 原生支持，Loom 生成 refmap | 同为 Mixin，另有 `@EventBusSubscriber` 等便利注解 |
| 数据生成 | `FabricDataGenerator` + `fabric-datagen` 入口 | `DataGenerator` + `GatherDataEvent` |
| 客户端注册 | 各 `...Registry` 静态注册器（`EntityRendererRegistry` 等） | `EntityRenderers.register` / `RegisterClientRenderersEvent` |
| 依赖嵌入 | `include`（JiJ） | `jarJar`（NeoForge）/ Shadow |

要点：

- Fabric 没有内置配置 API。常见做法：Cloth Config（`AutoConfig` + GUI）+ 自写 `ConfigManager` 读写 `config/<modid>.json`（用 Gson，路径 `FabricLoader.getInstance().getConfigDir()`）。
- Fabric 的 “Capability” 等价物是 `AttachmentRegistry`；`AttachmentType` 可以挂在 `ItemStack`、`Entity`、`BlockEntity`、`Level`、`Chunk` 上，并可 `persistent(codec)` / `syncWith(...)`。
- Forge 的 `RegistryEvent` 是「注册表事件」，Fabric 没有；Fabric 用注册表 API 直接注册。

---

## 13. 常见坑与排查

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| `Identifier` 构造器不可用 | 1.21 起构造器私有 | 用 `Identifier.of(namespace, path)` / `Identifier.of(path)` / `Identifier.ofVanilla(path)` |
| 物品/方块在游戏里是 `minecraft:air` 或不存在 | 注册发生在类加载之后，或类从未被初始化 | 在 `onInitialize()` 里显式调用 `ModRegistry.init()`；确认静态字段所在类被引用 |
| 专用服务器 `NoClassDefFoundError: net/minecraft/client/...` | common 代码引用了客户端类 | 客户端代码放 `src/client/java`，或用 `@Environment(EnvType.CLIENT)` + 环境判断 |
| 启动报 `fabric.mod.json` 解析失败 | 缺 `schemaVersion` / `version` 非法 / JSON 语法错 | 必须有 `"schemaVersion": 1`；`version` 用 `processResources` 展开；用 JSON 校验器 |
| Mixin 注入失败但编译通过 | 方法名或描述符不匹配、映射混用、refmap 未生成 | `-Dmixin.debug.export=true` 导出字节码；`genSources` 核对名字；确认没手写 `refmap` |
| `NoClassDefFoundError: net/fabricmc/fabric/api/...` | 没依赖 `fabric-api` 或在 mod 里没声明 | `modImplementation` 引入 + `fabric.mod.json` 的 `depends` 写 `fabric-api` |
| 拆分 sourceSet 后报「包不存在」 | 客户端代码仍写在 `src/main/java` | 客户端类移到 `src/client/java`，包名保持一致；`loom { mods { ... sourceSet sourceSets.client } }` |
| JiJ 后运行期缺依赖 | `include` 只嵌一层，传递依赖缺失 | 逐个 `include` 传递依赖，或 Shadow 打 fat jar 再 `include` |
| Loom 与 Java 版本报错 | Gradle 用的 JDK 不是 21 / 未设 toolchain | 设 `java.toolchain` 与 `options.release = 21`；`./gradlew -v` 确认 JVM |
| `runDatagen` 任务不存在 | Loom 未生成 datagen run config | 在 `loom { runs { datagen { ... } } }` 显式声明；确认 `fabric-datagen` 入口已在 `fabric.mod.json` |
| 生成的数据没进 jar | 输出目录没加到 resources | `sourceSets.main.resources.srcDirs += ['src/main/generated']` |
| 网络包发不出去 / 收不到 | 类型没注册、只注册了一端、在错误线程调用 | 两端都 `register`；服务端收包注册 `playC2S`、发包注册 `playS2C`；客户端发包在主线程 |
| 发包报 `IllegalArgumentException` | 先注册 receiver 后注册类型 | 先 `PayloadTypeRegistry.register`，再 `registerGlobalReceiver` |
| HUD 写法报 `NoClassDefFoundError: .../HudLayerRegistrationCallback` | 用了 1.21.2+ 的 API | 1.21.1 用 `HudRenderCallback` |
| 方块没有模型（紫黑格） | 缺 `blockstates/*.json` 或 `models/block/*.json` | 用 `FabricModelProvider` 生成，或手写两个 json + 贴图 |
| 配方/战利品表不加载 | 目录用了复数（`recipes/`、`loot_tables/`） | 1.21.1 用单数 `recipe/`、`loot_table/`、`advancement/` |
| 资源包提示不兼容 | `pack_format` 写错 | 1.21.1 资源包 34、数据包 48 |
| 玩家进出服事件找不到 | 以为有 `PlayerEvents.JOIN` | 用 `ServerPlayConnectionEvents.JOIN` / `DISCONNECT` |
| 服务端启动即崩在 `onInitialize` 访问世界 | 初始化时世界/玩家不存在 | 移到 `ServerLifecycleEvents.SERVER_STARTING`/`STARTED` |
| `FabricBlockEntityTypeBuilder` 有删除警告 | 1.21.1 已废弃 | 改 `BlockEntityType.Builder.create(...).build()` |
| 按键注册报 `IllegalArgumentException` | 同一 ID 注册了两次 | 检查是否在 `onInitializeClient` 里重复注册；ID 唯一 |
| 物品组里没有自己的物品 | 只注册了物品，没加进组 | `ItemGroupEvents.modifyEntriesEvent(...)` 或自建 `FabricItemGroup` |

---

## 14. 官方文档链接

以下链接均已实际访问验证（内容主体对应当前文档版本，**类名/方法名以 1.21.1 源码为准**，文档站默认展示新版本，注意命名差异）：

- 事件：<https://docs.fabricmc.net/develop/events>（可访问；示例代码用 Mojmap 风格命名）
- 网络：<https://docs.fabricmc.net/develop/networking>（可访问；示例按 Mojmap 命名，`CustomPacketPayload`/`StreamCodec` 对应 Yarn 的 `CustomPayload`/`PacketCodec`）
- Fabric 文档首页/开发指南：<https://docs.fabricmc.net/develop/>
- Fabric API 1.21.1 源码（本文件签名核对来源）：<https://github.com/FabricMC/fabric-api/tree/1.21.1>
- Fabric API 0.102.0+1.21.1 Javadoc 索引：<https://maven.fabricmc.net/docs/fabric-api-0.102.0+1.21.1/>
- 官方示例工程（1.21.1 分支，`build.gradle`/`gradle.properties`/`fabric.mod.json`/mixin 配置核对来源）：<https://github.com/FabricMC/fabric-example-mod/tree/1.21.1>
- 版本查询（选 Loader/API/Yarn 版本）：<https://fabricmc.net/develop/>

不可用/已变更的链接（记录备查）：

- `https://docs.fabricmc.net/1.21.1/develop/...`：不存在对应路径（站点不提供按版本切分的旧文档），返回空页面。
- `https://docs.fabricmc.net/develop/blocks/first-block`、`/develop/items/first-item`、`/develop/data-generation/setup`：本次未作为事实来源（内容随文档版本变化，且示例为 Mojmap 命名）；注册与数据生成的具体签名改为直接核对 1.21.1 源码与官方示例工程。
