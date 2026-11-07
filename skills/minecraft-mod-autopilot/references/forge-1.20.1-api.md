# Forge 1.20.1 API 速查（本仓库适配版）

> 适用：Minecraft 1.20.1 + Forge 47.4.x + Java 17 + `official` 映射 + ForgeGradle 6.0.x。
> 其它版本请先核对方法签名，不要直接照搬。

## 1. 工程坐标（占位符，替换为你的模组）

| 项 | 值 |
| --- | --- |
| Mod ID | `<modid>` |
| 主类 | `<group>.<modid>.GeneratedMod` |
| 包根 | `<group>.<modid>` |
| 构建产物 | `build/libs/<archivesName>-<version>.jar` |
| 运行目录 | `run`（client/server）、`run-data`（datagen） |
| 软依赖 | 车万女仆 `touhou_little_maid`、`curios` |

`gradle.properties` 里的展开键（形如 `<archivesName>=<modid>`）是 `mods.toml` 的 `modId` 来源：`build.gradle` 用 `${<archivesName>}` 展开。**不要只改键名**，否则 `mods.toml`、run 配置与 `mods {}` 块会一起失效。

## 2. 入口与两条总线

```java
@Mod(GeneratedMod.MOD_ID)
public final class GeneratedMod {
    public static final String MOD_ID = "<modid>";

    public GeneratedMod() {
        IEventBus modBus = FMLJavaModLoadingContext.get().getModEventBus();
        // 注册：DeferredRegister.register(modBus)
        // 配置：ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, SPEC)
        // 网络：SimpleChannel 必须在构造期创建，避免 "Registration of impl channels is locked"
    }
}
```

- **MOD 总线**：注册、`FMLCommonSetupEvent`、`FMLClientSetupEvent`、`EntityRenderersEvent`、`GatherDataEvent`。
- **FORGE 总线**：`ServerTickEvent`、`EntityJoinLevelEvent`、`ProjectileImpactEvent`、`LivingHurtEvent`、`RegisterCommandsEvent` 等游戏事件。
- 订阅方式二选一：`@Mod.EventBusSubscriber(modid = MOD_ID, bus = ...)`，或 `MinecraftForge.EVENT_BUS.register(instance)`。

## 3. DeferredRegister

```java
public static final DeferredRegister<Item> ITEMS =
        DeferredRegister.create(ForgeRegistries.ITEMS, MOD_ID);

public static final RegistryObject<Item> RUBY =
        ITEMS.register("ruby", () -> new Item(new Item.Properties()));
```

规则：

- 一个注册表一个 `DeferredRegister`，在模组构造器里 `register(modBus)`。
- `RegistryObject.get()` 只能在注册完成后调用；静态字段初始化阶段不要取值。
- 注册名必须小写、仅 `[a-z0-9_.-/]`。

## 4. 物品与方块

```java
public static final RegistryObject<Block> RUBY_BLOCK =
        BLOCKS.register("ruby_block", () -> new Block(BlockBehaviour.Properties.of()
                .strength(3.0F).requiresCorrectToolForDrops()));

public static final RegistryObject<Item> RUBY_BLOCK_ITEM =
        ITEMS.register("ruby_block", () -> new BlockItem(RUBY_BLOCK.get(), new Item.Properties()));
```

资源路径（缺失纹理/模型是启动崩溃高发点）：

```text
assets/<modid>/models/item/ruby.json
assets/<modid>/textures/item/ruby.png
assets/<modid>/blockstates/ruby_block.json
assets/<modid>/models/block/ruby_block.json
assets/<modid>/lang/en_us.json, zh_cn.json
```

## 5. 实体

```java
public static final DeferredRegister<EntityType<?>> ENTITY_TYPES =
        DeferredRegister.create(ForgeRegistries.ENTITY_TYPES, MOD_ID);

public static final RegistryObject<EntityType<MyArrow>> MY_ARROW =
        ENTITY_TYPES.register("my_arrow", () -> EntityType.Builder
                .<MyArrow>of(MyArrow::new, MobCategory.MISC)
                .sized(0.5F, 0.5F)
                .clientTrackingRange(4)
                .updateInterval(20)
                .build("my_arrow"));
```

- 构造函数必须提供 `(EntityType<? extends X>, Level)` 与 `(Level, double, double, double)` 两种。
- 渲染器在 MOD 总线注册：

```java
@Mod.EventBusSubscriber(modid = GeneratedMod.MOD_ID, bus = Mod.EventBusSubscriber.Bus.MOD,
        value = Dist.CLIENT)
public final class ModClientEvents {
    @SubscribeEvent
    public static void onRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(ModEntities.MY_ARROW.get(), ArrowRenderer::new);
    }
}
```

- 有 AI 的 `Mob` 还需 `EntityAttributeCreationEvent` 注册属性。

## 6. 附魔

```java
public static final DeferredRegister<Enchantment> ENCHANTMENTS =
        DeferredRegister.create(ForgeRegistries.ENCHANTMENTS, MOD_ID);

public static final RegistryObject<Enchantment> MY_ENCHANT =
        ENCHANTMENTS.register("my_enchant", () -> new Enchantment(
                Enchantment.Rarity.COMMON,
                EnchantmentCategory.WEAPON,
                EquipmentSlot.MAINHAND) {
            @Override
            public int getMaxLevel() { return 5; }
        });
```

- 自定义类别：`EnchantmentCategory.create("weapon_arrows", stack -> stack.getItem() instanceof BowItem)`。
- 等级上限若来自配置，读取必须发生在配置加载之后（游戏运行期）。

## 7. 投射物与命中

```java
public class MyArrow extends Arrow {
    public MyArrow(EntityType<? extends Arrow> type, Level level) { super(type, level); }

    @Override
    public void tick() {
        if (!this.level().isClientSide) {
            // 服务端逻辑
        }
        super.tick();
    }

    @Override
    protected void onHitEntity(EntityHitResult result) {
        if (!this.level().isClientSide) {
            // 结算伤害；注意避免与原版重复结算
        }
    }

    @Override
    protected void onHitBlock(BlockHitResult result) {
        if (!this.level().isClientSide) { this.discard(); }
    }
}
```

- 跨实体携带状态：`entity.getPersistentData().putInt("key", level)`；客户端不可依赖该数据做判定。
- 箭类事件：`EntityJoinLevelEvent`（打标记）、`ProjectileImpactEvent`（分发附魔效果）。
- 防递归：生成型自定义箭要在命中入口按类型排除，避免无限生成。

## 8. 常用事件

| 事件 | 总线 | 用途 |
| --- | --- | --- |
| `FMLCommonSetupEvent` | MOD | 通用初始化 |
| `FMLClientSetupEvent` | MOD | 客户端初始化 |
| `EntityRenderersEvent.RegisterRenderers` | MOD | 实体渲染器 |
| `EntityAttributeCreationEvent` | MOD | 生物属性 |
| `GatherDataEvent` | MOD | 数据生成 |
| `ServerAboutToStartEvent` | FORGE | 服务器启动前清空全局状态 |
| `ServerStoppedEvent` | FORGE | 服务器停止后清理 |
| `ServerTickEvent` | FORGE | 每 tick 推进管理器 |
| `EntityJoinLevelEvent` | FORGE | 实体入世界时打标记 |
| `ProjectileImpactEvent` | FORGE | 投射物命中分发 |
| `LivingHurtEvent` | FORGE | 伤害倍率/减伤 |
| `RegisterCommandsEvent` | FORGE | 注册命令 |

## 9. 配置

```java
public static final ForgeConfigSpec SPEC;
static {
    ForgeConfigSpec.Builder b = new ForgeConfigSpec.Builder();
    ENABLE_TASKS = b.comment("enable tasks").define("enableTasks", true);
    SPEC = b.build();
}
// 构造器里：
ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, SPEC);
```

- 配置值用 `.get()` 读取，不要在静态初始化里读。
- 服务端/客户端都需要的放 `COMMON`；只影响画面的放 `CLIENT`。

## 10. 网络

```java
private static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
        new ResourceLocation(MOD_ID, "main"),
        () -> "1",
        "1"::equals,
        "1"::equals);

public static void init() {
    CHANNEL.registerMessage(0, MyPacket.class, MyPacket::encode, MyPacket::decode, MyPacket::handle);
}
```

- 频道必须在模组构造期创建；首个 tick 才 `new SimpleChannel` 会触发 `Registration of impl channels is locked`。
- `ResourceLocation(String)` 构造器在 1.20.1 已弃用，优先 `new ResourceLocation(namespace, path)`。

## 11. 资源与数据生成

- `mods.toml` 使用 `${mod_id}`、`${mod_version}` 等占位符，由 `processResources` 展开。
- 数据包路径：`data/<modid>/damage_type/*.json`、`tags/...`、`recipes/...`、`loot_tables/...`。
- `GatherDataEvent` 里注册 provider：

```java
@SubscribeEvent
public static void gather(GatherDataEvent event) {
    var gen = event.getGenerator();
    var out = gen.getPackOutput();
    if (event.includeClient()) {
        gen.addProvider(true, new LanguageProvider(out, MOD_ID, "en_us"));
    }
    if (event.includeServer()) {
        // DatapackBuiltinEntriesProvider / TagsProvider / RecipeProvider
    }
}
```

- 生成产物在 `src/generated/resources`，已加入 `sourceSets.main.resources`。
- 改完 datagen 后执行 `.\gradlew runData`，不要手改生成文件。

## 12. 本仓库的软依赖约定

1. **先判断再接触**：主类构造器只调用 `ModList.get().isLoaded("touhou_little_maid")`，不要 `new` 任何引用女仆类的对象。
2. **扩展入口隔离**：`TouhouLittleMaidBridge` 标注 `@LittleMaidExtension` 并实现 `ILittleMaid`；女仆模组不在时该类不会被加载。
3. **开发期依赖**：`libs/touhou_little_maid-1.5.3-named.jar` 同时用于 `compileOnly` 与 `runtimeOnly`；缺它会导致 TLM 相关类编译失败或运行期 `NoClassDefFoundError`。
4. **Mixin dev 参数**：`build.gradle` 已为 run 配置设置 `mixin.env.remapRefMap`、`refMapRemappingFile`、`GradleStart.srg.srg-mcp`；这三个属性与 TLM 的 named jar 配套，不要随意删除。
5. **SnakeYAML**：TLM named jar 未内置，`runtimeOnly 'org.yaml:snakeyaml:2.4'` 不能删，否则读取 AI 配置时 `NoClassDefFoundError`。
6. **TLM API 包名**：`com.github.tartaricacid.touhoulittlemaid.api.*`、`entity.task.TaskManager`、`item.bauble.BaubleManager`、`entity.task.meal.MaidMealManager`。
7. **日志格式**：统一 `LOGGER.info("[{}] ...", MOD_ID)`，便于脚本按 `[<modid>]` 过滤。

## 13. 最小事件订阅模板

```java
@Mod.EventBusSubscriber(modid = GeneratedMod.MOD_ID) // 默认 FORGE 总线
public final class MyEvents {
    @SubscribeEvent
    public static void onTick(ServerTickEvent event) {
        if (event.phase != TickEvent.Phase.END) return; // 1.20.1 用 Phase
        // ...
    }
}
```

> 1.20.1 的 `ServerTickEvent` 使用 `TickEvent.Phase`；1.21+ 已改为 `PostTickEvent` 等，不要混用。