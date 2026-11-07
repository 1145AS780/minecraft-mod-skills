---
name: "minecraft-mod-maker"
description: "Minecraft 模组制作器。按从 0 到 1 的流程做模组：需求→MVP 切片→DeferredRegister 注册物品/方块/实体→创造组/工具提示/合成表→datagen 模型与语言文件→runClient 测试→reobf 打包。与 minecraft-mod-dev/Mixin 映射等深水区互补，适合边做边走通全流程。当要做一个模组、加一个物品/方块/合成表/实体、出可用 jar 时调用。"
---

# Minecraft 模组制作器

把「想法」落实到「能跑的模组」的完整制作流程（1.20.1 / Forge 视角）。

## 1. 先想清楚再动手

- **MVP 化**：下一个想法第一步只做一个可验证切片（例：先能注册一个物品并能拿到手里），再逐步加逻辑。
- **列清单**：要东西（物品/方块/实体/合成/标签/语言/纹理/数据生成/联机）。
- 规划依赖软硬：是否依赖其他 mod（车万女仆等）→ 软依赖策略见 `minecraft-mod-dev` §7。

## 2. 初始化与主类骨架

```
@Mod(GeneratedMod.MOD_ID)
public class GeneratedMod {
    public static final String MOD_ID = "modid";
    public GeneratedMod() { /* 注册网络/配置等早期初始化 */ }
}
```
- `META-INF/mods.toml` 声明 modid、版本、loader 版本区间、依赖（软依赖 `mandatory=false`）。
- 模组目录约定：代码 `src/main/java`，资源 `src/main/resources/{assets,data,META-INF}/`。

## 3. 物品/方块/实体注册（DeferredRegister）

```java
public static final DeferredRegister<Item> ITEMS =
    DeferredRegister.create(ForgeRegistries.ITEMS, MOD_ID);
public static final RegistryObject<Item> MY_ITEM =
    ITEMS.register("my_item", () -> new Item(new Item.Properties()));
```
- 注册推进：`ITEMS.register(Bus.MOD)`（`eventBus.addListener` 或在 `@Mod` 里）。
- 创造组：`new Item.Properties().tab(CreativeModeTabs.TAB)`（指定生成/工具/红石/食物/战斗等 Tab）。

## 4. 配方与标签

- 合成表：`data/<modid>/recipes/*.json`（crafting_shaped/shapeless）。
- 物品分类标签：`data/<modid>/tags/items/*.json`，服务端按 tag 逻辑判定武器/食物/图腾等。
- 熔炼/锻造同理放 `recipes/`；标签能显著简化物品逻辑判断。

## 5. 模型与语言文件

- 纹理：`assets/<modid>/textures/item|block/*.png`（物品 16x16）。
- 模型：`assets/<modid>/models/item/*.json`（`{"parent":"minecraft:item/generated","textures":{"layer0":"modid:item/my_item"}}`）。
- `assets/<modid>/lang/zh_cn.json`、`en_us.json`：`"item.modid.my_item":"名字"`（UTF-8）。
- 数据生成（datagen）可自动化模型/合成/语言，减少手写 JSON 出错。

## 6. 逻辑、事件与网络

- 事件处理用 `@SubscribeEvent`（登录/掉落/按键/客户端 tick 等），别在 tick 里懒建网络频道。
- 客户端=服务端事件区分：客户端事件进客户端线；频道消息跨端用 SimpleChannel（见 `minecraft-mod-dev` §5）。
- 按键/交互逻辑：先判断服务端 `level.isClientSide`，避免双击/双执行。

## 7. 测试闭环（每步都 runClient）

- 改完 → `.\gradlew runClient`（本技能低版本 demo 首次做即可），单人次建世界验证新增内容可用。
- 有崩溃看 `run/logs/latest.log` 的 `Caused by:`（OOM/映射/缺依赖，见 `minecraft-mod-dev` §3/§9）。
- 把「可进世界 + 新物品可在创造拿到 + 可合成」作为验收门槛。

## 8. 打包发布

- `.\gradlew build` 零错误 → 用 `build/libs` 里 **reobf 后的 jar**（运行时 SRG 版）发给玩家/服务端。
- `mods.toml` 依赖软硬正确；玩家端/服务端版本一致。
- 把可复用的「注册-模型-语言-合成-测试」套路沉淀进本项目技能，避免下次重踩。

## 9. 与其它两技能的协作

- 深水区/Mixin/映射问题 → 查 `minecraft-mod-dev`。
- 环境/构建/镜像/依赖拉取问题 → 查 `minecraft-java-build-env`。
- 三者配合：**构建环境是地基，注册建模是主体，混入 Mixin 时再求深水区**。