# Paper / Bukkit 插件 API（1.21.1 与 1.20.1）

Paper 1.21.1 需要 Java 21，API 是 Bukkit + Mojang Brigadier + Adventure 的组合。Spigot 兼容代码基本可用，但 `io.papermc.paper.*` 下的专有 API 在 Spigot 上不存在；反过来，Spigot 的 `org.bukkit.*` 在 Paper 上全部保留。

## 0. 版本与依赖速查

| 项 | 1.21.1 | 1.20.1 |
|---|---|---|
| Java | 21 | 17 |
| API 坐标 | `io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT` | `io.papermc.paper:paper-api:1.20.1-R0.1-SNAPSHOT` |
| `api-version` | `'1.21'` | `'1.20'` |
| Adventure | 内置 | 内置（1.16.5 起） |
| Brigadier 命令 API | 有（`io.papermc.paper.command.brigadier`） | 无，用传统 `PluginCommand` |
| 数据组件 | 有 `io.papermc.paper.datacomponent` | 无，用 `ItemMeta` + NBT |
| Folia 调度器 | 有 | 有（1.20+） |
| 属性字段 | 去掉 `GENERIC_` 前缀（`Attribute.MAX_HEALTH`） | `Attribute.GENERIC_MAX_HEALTH` |

跨版本时最常炸的三处：`Attribute` 字段改名、`PotionEffectType`/`Enchantment` 变成 Registry、物品组件取代 NBT。

## 1. 构建配置

### Gradle Kotlin DSL

```kotlin
plugins {
    java
    id("com.gradleup.shadow") version "8.3.5"   // 需要打包依赖时才加
}

group = "com.example"
version = "1.0.0"

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    compileOnly("io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT")
    // 需要打包的第三方库用 implementation，再由 shadowJar 重定位
    implementation("com.zaxxer:HikariCP:5.1.0")
    // 测试可用的 mock 服务器
    testImplementation("io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT")
}

java {
    toolchain { languageVersion.set(JavaLanguageVersion.of(21)) }
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.release.set(21)   // 1.20.1 用 17
}

tasks.processResources {
    filesMatching("plugin.yml") { expand("version" to project.version) }
}

tasks.shadowJar {
    archiveClassifier.set("")
    relocate("com.zaxxer.hikari", "com.example.libs.hikari")
    minimize()
}
```

### Gradle Groovy DSL

```groovy
dependencies {
    compileOnly 'io.papermc.paper:paper-api:1.21.1-R0.1-SNAPSHOT'
}
java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }
```

### Maven

```xml
<repository>
  <id>papermc</id>
  <url>https://repo.papermc.io/repository/maven-public/</url>
</repository>
<dependency>
  <groupId>io.papermc.paper</groupId>
  <artifactId>paper-api</artifactId>
  <version>1.21.1-R0.1-SNAPSHOT</version>
  <scope>provided</scope>
</dependency>
```

### 本地测试服务器（paperweight / run-paper）

```kotlin
plugins {
    id("xyz.jpenilla.run-paper") version "2.3.1"
}
tasks.runServer {
    minecraftVersion("1.21.1")
}
```

`paperweight-userdev` 用于写 NMS/mixin 插件（需要 Mojang 映射与 Paper 反编译产物），普通插件不要引入，构建会慢很多。

### 依赖范围规则

- Paper API 永远 `compileOnly`（服务器自带），打进 jar 会 `ClassCastException` / `LinkageError`。
- 只被服务器加载的库（Adventure、Gson、Guava、snakeyaml）不要打包。
- 必须自带的库（数据库驱动、HTTP 客户端）用 `implementation` + shadowJar + `relocate`，避免和别的插件撞包。
- 1.21.1 编译出的 class 是 65，1.20.1 服务器（Java 17）无法加载，反之可以。

## 2. 插件描述文件

### plugin.yml（推荐，Bukkit/Spigot/Paper 通吃）

```yaml
name: MyPlugin
version: '${version}'
main: com.example.myplugin.MyPlugin
api-version: '1.21'
authors: [ YourName ]
contributors: [ Helper ]
description: Example Paper plugin
website: https://example.com
logger: com.example.myplugin.MyLogger   # 可选，自定义 java.util.logging.Logger
load: POSTWORLD                          # STARTUP / POSTWORLD
folia-supported: true                    # 声明兼容 Folia 区域调度器
depend: [ Vault ]
softdepend: [ PlaceholderAPI, LuckPerms ]
loadbefore: [ SomePlugin ]
libraries:
  - com.zaxxer:HikariCP:5.1.0            # 运行期由服务器下载到 libs/
commands:
  mycmd:
    description: Example command
    usage: /mycmd <sub>
    aliases: [ mc ]
    permission: myplugin.use
    permission-message: You need myplugin.use
    executor: myplugin        # 可选，指定 executor 名（多命令共享）
permissions:
  myplugin.use:
    description: Allows using /mycmd
    default: op
  myplugin.admin:
    default: false
    children:
      myplugin.use: true
```

字段说明：

| 字段 | 说明 |
|---|---|
| `main` | 全限定类名，必须继承 `JavaPlugin` |
| `api-version` | 只写 `1.21` / `1.20`，写 `1.21.1` 会被当作非法值 |
| `load` | `STARTUP` 在物品/方块注册前加载，`POSTWORLD` 在世界生成后 |
| `depend` | 硬依赖，缺失则本插件不加载 |
| `softdepend` | 软依赖，只影响加载顺序 |
| `libraries` | Maven 坐标，服务器启动时下载（需要网络，离线服不要用） |
| `folia-supported` | 不声明则在 Folia 上直接拒绝加载 |

### paper-plugin.yml（Paper 专有）

```yaml
name: MyPlugin
version: '${version}'
main: com.example.myplugin.MyPlugin
api-version: '1.21'
bootstrapper: com.example.myplugin.MyPluginBootstrap
loader: com.example.myplugin.MyPluginLoader
folia-supported: true
dependencies:
  bootstrap:
    SomeRegistryPlugin:
      load: BEFORE
      required: true
      join-classpath: true
  server:
    SomeEconomyPlugin:
      load: AFTER
      required: false
      join-classpath: false
```

要点：

- `paper-plugin.yml` 不是 `plugin.yml` 的等价替代：依赖必须放在 `bootstrap` 或 `server` 段，`depend`/`softdepend` 不生效。
- `bootstrapper` 在服务器引导阶段运行，能访问 `RegistryAccess`，适合注册自定义注册表项；`loader` 负责构造类加载器。
- 两个文件同时存在时 Paper 优先读 `paper-plugin.yml`；插件同时要跑 Spigot 时只写 `plugin.yml`。

```java
public final class MyPluginBootstrap implements PluginBootstrap {
    @Override
    public void bootstrap(BootstrapContext context) {
        context.getLogger().info("bootstrap");
    }
}

public final class MyPluginLoader implements PluginLoader {
    @Override
    public ClassLoader classLoader(PluginLoaderContext context) {
        return context.getClassLoader();
    }
}
```

## 3. 主类与生命周期

```java
package com.example.myplugin;

import org.bukkit.plugin.java.JavaPlugin;

public final class MyPlugin extends JavaPlugin {

    private static MyPlugin instance;

    public static MyPlugin get() {
        return instance;
    }

    @Override
    public void onLoad() {
        instance = this;
        // 此时 getServer() 可用，但世界/玩家还不可用
    }

    @Override
    public void onEnable() {
        saveDefaultConfig();
        getServer().getPluginManager().registerEvents(new MyListener(this), this);
        registerCommands();
        getLogger().info("MyPlugin enabled on " + getServer().getVersion());
    }

    @Override
    public void onDisable() {
        // 取消任务、关闭连接池、保存数据
        getServer().getScheduler().cancelTasks(this);
        getLogger().info("MyPlugin disabled");
    }
}
```

顺序：`onLoad()` → `onEnable()` → 运行期 → `onDisable()`。构造器里不要碰世界、玩家、`getConfig()`（配置在 `onEnable` 前才可用）。静态实例用 `getPlugin(MyPlugin.class)` 或自己保存，不要用 `JavaPlugin.getProvidingPlugin` 猜。

重载（`/reload`）会重新 `onDisable`/`onEnable` 但不重置静态字段，这是静态缓存失效的常见来源。

## 4. 生命周期事件（Paper）

```java
import io.papermc.paper.plugin.lifecycle.event.types.LifecycleEvents;

@Override
public void onEnable() {
    getLifecycleManager().registerEventHandler(LifecycleEvents.COMMANDS, event -> {
        event.registrar().register(
            Commands.literal("mycmd")
                .requires(src -> src.getSender().hasPermission("myplugin.use"))
                .executes(ctx -> {
                    ctx.getSource().getSender().sendMessage(Component.text("Hello"));
                    return Command.SINGLE_SUCCESS;
                })
                .build()
        );
    });
}
```

可用事件：`LifecycleEvents.COMMANDS`（注册 Brigadier 命令）、`LifecycleEvents.TAGS`（向原版标签追加内容）、以及 bootstrap 阶段的 `LifecycleEvents.REGISTRIES` 等。生命周期事件只在插件启用期注册有效，`onDisable` 后不再触发。

## 5. 事件系统

### 5.1 监听器写法

```java
public final class MyListener implements Listener {

    private final MyPlugin plugin;

    public MyListener(MyPlugin plugin) {
        this.plugin = plugin;
    }

    @EventHandler(priority = EventPriority.NORMAL, ignoreCancelled = true)
    public void onJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();
        event.joinMessage(Component.text("欢迎 " + player.getName()));
    }
}
```

硬性要求：

- 类实现 `Listener`，方法 `public`、返回 `void`、参数恰好一个事件对象。
- 必须注册：`getServer().getPluginManager().registerEvents(listener, plugin)`。
- 方法不能是 `static`；同类里多个 `@EventHandler` 方法可以指向不同事件。
- `@EventHandler` 缺省 `priority = NORMAL`、`ignoreCancelled = false`。

### 5.2 优先级

| 优先级 | 用途 |
|---|---|
| `LOWEST` | 最早看到事件，适合强制覆盖 |
| `LOW` | 在插件之前处理 |
| `NORMAL` | 默认 |
| `HIGH` | 在多数插件之后处理 |
| `HIGHEST` | 最终决定 |
| `MONITOR` | 只观察，**禁止修改事件** |

同一个优先级内按插件加载顺序执行；`MONITOR` 用于统计、日志、同步镜像状态。

### 5.3 取消与自定义事件

```java
@EventHandler(ignoreCancelled = true)
public void onBreak(BlockBreakEvent event) {
    if (event.getBlock().getType() == Material.BEDROCK) {
        event.setCancelled(true);
    }
}
```

自定义事件（可取消 + 带 HandlerList）：

```java
public class RubyGainedEvent extends Event implements Cancellable {

    private static final HandlerList HANDLERS = new HandlerList();
    private final Player player;
    private int amount;
    private boolean cancelled;

    public RubyGainedEvent(Player player, int amount) {
        this.player = player;
        this.amount = amount;
    }

    public Player getPlayer() { return player; }
    public int getAmount() { return amount; }
    public void setAmount(int amount) { this.amount = amount; }

    @Override public boolean isCancelled() { return cancelled; }
    @Override public void setCancelled(boolean cancel) { this.cancelled = cancel; }
    @Override public HandlerList getHandlers() { return HANDLERS; }
    public static HandlerList getHandlerList() { return HANDLERS; }

    @Override
    public boolean isAsynchronous() { return false; }   // 异步事件返回 true
}
```

`getHandlerList()` 必须是 `public static`，否则 Bukkit 注册时报 `Invalid event`。

### 5.4 常用事件清单

| 分类 | 事件 |
|---|---|
| 玩家 | `PlayerJoinEvent`、`PlayerQuitEvent`、`PlayerKickEvent`、`PlayerMoveEvent`、`PlayerTeleportEvent`、`PlayerRespawnEvent`、`PlayerDeathEvent`、`PlayerGameModeChangeEvent`、`PlayerLevelChangeEvent`、`PlayerExpChangeEvent`、`PlayerChangedWorldEvent`、`PlayerBedEnterEvent`、`PlayerDropItemEvent`、`PlayerItemConsumeEvent`、`PlayerSwapHandItemsEvent` |
| 交互 | `PlayerInteractEvent`、`PlayerInteractEntityEvent`、`PlayerInteractAtEntityEvent`、`PlayerAnimationEvent`、`PlayerToggleSneakEvent`、`PlayerToggleSprintEvent` |
| 方块 | `BlockBreakEvent`、`BlockPlaceEvent`、`BlockPhysicsEvent`、`BlockBurnEvent`、`BlockExplodeEvent`、`BlockGrowEvent`、`BlockFormEvent`、`BlockSpreadEvent`、`BlockFadeEvent`、`BlockPistonExtendEvent`、`BlockPistonRetractEvent`、`SignChangeEvent`、`NotePlayEvent` |
| 实体 | `EntityDamageEvent`、`EntityDamageByEntityEvent`、`EntityDeathEvent`、`EntityExplodeEvent`、`EntitySpawnEvent`、`CreatureSpawnEvent`、`EntityTameEvent`、`EntityBreedEvent`、`EntityTargetEvent`、`ProjectileLaunchEvent`、`ProjectileHitEvent`、`EntityCombustEvent`、`EntityTransformEvent` |
| 物品栏 | `InventoryOpenEvent`、`InventoryCloseEvent`、`InventoryClickEvent`、`InventoryDragEvent`、`PrepareItemCraftEvent`、`CraftItemEvent`、`FurnaceSmeltEvent`、`BrewEvent`、`PlayerPickupItemEvent`（已弃用） |
| 世界 | `WorldLoadEvent`、`WorldUnloadEvent`、`ChunkLoadEvent`、`ChunkUnloadEvent`、`ChunkPopulateEvent`、`WeatherChangeEvent`、`ThunderChangeEvent`、`TimeSkipEvent`、`WorldSaveEvent` |
| 服务端 | `ServerListPingEvent`、`ServerCommandEvent`、`RemoteServerCommandEvent`、`PluginEnableEvent`、`PluginDisableEvent`、`AsyncPlayerPreLoginEvent`、`PlayerLoginEvent` |
| 聊天/命令 | `AsyncChatEvent`（Paper）、`AsyncPlayerChatEvent`（旧）、`PlayerCommandPreprocessEvent`、`ServerCommandEvent`、`TabCompleteEvent` |
| 计分板 | `ScoreboardObjectiveChangeEvent`、`PlayerScoreboardRemoveEvent`（Paper） |

### 5.5 Paper 聊天事件

```java
import io.papermc.paper.event.player.AsyncChatEvent;

@EventHandler(priority = EventPriority.NORMAL, ignoreCancelled = true)
public void onChat(AsyncChatEvent event) {
    event.viewers().removeIf(audience -> audience instanceof Player p
        && p.hasPermission("myplugin.silent"));
    event.renderer((source, sourceDisplayName, message, viewer) ->
        Component.text("<").append(sourceDisplayName).append(Component.text("> "))
            .append(message));
}
```

- `AsyncChatEvent` 在异步线程触发，只能读事件对象，禁止 `world.setBlock`、`player.teleport` 等主线程 API。
- 改消息用 `renderer(...)`，不要 `setMessage`（没有这个方法）。
- `event.message()` / `event.originalMessage()` 返回 `Component`，不是字符串；取纯文本用 `PlainTextComponentSerializer.plainText().serialize(component)`。
- 需要主线程动作时用 `getServer().getScheduler().runTask(plugin, ...)` 或 `player.getScheduler().run(...)`。

## 6. 命令

### 6.1 Brigadier（Paper 1.20.5+）

```java
Commands.literal("home")
    .requires(src -> src.getSender() instanceof Player)
    .then(Commands.argument("name", StringArgumentType.word())
        .suggests((ctx, builder) -> {
            builder.suggest("base").suggest("farm");
            return builder.buildFuture();
        })
        .executes(ctx -> {
            Player player = (Player) ctx.getSource().getSender();
            String name = StringArgumentType.getString(ctx, "name");
            player.sendMessage(Component.text("Teleport to " + name));
            return Command.SINGLE_SUCCESS;
        }))
    .then(Commands.literal("list").executes(ctx -> {
        ctx.getSource().getSender().sendMessage(Component.text("home list"));
        return Command.SINGLE_SUCCESS;
    }))
    .build();
```

参数类型对照：

| 需求 | 参数类型 | 取值 |
|---|---|---|
| 单词/短语/剩余全部 | `StringArgumentType.word()` / `.phrase()` / `.greedyString()` | `getString(ctx, "x")` |
| 整数 | `IntegerArgumentType.integer(min, max)` | `getInteger(ctx, "x")` |
| 小数 | `DoubleArgumentType.doubleArg(min, max)` | `getDouble(ctx, "x")` |
| 布尔 | `BoolArgumentType.bool()` | `getBool(ctx, "x")` |
| 玩家名 | `EntityArgument.player()` | `EntityArgument.getPlayer(ctx, "x")`（Paper 返回 `Player`） |
| 实体（含选择器） | `EntityArgument.entities()` | `EntityArgument.getEntities(ctx, "x")` |
| 方块坐标 | `BlockPosArgument.blockPos()` | `BlockPosArgument.getBlockPos(ctx, "x")` |
| 注册表项 | `RegistryArgument` / `ResourceLocationArgument` | 依类型取 |

`CommandSourceStack`：

```java
CommandSourceStack src = ctx.getSource();
CommandSender sender = src.getSender();
Location loc = src.getLocation();            // 可能为 null（控制台）
Entity executor = src.getExecutor();         // 可能为 null
src.getServer();
```

权限：`requires(src -> src.getSender().hasPermission("node"))`，无权限时该节点在客户端补全中被隐藏。

注册别名/描述：

```java
event.registrar().register(command, List.of("alias"), "description");
```

### 6.2 传统命令（1.20.1 与兼容 Spigot）

`plugin.yml` 声明后：

```java
@Override
public void onEnable() {
    PluginCommand cmd = getCommand("mycmd");
    if (cmd == null) {
        getLogger().severe("plugin.yml 缺少 mycmd");
        return;
    }
    cmd.setExecutor(this);
    cmd.setTabCompleter(this);
}

@Override
public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
    if (!sender.hasPermission("myplugin.use")) {
        sender.sendMessage(Component.text("No permission"));
        return true;
    }
    if (args.length == 0) {
        sender.sendMessage(Component.text("Usage: /" + label + " <reload|info>"));
        return true;
    }
    switch (args[0].toLowerCase()) {
        case "reload" -> { reloadConfig(); sender.sendMessage(Component.text("Reloaded")); }
        case "info"   -> sender.sendMessage(Component.text("v" + getPluginMeta().getVersion()));
        default       -> sender.sendMessage(Component.text("Unknown subcommand"));
    }
    return true;
}

@Override
public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
    if (args.length == 1) {
        return List.of("reload", "info").stream()
            .filter(s -> s.startsWith(args[0].toLowerCase()))
            .toList();
    }
    return List.of();
}
```

返回 `true` 表示命令已被处理，服务器不再打印 usage。`getPluginMeta()` 是 Paper API；Spigot 用 `getDescription()`。

## 7. 调度器

### 7.1 BukkitScheduler（非 Folia）

```java
// 下一 tick
getServer().getScheduler().runTask(this, () -> { /* 主线程 */ });

// 延迟 20 tick（约 1 秒）
getServer().getScheduler().runTaskLater(this, () -> { /* 主线程 */ }, 20L);

// 立即开始、每 20 tick 重复
BukkitTask task = getServer().getScheduler()
    .runTaskTimer(this, t -> { /* 主线程 */ }, 0L, 20L);
task.cancel();

// 异步：只做 IO / 计算
getServer().getScheduler().runTaskAsynchronously(this, () -> {
    String data = fetchFromWeb();                       // OK
    getServer().getScheduler().runTask(this, () -> {    // 回主线程
        player.sendMessage(Component.text(data));
    });
});

// 异步定时
getServer().getScheduler()
    .runTaskTimerAsynchronously(this, t -> { /* 异步 */ }, 0L, 20L);

// 判断当前线程
Bukkit.isPrimaryThread();
```

`BukkitTask` 有 `cancel()`、`isCancelled()`、`getTaskId()`、`isSync()`。插件禁用时所有任务自动取消。

### 7.2 Folia 区域调度器（Paper 通用写法）

```java
import io.papermc.paper.threadedregions.scheduler.ScheduledTask;

// 全局区域：世界时间、天气、无位置依赖的逻辑
Bukkit.getGlobalRegionScheduler().execute(this, () -> { /* ... */ });
Bukkit.getGlobalRegionScheduler().runAtFixedRate(this, t -> { /* ... */ }, 1L, 20L);

// 区域：绑定到某个位置所在的区块区域
Bukkit.getRegionScheduler().execute(this, location, () -> { /* ... */ });
Bukkit.getRegionScheduler().runAtFixedRate(this, location, t -> { /* ... */ }, 1L, 20L);

// 实体：绑定到实体所属区域，实体卸载/死亡时自动取消
player.getScheduler().run(this, t -> { /* ... */ }, () -> { /* retired */ });
player.getScheduler().runDelayed(this, t -> { /* ... */ }, null, 20L);
player.getScheduler().runAtFixedRate(this, t -> { /* ... */ }, null, 1L, 20L);

// 异步：真实时间单位
Bukkit.getAsyncScheduler().runNow(this, t -> { /* 异步 */ });
Bukkit.getAsyncScheduler().runAtFixedRate(this,
    t -> { /* 异步 */ }, 0L, 50L, java.util.concurrent.TimeUnit.MILLISECONDS);
```

规则：

- 区域调度器的延迟/周期单位是 **tick**；异步调度器用 `TimeUnit`（`MILLISECONDS`/`SECONDS`/`TICKS` 中 `TICKS` 在 Paper 的 `TimeUnit` 里不存在，别写）。
- `Bukkit.getScheduler()` 在 Folia 上直接抛 `UnsupportedOperationException`。
- 在区域线程内不能跨区域改方块；跨区域用 `RegionScheduler#execute(plugin, Location, ...)` 分别投递。
- 实体调度器的 retired 回调在实体消失时执行，用来清理地图/缓存。
- `ScheduledTask#cancel()` 是幂等的；`plugin` 禁用时该插件的所有任务被取消。

### 7.3 常用的安全模式

```java
// 异步读文件后回主线程改方块
getServer().getScheduler().runTaskAsynchronously(this, () -> {
    List<Location> locs = loadFromDisk();
    getServer().getScheduler().runTask(this, () -> locs.forEach(l -> l.getBlock().setType(Material.GOLD_BLOCK)));
});

// 传送用异步 API，避免卡主线程
player.teleportAsync(target).thenRun(() -> player.sendMessage(Component.text("done")));

// 区块异步加载
world.getChunkAtAsync(x, z).thenAccept(chunk -> { /* 主线程回调 */ });
```

## 8. 消息与 Adventure

```java
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextColor;
import net.kyori.adventure.text.format.TextDecoration;
import net.kyori.adventure.text.minimessage.MiniMessage;
import net.kyori.adventure.text.minimessage.tag.resolver.Placeholder;
import net.kyori.adventure.title.Title;
import net.kyori.adventure.bossbar.BossBar;
import net.kyori.adventure.sound.Sound;

player.sendMessage(Component.text("Hello", NamedTextColor.GREEN));
player.sendMessage(Component.text("警告", NamedTextColor.RED)
    .decoration(TextDecoration.BOLD, true)
    .decoration(TextDecoration.ITALIC, false));

// 拼接
Component msg = Component.text()
    .append(Component.text("[", NamedTextColor.DARK_GRAY))
    .append(Component.text(player.getName(), NamedTextColor.AQUA))
    .append(Component.text("] ", NamedTextColor.DARK_GRAY))
    .append(Component.text("joined"))
    .build();

// 换行与空组件
Component.text("line1").append(Component.newline()).append(Component.text("line2"));

// MiniMessage
Component mm = MiniMessage.miniMessage().deserialize(
    "<gradient:#00ff00:#ff0000>Gradient</gradient> <gray>by</gray> <click:run_command:/spawn><hover:show_text:'go spawn'>click</hover></click>");
Component withPlaceholder = MiniMessage.miniMessage().deserialize(
    "<red>Player: <name>", Placeholder.unparsed("name", player.getName()));

// 序列化回字符串
String json = net.kyori.adventure.text.serializer.gson.GsonComponentSerializer.gson().serialize(msg);
String plain = net.kyori.adventure.text.serializer.plain.PlainTextComponentSerializer.plainText().serialize(msg);

// 标题、动作栏、BossBar
player.showTitle(Title.title(Component.text("标题"), Component.text("副标题")));
player.sendActionBar(Component.text("Action bar"));
BossBar bar = BossBar.bossBar(Component.text("Boss"), 1.0f,
    BossBar.Color.RED, BossBar.Overlay.PROGRESS);
player.showBossBar(bar);
bar.progress(0.5f);
player.hideBossBar(bar);

// 音效（Adventure 方式，支持自定义 sound key）
player.playSound(Sound.sound(org.bukkit.Sound.ENTITY_PLAYER_LEVELUP, Sound.Source.PLAYER, 1.0f, 1.0f));

// 广播
Bukkit.broadcast(Component.text("全服广播"));
getServer().sendMessage(Component.text("控制台消息"));
```

要点：

- 1.21.1 的 `sendMessage` 只接受 `Component`，传 `String` 编不过；旧代码 `sendMessage("text")` 要改。
- 颜色不要写 `§c`，`Component.text("§c")` 会原样显示。
- 物品名、Lore 默认斜体，用 `.decoration(TextDecoration.ITALIC, false)` 关掉。
- `MiniMessage` 支持 `<gradient>`、`<rainbow>`、`<click>`、`<hover>`、`<keybind>`、`<transition>`；用户输入的内容必须用 `Placeholder.unparsed`，否则会被当标签解析。
- `LegacyComponentSerializer.legacySection()` 用于和旧字符串互转。

## 9. 物品、ItemMeta 与持久化数据

### 9.1 创建物品

```java
public ItemStack createRuby(MyPlugin plugin) {
    ItemStack stack = new ItemStack(Material.DIAMOND_SWORD);

    stack.editMeta(meta -> {
        meta.displayName(Component.text("Excalibur", NamedTextColor.GOLD)
            .decoration(TextDecoration.ITALIC, false));
        meta.lore(List.of(
            Component.text("+5 Attack", NamedTextColor.GRAY).decoration(TextDecoration.ITALIC, false),
            Component.text("Owner: Steve", NamedTextColor.DARK_GRAY).decoration(TextDecoration.ITALIC, false)));
        meta.setCustomModelData(1001);
        meta.setUnbreakable(true);
        meta.addItemFlags(ItemFlag.HIDE_UNBREAKABLE, ItemFlag.HIDE_ATTRIBUTES);
        meta.getPersistentDataContainer().set(
            new NamespacedKey(plugin, "ruby_id"), PersistentDataType.STRING, "excalibur");
        meta.getPersistentDataContainer().set(
            new NamespacedKey(plugin, "ruby_level"), PersistentDataType.INTEGER, 5);
    });

    return stack;
}
```

- `editMeta` 自动写回；`getItemMeta()` + 手动改 + `setItemMeta(meta)` 必须三步齐全。
- `ItemStack` 不是不可变对象，`clone()` 后再改，避免改到共享实例。
- 1.21 起 `setCustomModelData` 仍可用，但底层是 `custom_model_data` 组件；需要完整组件控制时用 `io.papermc.paper.datacomponent.DataComponentTypes`。

### 9.2 PDC（PersistentDataContainer）

```java
NamespacedKey key = new NamespacedKey(plugin, "owner");

// 写
meta.getPersistentDataContainer().set(key, PersistentDataType.STRING, "steve");

// 读
String owner = meta.getPersistentDataContainer().get(key, PersistentDataType.STRING);

// 判空 / 默认值
int level = meta.getPersistentDataContainer()
    .getOrDefault(new NamespacedKey(plugin, "level"), PersistentDataType.INTEGER, 0);

// 删除
meta.getPersistentDataContainer().remove(key);
```

| `PersistentDataType` | Java 类型 |
|---|---|
| `STRING` | `String` |
| `INTEGER` | `Integer` |
| `LONG` | `Long` |
| `DOUBLE` / `FLOAT` | `Double` / `Float` |
| `BYTE` / `SHORT` | `Byte` / `Short` |
| `BOOLEAN` | `Boolean` |
| `BYTE_ARRAY` / `INTEGER_ARRAY` / `LONG_ARRAY` | 对应数组 |
| `TAG_CONTAINER` | `PersistentDataContainer`（嵌套） |
| 自定义 | `new PersistentDataType.…<>() { … }` 实现 `PrimitiveStructure` |

PDC 可挂在 `ItemMeta`、`Entity`、`Block`（`TileState`）、`Chunk`、`OfflinePlayer`、`World`（Paper）、`Structure`、`ItemStack`（Paper 的 `ItemStack#getPersistentDataContainer()` 不存在，用 `ItemMeta`）。键名会存成 `namespace:key`，改命名空间等于丢数据。

### 9.3 物品序列化

```java
// Paper：二进制（推荐，保留全部组件）
byte[] bytes = stack.serializeAsBytes();
ItemStack back = ItemStack.deserializeBytes(bytes);
String base64 = Base64.getEncoder().encodeToString(bytes);

// 通用：ConfigurationSerializable，可塞进 YAML
config.set("item", stack);
ItemStack fromConfig = config.getItemStack("item");
```

### 9.4 1.21 数据组件（Paper API）

```java
import io.papermc.paper.datacomponent.DataComponentTypes;

// 读
Integer damage = stack.getData(DataComponentTypes.DAMAGE);
Component name = stack.getData(DataComponentTypes.CUSTOM_NAME);

// 写（返回副本，需 set）
stack.setData(DataComponentTypes.CUSTOM_NAME, Component.text("Blade"));
stack.unsetData(DataComponentTypes.CUSTOM_NAME);

// 判空
stack.hasData(DataComponentTypes.CUSTOM_NAME);
```

常规开发优先 `ItemMeta`，只有需要精确控制 `max_stack_size`、`food`、`tool`、`enchantments` 等组件时才直接用 `DataComponentTypes`。跨版本到 1.20.1 时全部退回 `ItemMeta` + NBT。

## 10. 方块、世界、实体

```java
World world = player.getWorld();
Block block = world.getBlockAt(10, 64, 10);

block.setType(Material.STONE, false);       // false = 不触发物理/邻居更新
block.setBlockData(BlockData.createBlockData("minecraft:oak_log[axis=x]"));
Material type = block.getType();

Location loc = new Location(world, 10.5, 65.0, 10.5, 90f, 0f);
world.spawnEntity(loc, EntityType.ZOMBIE);
world.playSound(loc, Sound.ENTITY_PLAYER_LEVELUP, 1.0f, 1.0f);
world.spawnParticle(Particle.FLAME, loc, 20, 0.2, 0.2, 0.2, 0.01);
world.setStorm(true);
world.setTime(6000);
world.setDifficulty(Difficulty.HARD);
world.getWorldBorder().setSize(1000);
world.setSpawnLocation(loc);
```

区块与异步：

```java
Chunk chunk = world.getChunkAt(0, 0);
boolean loaded = chunk.isLoaded();
world.getChunkAtAsync(0, 0).thenAccept(c -> { /* 主线程 */ });
```

实体属性（1.21.1）：

```java
AttributeInstance attr = player.getAttribute(Attribute.MAX_HEALTH);
if (attr != null) {
    attr.setBaseValue(30.0);           // 上限由 Attribute#getMaxValue 限制（1.21+）
    attr.addModifier(new AttributeModifier(
        new NamespacedKey(plugin, "boost"), 5.0, AttributeModifier.Operation.ADD_NUMBER));
}
```

1.20.1 用 `Attribute.GENERIC_MAX_HEALTH`；1.21 改成 `Attribute.MAX_HEALTH`（`GENERIC_` 前缀被移除），1.21.2+ 又引入 `AttributeInstance#getMaxValue` 等限制，写之前先用 IDE 补全确认真实字段名。

## 11. GUI（Inventory）

```java
public final class MenuHolder implements InventoryHolder {

    private final Inventory inventory;
    private final Map<Integer, Consumer<Player>> actions = new HashMap<>();

    public MenuHolder() {
        this.inventory = Bukkit.createInventory(this, 27, Component.text("菜单"));
    }

    public MenuHolder button(int slot, ItemStack icon, Consumer<Player> action) {
        inventory.setItem(slot, icon);
        actions.put(slot, action);
        return this;
    }

    public void click(Player player, int slot) {
        Consumer<Player> action = actions.get(slot);
        if (action != null) action.accept(player);
    }

    @Override public Inventory getInventory() { return inventory; }
}

// 打开
MenuHolder menu = new MenuHolder()
    .button(13, icon, p -> p.sendMessage(Component.text("中心按钮")));
player.openInventory(menu.getInventory());   // 1.20.5+ 也可 player.openInventory(inventory, page)
```

```java
@EventHandler
public void onClick(InventoryClickEvent event) {
    Inventory top = event.getView().getTopInventory();
    if (!(top.getHolder() instanceof MenuHolder menu)) return;

    event.setCancelled(true);               // 禁止拿走 GUI 物品

    if (event.getClickedInventory() == top && event.getWhoClicked() instanceof Player player) {
        menu.click(player, event.getRawSlot());
    }
}
```

拖拽同样要拦：

```java
@EventHandler
public void onDrag(InventoryDragEvent event) {
    if (event.getView().getTopInventory().getHolder() instanceof MenuHolder) {
        event.setCancelled(true);
    }
}
```

要点：

- 用 `InventoryHolder` 判定 GUI，比比较 `Inventory` 实例更可靠（重开界面后实例会变）。
- `getRawSlot()` 是视图坐标，`getSlot()` 是点击的 Inventory 内坐标；判断 `top` 用 `event.getClickedInventory() == top`。
- 不取消点击，玩家可以把 GUI 里的按钮物品拖进背包复制。
- `InventoryClickEvent` 在 1.21 里 `getCurrentItem()` 可能为 `null`，先判空。
- 需要翻页/滚动时用 `openInventory(inventory, page)`（1.20.5+）或自己做多页 Inventory。

## 12. 配置文件

```java
saveDefaultConfig();                                  // 首次复制 jar 内 config.yml
String value = getConfig().getString("settings.message", "default");
int number = getConfig().getInt("settings.count", 10);
boolean flag = getConfig().getBoolean("settings.debug", false);
List<String> list = getConfig().getStringList("settings.list");

getConfig().set("settings.message", "new");
getConfig().options().copyDefaults(true);
saveConfig();
reloadConfig();

saveResource("example.yml", false);                   // 复制任意资源到数据目录
getDataFolder();                                      // plugins/MyPlugin
```

自定义配置文件：

```java
File file = new File(getDataFolder(), "messages.yml");
if (!file.exists()) saveResource("messages.yml", false);
YamlConfiguration cfg = YamlConfiguration.loadConfiguration(file);
cfg.save(file);
```

- YAML 路径用 `.` 分隔（`settings.message`），键名里真有点时用 `getConfigurationSection` 逐层取。
- `saveDefaultConfig()` 不会覆盖已存在的文件；改默认值要删数据目录或手动迁移。
- `getConfig()` 在 `onEnable` 之前不可用；`onLoad` 里只能读 `getConfig()` 之外的资源。
- 保存 `ItemStack` 直接 `config.set(path, stack)`，读取 `getItemStack(path)`；Location/Vector 同理有内置序列化。

## 13. 权限

```java
player.hasPermission("myplugin.use");
player.isOp();
player.addAttachment(plugin, "myplugin.use", true);        // 临时授予
player.addAttachment(plugin, "myplugin.use", true, 60);    // 60 tick 后失效
```

`plugin.yml` 的 `default` 取值：`true`、`false`、`op`、`not_op`。权限节点建议 `插件名.功能`，子权限用 `children` 组合。

## 14. 计分板、BossBar、队伍

```java
Scoreboard sb = Bukkit.getScoreboardManager().getNewScoreboard();
Objective obj = sb.registerNewObjective("rubies", Criteria.DUMMY,
    Component.text("Rubies"));
obj.setDisplaySlot(DisplaySlot.SIDEBAR);
Score score = obj.getScore(player.getName());
score.setScore(42);
player.setScoreboard(sb);
```

1.20.5+ 的 `Criteria` 也是 Registry，`Criteria.DUMMY` 仍可用；自定义统计用 `Criteria.DUMMY` 手动维护最简单。队伍用 `sb.registerNewTeam("red")` + `team.addEntry(name)`，前缀 `team.prefix(Component)`。

## 15. 插件通信

```java
// 发送（BungeeCord 兼容通道示例）
getServer().getMessenger().registerOutgoingPluginChannel(this, "BungeeCord");
ByteArrayDataOutput out = ByteStreams.newDataOutput();
out.writeUTF("Connect");
out.writeUTF("lobby");
player.sendPluginMessage(this, "BungeeCord", out.toByteArray());

// 接收
getServer().getMessenger().registerIncomingPluginChannel(this, "myplugin:main",
    (channel, player, message) -> {
        ByteBuffer buf = ByteBuffer.wrap(message);
        int id = buf.getInt();
    });
```

- 通道名必须小写、带命名空间（`myplugin:main`）；`BungeeCord` 是历史大写例外。
- 1 字节长度上限 32766，大数据要分片。
- Paper 有 `PluginMessenger` 的 `sendPluginMessage` 异步版本；跨服建议改用 Velocity/Redis 消息。

## 16. 日志与调试

```java
getLogger().info("info");
getLogger().warning("warn");
getLogger().severe("severe");
getLogger().log(Level.FINE, "debug", throwable);
```

- 插件日志前缀自动加 `[MyPlugin]`。
- 性能排查用 spark（Paper 自带 `/spark profiler`），不要长期开 timings。
- 高频事件（`PlayerMoveEvent`、`BlockPhysicsEvent`）里避免 `getBlock()` 循环与字符串拼接。

## 17. 1.20.1 与 1.21.1 的 API 差异（插件侧）

| 项 | 1.20.1 | 1.21.1 |
|---|---|---|
| Java / class 版本 | 17 / 61 | 21 / 65 |
| `api-version` | `'1.20'` | `'1.21'` |
| 属性 | `Attribute.GENERIC_MAX_HEALTH` | `Attribute.MAX_HEALTH` |
| 附魔 | `Enchantment.DURABILITY` 等枚举字段 | Registry 查询（`Registry.ENCHANTMENT`） |
| 药水效果 | `PotionEffectType.SPEED` | Registry 查询（`Registry.POTION_EFFECT_TYPE`） |
| 物品 NBT | `ItemMeta` + `getPersistentDataContainer` | 同上 + `DataComponentTypes` |
| 命令 API | `PluginCommand` | Brigadier `LifecycleEvents.COMMANDS` |
| 聊天 | `AsyncChatEvent`（Adventure） | 同上，`renderer` 更常用 |

写跨版本插件时把版本相关代码抽到单独的类，用反射或两个源集（`src/main/java` 共用 + `src/v1_21/java`）隔离。

## 18. 常见坑

- `plugin.yml` 必须在 `src/main/resources`，且 `main` 类名区分大小写；`getCommand("x")` 返回 `null` 就是没声明或拼错。
- `api-version` 缺失会进入 legacy 兼容模式，`Material` 名称、音效枚举行为都不同。
- `reloadConfig()` 只重载 YAML，不重载类；`/reload` 不重置静态字段，插件级缓存要自己清。
- 异步上下文（`AsyncChatEvent`、`runTaskAsynchronously`）调用世界/实体/背包 API 会抛 `IllegalStateException`。
- `ItemMeta` 改完不 `setItemMeta` 不生效；`ItemStack` 直接改会污染共享实例。
- GUI 不 `setCancelled(true)` 会被拖走；只拦 `InventoryClickEvent` 不拦 `InventoryDragEvent` 也能拖。
- `MONITOR` 优先级里改事件结果无效，还会被其他插件覆盖。
- PDC 键用 `new NamespacedKey(plugin, "x")`，换插件名/大小写即读不到。
- 1.20.1 服务器加载 Java 21 编译的插件直接 `UnsupportedClassVersionError`。
- `getConfig().getString()` 返回 `null` 时拼进 `Component.text(null)` 会 NPE，用 `getString(path, default)`。
- `player.getInventory().getItemInMainHand()` 在 1.21 仍可用，但读物品数据要用 `ItemMeta` 或 `DataComponentTypes`，不要找 `getNBT()`。
