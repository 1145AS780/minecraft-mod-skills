# 配置体系、事件层与数据驱动预设

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.43 配置体系：分片 SPEC + 静态快照 + 列表默认值迁移 + 文件拆分迁移

配置是这个项目里最容易踩坑的地方（改完不生效、老存档配置丢失、reload 后行为错乱）。五个范式。

**① 一个聚合类 + N 个分片 SPEC**

```
Config.java            ← 只做聚合：持有 6 个 SPEC + 所有静态快照字段
├── ConfigCombat       ← 战斗数值
├── ConfigBaubles      ← 饰品数值（282 行，最大）
├── ConfigRetreat      ← 私人维度
├── ConfigCompat       ← 兼容开关
├── ConfigWinefox      ← Boss 挑战
└── ConfigWorldgen     ← 结构生成
```

```java
// Config.java
public static final ForgeConfigSpec COMBAT_SPEC  = ConfigCombat.SPEC;
public static final ForgeConfigSpec BAUBLES_SPEC = ConfigBaubles.SPEC;
// ...
public static double maxSpellRange;          // ← 静态快照，不是 ConfigValue
public static int meleeAttackInterval;
```

- **分片而不是一个巨型 SPEC**：一个 1000 项的 SPEC 会让 `config.toml` 变成几百行，玩家改一项要滚半天；
  分片后每个文件只讲一件事，也方便「只 reload 某一类」。
- **聚合类只做聚合**：不定义任何 `ConfigValue`，只放 SPEC 引用 + 静态快照。**职责单一，改配置项时只动一个分片文件**。

**② 加载：按 `getSpec()` 分派，不按文件名**

```java
@SubscribeEvent
static void onLoad(ModConfigEvent event) {
    Object spec = event.getConfig().getSpec();
    if (spec == COMBAT_SPEC)  { ConfigCombat.load();   combatLoaded  = true; }
    else if (spec == BAUBLES_SPEC) { ConfigBaubles.load(event); baublesLoaded = true; }
    // ...
    if (combatLoaded && baublesLoaded && retreatLoaded && compatLoaded && winefoxLoaded && worldgenLoaded) {
        applyRuntimeValues();                       // ← 全部就绪才应用
    }
}
```

- **用 `event.getConfig().getSpec()` 的**引用**比对，不要用文件名**。文件名会随本地化/版本变化，
  而且 `ModConfigEvent` 的 `getConfig()` 在不同加载阶段可能返回不同实例。
- **必须等全部 SPEC 加载完才 `applyRuntimeValues()`**：Forge **不保证**多个 config 的加载顺序。
  早应用的话，先加载的那份会拿另一份的默认值（0 或 null）算出来。
- **`ModConfigEvent` 会多次触发**（首次加载 + 每次 reload）。所有 `load()` 必须是**幂等**的
  （只做「读值写静态字段」，不要在里面注册回调/分配对象）。
- 每个分片置一个 `xxxLoaded` 布尔，比「计数到 6」更安全（reload 时不会因为重复触发而提前满足条件）。

**③ 静态快照：热路径读 static，但必须同步下游常量**

```java
// ConfigCombat.load()
Config.maxSpellRange = MAX_SPELL_RANGE.get();

// Config.applyRuntimeValues()
SpellCombatMeleeTask.setSpellRange((float) maxSpellRange);      // ← 推到别的类的静态常量
SimplifiedSpellCaster.MELEE_RANGE = (double) ((float) meleeRange);
Global.resetCommonDamageCalc();                                  // ← 让缓存的公式失效
Global.resetCommonCoolDownCalc();
DreamCatCrystalBauble.registerCommonCallbacks();
```

- **为什么用静态快照**：`ConfigValue.get()` 每次调用都有装箱 + 类型检查开销。战斗数值每 tick 都要读，
  快照一次后热路径就是普通字段访问。
- **陷阱一：只更新 `Config.maxSpellRange` 就以为生效了**。任务类里还有一份自己的 `SPELL_RANGE` 静态常量
  （见 §14.40），**不改它的话「改了配置但射程没变」**。所有下游副本都必须在 `applyRuntimeValues()` 里推一遍。
- **陷阱二：公式缓存**。`Global.resetCommonDamageCalc()` 这类方法的存在，说明伤害/冷却公式是**懒加载缓存**的。
  配置变更后不清缓存，新数值永远不会生效——**加一个静态快照字段，就必须问一句「有没有缓存依赖它」**。
- **陷阱三：回调重复注册**。`registerCommonCallbacks()` 如果内部不幂等，每次 reload 都会多注册一份，
  玩家改 3 次配置伤害就翻 3 倍。

**④ 列表型默认值新增项：`migrationVersion` + 比对旧默认值**

给黑名单加一个新默认项，最麻烦的是：**玩家改过的列表不能被覆盖，没改过的要自动补上新项**。

```java
static void migrateDreamCrystalEffectBlacklist(
        ModConfigEvent event, ConfigValue<List<? extends String>> blacklist,
        IntValue migrationVersion, List<String> defaults) {
    if (migrationVersion.get() < 1) {
        List<? extends String> configured = blacklist.get();
        List<String> previousDefaults = defaults.subList(0, defaults.size() - 1);   // 去掉新加的那项
        if (configured.equals(previousDefaults)) {                                   // ① 玩家没改过
            List<String> migrated = new ArrayList<>(configured);
            migrated.add(defaults.get(defaults.size() - 1));                          // ② 才追加
            blacklist.set(migrated);
        }
        migrationVersion.set(1);                                                     // ③ 版本号推进
        event.getConfig().save();                                                    // ④ 立刻落盘
    }
}
```

- **`IntValue migrationVersion` 是必需的**。没有版本号的话，每次启动都会执行迁移逻辑，
  玩家删掉的那一项会被反复加回来。
- **「比对旧默认值」是关键判定**：只有列表内容**完全等于旧默认值**才认为是「没改过」，才追加新项。
  直接 `contains` 判断会把玩家自己添加的列表也当成默认值。
- **`save()` 必须显式调**。只 `set()` 不 `save()`，下次启动读到的还是旧文件，迁移等于白做。
- `defaults` 用「完整列表」，`previousDefaults` 用 `subList(0, size-1)`：**新默认项永远追加在末尾**，
  这样「旧默认值」的推导是确定的，不需要维护两份列表。

**⑤ 文件结构迁移：拆文件 + 改名备份，绝不删旧文件**

单文件 `common.toml` → 按分类拆到 `config/<modid>/{combat,baubles,...}.toml`：

```java
CommentedFileConfig source = CommentedFileConfig.builder(legacy)
        .preserveInsertionOrder()      // ← 保留键顺序，迁移后文件顺序和原来一致
        .build();
// 按 section 名分发到各目标文件
moveLegacyAside(legacy);               // 改名为 xxx.toml.migrated，不删除
```

- **`preserveInsertionOrder()`**：不加的话迁移出来的文件键顺序会被打乱，玩家 diff 时会看到「整个文件都变了」。
- **`CommentedFileConfig` 而不是普通 `FileConfig`**：要保留注释，否则玩家的自定义注释全丢。
- **迁移后改名 `.migrated` 而不是删除**：玩家发现配置丢了还能找回原文件。**永远不要在迁移里删用户文件**。
- **迁移失败只 `warn` 不抛异常**（除了少数必须成功的场景）：配置迁移失败不该让游戏起不来。
- 迁移入口放在**极早期**（`Mod` 构造/`FMLCommonSetupEvent` 之前），必须早于 Forge 读取 config 的时间点，
  否则 Forge 已经按「文件不存在」生成了默认配置，迁移逻辑就变成往新文件里塞旧值。

**⑥ 注释双语，一行英文一行中文**

```java
BUILDER.comment(new String[]{
    "酒狐最大生命；修改后对新生成或重新加载的实体生效",
    "Winefox max health; changes apply when a boss spawns or reloads." })
```

- **`String[]` 两行，中英各一**：`config.toml` 是纯文本，没有本地化机制，只能写死两种语言。
- 注释里**必须写清「什么时候生效」**（新生成/重载/立即）。玩家改完没生效，八成是没看懂这行。

### 14.44 事件层：回调注册表 + 两段式伤害管线 + 第三方伪施法者识别

13 个事件类、1575 行。核心是一个 669 行的 `MaidSpellEventHandler` + 12 个专项事件类 + 一个 `Global` 注册表。

**① 一个大事件类 + 若干专项类，不要一个事件一个类**

```
event/
├── MaidSpellEventHandler    669 行，主线：生命周期 / 伤害 / 装备 / 服务器 tick
├── DreamCrystalMaidEvents   174 行，单一饰品（梦猫水晶）的完整逻辑
├── MaidSpellAllyEvents      109 行，友军判定缓存
├── FestivalGreetingManager  122 行，节日问候（含独立 Data 类）
├── MaidSuppressionEvents / StaranchorPearlEvents / WinefoxProgressSyncEvents ...
```

- **主线事件全在一个类**：它们共享同一套静态字段（`activeMaids`、`ownerMaidRegistry`）和同一套判定工具。
  拆成 20 个类后每个类都要 `import` 一遍，改一个判定要改 20 处。
- **专项逻辑单独成类**（`DreamCrystalMaidEvents`）：一个饰品的 5 个事件全放在一起，
  和主线解耦。**判据是「有没有自己独占的状态」**——有独占静态状态就独立成类。

**② `Global`：回调注册表，而不是在每个事件里写 `if (装了XX饰品)`**

```java
public static final List<BiFunction<LivingHurtEvent, EntityMaid, Void>> commonHurtCalc = new CopyOnWriteArrayList<>();
public static final Map<Item, BiFunction<LivingHurtEvent, EntityMaid, Void>> baubleHurtEventHandlers = new ConcurrentHashMap<>();
public static final List<BiFunction<LivingDamageEvent, Player, Void>> playerDamageHandlers = new CopyOnWriteArrayList<>();
```

事件处理里只做「遍历分发」，不知道任何具体饰品：

```java
Global.commonHurtCalc.forEach(fn -> fn.apply(event, maid));
Global.baubleHurtEventHandlers.forEach((item, fn) -> {
    if (BaubleStateManager.hasBauble(maid, item)) fn.apply(event, maid);
});
```

- **`CopyOnWriteArrayList`**：**读极多、写极少**（每 tick 每实体都遍历，注册只在初始化时一次）。
  用它而不是 `ArrayList` 是因为遍历期间可能有注册（并发修改会抛 CME）。
- **`ConcurrentHashMap<Item, fn>` 按物品索引**：只有装了该饰品的女仆才调该回调，
  20 个饰品 × 100 个女仆，从「2000 次判断」降到「1 次 `hasBauble` + 命中项」。
- **`resetCommonDamageCalc()` / `resetCommonCoolDownCalc()` 重建列表**：
  配置 reload 后要重算数值。**重建而不是原地改**，保证列表内容和配置版本一致（见 §14.43 陷阱二）。

**③ 两段式伤害管线：`LivingHurtEvent`（前） + `LivingDamageEvent`（后）**

Forge 的伤害有两次事件，**必须理解区别再用**：

| 事件 | 时机 | 能做什么 |
|---|---|---|
| `LivingHurtEvent` | 减伤/护甲/附魔**计算之前** | 改 `amount`（原始伤害）、`setCanceled`（完全拦截） |
| `LivingDamageEvent` | 护甲/抗性**计算之后**，即将扣血 | 只能看到最终值，改它等于「改最终伤害」 |

```java
// 前段
if (event.getSource().getEntity() instanceof EntityMaid maid) processor_pre(event, maid);   // 女仆是攻击者
if (entity instanceof EntityMaid maid) {
    Global.commonHurtCalc.forEach(...);                        // 女仆是受害者
    Global.baubleHurtEventHandlers.forEach(...);               // 受害者装的饰品
}

// 后段
if (event.getSource().getEntity() instanceof EntityMaid maid) processorAft(event, maid);
else if (event.getSource().getDirectEntity() instanceof EntityMaid maid) processorAft(event, maid);  // ← 注意 else if
if (entity instanceof Player player) Global.playerDamageHandlers.forEach(...);
```

三个必须分清的方法：

- **`event.getEntity()`** = 受害者。
- **`event.getSource().getEntity()`** = **真正造成伤害的实体**（可能是一个召唤物，其 owner 是女仆）。
- **`event.getSource().getDirectEntity()`** = **物理命中的实体**（箭矢、火球本体）。

**陷阱**：后段用了 `else if` 而不是两个独立 `if`——因为「攻击者是女仆」和「直接实体是女仆」在同一次伤害里
可能同时成立（女仆徒手打），走两遍 `processorAft` 会导致**伤害结算被执行两次**。
前段则两个独立 `if`：一个管「女仆打别人」，一个管「女仆被打」，语义不同，必须都跑。

**④ 第三方「伪施法者」识别：三道递进判定**

第三方模组（Psi）的法术需要一个 `Player` 施法者，于是伪造 `FakePlayer`。要拦住「女仆的法术误伤玩家」：

```java
private static boolean shouldBlockMaidPsiPlayerDamage(LivingEntity target, DamageSource source) {
    if (!PSI_LOADED || !(target instanceof Player)) return false;         // ① 先便宜判定
    Entity causing = source.getEntity(), direct = source.getDirectEntity();
    if (isMaidPsiFakeCaster(causing) || isMaidPsiFakeCaster(direct)) return true;   // ② 直接是伪施法者
    if (direct != null && isPsiSpellEntity(direct)) return true;                   // ③ 直接是法术实体
    Vec3 pos = source.getSourcePosition();                                        // ④ 位置近邻兜底
    return pos != null && isNearActiveMaidPsiSpell(target.level(), pos);
}
```

- **必须用 `PSI_LOADED` 短路在最前**：软依赖模组没装时，后面所有判断都不该执行（而且 `instanceof` 目标类可能不存在）。
- **伪施法者靠「FakePlayer + UUID 映射」识别**：`PsiProvider.getMaidUuidFromCaster(fakePlayer) != null`
  说明这个假玩家是我们为某个女仆创建的。
- **法术实体靠注册名判断**：`entity.getType().getKey().toString().startsWith("psi:") && contains("spell")`。
  没有 API 能查「这个实体属于哪个模组的哪个法术」，注册名是唯一可靠依据。
- **最后一道是「位置近邻」**：某些法术伤害的 `source` 完全不带实体（环境伤害型），
  只能靠「伤害位置 3 格内有没有我们的法术实体」兜底。**这是最后的保险，宁可多拦也不能误伤玩家**。
- **拦截后打 `debug` 日志，带 registry id + uuid**（不是 `toString()`）：
  玩家反馈「我的女仆打我」时，一条日志就能定位是哪个模组的哪个实体。

**⑤ 生命周期事件必须成对，一个注册一个清理**

| 注册 | 清理 | 不清理的后果 |
|---|---|---|
| `EntityJoinLevel` | `EntityLeaveLevel` | `activeMaids` 无限增长 |
| `PlayerLoggedIn` | `PlayerLoggedOut` | `ownerMaidRegistry` 里留着离线玩家 |
| `PutOn`（饰品穿上） | `TakeOff`（脱下） | 饰品回调永久生效，脱了还有效果 |
| `ToItem`（女仆变蛋） | `ToMaid`（蛋变女仆） | 运行时状态残留 |
| `ServerAboutToStart` | `ServerStopped` | 静态 map 跨世界残留 |

- **`EntityLeaveLevel` 比 `EntityDeath` 更可靠**：卸载区块、换维度、被 `discard` 都不会触发死亡事件，
  但一定会触发 `LeaveLevel`。清理逻辑挂在 `LeaveLevel` 上，才能覆盖所有移除路径。
- **`RemovalReason` 要显式分类**：

```java
private static boolean shouldReleaseMaidChunkLoading(RemovalReason reason) {
    return reason == UNLOADED_WITH_PLAYER || reason == CHANGED_DIMENSION
        || reason == KILLED || reason == DISCARDED;
}
```

`UNLOADED`（区块卸载，女仆还在）和 `KILLED`（真死了）要区别对待——前者不能清存档数据，后者要清。

**⑥ `ServerTickEvent` 必须判 `phase == END`**

```java
@SubscribeEvent
public static void onServerTick(ServerTickEvent event) {
    if (event.phase == Phase.END) {
        EnderPocketService.tickRemoteSessions(event.getServer());
        MaidHardRemovalProtection.tick(event.getServer());
        SpellBookManager.tickPendingRemovals(event.getServer());
    }
}
```

`ServerTickEvent` 每 tick 触发**两次**（START 和 END）。不判 phase 就是所有逻辑跑两遍——
表现为「冷却减半、计时器加速、日志翻倍」。**统一用 END**（此时本 tick 的世界状态已经稳定）。

**⑦ 用穷尽 switch 让新增枚举值立刻暴露**

```java
private static boolean isControlledRetreatSpawnType(MobSpawnType spawnType) {
    return switch (spawnType) {
        case NATURAL, CHUNK_GENERATION, SPAWNER, STRUCTURE, JOCKEY, EVENT, REINFORCEMENT, TRIGGERED, PATROL -> true;
        case BREEDING, MOB_SUMMONED, CONVERSION, BUCKET, SPAWN_EGG, COMMAND, DISPENSER -> false;
        default -> throw new IncompatibleClassChangeError();       // ← 枚举新增值会走到这里
    };
}
```

**`default -> throw` 而不是 `default -> false`**：Minecraft 每次版本更新都可能给 `MobSpawnType` 加值
（例如 1.21 新增的若干种）。用 `false` 兜底的话，新类型会被静默当作「不受控生成」，
表现为「新版本某些怪物能刷进私人维度」。抛异常能在测试时立刻发现。

### 14.48 数据驱动预设：从结构 NBT 抽数据 + ReloadListener 的歧义剔除

「预设」类数据（女仆出身、Boss 属性模板、刷怪配置）最省事的来源是**结构文件**——
用结构方块摆一个样板实体，导出 `.nbt`，运行时从 `entities` 里读出效果列表。这样策划改数值不用碰代码。

**① 从结构 NBT 抽实体数据的解析骨架**

```java
protected Map<String, ListTag> prepare(ResourceManager resources, ProfilerFiller profiler) {
    Map<String, ListTag> result = new HashMap<>();
    Set<String> ambiguous = new HashSet<>();
    resources.listResources("structures", id ->
            "touhou_little_maid_spell".equals(id.getNamespace()) && id.getPath().endsWith(".nbt"))
        .forEach((id, resource) -> {
            try (InputStream in = resource.open()) {
                CompoundTag template = NbtIo.readCompressed(in);
                for (Tag element : template.getList("entities", 10)) {
                    CompoundTag entity = ((CompoundTag) element).getCompound("nbt");
                    if ("touhou_little_maid:maid".equals(entity.getString("id"))) {   // ← 按注册名过滤
                        String source = MaidOriginData.getOrigin(entity).getString("Source");
                        if (source.isEmpty()) continue;
                        ListTag effects = MaidOriginData.collectPresetEffects(entity.getList("ActiveEffects", 10));
                        if (!mergeSource(result, source, effects)) ambiguous.add(source);
                    }
                }
            } catch (IOException e) {
                MaidSpellMod.LOGGER.warn("Cannot read structure maid presets from {}", id, e);
            }
        });
    ambiguous.forEach(result::remove);     // ← 有冲突的整体剔除
    return Map.copyOf(result);
}
```

- **`listResources("structures", filter)` 的过滤谓词必须同时判 namespace**：不加 namespace 会把
  所有模组的结构都扫一遍，别人同名 key 会覆盖你的预设。
- **`getList("entities", 10)` 第二参数是元素类型**：类型不符时返回空列表而不是抛异常，
  这样「结构里没实体」和「结构里实体类型错」都不会崩。
- **单个文件 `IOException` 只 warn 不中断**：一个坏文件不该让整份预设失效。

**② 冲突处理：同 key 不同值 → 整个 key 剔除，而不是「后者覆盖前者」**

```java
static boolean mergeSource(Map<String, ListTag> result, String source, ListTag effects) {
    ListTag previous = result.putIfAbsent(source, effects);
    return previous == null || new HashSet<>(previous).equals(new HashSet<>(effects));
}
```

- **用 `Set` 比较而不是 `List`**：效果顺序不同但内容相同应视为一致，否则顺序抖动就误判冲突。
- **歧义不是「取第一个」，是「全部丢弃并留空」**：两个数据包同名预设值不同，说明数据本身有错，
  静默选一个会让线上表现随机复现。**宁缺勿错**——玩家看到「预设不存在」比看到「属性随机」好排查。

**③ ReloadListener 的三条硬规矩**

```java
@EventBusSubscriber(modid = "touhou_little_maid_spell")
public final class MaidOriginPresetReloadListener extends SimplePreparableReloadListener<Map<String, ListTag>> {
    private static volatile Map<String, ListTag> presets = Map.of();   // ← volatile + 不可变

    @SubscribeEvent public static void addListener(AddReloadListenerEvent e) { e.addListener(new MaidOriginPresetReloadListener()); }
    @SubscribeEvent public static void stop(ServerStoppedEvent e) { presets = Map.of(); }   // ← 必须清

    protected void apply(Map<String, ListTag> loaded, ResourceManager r, ProfilerFiller p) { presets = loaded; }
}
```

1. **字段 `volatile` + `Map.copyOf` 不可变**：`prepare` 在后台线程跑、`apply` 在主线程写、业务代码随时读。
   非 volatile 会读到半初始化的 Map（旧 JVM 内存模型下真实可复现）。
2. **`ServerStoppedEvent` 必须清空**：单人游戏「退出到主菜单 → 换存档」时静态字段不清，
   新存档读到上一个存档的数据包内容。
3. **`prepare` / `apply` 两段式**：`prepare` 只做 IO + 解析（可并发），`apply` 只做赋值（主线程、无 IO）。
   **绝不能在 `prepare` 里访问 `ServerLevel`、`MinecraftServer`、`ItemStack` 以外的世界状态**——它在后台线程。

**④ 用 `AddReloadListenerEvent` 而不是自己 `listener` 注册**

`AddReloadListenerEvent` 保证你的 listener 排在原版之后、`/reload` 时一起跑。
自己 hook `ReloadableServerResources` 会漏掉 `/reload` 路径（只在启动时跑一次）。

**⑤ 预设的读取入口要能容忍「没有预设」**

```java
@Nullable static ListTag find(String source) { return presets.get(source); }
```

调用方 `find()` 返回 null 时必须走默认值分支，**不要 `orElseThrow`**——
预设是可选数据，缺了应当降级而不是崩服。
