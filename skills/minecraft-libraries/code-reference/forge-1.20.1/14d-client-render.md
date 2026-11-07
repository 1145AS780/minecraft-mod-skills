# 客户端：渲染复用阶梯、骨挂点、动画、BGM、HUD、注册收口

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

### 14.17 客户端渲染：四级复用阶梯（先问「别人是不是已经写好」）

本项目 `client/` 实测 **39 个 .java**（顶层 5 + 10 个子包共 34：`renderer` 10 · `event` 6 · `gui` 5 · `animation` 3 · `model` 3 · `overlay` 3 · `particle`/`resource`/`spell`/`winefox` 各 1）。
真正「原创绘制」的只有 4 组——七曜引导 `SevenStarGuidanceRenderer` 505 行、剑阵 `SwordArrayRenderer` 274 行、
黑球族 `PalmBlackHoleRenderer` 122 / `LocalBlackHoleRenderer` 149 / `SupernovaBlackHoleRenderer` 123 行、场域 `ThreeEnclosuresFieldRenderer` 146 行。
**注意这 4 组都不在 `client/` 里**，而在 `compat/irons_spellbooks/client/renderer/entity`（16 个文件）——找原创绘制要去 compat 目录，别在 `client/` 里翻。
其余全是**复用 + 参数化**。按复用深度分四级，**永远从 L0 往下试，能停就停**：

> **⚠ 编号消歧**：本节 L0~L3 是**渲染器复用深度**，与 14e2 §14.49 的 **L0~L3 字节码侵入分级**是两套完全无关的分级，
> 只是恰好都用了 L 前缀。**本节 L 级别只在本节内有效**，跨文件引用「L3」时默认指 14e2 的「运行时自挂 agent」。
> 需要引用本节层级请写「渲染 L3」或「§14.17 L3」。

| 层级 | 基类来源 | 适用场景 | 本项目实例 | 代码量 |
| --- | --- | --- | --- | --- |
| **L0** | 直接 new 第三方渲染器 | 形状相同、只差尺寸 | `new CometRenderer(ctx, 0.75F)`（星落彗星）；纯逻辑实体用 `NoopRenderer` | 0 行 |
| **L1** | 宿主模组渲染器 | 实体本身就是女仆 | `MagicalWinefoxBossRenderer extends EntityMaidRenderer` | 15 行 |
| **L2** | 第三方抽象渲染器 | 第三方已有同族实体 | `GenericSpellHumanoidRenderer extends AbstractSpellCastingMobRenderer` | 9 行 |
| **L3** | 自建参数化基类 | 特效用例（无现成可借） | `LocalBlackHoleRenderer`（10 个构造参数 + 模板方法） | 135 行 → 子类各 10 行 |

**L0 的 `NoopRenderer` 是个常被忽略的好东西**：实体只承担逻辑（区域判定、计时），
用 `NoopRenderer::new` 注册即可，不必为它写一个空渲染器。

**L2 的关键是把「差异」提到模型层，而不是复制渲染器**。四个法术人形怪共用同一个渲染器：

```java
public class GenericSpellHumanoidModel extends AbstractSpellCastingMobModel {
   private final ResourceLocation model;
   private final ResourceLocation texture;
   public ResourceLocation getModelResource(AbstractSpellCastingMob a) { return this.model; }
   public ResourceLocation getTextureResource(AbstractSpellCastingMob a) { return this.texture; }
}
```

注册处只换两个 `ResourceLocation`：

```java
event.registerEntityRenderer(CORRUPTED_KNIGHT.get(), ctx -> new GenericSpellHumanoidRenderer(
    ctx, new GenericSpellHumanoidModel(rl("geo/corrupted_knight.geo.json"),
                                       rl("textures/entity/corrupted_knight.png"))));
```

> **反模式**：给每个怪物写一个 `XxxRenderer` 类。4 个怪物 = 4 份完全相同的 9 行样板，改一次要改 4 处。

**L3 的判据：子类只差常量时，把常量提成构造参数，不要复制类。**
`LocalBlackHoleRenderer` 把 `centerTexture / beamTexture / centerColor / beamColor / beamAlpha /
beamBuildTicks / beamDensity / hoverAboveEyes / centerScale` 全部收进构造器，只留一个钩子：

```java
protected float visualScale(T entity) { return 1.0F; }
```

于是三个变体每个只有 10 行左右：

```java
public class CompanionBlackHoleRenderer extends LocalBlackHoleRenderer<CompanionBlackHoleEntity> {
   public CompanionBlackHoleRenderer(Context ctx) {
      super(ctx, CENTER, BEAM, 0xFFFFFF, 0xFF00FF, 255, 100, 20, 5.0, 1.0F);
   }
   protected float visualScale(CompanionBlackHoleEntity e) { return 0.5F; }
}
```

构造参数超过 6 个时，用**静态工厂 + 命名常量**包装，别让注册表里出现 10 个字面量。

**`shadowRadius`（SRG `f_114477_`）必须显式设**：默认 0，浮空法术实体忘了设会有贴地黑影。

> 归属要说清：`f_114477_` 是 `net.minecraft.client.renderer.entity.EntityRenderer` 的 `protected float` 字段（不是 `Entity` 的）。
> 实证：`EntityRenderer` 字段数 SRG 5 = 混淆 5；`f_114477_` 在第 3 位 → 混淆 `d` → `client_mappings.txt` 该类段
> `float shadowRadius -> d`（紧邻第 4 位 `f_114478_` → `e` → `float shadowStrength`，与 `setShadowRadius/getShadowRadius` 成对）。
本项目两处实证：浮空黑球 `= 0.0F`（关阴影），Boss `= 0.8F`（放大阴影）。

### 14.18 骨挂点渲染：把特效挂在女仆骨骼上（本项目最难的一段）

需求：黑球实体位置由服务端算（跟随施法者），但客户端要让它**从女仆手心飞出**——
必须拿到骨骼**动画后**的世界矩阵。在 `GeoLayerRenderer.render` 里三步：

```java
// 1. 取骨骼（模型里的挂点名）
AnimatedGeoBone locator = (AnimatedGeoBone) model.bones().get("Blackhole");
if (locator == null || locator.getScaleX() <= 1.0E-4F) return;   // 被动画隐藏了

// 2. 沿 parent() 往上收集，reverse 成「父 → 子」顺序
ArrayList<AnimatedGeoBone> hierarchy = new ArrayList<>();
AnimatedGeoBone bone = locator;
while (bone != null) {
   hierarchy.add(bone);
   GeoBone parent = bone.geoBone().parent();
   bone = parent == null ? null : (AnimatedGeoBone) model.bones().get(parent.name());
}
Collections.reverse(hierarchy);

// 3. local matrix = base⁻¹ · 骨骼矩阵
poses.pushPose();
Matrix4f base = new Matrix4f(poses.last().pose());
RenderUtils.prepMatrixForLocator(poses, hierarchy);
Matrix4f local = base.invert().mul(poses.last().pose());
PalmBlackHoleRenderer.rememberLocator(ritual, local, witch, witchScale, partialTick);
poses.popPose();
```

缓存与消费：

```java
private static final Map<PalmBlackHoleEntity, PalmBlackHoleReleasePose> LOCATOR_POSES = new WeakHashMap<>();
```

- **`WeakHashMap` 不是可选项**：实体被卸载后 key 自动失效；用 `HashMap` 就是稳定的内存泄漏。
- 世界坐标 = 施法者插值位置 + `world.getTranslation()`，其中
  `world = translate(0, 0.01, 0) · rotateY(180° − lerp(yBodyRot)) · scale(witchScale) · local`。
- 消费端用**同一个 renderer** 走两条路径：`locatorRender` 布尔 + `try/finally` 复位；
  `modelScale()` 里 `locatorRender ? 1.6F : 0.0F`，`translateToCenter()` 里判断是否走骨骼矩阵。

**三个必踩细节**：

1. 骨骼缩放到 0（动画隐藏骨骼）时，反算矩阵会得到退化/NaN 矩阵 → **先判 `getScaleX()`**。
2. 用 `visualAge(partialTick)` 而不是 `tickCount`，否则实体移动时特效抖动。
3. 渲染器实例在 Layer **构造器里 new 一次**，绝不能在 `render()` 里 new（每帧一个对象）。

### 14.19 女仆动画接入：`@LittleMaidExtension` + Provider 竞争 + 序号防重播

TLM 的扩展入口是一个带注解的类，**不需要手动注册**：

```java
@LittleMaidExtension
public class MagicAnimationExtension implements ILittleMaid {
   @OnlyIn(Dist.CLIENT)
   public void addAdditionGeckoMaidLayer(GeckoEntityMaidRenderer<? extends Mob> r, Context ctx) {
      if (IronsSpellbooksCompat.isLoaded()) r.addGeoLayerRenderer(new PalmBlackHoleLocatorLayer(r, ctx));
   }
   @OnlyIn(Dist.CLIENT)
   public void registerMagicCastingAnimation(MagicCastingAnimationManager m) {
      if (IronsSpellbooksCompat.isLoaded()) {
         m.register(new ISSCastingAnimationProvider());
         m.register(new WinefoxActionAnimationProvider());
      }
   }
}
```

**三条纪律**：

- `@LittleMaidExtension` 打在类上 + `implements ILittleMaid`，由 TLM 自己扫描发现。
- 每个回调都要在**体内** `if (Compat.isLoaded())` 守卫，且**签名里不能出现第三方类型**——
  否则没装 Irons 时类加载直接 `NoClassDefFoundError`。
- `@OnlyIn(Dist.CLIENT)` 不能省：专用服务器上没有 client 包。

**Provider 竞争模型**：`IMagicCastingAnimationProvider` 靠 `getPriority()` 抢顺序（本项目 Winefox 用 `200`），
`IMagicCastingState.CastingPhase` 是唯一的「动画语义」通道：

| Phase | 语义 | 对应 loop 类型 |
| --- | --- | --- |
| `NONE` | 不播（让位给下一个 Provider） | — |
| `START` | 起手 | `PLAY_ONCE` |
| `CASTING` | 持续引导 | `LOOP` |
| `INSTANT` | 瞬发 | `PLAY_ONCE` |
| `END` | 收尾 | `PLAY_ONCE` |

**`claimSerial` 防重播（本项目实证，最容易写错的一处）**：

```java
return state.claimSerial(boss.animationActionSerial()) ? CastingPhase.INSTANT : CastingPhase.NONE;
```

`getMagicCastingState()` **每帧都会被调用**。如果每帧都返回 `INSTANT`，动画会**每 tick 重启**，
表现是「卡在第一帧」而不是「播一遍」。用「动作序号」claim：序号没变就返回 `NONE`。
这是**幂等化**，不是状态机——别用 `boolean 已播放` 标志，动作重入时会失效。

**另一套：`AnimationManager` 状态注册**（用于持续姿态，不是施法）：

```java
AnimationManager.getInstance().register(
    new AnimationState("fly", EDefaultLoopTypes.LOOP, 1,
        boss((b, e) -> !b.isCurtsying() && isHovering(b) && isMoving(e))));
```

- 谓词签名 `BiPredicate<IMaid, AnimationEvent<?>>`；用一个 `boss(...)` 包装器统一补
  `instanceof + !isSeated()` 前置，避免每个谓词重复写。
- 第 3 个参数（优先级）就是**状态机的先后顺序**，别写成 if-else 链。
- 一次性姿态用 `EDefaultLoopTypes.PLAY_ONCE`（本项目 `curtsy`）。

### 14.20 客户端 BGM 独占：`PlaySoundEvent` 拦截 + 单例管理

```java
@SubscribeEvent
public static void onClientTick(ClientTickEvent event) {
   if (event.phase != Phase.END) return;
   Minecraft mc = Minecraft.getInstance();
   boolean active = hasActiveEncounter(mc);
   if (current != null && (!mc.getSoundManager().isActive(current) || !active)) {
      mc.getSoundManager().stop(current); current = null;
   }
   if (active && mc.options.getSoundSourceVolume(SoundSource.MUSIC) > 0) {
      if (current == null) {
         mc.getMusicManager().stopPlaying();                     // 先掐原版音乐
         current = new SimpleSoundInstance(BGM_ID, SoundSource.MUSIC, 1F, 1F,
             SoundInstance.createUnseededRandom(), true, 0, Attenuation.NONE, 0, 0, 0, true);
         mc.getSoundManager().play(current);
      }
   }
}

@SubscribeEvent
public static void onPlaySound(PlaySoundEvent event) {
   SoundInstance s = event.getSound();
   if (isOurMusicPlaying() && s != null && s != current && s.getSource() == SoundSource.MUSIC)
      event.setSound(null);                                     // 独占：掐掉别的 MUSIC
}
```

**五个要点**：

1. `event.setSound(null)` 的**条件必须排除自己**（`s != current`），否则把自己的 BGM 一起掐了。
2. `current` 用静态字段做**单例**；在 tick 里 `new SimpleSoundInstance` 会每 tick 泄漏一个音源。
3. `Attenuation.NONE` + 坐标全 0 = 非定位音源（BGM 不该随玩家转头忽大忽小）。
4. `LoggingIn` **和** `LoggingOut` 都要 `stopCurrent`：切存档不重置，BGM 会被带进下一个世界。
5. 尊重玩家设置：`options.getSoundSourceVolume(MUSIC) <= 0` 时**不播**，也不要抢音乐通道。

定位音效（跟随实体的声音）另走 `AbstractTickableSoundInstance`（本项目 `PalmBlackHoleSoundInstance` /
`WinefoxSeatedAmbienceSoundInstance`），并在 `tick()` 里判实体存活，实体死了自己 `stop()`。

**判据**：客户端表现类逻辑（音乐、氛围、UI）一律 `MinecraftForge.EVENT_BUS.register(XxxController.class)`
在 `onClientSetup()` 里注册，**不要**混进 mod 事件总线——专用服务器上会白跑一遍。

### 14.37 客户端 HUD：叠加层避让 + 拖拽编辑器 + 预览缓存

自绘 HUD（`IGuiOverlay`）真正的难点不是画，是**不和别人的 HUD 叠在一起**、**缩放后不越界**、**装不下时不溢出**。

**① 注册用相对定位，不用绝对序号**

```java
event.registerAbove(VanillaGuiOverlay.HOTBAR.id(), "ender_pocket_status", new EnderPocketHudOverlay());
```

`registerAbove(vanillaId, ...)` 表示「排在原版快捷栏之上」。写死 `order` 数字的话，
别人也插在同一个位置时谁上谁下完全看注册顺序，而注册顺序取决于模组加载序——不可控。

**② render 开头的六项守卫，一项都不能少**

```java
if (mc.player != null && mc.level != null
        && !mc.options.hideGui            // F1 隐藏界面
        && mc.screen == null              // 有任意 GUI 打开时不要画
        && !visibleInfos.isEmpty()
        && EnderPocketClientConfig.HUD_ENABLED.get()) { ... }
```

- 漏 `mc.screen == null` → 打开背包/设置界面时 HUD 还浮在上面，看着像 bug。
- 漏 `hideGui` → F1 截图里带着自己的 HUD。
- 漏 `mc.player/level != null` → 加载世界、断线回主菜单时 NPE（这类崩溃日志里只有 `IGuiOverlay.render` 一行，极难定位）。

**③ 可用高度必须扣掉原版两块「动态高度」**

```java
int usableBottom = screenHeight - Math.max(gui.leftHeight, gui.rightHeight) - 6;
```

`gui.leftHeight` / `gui.rightHeight` 是**药水效果栏和聊天栏当前撑出来的高度**，会随状态变化。
用固定 `screenHeight - 60` 之类的常量，玩家一开聊天框 HUD 就被盖住。

**④ 配置坐标先钳制，再参与布局**

```java
int preferredX = Mth.clamp(config.HUD_X.get(), 0, Math.max(0, screenWidth  - ROW_WIDTH));
int preferredY = Mth.clamp(config.HUD_Y.get(), 0, Math.max(0, usableBottom - ROW_HEIGHT));
```

玩家在 4K 下拖到右下角、换到 1080p 后，存档里的坐标直接越界。**钳制放在渲染期**，
比在保存时钳制可靠——分辨率随时可能变（改窗口大小、切全屏）。

**⑤ 行数自适应 + 逐行降级**

```java
int maxRows = Math.min(visibleInfos.size(), Math.max(0, (usableBottom + 3) / rowPitch));
int visibleRows = maxRows;
int[] position = null;
while (visibleRows > 0 && position == null) {
    int hudHeight = visibleRows * rowPitch - 3;
    position = findNearestFreePosition(preferredX, preferredY, ROW_WIDTH, hudHeight,
                                       screenWidth, usableBottom, exclusions);
    if (position == null) visibleRows--;      // 挤不下就少画一行，而不是放弃或溢出
}
```

降级顺序是「**少显示几条 > 溢出屏幕 > 什么都不显示**」。反过来（直接 return）会让玩家以为功能坏了。

**⑥ 第三方 HUD 避让：可替换 provider + 抛异常即视为「无排除区」**

```java
public final class HudExclusionAreas {
    private static volatile Supplier<List<Rect2i>> provider = List::of;   // 默认无排除区

    public static void setProvider(Supplier<List<Rect2i>> p) {
        provider = p == null ? List::of : p;
    }

    public static List<Rect2i> get() {
        try { return List.copyOf(provider.get()); }
        catch (RuntimeException e) { return List.of(); }    // 别人炸了，我自己照常画
    }
}
```

三个设计点：
- `volatile` + `Supplier`：其他模组可以在任意时刻替换（本项目让 TLM 把自己的 HUD 区域推进来）。
- **默认 `List::of`**：没装任何协作模组时行为完全不变，零成本。
- **`get()` 内 try/catch**：别人的 provider 抛异常不能拖垮我的 HUD 渲染（渲染线程抛异常 = 整个游戏崩）。

**⑦ 候选坐标法：枚举「贴边位置」而不是网格扫描**

```java
xCandidates.add(clamp(preferredX, 0, maxX));
xCandidates.add(0);  xCandidates.add(maxX);                       // 屏幕左右边
for (Rect2i area : exclusions) {
    xCandidates.add(clamp(area.getX() - width - 4, 0, maxX));      // 贴排除区左侧
    xCandidates.add(clamp(area.getX() + area.getWidth() + 4, 0, maxX)); // 贴排除区右侧
}
// y 同理；然后 x × y 全组合里选「与 preferred 的平方距离最小」的那个
long distance = dx * dx + dy * dy;
```

- **候选点只来自「配置点 + 屏幕四边 + 每个排除矩形的四条边」**，数量是 `O(排除区数)`，
  不是把屏幕按像素网格扫一遍。HUD 每帧都画，性能必须算清楚。
- 用**平方距离**比较，不开方（省一次 `sqrt`，且比较结果等价）。
- 贴边留 4px 间隙，避免和排除区像素级接壤。

**⑧ 预览实体缓存：Map + 同步清理**

```java
private static final Map<UUID, EntityMaid> PREVIEW_MAIDS = new HashMap<>();

public static void update(List<MaidInfo> infos) {
    maidInfos = List.copyOf(infos);
    PREVIEW_MAIDS.keySet().removeIf(id -> infos.stream().noneMatch(i -> i.maidUUID().equals(id)));
}
```

HUD 里要画女仆头像时，每次都 `new EntityMaid(level)` 会造成大量临时实体（客户端实体 tick + 内存）。
缓存按 UUID 索引，**数据刷新时同步剔除已消失的 UUID**——只加不清的缓存是长期运行的隐形内存泄漏。

**⑨ 拖拽编辑器：拖 + 输入框双通道，且先 clamp 再显示**

```java
protected void init() {
    ...
    this.clampPosition();        // 打开编辑器第一件事：把坐标拉回合法范围
    this.updateInputValues();    // 再回填到输入框
}
```

- 拖拽（`mouseClicked` 命中预览区 → 记 `dragOffset`）与数字输入框两条通道同时支持：
  鼠标拖给「大概位置」，输入框给「精确像素」。
- 输入框用 `setFilter(只允许整数)`，而不是提交时再校验——非法字符根本进不去。
- `save` / `cancel` 分开：cancel 走 `onClose()` 不写配置。**编辑器必须能反悔**。
- 预览与真实渲染共用同一个 `renderEditorPreview(...)`，保证「编辑时看到的」和「保存后看到的」一致。

### 14.38 客户端注册：一次 enqueueWork 收口 + 相对定位 + 内嵌资源包

**① 客户端事件全部挂在一个 `@EventBusSubscriber(bus = Bus.MOD, value = Dist.CLIENT)` 类上**

```java
@EventBusSubscriber(modid = MODID, bus = Bus.MOD, value = Dist.CLIENT)
public class MaidSpellClientMod {
    @SubscribeEvent
    public static void onClientSetup(FMLClientSetupEvent event) {
        event.enqueueWork(() -> {
            MenuScreens.register(Containers.SPELL_WHITE_LIST.get(), SpellWhiteListScreen::new);
            MenuScreens.register(Containers.WINEFOX_CHALLENGE_CONFIG.get(), WinefoxChallengeConfigScreen::new);
            GeckoLibCompat.initClientSetup();
            registerCompassAngleProperty();
            registerTravelerTitlesCompat();
        });
    }
}
```

- `value = Dist.CLIENT`：专用服务端根本不加载这个类，**不需要在方法体里再判 `Dist`**。
- `MenuScreens.register` 必须放进 `enqueueWork`：`FMLClientSetupEvent` 的触发时机早于部分注册完成，
  直接写会出现「菜单类型还没注册就去绑定界面」的 `null`。
- `registerTravelerTitlesCompat()` 内部才判 `ModList.get().isLoaded("travelerstitles")`，
  再 `MinecraftForge.EVENT_BUS.register(...)`。**可选模组的兼容注册放在方法里判，不要放静态块**——
  静态块执行时机不受控，可能早于 `ModList` 就绪。

**② 各类注册用对应的专用事件，不要挤在 setup 里**

| 要注册的东西 | 事件 | 备注 |
| --- | --- | --- |
| 界面绑定 | `FMLClientSetupEvent` + `enqueueWork` | 构造器引用即可 |
| 粒子 Provider | `RegisterParticleProvidersEvent` | `registerSpriteSet(type, Provider::new)` |
| 按键 | `RegisterKeyMappingsEvent` | 一个 `KeyMapping` 常量 |
| HUD 叠加 | `RegisterGuiOverlaysEvent` | `registerAbove(vanillaId, name, overlay)` |
| 额外模型 | `RegisterAdditional` | 物品/方块模型在模型烘焙前注册 |
| 实体渲染器 | `RegisterRenderers` | `registerEntityRenderer(type, Renderer::new)` |
| 图层定义 | `RegisterLayerDefinitions` | `registerLayerDefinition(LAYER_LOCATION, Model::createBodyLayer)` |

**③ 共享模型 + 独立图层定义**

```java
event.registerLayerDefinition(SharedHaloModel.LAYER_LOCATION,  SharedHaloModel::createBodyLayer);
event.registerLayerDefinition(UnholyHaloModel.LAYER_LOCATION, UnholyHaloModel::createBodyLayer);
```

`SharedHaloModel` / `UnholyHaloModel` 都是 40 行的小类，**几何形状共用、只差贴图**。
做「同一个挂点、多种外观」时按外观拆 Model 类、共用 `createBodyLayer()` 结构，
比在一个 Model 里塞 `if (isUnholy)` 好——渲染层不该有分支状态。

**④ 内嵌资源包：用 `RepositorySource` 把 `legacy_pack` 目录挂成默认包**

```java
public class LegacyPackRepositorySource implements RepositorySource {
    public void loadPacks(Consumer<Pack> consumer) {
        IModFile modFile = ModList.get().getModFileById(MODID).getFile();
        Path legacyPackPath = modFile.findResource("legacy_pack");     // ← 必须用 findResource
        Pack pack = Pack.create(id, title, false,
                id -> new PathPackResources(id, legacyPackPath, false),
                PackType.CLIENT_RESOURCES, Position.TOP, PackSource.BUILT_IN);
        if (pack != null) consumer.accept(pack);
    }
}
```

三个坑：
- **路径必须走 `modFile.findResource("legacy_pack")`**，不能用 `Paths.get("...")` 或写死相对路径。
  dev 环境是 `build/resources/main`，生产环境是 jar 内路径，`findResource` 是唯一两端都对的方式。
- `Position.TOP` 让这个包默认排在资源包列表顶部，玩家不需要手动拖。
- `Pack` 的 id 用 `modid_xxx` 前缀，避免与其他模组的内嵌包撞名（撞名会互相覆盖贴图，且不报错）。

**⑤ 客户端类统一 `@OnlyIn(Dist.CLIENT)`**

```java
@OnlyIn(Dist.CLIENT)
public final class EnderPocketHudOverlay implements IGuiOverlay { ... }
```

`@OnlyIn` 不只是文档标注：它在**类被加载到错误侧时立刻抛异常**，
比「运行到某个方法才 NPE」早得多。配合 §14.35 的 `DistExecutor.unsafeRunWhenOn`，
形成「类不会被加载 → 加载了立刻报错」的双层保护。