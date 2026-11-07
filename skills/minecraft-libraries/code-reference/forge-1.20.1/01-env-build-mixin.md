# 基础：开发环境 / 命名映射 / Mixin / 事件总线 / 网络频道 / 资源包 / 依赖获取

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)

## 1. 开发环境与构建

ForgeGradle 6.x 两个核心命令：

```
.\gradlew build      # 编译 + 打包 + reobfJar（产出 SRG 运行时 jar）
.\gradlew runClient  # 启动客户端→进主菜单/世界，验证运行
```

关键约定：
- `runtimeOnly`/`implementation` 依赖只对当前模组可见；**第三方模组运行时依赖需打进它自己的 jar**，否则其 `ModuleClassLoader` 找不到类（报 `NoClassDefFoundError`）。
- 对第三方 mod jar 补运行库时，优先用 `ZipOutputStream` 的安全注入工具（逐条复制后追加），**不要用 `jar uf`**——会破坏 `SecureJar` 结构。
- 发布版玩家 jar 应跑 `reobfJar`；内部 `mods.toml` 里的依赖软硬由 `mandatory=true/false` 控制。
- 第三方依赖从哪取、CurseForge 直链怎么拼、下载后怎么校验，见 §15。

## 2. 命名映射（Mappings）：Mojmap vs SRG

- 开发期用 Mojang 官方名（mojmap，`net.minecraft.world.entity.Mob`、`f_{id}` 是 SRG 名）。
- 运行时（reobfJar 后 / 玩家端）加载的是 **SRG 名**。
- Forge 在 dev 环境用 `net.minecraftforge.gradle.GradleStart.srg.srg-mcp` 指向的 `output.srg` 做运行时反向映射，把第三方 mod 的 SRG 名转回 mojmap，让 dev 调试可用。

**读反编译代码必换的 SRG 名**（1.20.1 反编译产物实测，左为所见、右为 mojmap 真名）：

| 反编译所见 | 实际 mojmap | 归属 |
| --- | --- | --- |
| `m_6274_()` | `getBrain()` | `LivingEntity`（不是 `Entity`） |
| `m_21879_(type, v)` | `setMemory(type, v)` | `Brain` |
| `m_21952_(type)` | `getMemory(type)` → `Optional` | `Brain` |
| `m_21936_(type)` | `eraseMemory(type)` | `Brain` |
| `f_19797_` | `tickCount` | `Entity` |
| `m_20148_()` | `getUUID()` | `Entity` |
| `m_5448_()` | `getTarget()` | `Mob` |
| `m_20270_(e)` | `distanceTo(e)`（返回 `float`，**不是** `distanceToSqr`） | `Entity` |
| `m_19879_()` | `getId()` | `Entity` |
| `m_135785_(...)` | `ResourceKey.create(ResourceKey, ResourceLocation)` | `ResourceKey` |
| `f_256858_` | `Registries.DIMENSION`（`Registries` 里**没有** `LEVEL` 字段） | `Registries` |
| `f_26372_` | `MemoryModuleType.ATTACK_TARGET` | `MemoryModuleType` |

> **这 12 条的实证方式（2026-11 全量复核，已闭环）**
> 1. `javap -p` 导出 SRG 类（`joined-*-srg.jar`）与混淆类（`client.jar`）的成员列表，按下标逐位对齐；
> 2. 取 SRG 成员在混淆类同一下标的名字，得到 obf 名；
> 3. 在 `client_mappings.txt` 的该类段里按 **obf 名精确（大小写敏感）** 过滤，再用 javap 里的
>    返回类型 + 参数类型 + 泛型签名消歧。
>
> 前提校验（SRG 侧与混淆侧成员数必须相等，否则下标对齐不成立）：
> `Entity` 字段 112=112 / 方法 437=437；`LivingEntity` 104=104 / 303=303；`Mob` 40=40 / 136=136；
> `Brain` 14=14 / 53=53；`ResourceKey` 4=4 / 12=12；`Registries` 88=88 / 4=4；`MemoryModuleType` 99=99 / 5=5。
>
> **两个容易踩的实证陷阱（本表就是踩过之后改对的）**
> - **大小写必须敏感**：ProGuard 短名会同时出现 `a`/`A`、`e`/`E`、`ct`/`cT`、`aH`/`ah`。
>   用不区分大小写的比较，会把 `Registries.DIMENSION`(`aH`) 和 `STRUCTURE_POOL_ELEMENT`(`ah`) 混成一条，
>   从而把 `f_256858_` 误判成根本不存在的 `Registries.LEVEL`。
> - **同名多候选要靠类型消歧，不能靠“看起来像”**：`Entity` 的 obf `e` 同时对应
>   `float distanceTo(Entity)` 与 `double distanceToSqr(Vec3)`，SRG 侧是 `float m_20270_(Entity)`，
>   所以只能是 `distanceTo`。凭语义猜「距离平方」会直接写错。

判断一份反编译产物是不是 SRG 空间：`m_[0-9]+_` / `f_[0-9]+_` 高频出现即是。
把这几条换回真名，大部分 AI 行为逻辑（Brain 记忆读写、目标追踪）立刻可读。

## 3. Mixin 与 refmap（重点坑）

- Mixin 注解里写 mojmap 对象名，通过 `refmap` + `createSrgToMcp` 映射链在编译期生成 `.refmap.json`，运行时由 Mixin 面板把目标还原成正确名字。
- **`@Shadow` 普通字段在 dev 环境找不到（`was not located in the target class`）**：
  普通 `@Shadow` 字段查找依赖 Forge 提供的 **srg↔mcp 反射 remapper**，而**第三方 jar 里的 mixin 在 dev 环境拿不到这个 remapper**，因此其 `@Shadow` 字段会定位失败并崩溃。
  规避：a) 去掉含此类 mixin 的发布版 jar，只保留源码构建的 named jar；或 b) 编辑第三方 `mixins.json` 摘除含普通 `@Shadow` 字段的 mixin 类。
- `@Inject`/`@Accessor` 走的是与 `@Shadow` 不同的、可被重映射的链路，相对不易出此问题。
- 本模组若无 mixin，发布版无需 refmap，天然规避此类崩溃。

## 4. 事件总线与初始化

- `@Mod` 构造器里做配置注册与早期初始化（如提前触发网络频道创建）。
- **SimpleChannel 要在模组构造/静态初始化期创建**（官方与社区推荐的规范写法：频道在 `@Mod` 构造器或静态块里 `newSimpleChannel`，不要在首次 tick 才惰性注册）。本项目曾因延迟到 tick 首次触碰才创建而崩出 `Registration of impl channels is locked`（详见 §10，此为实测观察串）。
- Forge 事件：`ForgeEventFactory.onPostClientTick` → `ClientTickEvent` 等，事件处理器用 `@SubscribeEvent` 注册到事件总线。

## 5. 网络频道（SimpleChannel）

```java
public static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
    new ResourceLocation(MOD_ID, "learn"),
    () -> PROTOCOL, PROTOCOL::equals, PROTOCOL::equals);

CHANNEL.registerMessage(id, MsgClass.class, 编码, 解码, (msg, ctx) -> { ... });
```

- 客户端 → 服务端用 `CHANNEL.sendToServer(msg)`；服务端回传用 `ctx.enqueueWork` + 对端追踪器。
- 记录类（record）作为 payload 时，注意编解码的字段顺序必须一致。

## 6. 数据包 / 资源包 / 标签

- 物品分类用标签：`data/<modid>/tags/items/*.json`，服务端按 tag 判定“武器/食物/护甲/图腾/药剂”等。
- 语言文件 `assets/<modid>/lang/{zh_cn,en_us}.json`，UTF-8；菜单/存档路径等中文均在 mods.toml 与 lang 中出现，注意终端乱码≠文件损坏（GBK 解码 UTF-8 的假象）。

## 15. 依赖获取与下载（CurseForge 直链与校验）

**直链格式**（`mediafilez.forgecdn.net`）：

```
files/<文件 id 前 4 位>/<后 3 位，去前导零>/<文件名>
```

- 例：`6472034` → `6472/34`；**写成 `6472/034` 直接 403**。
- 这个坑的隐蔽性在于：`6688854` → `6688/854` 后三位恰好没有前导零，所以正常；**只有文件 id 的后三位含前导零时才会炸**。Psi 就这么挂过一次，而同一批里的 Ars 不触发——只拿「随便一个 id」试，很容易漏掉这个规则。
- 取后三位的正确姿势是字符串切片后**转整数**（整数化自动吃掉前导零），等价于 `id % 1000`：

```powershell
$id='6472034'; $s="$id"; $file='<文件名>.jar'
$url = "https://mediafilez.forgecdn.net/files/$($s.Substring(0,4))/$( [int]$s.Substring(4) )/$file"
```

**元数据接口**：

| 接口 | 状态 | 说明 |
| --- | --- | --- |
| `api.curseforge.com` | **403** | 直连需 API key，不适合临时取数 |
| `api.cfwidget.com` | 可用 | 免 key，`files[]` 直接带 `id` / `filesize` / `versions` |
| `api.modrinth.com` | 可用 | 免 key，另一套 id 体系，适合做交叉来源 |

**下载后必查三件事**（少一件就会把坏包带进 dev 环境）：

1. **字节数 == `filesize`**：接口返回的大小与实际文件逐字节对不上就别解包。
2. **zip 能打开且 entry 数正常**：`[System.IO.Compression.ZipFile]::OpenRead` 能开、条目数与预期同量级（不能只是几百字节的占位包）。
3. **`META-INF/mods.toml` 的 `modId` 符合预期**：文件名里的模组名不可信；`-all.jar` 还要**下钻内层 jar** 再读一次 `mods.toml`（接口下到的常常是壳）。