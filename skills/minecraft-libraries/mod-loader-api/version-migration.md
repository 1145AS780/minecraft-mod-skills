# 版本差异与迁移对照

先用本页确认版本、映射和破坏性变更，再进入具体平台参考文件。版本号必须成组对齐：MC 版本、加载器版本、API 依赖、Java 版本、映射，只改其中一个是崩溃与 `NoSuchMethodError` 的主要来源。

## 1. 版本矩阵

| MC | Java | 数据包 pack_format | 资源包 pack_format | Paper `api-version` | Forge | NeoForge | Fabric |
|---|---|---|---|---|---|---|---|
| 1.20.1 | 17 | 15 | 15 | `1.20` | 47.x（本文用 47.4.10） | 47.1.x | Loader 0.14–0.16，API 0.92.x+1.20.1 |
| 1.20.2 | 17 | 18 | 18 | `1.20` | 48.x | 20.2.x | 0.14–0.16 |
| 1.20.4 | 17 | 26 | 22 | `1.20` | 49.x | 20.4.x | 0.15+ |
| 1.20.5 | 21 | 41 | 32 | `1.20` | 50.x | 20.5.x | 0.15+ |
| 1.20.6 | 21 | 41 | 32 | `1.20` | 51.x | 20.6.x | 0.15+ |
| 1.21 | 21 | 48 | 34 | `1.21` | 52.x | 21.0.x | 0.15+ |
| 1.21.1 | 21 | 48 | 34 | `1.21` | 52.x | 21.1.x（本文用 21.1.264） | 0.16.x / API 0.102.x+1.21.1 |

容易记错的点：

- 1.20.1 **有** NeoForge（47.1.x，是 Forge 47 的分叉），不是“只有 Forge”。
- Forge 1.21.1 也存在（52.x），只是生态与文档远少于 NeoForge，本库默认用 NeoForge 讲 1.21.1。
- `api-version` 只写大版本（`1.20` / `1.21`），写 `1.21.1` 会被当非法值。
- 1.20.5 起 Java 要求从 17 抬到 21，这是 1.20.4 → 1.20.5 迁移最常见的失败点。

## 2. 依赖坐标

### Paper

```kotlin
compileOnly("io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT")
compileOnly("io.papermc.paper:paper-api:1.20.1-R0.1-SNAPSHOT")
```

### Forge（ForgeGradle 6）

```groovy
minecraft {
    mappings channel: 'official', version: '1.20.1'
    // 1.21.1 用: mappings channel: 'official', version: '1.21.1'
}
dependencies {
    minecraft 'net.minecraftforge:forge:1.20.1-47.4.10'
    // 1.21.1 用: minecraft 'net.minecraftforge:forge:1.21.1-52.0.x'
}
```

### NeoForge（ModDevGradle 2.0.x）

```groovy
neoForge {
    version = '21.1.264'
    parchment {
        minecraftVersion = '1.21.1'
        mappingsVersion = '2024.11.17'
    }
}
```

### Fabric（Loom 1.7）

```properties
minecraft_version=1.21.1
yarn_mappings=1.21.1+build.3
loader_version=0.16.9
fabric_version=0.102.0+1.21.1
```

## 3. Java 与字节码

| MC | 最低 Java | class 文件版本 | Gradle toolchain 建议 |
|---|---|---|---|
| 1.20.1 | 17 | 61 | `JavaLanguageVersion.of(17)` |
| 1.20.5+ | 21 | 65 | `JavaLanguageVersion.of(21)` |
| 1.21.1 | 21 | 65 | 21（JDK 22–26 可能让 Gradle/ForgeGradle 报错） |

- 用 Java 21 编译的插件/模组无法在 1.20.1（Java 17）服务器加载：`UnsupportedClassVersionError`。
- ForgeGradle 6 在 JDK 21+ 下常报 `Unsupported class file major version`（Gradle 自身字节码问题），用 JDK 17 跑 Gradle；NeoForge ModDevGradle 用 JDK 21。
- PATH 上的默认 `java` 未必是目标版本，构建前显式把 `JAVA_HOME` 指向对应 JDK（Forge 1.20.1 用 17，NeoForge 1.21.1 用 21）。

## 4. Forge 1.20.1 → NeoForge 1.21.1

### 4.1 包与类

| Forge 1.20.1 | NeoForge 1.21.1 |
|---|---|
| `net.minecraftforge.*` | `net.neoforged.*` |
| `net.minecraftforge.fml.common.Mod` | `net.neoforged.fml.common.Mod` |
| `net.minecraftforge.fml.common.Mod.EventBusSubscriber` | `net.neoforged.fml.common.EventBusSubscriber` |
| `net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext` | 构造函数注入 `net.neoforged.bus.api.IEventBus` |
| `net.minecraftforge.common.MinecraftForge.EVENT_BUS` | `net.neoforged.neoforge.common.NeoForge.EVENT_BUS` |
| `net.minecraftforge.registries.ForgeRegistries` | `net.neoforged.neoforge.registries.NeoForgeRegistries`（原版注册表用 `BuiltInRegistries`） |
| `net.minecraftforge.registries.DeferredRegister` | `net.neoforged.neoforge.registries.DeferredRegister` |
| `net.minecraftforge.registries.RegistryObject` | `DeferredHolder` / `DeferredItem` / `DeferredBlock` |
| `net.minecraftforge.common.ForgeConfigSpec` | `net.neoforged.neoforge.common.ModConfigSpec` |
| `net.minecraftforge.network.simple.SimpleChannel` | `PayloadRegistrar`（`RegisterPayloadHandlersEvent`） |
| `net.minecraftforge.network.NetworkRegistry` | `net.neoforged.neoforge.network.registration.NetworkRegistry`（一般不直接用） |
| `net.minecraftforge.common.capabilities.Capability` | `AttachmentType` / `DataComponentType` / `Capabilities` |
| `net.minecraftforge.eventbus.api.SubscribeEvent` | `net.neoforged.bus.api.SubscribeEvent` |
| `net.minecraftforge.eventbus.api.EventPriority` | `net.neoforged.bus.api.EventPriority` |
| `net.minecraftforge.api.distmarker.Dist` / `@OnlyIn` | `net.neoforged.api.distmarker.Dist` / `@OnlyIn` |

### 4.2 描述文件

| Forge | NeoForge |
|---|---|
| `src/main/resources/META-INF/mods.toml` | `src/main/resources/META-INF/neoforge.mods.toml` |
| `modLoader = "javafml"` | `modLoader = "javafml"`（不变） |
| `[[dependencies.modid]]` 中 `mandatory = true` | `type = "required"`（`"optional"` / `"incompatible"` / `"discouraged"`） |
| `versionRange = "[47,)"` | `versionRange = "[21.1,)"`（loader 用 `loader_version_range=[1,)`） |
| `displayTest = "IGNORE_ALL_VERSION"` | `displayTest = "IGNORE_ALL_VERSION"`（字段保留，行为有差异） |

### 4.3 主类与初始化

Forge 1.20.1：

```java
@Mod("mymod")
public class MyMod {
    public MyMod() {
        IEventBus modBus = FMLJavaModLoadingContext.get().getModEventBus();
        ModItems.register(modBus);
        modBus.addListener(this::commonSetup);
    }
    private void commonSetup(FMLCommonSetupEvent event) { }
}
```

NeoForge 1.21.1：

```java
@Mod("mymod")
public class MyMod {
    public MyMod(IEventBus modBus, ModContainer container) {
        ModItems.register(modBus);
        modBus.addListener(this::commonSetup);
        container.registerConfig(ModConfig.Type.COMMON, Config.SPEC);
    }
    private void commonSetup(FMLCommonSetupEvent event) { }
}
```

要点：

- NeoForge 不再有 `FMLJavaModLoadingContext`，构造器参数注入是唯一正规方式。
- 构造函数参数顺序不限，按类型注入；`IEventBus` 是 mod 总线，`ModContainer` 是本 mod 容器。
- `ModLoadingContext.get()` 在 NeoForge 仍存在，但推荐用注入的 `ModContainer`。
- `@Mod.EventBusSubscriber` 改名 `@EventBusSubscriber`，`bus = EventBusSubscriber.Bus.MOD` 才是 mod 总线（默认是 game 总线）。

### 4.4 总线对照

| 事件 | Forge 1.20.1 | NeoForge 1.21.1 |
|---|---|---|
| `FMLCommonSetupEvent` | mod bus | mod bus |
| `FMLClientSetupEvent` | mod bus | mod bus |
| `RegisterEvent` | mod bus | mod bus |
| `EntityAttributeCreationEvent` | mod bus | mod bus |
| `BuildCreativeModeTabContentsEvent` | mod bus（`CreativeModeTabEvent.BuildContents`） | mod bus |
| `ServerStartingEvent` | `MinecraftForge.EVENT_BUS` | `NeoForge.EVENT_BUS` |
| `PlayerTickEvent` / `LevelTickEvent` | `MinecraftForge.EVENT_BUS` | `NeoForge.EVENT_BUS` |
| `LivingDamageEvent` | `MinecraftForge.EVENT_BUS` | `NeoForge.EVENT_BUS` |
| `RegisterCommandsEvent` | `MinecraftForge.EVENT_BUS` | `NeoForge.EVENT_BUS` |

写错总线的表现：事件监听器注册成功但永远不触发，或启动时抛 `IllegalArgumentException: Bus not found`。

### 4.5 网络迁移

Forge 1.20.1（`SimpleChannel`，实际包名 `net.minecraftforge.network.simple.SimpleChannel`）：

```java
private static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
    new ResourceLocation("mymod", "main"),
    () -> "1.0", s -> true, s -> true);

CHANNEL.registerMessage(0, MyPacket.class,
    MyPacket::encode, MyPacket::decode, MyPacket::handle);
CHANNEL.sendToServer(new MyPacket(...));
CHANNEL.send(PacketDistributor.PLAYER.with(() -> player), new MyPacket(...));
```

NeoForge 1.21.1（payload）：

```java
@SubscribeEvent
static void register(RegisterPayloadHandlersEvent event) {
    PayloadRegistrar registrar = event.registrar("1");   // 版本号
    registrar.playToServer(MyPayload.TYPE, MyPayload.STREAM_CODEC, ServerHandler::handle);
    registrar.playToClient(MyPayload.TYPE, MyPayload.STREAM_CODEC, ClientHandler::handle);
}
```

对照要点：

| Forge | NeoForge |
|---|---|
| `SimpleChannel#registerMessage(id, ...)` | `PayloadRegistrar#playToServer/playToClient/playBidirectional` |
| `encode/decode` 手写 | `StreamCodec`（`StreamCodec.composite`） |
| `Channel#sendToServer` | `PacketDistributor.sendToServer(payload)` |
| `PacketDistributor.PLAYER.with(...)` | `PacketDistributor.sendToPlayer(player, payload)` |
| 无版本协商 | 需要时 `registrar.versioned("1")` |
| 无 optional | `registrar.optional()` 允许缺失 mod 的客户端连接 |

### 4.6 Capability → Attachment / DataComponent

| Forge 1.20.1 | NeoForge 1.21.1 |
|---|---|
| `Capability<T>` + `CapabilityManager.get(new CapabilityToken<>(){})` | `AttachmentType<T>`（实体/区块/等级）或 `DataComponentType<T>`（物品） |
| `AttachCapabilitiesEvent<ItemStack>` | 物品用 DataComponent，或用 `RegisterCapabilitiesEvent` 注册 `IItemHandler` |
| `LazyOptional<T>` | 直接 `getData(...)`，无 Optional 包装 |
| `IItemHandler` 存在 | 仍是 `IItemHandler`，通过 `Capabilities.ItemHandler.BLOCK` 获取 |
| `level.getCapability(Capabilities.ItemHandler.BLOCK, pos, side)` | `level.getCapability(Capabilities.ItemHandler.BLOCK, pos, side)`（NeoForge 侧常量在 `Capabilities`） |

能力常量在 NeoForge 是 `net.neoforged.neoforge.capabilities.Capabilities`，Forge 是 `net.minecraftforge.common.capabilities.ForgeCapabilities`。

### 4.7 配置迁移

```java
// Forge 1.20.1
ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, Config.SPEC);

// NeoForge 1.21.1
container.registerConfig(ModConfig.Type.COMMON, Config.SPEC);
```

`ForgeConfigSpec.Builder` 与 `ModConfigSpec.Builder` 的 `define/defineInRange/defineEnum/defineList` 用法基本相同；类名、包名和注册入口不同。`ModConfigSpec` **没有** `defineMap`，需要 map 时用 `defineList` 或自定义 codec。

### 4.8 事件迁移细节

| Forge 1.20.1 | NeoForge 1.21.1 | 说明 |
|---|---|---|
| `TickEvent.PlayerTickEvent` | `PlayerTickEvent.Post` / `.Pre` | 不再是带 phase 的单一类 |
| `TickEvent.LevelTickEvent` | `LevelTickEvent.Post` / `.Pre` | 同上 |
| `TickEvent.ServerTickEvent` | `ServerTickEvent.Post` / `.Pre` | 同上 |
| `LivingHurtEvent` | 无直接等价，用 `LivingDamageEvent.Pre` 或 `LivingIncomingDamageEvent` | 语义按伤害计算阶段拆分 |
| `LivingDamageEvent` | `LivingDamageEvent.Pre` / `.Post` | |
| `CreativeModeTabEvent.BuildContents` | `BuildCreativeModeTabContentsEvent` | |
| `RegisterMenuScreensEvent`（Forge 无） | `RegisterMenuScreensEvent`（NeoForge 有） | Forge 用 `FMLClientSetupEvent#enqueueWork` + `MenuScreens.register` |
| `RegisterKeyMappingsEvent`（Forge 有） | `RegisterKeyMappingsEvent`（NeoForge 有） | 两边都在 mod bus |
| `EntityJoinLevelEvent` | `EntityJoinLevelEvent` | 包名变为 `net.neoforged.neoforge.event.entity` |

### 4.9 迁移顺序

1. 换构建：NeoGradle/ModDevGradle、`neo_version=21.1.x`、Java 21。
2. 重命名描述文件为 `neoforge.mods.toml`，改依赖 `type`。
3. 全局替换 `net.minecraftforge` → `net.neoforged`，编译，逐个修。
4. 改主类构造器注入、配置注册、`@EventBusSubscriber`。
5. 重写网络层为 payload。
6. 把物品 NBT 改 DataComponents，Capability 改 Attachment/DataComponent。
7. 处理 tick/damage 事件拆分、`RegistryObject`→`DeferredHolder`。
8. 跑 `runData` 重新生成资源，再 `runClient` 验证。

## 5. 1.20.1 → 1.21.1 原版破坏性变更

### 5.1 物品数据：NBT → DataComponents

1.20.1：

```java
ItemStack stack = new ItemStack(Items.DIAMOND_SWORD);
CompoundTag tag = stack.getOrCreateTag();
tag.putString("owner", "steve");
tag.putInt("level", 5);
String owner = stack.getTag().getString("owner");
```

1.21.1：

```java
ItemStack stack = new ItemStack(Items.DIAMOND_SWORD);
// 自定义数据统一放 CUSTOM_DATA（CustomData）
stack.set(DataComponents.CUSTOM_DATA, CustomData.of(compound));
CompoundTag tag = stack.get(DataComponents.CUSTOM_DATA).copyTag();

// 原版组件直接读写
stack.set(DataComponents.CUSTOM_NAME, Component.literal("Excalibur"));
int damage = stack.getOrDefault(DataComponents.DAMAGE, 0);
stack.set(DataComponents.ENCHANTMENTS, ...);
```

| 1.20.1 NBT | 1.21.1 组件 |
|---|---|
| `tag.display.Name` | `DataComponents.CUSTOM_NAME` |
| `tag.display.Lore` | `DataComponents.LORE` |
| `tag.Enchantments` | `DataComponents.ENCHANTMENTS` |
| `tag.StoredEnchantments` | `DataComponents.STORED_ENCHANTMENTS` |
| `tag.AttributeModifiers` | `DataComponents.ATTRIBUTE_MODIFIERS` |
| `tag.CustomModelData` | `DataComponents.CUSTOM_MODEL_DATA` |
| `tag.Unbreakable` | `DataComponents.UNBREAKABLE` |
| `tag.Damage` | `DataComponents.DAMAGE` |
| `tag.HideFlags` | `DataComponents.HIDE_FLAGS` 或各组件 `show_*` |
| `tag.display.color` | `DataComponents.DYED_COLOR` |
| `tag.SkullOwner` | `DataComponents.PROFILE` |
| `tag.BlockEntityTag`（容器） | `DataComponents.CONTAINER` |
| `tag.Potion` | `DataComponents.POTION_CONTENTS` |
| 自定义键 | `DataComponents.CUSTOM_DATA` + `CustomData` |

判断“是否有自定义数据”用 `stack.has(DataComponents.CUSTOM_DATA)`，不要再用 `hasTag()`。

### 5.2 附魔与药水效果数据驱动

| 主题 | 1.20.1 | 1.21.1 |
|---|---|---|
| 附魔注册 | 代码 `DeferredRegister<Enchantment>` | 数据包 `data/<ns>/enchantment/<id>.json`，代码只引用 `Holder<Enchantment>` |
| 获取附魔 | `ForgeRegistries.ENCHANTMENTS.getValue(id)` | `level.registryAccess().holderOrThrow(Registries.ENCHANTMENT, id)` 或 `Holder` 注入 |
| 附魔等级 | `stack.getEnchantmentLevel(enchantment)` | `stack.getEnchantments().getLevel(holder)` |
| 药水效果 | `MobEffects.SPEED`（静态字段） | `MobEffects.SPEED` 仍是 `Holder<MobEffect>`，但注册表化后自定义效果需注册 |
| 状态效果实例 | `new MobEffectInstance(MobEffects.SPEED, 200, 1)` | 同，但构造器参数类型为 `Holder<MobEffect>` |

1.21 起附魔的 `max_level`、`rarity`、`supported_items`、`primary_items` 全在 JSON 里；代码里新增附魔不再可行（注册表是数据驱动的 `Registry`）。

### 5.3 属性重命名

| 1.20.1 | 1.21.1 |
|---|---|
| `Attribute.GENERIC_MAX_HEALTH` | `Attribute.MAX_HEALTH` |
| `Attribute.GENERIC_ATTACK_DAMAGE` | `Attribute.ATTACK_DAMAGE` |
| `Attribute.GENERIC_MOVEMENT_SPEED` | `Attribute.MOVEMENT_SPEED` |
| `Attribute.GENERIC_ARMOR` | `Attribute.ARMOR` |
| `Attribute.GENERIC_FOLLOW_RANGE` | `Attribute.FOLLOW_RANGE` |
| `Attribute.GENERIC_KNOCKBACK_RESISTANCE` | `Attribute.KNOCKBACK_RESISTANCE` |
| `Attribute.HORSE_JUMP_STRENGTH` | `Attribute.JUMP_STRENGTH` |

规则：1.21 去掉 `GENERIC_` 前缀，改为统一的注册表键 `minecraft:max_health` 等。1.21.2+ 又引入属性上限（`AttributeInstance#getMaxValue`），写死超大值会被裁剪。

### 5.4 物品类构造器

| 类 | 1.20.1 | 1.21.1 |
|---|---|---|
| `SwordItem` | `new SwordItem(Tier, int attackDamage, float attackSpeed, Properties)` | `new SwordItem(Tier, Properties)`，攻击力走 `Properties#attributes(ItemAttributeModifiers)` 或 `SwordItem.createAttributes(tier, damage, speed)` |
| `ArmorItem` | `new ArmorItem(ArmorMaterial, EquipmentSlot, Properties)` | `new ArmorItem(Holder<ArmorMaterial>, ArmorItem.Type, Properties)` |
| `FoodProperties` | `nutrition/saturationModifier/effect/alwaysEdible/fast` | 同名方法仍在（`nutrition`、`saturationModifier`、`effect`、`usingConvertsTo`），但通过 `DataComponents.FOOD` 绑定 |
| `BlockItem` | `new BlockItem(Block, Properties)` | 不变，但 `Item.Properties` 需要 `registryKey`（1.21.1 推荐，1.21.2+ 强制） |
| `MenuType` | `new MenuType<>(supplier)` | `new MenuType<>(supplier, FeatureFlagSet)`，或用 `MenuType.Builder` |

已验证的 1.21.1 签名：`SwordItem(Tier, Item.Properties)`、`SwordItem(Tier, Item.Properties, Tool)`、`ArmorItem(Holder<ArmorMaterial>, ArmorItem.Type, Item.Properties)`、`Item.Properties#attributes(ItemAttributeModifiers)`。

### 5.5 方块实体保存

1.20.1：

```java
@Override
protected void saveAdditional(CompoundTag tag) { super.saveAdditional(tag); }
@Override
public void load(CompoundTag tag) { super.load(tag); }
```

1.21.1：

```java
@Override
protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
    super.saveAdditional(tag, registries);
}
@Override
protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
    super.loadAdditional(tag, registries);
}
```

`HolderLookup.Provider` 是 1.20.5 引入的注册表视图，用来在 NBT 里解析 `Holder`（附魔、物品、效果）。`getUpdateTag(HolderLookup.Provider)` 同样多一个参数，`getUpdatePacket()` 不变。

### 5.6 资源位置与注册表

| 1.20.1 | 1.21.1 |
|---|---|
| `new ResourceLocation(ns, path)` | `ResourceLocation.fromNamespaceAndPath(ns, path)` / `ResourceLocation.parse("ns:path")` |
| `new ResourceLocation("path")` | `ResourceLocation.parse("minecraft:path")`（无命名空间默认 `minecraft`） |
| `Registry.ITEM` | `BuiltInRegistries.ITEM` |
| `ForgeRegistries.ITEMS` | `NeoForgeRegistries.ITEMS`（NeoForge）或 `BuiltInRegistries.ITEM` |
| `Registry.ENCHANTMENT` | `Registries.ENCHANTMENT`（`net.minecraft.core.registries.Registries`） |

`ResourceLocation` 构造器在 1.21 全部私有，旧写法直接编译失败；这是 1.21 迁移报错最多的一处。

### 5.7 数据包与命令

| 主题 | 1.20.1 | 1.21.1 |
|---|---|---|
| 数据包目录 | `functions/`、`recipes/`、`loot_tables/`、`tags/items/`、`advancements/`、`predicates/`、`item_modifiers/` | `function/`、`recipe/`、`loot_table/`、`tags/item/`、`advancement/`、`predicate/`、`item_modifier/` |
| pack_format | 15 | 48 |
| 物品写法 | `{id:"...",Count:1b,tag:{...}}` | `{id:"...",count:1,components:{...}}` |
| `give` 语法 | `give @s diamond_sword{display:{Name:'...'}}` | `give @s diamond_sword[custom_name='...']` |
| 容器内容 | `Items:[{Slot:0b,id:"...",Count:1b}]` | `items:[{slot:0,item:{id:"...",count:1}}]` |
| 实体装备 | `ArmorItems`、`HandItems` | 1.21.1 仍用 `ArmorItems`、`HandItems`（内部物品改成 `{id,count,components}`）；`equipment` 字段是 **1.21.5+** 才引入，不要写进 1.21.1 数据包 |
| 附魔 | `Enchantments:[{id:"sharpness",lvl:3s}]` | `enchantments:{levels:{"minecraft:sharpness":3}}` |
| 属性修饰 | `AttributeModifiers:[{AttributeName:"...",Amount:...,Slot:...}]` | `attribute_modifiers:[{type:"...",amount:...,slot:"mainhand",id:"..."}]` |
| 药水 | `Potion:"minecraft:swiftness"` | `potion_contents:{potion:"minecraft:swiftness"}` |

### 5.8 其他常见变更

- `Component.Serializer` 改为 codec：JSON 结构走 `{"text":"..."}` / `{"translate":...}`，读写用 `ComponentSerialization` 或 `Component.Serializer.CODEC`。
- `Player#sendMessage` → `sendSystemMessage`（服务端发系统消息）；Adventure 侧仍用 `sendMessage`。
- 配方 JSON 全面 codec 化：`RecipeSerializer` 的 `fromJson`/`toJson` 被 `MapCodec`/`StreamCodec` 取代，自定义配方要实现 `RecipeSerializer#codec()` 与 `streamCodec()`。
- `ItemStack#getItem()` 不变，但 `getUseDuration()`、`getFoodProperties()` 等读取路径改走组件。
- `BlockBehaviour.Properties` 的 `randomTicks()`、`noOcclusion()` 等不变；1.21 新增 `requiredFeatures(...)`。
- `GameRules` 新增/移除若干规则；用 `/gamerule` 而不要硬编码索引。
- 1.21.1 的 `Item.Properties#food(FoodProperties)` 已被验证存在，但推荐用 `DataComponents.FOOD`。

## 6. 1.21.1 → 1.21.2+ 前瞻（简表）

以下变更不属于本库重点版本（1.21.1），升级前先确认，不要凭记忆写：

| 主题 | 1.21.1 | 1.21.2+ |
|---|---|---|
| 物品注册 | `Item.Properties` 可不带 `registryKey` | `registryKey` 强制 |
| HUD 渲染（Fabric） | `HudRenderCallback` | `HudLayerRegistrationCallback` / `LayeredDraw` |
| 网络（Fabric） | `CustomPayload` + `PacketCodec` | `CustomPacketPayload` + `StreamCodec` |
| 属性 | 无上限 | `AttributeInstance#getMaxValue` 生效 |
| 物品模型 | `item/generated` 等 | `ItemModel` 定义（`items/*.json`） |

## 7. 跨平台 API 对照

| 任务 | Paper 1.21.1 | NeoForge 1.21.1 | Forge 1.20.1 | Fabric 1.21.1 |
|---|---|---|---|---|
| 发送聊天 | `player.sendMessage(Component)` | `player.sendSystemMessage(Component)` | 同 NeoForge | `player.sendMessage(Text)` |
| 定时任务 | `Bukkit.getScheduler()` / 区域调度器 | `ServerTickEvent.Post` / `Tickable` | `TickEvent.ServerTickEvent` | `ServerTickEvents.END_SERVER_TICK` |
| 注册物品 | 无（插件不改注册表） | `DeferredRegister.Items` | `DeferredRegister<Item>` | `Registry.register(Registries.ITEM, ...)` |
| 监听事件 | `@EventHandler` + `registerEvents` | `@SubscribeEvent` + `@EventBusSubscriber` | 同左，注解在 `Mod.EventBusSubscriber` | 回调 `XXX.EVENT.register(...)` |
| 配置 | `config.yml` + `getConfig()` | `ModConfigSpec` | `ForgeConfigSpec` | 无内置，自行读写 JSON |
| 玩家传送 | `player.teleport(loc)` / `teleportAsync` | `ServerPlayer#teleportTo(...)` | 同 NeoForge | `player.teleport(...)` |
| 播放音效 | `world.playSound(loc, Sound.X, vol, pitch)` | `level.playSound(null, pos, SoundEvents.X, SoundSource.PLAYERS, vol, pitch)` | 同 NeoForge | `world.playSound(...)` |
| 自定义物品数据 | `PersistentDataContainer` | `DataComponents` / Attachment | `ItemStack` NBT | 组件 / NBT |
| 注册方块 | 无 | `DeferredRegister.Blocks` | `DeferredRegister<Block>` | `Registry.register(Registries.BLOCK, ...)` |
| 客户端入口 | 无 | `Dist.CLIENT` 事件类 | `FMLClientSetupEvent` | `ClientModInitializer` |
| 发网络包 | `player.sendPluginMessage` | `PacketDistributor.sendToPlayer` | `CHANNEL.send(PacketDistributor.PLAYER.with(...))` | `ServerPlayNetworking.send` |
| 实体属性 | `Attribute.MAX_HEALTH` | `Attribute.MAX_HEALTH` | `Attribute.GENERIC_MAX_HEALTH` | `EntityAttributes.GENERIC_MAX_HEALTH` |
| 调度到主线程 | `runTask` / `EntityScheduler` | 事件里天然在主线程 | 同 NeoForge | `server.execute(...)` |

## 8. 映射对照

| 概念 | Mojmap（Forge/NeoForge/Paper 内部） | Yarn（Fabric 默认） |
|---|---|---|
| 世界 | `Level` / `ServerLevel` | `World` / `ServerWorld` |
| 玩家 | `Player` / `ServerPlayer` | `PlayerEntity` / `ServerPlayerEntity` |
| 物品栈 | `ItemStack` | `ItemStack` |
| 文本 | `Component` | `Text` |
| 界面容器 | `AbstractContainerMenu` | `ScreenHandler` |
| 方块实体 | `BlockEntity` | `BlockEntity` |
| 注册表 | `BuiltInRegistries` | `Registries` |
| 资源位置 | `ResourceLocation` | `Identifier` |
| 数据组件 | `DataComponents` | `DataComponentTypes` |
| 网络 payload | `CustomPacketPayload` | `CustomPayload` |

| 环境 | 映射 | 说明 |
|---|---|---|
| Forge / NeoForge | official（Mojmap） | 类名 `MinecraftServer`、`ServerPlayer`；方法 `tick`、`teleportTo` |
| Fabric 默认 | Yarn | 类名 `MinecraftServer`、`ServerPlayerEntity`；方法名与 Mojmap 不同 |
| Fabric 可选 | `loom.officialMojangMappings()` | 与 NeoForge/Forge 一致，便于共享逻辑 |
| Paper 插件 | Mojmap（NMS） | 通过 `paperweight-userdev`；普通插件只用 Bukkit 门面，不要引 NMS 类名 |
| Parchment | 叠加在 Mojmap 上 | 只补参数名，不改类名/方法名 |

铁律：一个工程只用一个映射集。混用 Yarn 与 Mojmap 会导致 Mixin 目标方法找不到、编译期与运行期名字不一致。

## 9. 报错对照

| 报错 | 常见原因 | 处理 |
|---|---|---|
| `UnsupportedClassVersionError` | Java 版本不对 | 1.20.1 用 17，1.21.1 用 21 |
| `Unsupported class file major version 65`（Gradle 自身） | 用 JDK 21+ 跑 ForgeGradle 6 | `JAVA_HOME` 指向 JDK 17 |
| `NoSuchMethodError` / `NoClassDefFoundError` | API 依赖与 MC 版本不匹配 | 对齐 `paper-api` / `neoforge` / `forge` 版本 |
| `Mod file ... missing mods.toml` | 描述文件路径/名字错 | 放 `src/main/resources/META-INF/`；NeoForge 用 `neoforge.mods.toml` |
| `ClassNotFoundException: net.minecraftforge...` | Forge 代码跑在 NeoForge | 全局替换为 `net.neoforged.*` |
| `Mixin apply failed` | 目标方法名、描述符或映射错误 | 统一映射，检查 `mixins.json` 的 `package` |
| `Cannot get config value before config is loaded` | 配置读取过早 | 在 `Loading`/`Reloading` 事件之后读 |
| `Plugin ... is not enabled` | `plugin.yml` 缺 `api-version` 或主类错 | 补 `api-version: '1.21'`，核对 `main` |
| `Unknown recipe` / 材质丢失 | 路径或目录单复数错 | 1.21 用单数目录，路径全小写 |
| 数据包显示不兼容 | `pack_format` 错 | 1.21.1 数据包 48、资源包 34 |
| `Incompatible mods found` | `neoforge.mods.toml` 版本范围过窄 | 放宽 `versionRange` 或对齐依赖版本 |
| `Attempted to load class ... for invalid dist` | 客户端类进了服务端 | 用 `Dist.CLIENT` 注解或拆源集 |
| `Access transformer ... not found` | AT 路径错 | 放 `META-INF/accesstransformer.cfg` 并在构建里声明 |
| `Registry is already frozen` | 在游戏启动后注册 | 所有注册放进 mod 构造器/`RegisterEvent` |
| `NullPointerException` on `DeferredHolder#get()` | 注册表未填充完就取值 | 延后到 `FMLCommonSetupEvent` 或首次使用 |
| `IllegalArgumentException: Payload type ... already registered` | payload 重复注册或 id 冲突 | 每个 `Type` 只注册一次，检查 `registrar` 命名空间 |
| `DataComponents.CUSTOM_DATA` 为 null | 物品没设置过自定义数据 | 用 `getOrDefault` 或先判 `has(...)` |
| `ResourceLocation` 构造器不可见 | 1.21 私有化 | 用 `fromNamespaceAndPath` / `parse` |
| `Attribute.GENERIC_MAX_HEALTH` 找不到符号 | 1.21 去掉前缀 | 改 `Attribute.MAX_HEALTH` |

## 10. 迁移检查清单

- [ ] `minecraft_version` / loader 版本 / API 版本 / Java 版本四者一致。
- [ ] 描述文件名与位置正确（`mods.toml` vs `neoforge.mods.toml`）。
- [ ] 主类入口：Forge 用 `FMLJavaModLoadingContext`，NeoForge 用构造器注入。
- [ ] 所有 `DeferredRegister` 都在构造器里 `register(bus)`。
- [ ] 事件注解的总线正确（mod vs game/forge）。
- [ ] 网络层已换成 payload/`StreamCodec`，不再有 `SimpleChannel`。
- [ ] 物品数据已从 `getOrCreateTag()` 改为 `DataComponents`。
- [ ] 配置注册入口已改，`ModConfigSpec` 无 `defineMap`。
- [ ] 资源目录单复数、`pack_format`、`pack.mcmeta` 已改。
- [ ] 附魔/药水/属性已改为注册表查询。
- [ ] `runData` 重新生成资源；`runClient`、`runServer` 各启动一次。
- [ ] 服务端不加载客户端类（`Dist` 注解/源集隔离）。

## 11. 验证命令

```bash
# NeoForge
./gradlew createMinecraftArtifacts
./gradlew runData
./gradlew runClient
./gradlew runServer

# Forge
./gradlew build
./gradlew runData
./gradlew runClient

# Paper 插件
./gradlew build
# 把 target/*.jar 放进 plugins/，启动 paper 1.21.1

# 数据包
# 把 zip 放进 world/datapacks/，执行 /reload，再 /datapack list
```

数据包验证要点：`/datapack list` 能看到包且状态 `enabled`；`/function <ns>:<name>` 能执行；`/reload` 后 `pack_format` 不兼容会有日志警告。