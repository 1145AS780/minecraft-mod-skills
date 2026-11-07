# 世界生成与运行时私有维度

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.41 世界生成：自定义 Placement + 地形守卫 + 可选模组模板 + 追溯改造

结构生成是「一旦生成就不可逆」的区域，四个可复用范式。

**① 自定义 StructurePlacement：多结构互斥 + Codec 自带校验**

原版 `RandomSpreadStructurePlacement` 只支持**一个** `exclusion_zone`。要「A 结构附近 12 格内不许出 B 结构」，
必须自己写一个子类：

```java
public class MultiExclusionSpreadPlacement extends RandomSpreadStructurePlacement {
    public static final Codec<MultiExclusionSpreadPlacement> CODEC = ExtraCodecs.validate(
        RecordCodecBuilder.mapCodec(i -> i.group(
            Vec3i.CODEC.optionalFieldOf("locate_offset", Vec3i.ZERO).forGetter(...),
            FrequencyReductionMethod.CODEC.optionalFieldOf("frequency_reduction_method", DEFAULT).forGetter(...),
            Codec.floatRange(0.0F, 1.0F).optionalFieldOf("frequency", 1.0F).forGetter(...),
            Codec.intRange(0, 4096).fieldOf("spacing").forGetter(RandomSpreadStructurePlacement::spacing),
            Codec.intRange(0, 4096).fieldOf("separation").forGetter(RandomSpreadStructurePlacement::separation),
            RandomSpreadType.CODEC.optionalFieldOf("spread_type", LINEAR).forGetter(...),
            Zone.CODEC.listOf().fieldOf("exclusion_zones").forGetter(MultiExclusionSpreadPlacement::exclusionZones)
        ).apply(i, MultiExclusionSpreadPlacement::new)),
        p -> p.spacing() <= p.separation()
            ? DataResult.error(() -> "Spacing has to be larger than separation")
            : DataResult.success(p)
    ).codec();

    @Override
    public boolean isPlacementChunk(ChunkGeneratorStructureState state, int x, int z) {
        if (!super.isPlacementChunk(state, x, z)) return false;
        for (Zone zone : exclusionZones)
            for (Holder<StructureSet> set : state.getPotentialStructureChunks(...))     // 遍历同层结构集
                if (set.is(zone.otherSet())
                    && state.hasStructureChunkInRange(set, x, z, zone.chunkCount()))    // 邻近有别的结构
                    return false;
        return true;
    }

    public record Zone(ResourceKey<StructureSet> otherSet, int chunkCount) { /* 自己的 CODEC */ }
}
```

- **Codec 里带 `ExtraCodecs.validate`**：`spacing <= separation` 是原版自身的硬约束。
  不校验的话，数据包写错只会「静默不生成」，排查时完全看不出原因；带上校验会在**加载阶段**就报错。
- `Zone` 用 `record` + 自己的 `CODEC`，`chunk_count` 限定 `intRange(1, 16)`——上限必须有，否则数据包填个 9999 直接把生成卡死。
- `isPlacementChunk` 里**先调 `super`**：父类做频率/盐值判定，先便宜后贵。

**② 地形特征 / 雕刻器守卫：Tag 驱动 + ThreadLocal 缓存**

地下洞穴、地表树、湖泊这些**原版特征**会在结构生成后继续切割地形，把刚放好的结构挖穿。守卫写法：

```java
public final class TerrainFeatureGuard {
    public static final TagKey<Structure> TAG =
        TagKey.create(Registries.STRUCTURE, new ResourceLocation(MODID, "no_terrain_features"));

    private static final ThreadLocal<List<BoundingBox>> PROTECTED = ThreadLocal.withInitial(List::of);

    public static void begin(WorldGenLevel level, BlockPos origin) {   // 包住一次特征生成
        PROTECTED.set(find(level, origin, 13));
    }
    public static void end() { PROTECTED.remove(); }

    public static boolean blocked(BlockPos pos) { return blocked(PROTECTED.get(), pos); }

    private static boolean blocked(List<BoundingBox> boxes, BlockPos pos) {
        for (BoundingBox b : boxes)
            if (pos.getY() >= b.minY() - 1
                && pos.getX() >= b.minX() - 2 && pos.getX() <= b.maxX() + 2
                && pos.getZ() >= b.minZ() - 2 && pos.getZ() <= b.maxZ() + 2) return true;
        return false;
    }
}
```

- **用 `TagKey<Structure>` 而不是硬编码结构列表**：数据包作者能自己声明「哪些结构不许被地形特征切」，代码零改动。
- **`ThreadLocal` 缓存包围盒**：`find()` 要遍历附近 3×3 区块的 `STRUCTURE_STARTS`，很贵。
  用 `begin()`/`end()` 包住一次特征生成，把结果缓存在当前线程（世界生成是多线程的，**不能用普通静态字段**）。
- **包围盒扩张是非对称的**：`y` 只向上扩 1（结构底部允许地形贴合），水平扩 2（防止特征从侧面切进来）。
  对称扩张会导致结构下面被误判为保护区，地形悬空。
- `find()` 只处理 `WorldGenRegion`（生成期才有）；`center.chunkDistance <= 8` 限制扫描范围，
  否则大结构（例如 40 区块的）会扫到几万个区块。

**③ 可选模组模板结构：`requiredMod` + `fallback` 双保险**

模板里塞了别的模组的方块（装饰、刷怪笼），玩家没装那个模组 → 生成时直接崩。做法：

```java
@Override
protected Optional<GenerationStub> findGenerationPoint(GenerationContext context) {
    if (!ModList.get().isLoaded(this.requiredMod)) return Optional.empty();          // 主模组没装 → 不生成
    StructurePoolElement element = ...;
    if (fallback.isPresent() && !ModList.get().isLoaded(fallback.get().mod()))        // 兜底模组也没装
        return Optional.empty();
    if (fallback.isPresent() && !ModList.get().isLoaded(this.requiredMod))
        element = StructurePoolElement.ofSingle(fallback.get().template().toString()) // 换兜底模板
                       .apply(Projection.RIGID);
    ...
}
```

- **`requiredMod` 是 Codec 字段**（不是硬编码）：同一个结构类可以复用给多个「依赖不同模组」的模板。
- **`fallback` 是可选的第二选择**：主模组没装时用另一个模板，两个都没装才放弃生成。
  注意这里有个易错点——`fallback` 分支必须在 `requiredMod` 未加载时才走，写成 `if (fallback.isPresent())` 会无条件替换模板。
- **`surface_offset` / `max_terrain_step` / `fill_foundation` 三个 Codec 参数**让结构自适应地形起伏：
  贴地采样 + 最大高差限制 + 自动填地基。没有这三个参数，模板会在陡坡上「一半埋土里一半悬空」。
- 地狱结构额外限制 `MAX_NETHER_TEMPLATE_Y = 122`（基岩层上方空间有限，超出直接不生成）。

**④ 追溯改造（Retrofit）：给已生成的世界补新结构**

老存档里已经有世界了，新版本加了结构，怎么补上？标准流程：

```java
public static void onServerStarted(ServerStartedEvent event) {
    runRetrofit(event.getServer());
}

private static void runRetrofit(MinecraftServer server) {
    if (StarfallGardenData.isRetrofitAttempted(server)) return;   // ① 持久标记，只尝试一次
    ...
    if (claimExisting(overworld, garden, candidates)) {           // ② 附近已有该结构 → 直接认领，不重复生成
        StarfallGardenData.markPlaced(existing.getBoundingBox().minX());
        return;
    }
    placeInto(server, overworld, garden, candidates);              // ③ 分帧生成
    StarfallGardenData.markRetrofitAttempted(server);
}
```

四条硬规则：

- **`isRetrofitAttempted` 必须是持久化的 SavedData 标记**。用内存标记的话，重启服务器又会重跑一次，
  玩家每次重启都发现「家门口又长出一个新结构」。
- **先 `claimExisting` 再生成**：扫描附近是否已经存在同结构（可能是上个版本生成过、或者别的来源），
  有就只记 `markPlaced`，**绝不重复放置**。
- **分帧执行**：`placeInto` 内部建一个 `PlacementTask`，用 `ServerTickEvent` 每 tick 处理一小块
  （`MAX_GRID_CELLS = 2_000_000` 上限切分）。**绝不能在 `ServerStartedEvent` 里同步跑完**——
  大结构的区块生成会让服务器启动卡住几十秒，客户端直接超时断开。
- **`AtomicBoolean PASS_SCHEDULED` 防重复调度**：`ServerStartedEvent` 和 `ServerTickEvent` 可能在不同时机触发，
  没有这个标记会同时调度两次任务，两个任务在同一片区块上打架。
- **`unlockForRetrofit()` / `relockAfterRetrofit()` / `reopenAfterRetrofit()` 成对调用**：
  改造期间要临时放开「该结构只生成一次」的锁，**每个提前 return 分支上都必须 relock**。
  这个文件里出现了 8 次 `relockAfterRetrofit()`，正是因为「任何一个分支漏了 relock，结构就会永久重复生成」。

### 14.42 运行时私有维度 + 分帧结构搜索

「每个玩家一个私人空间（撤退所/家园），进去后能快速到达某个结构」——这套功能横跨维度注册、传送、异步搜索、生命周期清理。

**① 维度 Key 命名规范：私有用 UUID 后缀，共享用固定名**

```java
private static final String PRIVATE_RETREAT_PREFIX = "the_retreat_";
private static final ResourceLocation SHARED_RETREAT_LOCATION = new ResourceLocation(MODID, "the_retreat");

public static ResourceKey<Level> getPlayerRetreatDimension(UUID uuid) {
    return ResourceKey.create(Registries.DIMENSION, new ResourceLocation(MODID, PRIVATE_RETREAT_PREFIX + uuid));
}
public static boolean isPrivateRetreatDimension(ResourceLocation loc) {
    return loc.getNamespace().equals(MODID) && loc.getPath().startsWith(PRIVATE_RETREAT_PREFIX);
}
```

- **私有维度用 `前缀 + UUID`**：反查玩家不需要额外的映射表，`isPrivate` 判断也只是 `startsWith`。
- 共享维度用固定 key，`isShared` 走精确匹配。**两者判断方法分开写**，不要用 `contains(uuid)` 之类模糊匹配——
  玩家 UUID 恰好包含在别的字符串里会误判。

**② 维度注册：运行时往 `MinecraftServer.levels` 里塞**

`ServerLevel` 的维度表是 `final` 的，运行时新增维度只能靠 Accessor：

```java
@Mixin(MinecraftServer.class)
public interface MinecraftServerAccessor {
    @Accessor("levels") Map<ResourceKey<Level>, ServerLevel> getLevels();
}
```

```java
public static void registerDimension(ResourceKey<Level> key, ServerLevel level) { dimensionRegistry.put(key, level); }
public static void unregisterDimension(ResourceKey<Level> key)                     { dimensionRegistry.remove(key); }
```

- **必须同时维护两份**：Minecraft 自己的 `levels` map（引擎用它找维度）+ 自己的 `ConcurrentHashMap`（模组逻辑用）。
  只加一份的话，要么 `server.getLevel(key)` 拿不到，要么模组自己查不到。
- 自己的注册表用 `ConcurrentHashMap`：维度注册/卸载可能发生在不同线程（区块生成线程、服务器线程）。
- **`unregisterDimension` 一定要在维度卸载时调**，否则 map 里留着已卸载的 `ServerLevel` → 内存泄漏 + 后续访问拿到「已死」的世界。

**③ 传送：自定义 `ITeleporter`，不要走传送门**

```java
public static record RetreatTeleporter(BlockPos targetPos) implements ITeleporter {
    @Override
    public Entity placeEntity(Entity entity, ServerLevel current, ServerLevel dest, float yaw, Function<Boolean, Entity> reposition) {
        Entity placed = reposition.apply(false);
        placed.moveTo(targetPos.getX() + 0.5, targetPos.getY(), targetPos.getZ() + 0.5, yaw, placed.getXRot());
        return placed;
    }
}
```

- **`reposition.apply(false)`**：参数 `false` 表示「不要走默认的位置计算」（默认会找传送门/找地表）。
- **落点必须自己校验 + 兜底**：
  - `estimateSurfaceHeight(DensityFunction, x, z, level)`：用密度函数估地表高度，**不要 `level.getHeight()`**（会强加载区块）。
  - `isSafeStandingPosition` / `isOpenForPlayer` / `isHazardousFloor`：脚下是岩浆/仙人掌/虚空 → 不安全。
  - `createSafePlatform(level, pos)`：实在找不到安全点就**在目标位置造一小块平台**，比把玩家扔进虚空好。
  - `ensureChunkLoaded(level, x, z)`：先加载区块再判断，否则读到的全是空气。

**④ 分帧结构搜索：`IWorker` + 环形遍历 + 全局配额**

在「几万区块范围里找一个结构」绝不能同步跑。标准做法是把搜索做成一个可暂停的工作单元：

```java
public class StructureSearchWorker implements IWorker {
    private int currentRing = 0, edgeIndex = 0;          // 环形遍历游标
    private volatile boolean finished = false;
    private final CompletableFuture<BlockPos> resultFuture = new CompletableFuture<>();
    private final AtomicBoolean counterDeducted = new AtomicBoolean(false);

    @Override public boolean hasWork() { return !finished && currentRing <= maxRadius; }
    @Override public boolean doWork()  { /* 处理一个候选，返回是否还有活 */ }
}
```

- **`hasWork()` / `doWork()` 双方法**：调度方每 tick 调 `doWork()` 一次（或按预算多次），
  `hasWork()` 为 false 就移除。**工作单元自己不能持有 tick 逻辑**，否则和调度器耦合。
- **环形遍历**（`ring` + `edgeIndex` + `edgeIndexToOffset`）：从中心一圈圈往外，**最近的结构优先找到**。
  直接遍历矩形会先扫到远处的角落，玩家等半天才拿到一个很远的点。
- **结果用 `CompletableFuture<BlockPos>`**：调用方 `thenAccept` 拿到结果，worker 内部不用回调、不用传引用。
- **`AtomicBoolean counterDeducted`**：全局搜索配额只扣一次。`doWork` 里有多条退出路径（找到/超半径/异常），
  没有这个标记会在每条路径上都扣一次，配额瞬间耗尽。
- **进度日志按 ring 变化打一次**（`lastLoggedRing`）：每 tick 打日志会把服务器日志刷爆。

**⑤ 两个必须有的缓存：负缓存 + 生成中位置**

```java
private static final long NEGATIVE_CACHE_TTL_TICKS = 6000L;   // 5 分钟
private static final Map<ResourceKey<Level>, BlockPos> generatedStructurePositions = new ConcurrentHashMap<>();
```

- **负缓存**：搜索结果是「这片区域没有结构」也要缓存，TTL 6000 tick（5 分钟）。
  只缓存成功结果的话，玩家每次传送都会重跑一次全量搜索。
- **`generatedStructurePositions` + `pollGeneratedStructurePos()`**：结构**正在生成**时就把位置记下来，
  worker 每轮先 `poll` 一次——**生成中的结构也能被立刻认领**，不用等它彻底生成完。
  `poll` 是「取走即删」，`peek` 是「只看不取」，两个方法都要有。

**⑥ 全局并发配额：`tryAcquireSearchPermit`**

```java
private static final AtomicInteger searchingCounter = new AtomicInteger(0);
public static boolean tryAcquireSearchPermit() { /* 超过上限返回 false */ }
public static void releaseSearchPermit()       { searchingCounter.decrementAndGet(); }
```

多个玩家同时进私人空间 → 多个 worker 同时跑 → 主线程被区块生成拖死。
**必须有全局上限**（不是每玩家上限），并且 `release` 要在所有退出路径上调到（try/finally 或 worker 完成时统一释放）。

**⑦ 生命周期清理：三层 shutdown**

```java
public static void shutdown(MinecraftServer server) {
    cancelRuntimeWork();                       // 取消所有 worker
    releaseAllForcedChunks(server);            // 释放强加载区块
    clearAll();                                // 清空所有静态 map
}
```

- **`releaseAllForcedChunks` 必须显式调用**。搜索时为了读结构会 `forceLoadChunk`，不释放的话
  这些区块**永久强加载**——服务器内存一路涨，玩家退出后还在涨。
  `forceLoadedChunks` map 记录「谁强加载了哪些区块」，就是为了这一刻能精确释放。
- **静态 map 在服务器停止时必须清空**。单人游戏「退出世界再进另一个世界」不会重启 JVM，
  静态 map 里的旧 `ServerLevel` 会让新世界拿到上个世界的引用。
- `shutdown()` 和 `shutdown(server)` 两个重载都要有：前者给无 server 的场合（崩溃/客户端），后者做完整清理。

**⑧ 存档数据三层分离**

| 类 | 作用域 | 存什么 |
|---|---|---|
| `RetreatDimensionData` | 全局（`SavedData`） | 已分配维度 key、玩家→维度映射 |
| `RetreatLevelData` | 每维度 | 该维度的结构位置、已生成标记 |
| `RetreatLevelStateData` | 每维度 | 运行时状态（是否已初始化、锁状态） |

**「配置/结果」和「运行时状态」分开放**：前者要落盘（`SavedData`），后者重启就该重置。
混在一个类里会导致「重启后锁状态还是上次的」，结构永远不再生成。
