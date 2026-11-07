# 光影包（Shaderpack）参考 · Minecraft 1.20.1 / Iris · OptiFine

> 适用读者：写 Forge 1.20.1 模组、需要适配光影、排查光影兼容问题的开发者。
>
> 本文只讲 **shaderpack**（Iris / OptiFine 的光影包），不讲资源包（resource pack）的 `pack.mcmeta`、blockstates/models/textures 规范——那是另一篇。
>
> 版本口径：**Minecraft 1.20.1** 对应的 Iris / OptiFine。所有结论尽量给出来源；没有官方依据的地方明确标注「未验证」。

---

## 0. 概念速查

### 0.1 shaderpack 与 resource pack 不是一回事

| 维度 | shaderpack（光影包） | resource pack（资源包） |
|---|---|---|
| 安装目录 | `.minecraft/shaderpacks/`（或实例目录下同名目录） | `.minecraft/resourcepacks/` |
| 入口文件 | `shaders/` 目录 + `shaders/shaders.properties` | `pack.mcmeta` + `assets/` |
| 由谁加载 | **Iris / Oculus / OptiFine**（原版不认） | 原版 Minecraft 即可 |
| 作用 | 替换/接管渲染管线（gbuffers、阴影、后处理） | 替换贴图、模型、字体、音效、语言 |
| 是否互斥 | 与资源包可同时启用 | 与光影包可同时启用 |
| 1.20.1 需不需要装 mod | **需要**（Iris/Oculus/OptiFine 之一） | 不需要 |
| 典型文件 | `.zip`（内含 `shaders/`）或文件夹 | `.zip`（内含 `pack.mcmeta`） |

要点：

- shaderpack **不需要** `pack.mcmeta`。它只有 `shaders/` 这一层约定，外加可选的 `shaders/lang/`、`shaders/textures/`、`shaders/block.properties` 等。
- shaderpack 的 zip 与文件夹两种形态都可用（OptiFine 文档：`$minecraftfolder/shaderpacks/*.zip` 或 `*/`）。
- 光影包本身不改方块贴图；PBR 的 `_n` / `_s` 贴图是**资源包**提供的，光影只负责采样（见第 8 节）。

### 0.2 OptiFine vs Iris vs Sodium（以及 Forge 侧的 Oculus / Embeddium）

| 名称 | 角色 | 平台 | 与光影的关系 |
|---|---|---|---|
| **OptiFine** | 一体化优化 + 光影加载 + 资源包扩展特性 | Forge / 独立安装（1.20.1 有 Forge 版） | 自己加载 shaderpack；闭源 |
| **Iris** | 专用光影加载器，兼容 OptiFine 光影包 | Fabric / Quilt（1.21.1+ 另有 NeoForge） | 加载 shaderpack；**依赖 Sodium** |
| **Sodium** | 渲染优化 mod | Fabric | **不含光影功能**；Iris 依赖它 |
| **Oculus** | Iris 的非官方 Forge 移植 | Forge（1.20.1 可用） | 在 Forge 上加载 shaderpack；依赖 Embeddium |
| **Embeddium** | Sodium 的 Forge 移植 | Forge | 渲染优化；不含光影 |

官方口径（CurseForge 的 Iris FAQ）：

- Iris **不支持 Forge**；Forge 1.20.1 及以下请用非官方移植 **Oculus**。
- Sodium 是 Iris 的**必需依赖**。
- Embeddium 是「最新的 Sodium Forge 移植」，Oculus 需要它（并提示可能需要手动删掉过时的 Rubidium）。

> 对写 Forge 1.20.1 模组的你：开发环境里同时出现 OptiFine、Oculus、Rubidium、Embeddium 中的多个，是典型的崩溃来源。只保留一套（Oculus + Embeddium，或 OptiFine）。

### 0.3 1.20.1 版本矩阵

| 组件 | 1.20.1 对应版本 | 依据 / 说明 |
|---|---|---|
| Iris | **1.6.x**（可查到的 1.20.1 构建为 `iris-mc1.20.1-1.6.17`） | CurseForge 文件页；1.6.9+1.20.1 的 changelog 写明「Updated to Sodium 0.5.3 on 1.20.1」 |
| Sodium | **0.5.x** | 同上；具体小版本以 Modrinth/CurseForge 的 game version 过滤为准 |
| OptiFine | **1.20.1 HD U I 系列**（写稿时 optifine.net 可下载 `OptiFine_1.20.1_HD_U_I6.jar`，另有 I6 pre 版） | optifine.net 下载页 |
| Oculus | `1.20.1-1.8.0`（第三方站点列出） | **未在官方页逐条核实**；以 CurseForge 的 1.20.1 过滤结果为准 |
| Embeddium | 1.20.1 线（具体版本号未核实） | 以 CurseForge/Modrinth 的 game version 过滤为准 |
| Forge | 47.x（1.20.1 线） | Forge 版本线 |
| Fabric Loader / Fabric API | 按 1.20.1 过滤 | — |

**不要背版本号**，装之前一律按 game version = 1.20.1 过滤，并检查依赖（Iris→Sodium；Oculus→Embeddium）。

### 0.4 安装路径与目录形态

```
.minecraft/                      # 或启动器实例目录
├── shaderpacks/
│   ├── ComplementaryShaders_v4.7.2.zip
│   └── MyPack/                  # 解压后的文件夹也可以
│       └── shaders/
│           ├── shaders.properties
│           ├── gbuffers_basic.vsh
│           ├── gbuffers_basic.fsh
│           ├── composite.fsh
│           └── ...
├── config/                      # Iris/Sodium 的配置文件目录
└── logs/
    └── latest.log
```

- 光影包在游戏内通过视频设置里的 Shaders / Shader Packs 界面选择（Iris 与 OptiFine 都有该界面）。**不要**记录任何未经官方文档确认的「重载快捷键」——本文只写有文档依据的调试手段（见第 10 节）。
- Iris 会把当前选中的光影包记录在 `config/` 下的配置里；具体文件名随版本变化，**未验证**，排查时直接看 `config/` 目录即可。

---

## 1. 最小可运行包

### 1.1 目录树

一个能加载、能出画面的最小包：

```
shaderpacks/Minimal/
└── shaders/
    ├── shaders.properties      # 可以为空文件，但建议存在
    ├── gbuffers_basic.vsh
    ├── gbuffers_basic.fsh
    ├── final.vsh
    └── final.fsh
```

说明：

- `shaders/` 是唯一必需目录；`shaders.properties` 缺失时按默认值运行，但建议显式提供。
- 没有 `gbuffers_terrain` 也没关系：Iris/OptiFine 有 fallback 链（`gbuffers_terrain` → `gbuffers_textured_lit` → `gbuffers_textured` → `gbuffers_basic`），最终没有就使用内置 shader（见 Iris gbuffers 文档的 fallback 表）。
- **不要**把 `pack.mcmeta` 放进 shaderpack；它不是资源包。

### 1.2 最小 `gbuffers_basic`（`#version 330 compatibility`）

`shaders/gbuffers_basic.vsh`：

```glsl
#version 330 compatibility

// gbuffers-style 程序：顶点 + 片元必需
// 顶点着色器必须写 gl_Position

out vec2 texcoord;
out vec4 glcolor;

void main() {
    // ftransform() = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex
    gl_Position = ftransform();

    // 纹理坐标：图集坐标（gbuffers 阶段图集是绑定的）
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    // 顶点色：包含生物群系 tint；开启 separateAo 时 ao 在 a 通道
    glcolor = gl_Color;
}
```

`shaders/gbuffers_basic.fsh`：

```glsl
#version 330 compatibility

uniform sampler2D gtexture;     // 主纹理图集（旧写法 texture 在 330 中为保留字）
uniform float alphaTestRef;     // cutout 的 alpha 阈值

in vec2 texcoord;
in vec4 glcolor;

// RENDERTARGETS 必须是多行注释，且独占一行
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;   // 写入 colortex0

void main() {
    color = texture(gtexture, texcoord) * glcolor;

    // gbuffers_basic 本身不是 cutout 程序，这里的 discard 仅作示范；
    // 真正需要 alpha test 的是 terrain / 实体等 cutout 几何。
    if (color.a < alphaTestRef) {
        discard;
    }
}
```

编译要点：

- `#version 330 compatibility` 下 `ftransform()`、`gl_Color`、`gl_MultiTexCoord0`、`gl_TextureMatrix[0]` 可用；这是 Iris 官方教程采用的写法。
- `layout(location = 0)` 的 `0` 是 **RENDERTARGETS 列表里的下标**，不是 colortex 编号。`/* RENDERTARGETS: 0 */` 时它们恰好相同；写成 `/* RENDERTARGETS: 5,3 */` 时，`location=0` 写 colortex5、`location=1` 写 colortex3。
- 如果不写 `RENDERTARGETS`/`DRAWBUFFERS`，默认绑定**前 8 个**颜色附件（Iris 文档）。

### 1.3 最小 `final`

`final` 是 composite-style 的最后一趟，直接输出到屏幕；**它不需要也不应该写 `RENDERTARGETS` 去输出到 colortex**。

`shaders/final.vsh`：

```glsl
#version 330 compatibility

out vec2 texcoord;

void main() {
    // 全屏四边形由 Iris/OptiFine 提供，沿用固定管线属性即可
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
```

`shaders/final.fsh`：

```glsl
#version 330 compatibility

uniform sampler2D colortex0;    // gbuffers_basic 写出的颜色
uniform float viewWidth;
uniform float viewHeight;

in vec2 texcoord;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 c = texture(colortex0, texcoord);

    // 演示：一个很轻的暗角，用于确认 final 真的在执行
    vec2 uv = texcoord * 2.0 - 1.0;
    float vig = 1.0 - 0.15 * dot(uv, uv);

    fragColor = vec4(c.rgb * vig, 1.0);
}
```

**最终输出 alpha 建议写 1.0**：window 的 framebuffer 不一定有 alpha 通道，写别的值在部分驱动上没有意义。

### 1.4 最小 `shaders.properties`

`shaders/shaders.properties`（最小但显式）：

```properties
# 关闭原版云，避免和自定义天空互相遮挡（调试期建议）
clouds=off

# 关闭原版水下贴图叠加，便于观察自己写的后处理
underwaterOverlay=false

# 关闭原版暗角（我们自己在 final 里做了一个）
vignette=false
```

空文件也是合法的。字段含义见第 6 节。

### 1.5 `#version 120` 版本对照（OptiFine 老包最常见）

同一功能的老写法，便于读旧包或做双版本兼容：

`gbuffers_basic.vsh`：

```glsl
#version 120

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    gl_Position = ftransform();
    texcoord = gl_TexCoord[0].xy;
    glcolor = gl_Color;
}
```

`gbuffers_basic.fsh`：

```glsl
#version 120

uniform sampler2D texture;   // 只有 #version 120 里 texture 才是合法别名
uniform float alphaTestRef;

varying vec2 texcoord;
varying vec4 glcolor;

/* DRAWBUFFERS:0 */

void main() {
    gl_FragColor = texture2D(texture, texcoord) * glcolor;
    if (gl_FragColor.a < alphaTestRef) discard;
}
```

注意：

- Iris 文档明确指出 `texture` 只在 `#version 120` 中合法，新版本 GLSL 里它是保留字；现代写法请用 `gtexture`。
- `/* DRAWBUFFERS:0 */` 最多只能引用 0–9 号附件；要写 `colortex10` 以上必须用 `/* RENDERTARGETS: ... */`（Iris 文档）。

### 1.6 可选的最小 `shadow` 程序

要看到阴影，至少需要 `shadow.vsh` / `shadow.fsh`（`shadow` 只有这一对文件，所有几何共用，用 `renderStage` 区分）。

`shaders/shadow.vsh`：

```glsl
#version 330 compatibility

out vec2 texcoord;

void main() {
    // 阴影 pass 的模型/视图/投影矩阵由 Iris 设置，ftransform 即可
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
```

`shaders/shadow.fsh`：

```glsl
#version 330 compatibility

uniform sampler2D gtexture;

in vec2 texcoord;

void main() {
    // 只写深度时颜色可以不写；这里写 alpha 供 alpha test 使用
    vec4 c = texture(gtexture, texcoord);
    if (c.a < 0.1) discard;      // 简化：固定阈值，真实包应使用 alphaTestRef
    // 不写 gl_FragData；深度由管线自动写入 shadowtex0/shadowtex1
}
```

（`shadow` 的 fragment 可以没有颜色输出，深度由管线写入；若要写 `shadowcolor0`，用 `/* RENDERTARGETS: 0 */` 指向 shadowcolor0。）

### 1.7 最小包验证清单

| 检查项 | 预期 |
|---|---|
| 游戏能进世界 | 没有红色报错界面、没有崩溃 |
| 画面有变化 | `final` 的暗角可见（说明 final 在跑） |
| 天空/云行为 | `clouds=off` 生效说明 `shaders.properties` 被读到 |
| `logs/latest.log` | 无 shader 编译错误（关键词见第 10 节） |
| 切换光影开关 | 关闭后回到原版渲染，无残留 |

---

## 2. 渲染阶段与程序清单

### 2.1 一帧内的执行顺序

Iris 文档给出的顺序（OptiFine 的管线与其基本一致，但**没有** `setup`/`begin`）：

| 顺序 | 程序 | 类型 | 说明 |
|---|---|---|---|
| 1 | `setup`（无后缀、1–99） | compute-only | 光影包加载后、窗口尺寸变化时执行一次；**仅 Iris** |
| 2 | `begin`（无后缀、1–99） | composite-style | 在主渲染前初始化缓冲；**Iris 文档阶段，OptiFine 无** |
| 3 | `shadow` | gbuffers-style | 从光源视角渲染所有几何到 shadowtex / shadowcolor |
| 4 | `shadowcomp`（1–99） | composite-style | 阴影图的后处理（如降噪、模糊） |
| 5 | `prepare`（1–99） | composite-style | 地形前准备（如生成 LPV、清屏、预计算） |
| 6 | `gbuffers`（**不透明**几何） | gbuffers-style | 地形/实体/方块实体/粒子等 |
| 7 | `deferred`（1–99） | composite-style | 延迟光照（只处理屏幕上可见的不透明像素） |
| 8 | `gbuffers`（**半透明**几何） | gbuffers-style | 默认只有 `gbuffers_water`、`gbuffers_hand_water`、`gbuffers_weather` 在这一步；Iris 通过 `particles.ordering` 等扩展 |
| 9 | `composite`（1–99） | composite-style | 后处理（Bloom、SSR、TAA、色调映射……） |
| 10 | `final`（唯一） | composite-style | 输出到屏幕 |

要点：

- **gbuffers 顺序不固定**（除了不透明组在半透明组之前，以及部分 gbuffers 与 deferred 的关系）。不要假设 `gbuffers_terrain` 一定在 `gbuffers_entities` 之前。
- 后缀规则：composite-style 每个类别最多 100 个程序（无后缀 + 1–99）；`final` 只能有一个。
- compute 阶段在 composite-style 的顶点阶段**之前**执行；一个 pass 最多 27 个 compute（`_a`..`_z`），按字母序串行，`allowConcurrentCompute` 可并发（Iris）。

### 2.2 `shadow` 程序

| 项目 | 内容 |
|---|---|
| 文件名 | `shadow.vsh` / `shadow.fsh`（可加 `.gsh`；Iris 还支持 `.tcs`/`.tes`） |
| 职责 | 从太阳/月亮视角渲染全部几何，写 `shadowtex0`/`shadowtex1`，可选 `shadowcolor0/1` |
| 输入 | 与 gbuffers 相同的顶点属性；`shadowModelView`、`shadowProjection`、`renderStage` 等 |
| 输出 | 深度（自动）、`shadowcolor0/1`（需 `RENDERTARGETS`） |
| 区分几何 | 用 `renderStage` uniform（因为只有一对 shader 文件） |
| 视角 | 默认正交投影，可用 `const float shadowMapFov` 改成透视（Iris 常量 `shadowMapFov`） |

Iris 1.8+ 额外提供 `shadow_solid` / `shadow_cutout` / `shadow_water` / `shadow_entities` / `shadow_block`；**1.20.1 的 Iris 1.6.x 不保证有这些拆分**（未验证），建议只写 `shadow`。

### 2.3 `gbuffers` 程序全表

下表的 fallback 来自 Iris 文档；OptiFine 的 fallback 基本一致（差异见「备注」列）：

| 程序 | 渲染内容 | fallback | 备注 |
|---|---|---|---|
| `gbuffers_basic` | 拴绳（leash）、调试区块边框 | 无 | 最基础的兜底 |
| `gbuffers_line` | 方块选中框、钓鱼线 | `gbuffers_basic` | **Iris 文档列出**；OptiFine 文档未列 `line` |
| `gbuffers_textured` | 世界边界、不支持光照的粒子 | `gbuffers_basic` | |
| `gbuffers_textured_lit` | 支持光照的粒子（大多数粒子） | `gbuffers_textured` | |
| `gbuffers_skybasic` | 天空颜色/地平线、星星、虚空 | `gbuffers_basic` | 无纹理版本 |
| `gbuffers_skytextured` | 太阳、月亮贴图 | `gbuffers_textured` | `sun=false`/`moon=false` 可关闭 |
| `gbuffers_clouds` | 原版云 | `gbuffers_textured` | OptiFine 表里 fallback 写的是 `<none>`；`clouds=off` 可关闭 |
| `gbuffers_terrain` | 静态方块（solid + cutout） | `gbuffers_textured_lit` | 最常写的一个 |
| `gbuffers_terrain_solid` | 仅 solid 地形 | `gbuffers_terrain` | Iris 文档列为**Iris 额外程序**；1.6.x 是否可用未验证 |
| `gbuffers_terrain_cutout` | 仅 cutout 地形 | `gbuffers_terrain` | 同上；Iris 认为 cutout 与 cutout_mipped 无差别 |
| `gbuffers_terrain_cutout_mip` | （历史名）cutout_mipped 地形 | — | **两份官方文档都未列出**；视为不存在（未验证） |
| `gbuffers_damagedblock` | 方块破坏裂纹 | `gbuffers_terrain` | |
| `gbuffers_block` | 方块实体、告示牌文字 | `gbuffers_terrain` | `blockEntityId` 只在这里有效 |
| `gbuffers_beaconbeam` | 信标光柱 | `gbuffers_textured` | |
| `gbuffers_entities` | 实体、名字标签文字 | `gbuffers_textured_lit` | `entityId` 只在这里有效 |
| `gbuffers_entities_glowing` | 光谱效果实体（不含描边本体） | `gbuffers_entities` | **OptiFine 专有；Iris 不识别此文件** |
| `gbuffers_armor_glint` | 物品/盔甲的附魔闪光 | `gbuffers_textured` | |
| `gbuffers_spidereyes` | 蜘蛛/末影人/末影龙的眼睛 | `gbuffers_textured` | 自发光，通常不参与光照 |
| `gbuffers_hand` | 第一人称手与手持物（不透明） | `gbuffers_textured_lit` | |
| `gbuffers_hand_water` | 半透明手持物 | `gbuffers_hand` | 在 deferred 之后 |
| `gbuffers_weather` | 雨/雪（不含粒子） | `gbuffers_textured_lit` | 在 deferred 之后 |
| `gbuffers_water` | 半透明地形（含水） | `gbuffers_terrain` | 在 deferred 之后 |
| `gbuffers_particles` | 粒子（Iris 拆分） | `gbuffers_textured_lit` | Iris 额外；配合 `particles.ordering` |
| `gbuffers_particles_translucent` | 支持半透明的粒子 | `gbuffers_particles` | Iris 额外；需 `particles.ordering=mixed` |
| `gbuffers_block_translucent` | 半透明方块实体 | `gbuffers_block` | Iris 额外；配合 `ENTITY_TRANSLUCENT` |
| `gbuffers_entities_translucent` | 半透明实体 | `gbuffers_entities` | Iris 额外 |
| `gbuffers_lightning` | 闪电、末影龙死亡光束 | `gbuffers_entities` | Iris 额外；注意「颜色写在 lightning，深度写在 basic」 |
| `gbuffers_item` | （历史程序）物品 | `gbuffers_textured_lit` | OptiFine 文档标注「未使用」 |

补充：

- **`gbuffers_entities_glowing`**：OptiFine 文档写它渲染 spectral 实体，Iris 文档明确写「This shader file is not recognized in Iris」。写跨加载器包时不要依赖它。
- **fallback 是链式的**：`gbuffers_terrain` 不存在 → 用 `gbuffers_textured_lit`；再不存在 → `gbuffers_textured` → `gbuffers_basic` → 内置 shader。
- Iris 的额外程序（`particles`、`block_translucent` 等）是 **Iris 1.7/1.8 时代**的文档内容；1.20.1 的 1.6.x 是否全部支持需按版本核对（**未验证**）。对 1.20.1，稳妥做法是只写 OptiFine 时代的程序名。

### 2.4 composite-style：`deferred` / `composite` / `final`

| 项目 | `deferred` | `composite` | `final` |
|---|---|---|---|
| 何时执行 | 不透明几何之后、半透明几何之前 | 半透明几何之后 | 最后 |
| 几何 | 全屏 quad | 全屏 quad | 全屏 quad |
| 典型用途 | 延迟光照、阴影采样、SSAO、SSR | Bloom、TAA、景深、色调映射、雾 | 颜色空间转换 / 输出 |
| 可读 | 所有 colortex / depthtex / shadowtex | 同左 | 同左 |
| 可写 | colortex（`RENDERTARGETS`） | colortex | **屏幕**（不是 colortex） |
| 后缀 | 1–99 | 1–99 | 无 |
| compute | 支持 `.csh`（先于顶点阶段） | 支持 | 支持 |

**为什么 deferred 在 composite 之前**：不透明几何写完后先做一次光照（只对可见像素），再把半透明几何 forward 渲染进去，最后做后处理。这样半透明物体能被光照影响，又不会让延迟光照重复计算透明层。

### 2.5 每个阶段的输入/输出速查

| 阶段 | 主要输入 | 主要输出 |
|---|---|---|
| `shadow` | 顶点属性、`shadowModelView`/`shadowProjection`、`renderStage` | `shadowtex0/1`（深度）、`shadowcolor0/1`（颜色，可选） |
| gbuffers（不透明） | 顶点属性、`gtexture`/`lightmap`/`normals`/`specular`、矩阵 | `colortex0..15`（`RENDERTARGETS`）、`depthtex0` |
| `deferred` | colortex、depthtex0/1、shadowtex0/1、`gbufferProjectionInverse` 等 | colortex（翻转后的 alt 缓冲） |
| gbuffers（半透明） | 同上；通常读 colortex 做折射/反射 | `colortex0` 等、`depthtex0` |
| `composite` | colortex、depthtex、shadowtex | colortex |
| `final` | colortex | 屏幕 |

---

## 3. 着色器文件结构

### 3.1 扩展名与阶段

| 扩展名 | 阶段 | Iris | OptiFine | 备注 |
|---|---|---|---|---|
| `.vsh` | 顶点 | 支持 | 支持 | 必需（gbuffers-style） |
| `.fsh` | 片元 | 支持 | 支持 | 必需（gbuffers-style） |
| `.gsh` | 几何 | 支持 | 支持 | 需要 GL 3.2+ 或 `GL_ARB_geometry_shader4` |
| `.csh` | 计算 | 支持（compute-only / composite-style） | 支持（除 gbuffers 外均可挂） | 需 GL 4.3；需 `#version 430` + `layout(local_size_x=...)` |
| `.tcs` / `.tes` | 细分控制/评估 | 支持（仅 gbuffers-style，需 `TESSELLATION_SHADERS` 标志） | 文档未列出 → 视为不支持（**未验证**） | 只支持三角形 |

文件命名：`<program>.<stage>`，例如 `gbuffers_terrain.vsh`、`deferred2.fsh`、`composite_a.csh`。

### 3.2 `#version`

| 写法 | 典型用途 | 注意 |
|---|---|---|
| `#version 120` | 老包 / 最大兼容 | 可用 `gl_FragColor`、`gl_FragData`、`texture` 别名、`varying` |
| `#version 330 compatibility` | Iris 官方教程风格 | 可用兼容内置（`gl_Color`、`ftransform`），但片元要显式 `out` |
| `#version 330 core` | 纯核心模式 | 不能再用 `gl_Color`/`ftransform`，必须用 `vaPosition`/`vaColor` 等 |
| `#version 430` | compute | 必须配合 local size 声明 |

- Iris 会把 `#version 120` 的包按兼容模式编译，但**不要**混用 `varying` 与 `in/out`。
- **OptiFine 1.20.1 对 `#version 330 compatibility` 的支持未验证**：老 OptiFine 以 `#version 120` + compute 430 为主。若要同时支持两者，最稳的是 `#version 120` 主体（或做两套文件，靠 `#ifdef` 无法切换版本号，因为 `#version` 必须在第一行）。
- 想要「一份代码、多加载器」时，实际做法是：主逻辑放 `#include` 的 `.glsl` 片段，两个入口文件各自写 `#version`。

### 3.3 属性（attributes）

属性只在**顶点阶段**可用，且只在 gbuffers-style（gbuffers/shadow）里存在。1.17+ 的核心属性：

| 兼容名（120） | 核心名（330 core） | 类型 | 含义 |
|---|---|---|---|
| `gl_Vertex` | `vaPosition` | vec3 | 顶点位置（地形相对区块原点，配 `chunkOffset`） |
| `gl_Color` | `vaColor` | vec4 | 顶点色（含 tint；`separateAo=true` 时 AO 在 a） |
| `gl_Normal` | `vaNormal` | vec3 | 模型空间法线 |
| `gl_MultiTexCoord0` | `vaUV0` | vec2 | 图集 UV |
| `gl_MultiTexCoord1/2` | `vaUV2` | ivec2 | 光照图坐标（lightmap） |
| `gl_MultiTexCoord1` (overlay) | `vaUV1` | ivec2 | 实体 overlay（受伤/燃烧） |
| — | `entityColor`（uniform） | vec4 | 实体 tint（不是 attribute） |

Iris/OptiFine 追加的属性（官方属性表）：

| 属性 | 类型 | 可用程序 | 含义 |
|---|---|---|---|
| `mc_Entity` | vec2 | terrain（`gbuffers_terrain`/`gbuffers_water`）、`shadow` | x = `block.properties` 分配的方块 ID（未分配为 `-1`）；y = render type（1 = 流体，-1 = 其它） |
| `mc_midTexCoord` | vec2 | gbuffers（方块类） | 精灵图中心 UV，用于判断 UV 是否越过精灵边界 |
| `at_tangent` | vec4 | 所有 gbuffers/shadow | xyz = 切线，w = 手性（用于翻转 bitangent） |
| `at_midBlock` | vec3 | 方块类 | 到方块中心的偏移，单位 1/64 米 |
| `at_velocity` | vec3 | 实体/方块实体 | 上一帧的顶点偏移（视图空间） |

`at_tangent` 的标准用法（官方示例）：

```glsl
vec3 normal    = normalMatrix * vaNormal;
vec3 tangent   = normalMatrix * at_tangent.xyz;
vec3 bitangent = cross(tangent, normal) * at_tangent.w;
```

### 3.4 varyings（顶点 → 片元）

- 名字与类型必须**逐字匹配**，否则链接失败。
- 片元里没用到的 varying 可能被优化掉；如果顶点着色器写了 `out` 而片元没声明同名 `in`，通常是合法的（不会被链接使用），但反向（片元声明了 `in` 而顶点没有 `out`）会链接失败。
- 整数用 `flat in/out`（例如 `flat out int blockId;`），否则插值会出错。
- 现代写法用 `out`/`in`；`#version 120` 用 `varying`。

### 3.5 `const` 常量

官方识别的常量必须写成**字面量初始化**，并且通常只需出现一次：

```glsl
const int   shadowMapResolution = 2048;   // [512 1024 2048 4096]
const float shadowDistance      = 128.0;  // [64.0 128.0 256.0]
const float shadowMapFov        = 70.0;
const bool  shadowHardwareFiltering = true;
```

- 方括号注释会把它变成「光影设置」里的可选项（Iris/OptiFine 都会扫描）。
- `const int colortex0Format = RGBA16F;` 这类「管线常量」**不是 GLSL 语法**（`RGBA16F` 不是 GLSL 标识符），必须放在块注释里，或自己 `#define RGBA16F 0` 后再写；且必须独占一行（Iris 文档明确要求）。
- OptiFine 文档列出的可识别 const 还包括：`shadowDistanceRenderMul`、`shadowIntervalSize`、`generateShadowMipmap`、`shadowtex0Mipmap`、`shadowtex1Mipmap`、`shadowcolor0Mipmap`、`shadowcolor1Mipmap`、`shadowtex0Nearest`、`shadowtex1Nearest`、`shadowcolor0Nearest`、`shadowcolor1Nearest`、`wetnessHalflife`、`drynessHalflife`、`eyeBrightnessHalflife`、`centerDepthHalflife`、`sunPathRotation`、`ambientOcclusionLevel`、`superSamplingLevel`、`noiseTextureResolution`。

### 3.6 `uniform` 声明

- 声明了但没用到的 uniform 会被 GLSL 编译器优化掉，运行时 location = -1。这**不是**错误，但如果你的代码依赖它「一定有值」就会踩坑。
- 同一个 uniform 可以在多个文件里重复声明，但类型必须一致。
- 不要给 uniform 赋初值（GLSL 不允许）。
- 采样器必须声明为 `uniform sampler2D`；对照 `sampler2DShadow` 只在 `shadowHardwareFiltering` 开启时使用。

### 3.7 `main` 约定

- 顶点：必须写 `gl_Position`（裁剪空间）。
- 片元：必须给声明的每个 `out` 都赋值；`RENDERTARGETS` 绑定了但没写的附件会收到**垃圾数据**（Iris 文档明确警告）。
- 片元可以 `discard`，但会破坏 early-z，慎用在大面积几何上。
- `gl_FragDepth` 若写入，必须在**所有执行路径**都赋值。

### 3.8 `#include`

```
#include "common.glsl"        // 相对当前文件目录
#include "/lib/common.glsl"    // 相对 shaders/ 根目录
```

- OptiFine 文档：最大嵌套深度 **10**。
- 用头文件守卫：

```glsl
#ifndef COMMON_GLSL
#define COMMON_GLSL
// ...
#endif
```

- Iris 会把 include 展开后的代码写到 `.minecraft/patched_shaders/`，报错行号对应展开后的文件（见第 10 节）。

---

## 4. uniforms 全表

约定：

- **可用阶段**一栏写「全部」表示 gbuffers / shadow / composite-style 都能读；写具体程序表示只在那里有意义。
- 标「动态」的 uniform 会随 draw call 变化（如 `entityId`、`entityColor`、`fogColor`），不要缓存。
- 标「未验证」的条目表示官方文档没给出明确类型/取值，不要拿它当硬保证。

### 4.1 矩阵类

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `gbufferModelView` | mat4 | 相机视角的 model-view 矩阵（渲染手时含手部变换） | 全部 |
| `gbufferModelViewInverse` | mat4 | 上者的逆矩阵；把视图空间还原到玩家相对世界空间 | 全部 |
| `gbufferProjection` | mat4 | 相机投影矩阵 | 全部 |
| `gbufferProjectionInverse` | mat4 | 上者的逆矩阵；用于从深度重建视图空间坐标 | 全部 |
| `shadowModelView` | mat4 | 光源视角的 model-view 矩阵 | 全部 |
| `shadowModelViewInverse` | mat4 | 上者的逆矩阵 | 全部 |
| `shadowProjection` | mat4 | 光源投影（默认正交） | 全部 |
| `shadowProjectionInverse` | mat4 | 上者的逆矩阵 | 全部 |
| `normalMatrix` | mat3 | 法线变换矩阵（= model-view 的逆转置的 3x3 部分） | gbuffers / shadow |
| `textureMatrix` | mat4 | 图集 UV 变换矩阵（旧 `gl_TextureMatrix[0]`） | gbuffers / shadow |

标准用法（从深度重建视图空间位置）：

```glsl
vec3 screenToView(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * ndc;
    return view.xyz / view.w;
}
```

### 4.2 相机 / 位置

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `cameraPosition` | vec3 | 相机在世界坐标中的位置 | 全部 |
| `previousCameraPosition` | vec3 | 上一帧的相机位置（TAA/重投影用） | 全部 |
| `sunPosition` | vec3 | 太阳**位置**（视图空间）；长度恒为 `100.0`，方向 = `sunPosition * 0.01` | 全部 |
| `moonPosition` | vec3 | 月亮**位置**（视图空间）；长度恒为 `100.0` | 全部 |
| `shadowLightPosition` | vec3 | 当前最高天体位置（视图空间，长度 `100.0`）；白天等于 `sunPosition`、夜晚等于 `moonPosition`，与阴影 pass 的光照方向一致 | 全部 |
| `upPosition` | vec3 | 视图空间中的「上」方向 | 全部 |
| `chunkOffset` | vec3 | 当前区块相对相机的偏移（地形顶点是区块局部坐标） | gbuffers / shadow（顶点） |

> 注意：地形几何的 `vaPosition` 是**区块局部**坐标，必须加 `chunkOffset` 才是世界坐标。这是写体积雾/世界坐标采样时最常见的错误之一。

### 4.3 世界 / 天气 / 时间

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `worldTime` | int | 当前世界时间（tick，0–23999，一天内的时刻） | 全部（动态） |
| `worldDay` | int | 世界天数 | 全部（动态） |
| `moonPhase` | int | 月相 0–7 | 全部 |
| `frameTime` | float | 上一帧耗时（秒），用于运动模糊/平滑 | 全部 |
| `frameTimeCounter` | float | 持续增长的累计时间（秒），用于程序化动画 | 全部 |
| `rainStrength` | float | 降雨强度 0–1 | 全部（动态） |
| `wetness` | float | 「潮湿度」0–1，随时间平滑，雨停后缓慢下降 | 全部 |
| `isEyeInWater` | int | 0 = 空气，1 = 水，2 = 岩浆，3 = 细雪（1.17+） | 全部 |
| `fogColor` | vec3 | 当前雾颜色（动态） | 全部 |
| `fogDensity` | float | 雾密度 | 全部 |
| `fogMode` | int | 雾模式（动态） | 全部 |
| `skyColor` | vec3 | 天空颜色 | 全部 |
| `sunAngle` | float | 太阳在昼夜循环中的相位 0–1：`0` 日出、`0.25` 正午、`0.5` 日落、`0.75` 午夜 | 全部 |
| `shadowAngle` | float | 同 `sunAngle`，但取自最高天体；范围 0–0.5（0 日落、0.25 午夜、趋近 0.5 日出） | 全部 |

### 4.4 玩家 / 屏幕 / 系统

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `nightVision` | float | 夜视强度 0–1 | 全部 |
| `blindness` | float | 失明强度 0–1 | 全部 |
| `screenBrightness` | float | 游戏「亮度」设置 0–1 | 全部 |
| `hideGui` | bool | 是否隐藏 GUI（F1） | 全部 |
| `viewWidth` | float | 视口宽度（像素） | 全部 |
| `viewHeight` | float | 视口高度（像素） | 全部 |
| `aspectRatio` | float | 宽高比 = viewWidth / viewHeight | 全部 |
| `near` | float | 投影近平面 | 全部 |
| `far` | float | 投影远平面 | 全部 |
| `frameCounter` | int | 帧计数 | 全部 |
| `alphaTestRef` | float | 当前 draw call 的 alpha test 阈值 | gbuffers / shadow（动态） |
| `renderStage` | int | 当前渲染阶段枚举 | gbuffers / shadow（动态） |
| `atlasSize` | ivec2 | 图集尺寸（像素） | gbuffers / shadow |
| `isSpectator` | bool | 是否旁观者模式（Iris 普通 uniform；OptiFine 仅自定义 uniform） | 全部（Iris） |
| `isRightHanded` | bool | 玩家是否右手（手臂模型） | 全部 |
| `currentColorSpace` | int | 当前输出色彩空间（Iris 1.6.4+） | 全部（Iris） |

### 4.5 ID 类（动态）

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `entityId` | int | 当前实体的 ID（`entity.properties` 分配） | `gbuffers_entities` 及其 fallback 链 |
| `blockEntityId` | int | 当前方块实体的 ID（`block.properties` 分配） | `gbuffers_block` |
| `heldItemId` | int | 手持物品 ID（`item.properties`） | 全部 |
| `heldItemId2` | int | 副手物品 ID | 全部 |
| `heldBlockLightValue` | int | 主手光源亮度 | 全部 |
| `heldBlockLightValue2` | int | 副手光源亮度 | 全部 |
| `currentRenderedItemId` | int | 当前正在渲染的物品/盔甲/trim ID | 全部（Iris） |
| `entityColor` | vec4 | 实体 tint 颜色（动态；非 gbuffers 程序里是最后一次的值） | 实体渲染时 |
| `currentSelectedBlockId` | int | 玩家选中的方块 ID | 全部（Iris） |

### 4.6 纹理 / 缓冲采样器

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `gtexture` | sampler2D | 主方块/实体图集（albedo） | gbuffers / shadow |
| `texture` | sampler2D | `gtexture` 的旧别名，**仅 `#version 120` 合法** | gbuffers / shadow |
| `lightmap` | sampler2D | 光照图（动态纹理） | gbuffers / shadow |
| `normals` | sampler2D | 法线图集（`_n`），无资源包时为平坦法线 (127,127,255,255)/255 | gbuffers / shadow |
| `specular` | sampler2D | 高光图集（`_s`），无资源包时全 0 | gbuffers / shadow |
| `colortex0..15` | sampler2D | 16 个颜色附件（1.20.1 的 Iris 1.6.x 上限为 16）；gbuffers 阶段只能采样 4–15 | 全部 |
| `colorimg0..15` | image2D | colortex 的 image load/store 视图（需 `layout(format)`） | 全部 |
| `depthtex0` | sampler2D | 含所有几何（含半透明、含手）的深度 | 全部（deferred 起有效） |
| `depthtex1` | sampler2D | 不含半透明几何的深度 | 全部（deferred 起有效） |
| `depthtex2` | sampler2D | 不含半透明与手部几何的深度 | 全部（deferred 起有效） |
| `shadowtex0` | sampler2D | 含所有几何的阴影深度 | 全部 |
| `shadowtex1` | sampler2D | 不含半透明几何的阴影深度 | 全部 |
| `shadowcolor0/1` | sampler2D | 阴影颜色附件 | 全部 |
| `noisetex` | sampler2D | 白噪声纹理（默认 256×256，RGB8） | 全部 |
| `gaux1..gaux4` | sampler2D | `colortex4..7` 的旧别名 | 全部 |
| `gcolor` / `gdepth` / `gnormal` / `composite` | sampler2D | `colortex0/1/2/3` 的旧别名 | 全部 |

采样器可用性的关键事实：

- **`colortex0..3` 在 gbuffers 阶段不能采样**：Iris 文档明确写「在 gbuffers 程序里采样这些 buffer 会采到图集」。只有 `colortex4..7`（gaux1..4）在 gbuffers 可读。
- `depthtex0/1/2` 在对应的 gbuffers 执行前是**垃圾数据**；`depthtex1` 最早在 `deferred` 才有意义（官方文档原话）。
- `shadowtex1` 只在半透明几何写入 shadow 时才有内容；若影子 pass 关闭或没有写半透明，它可能与 `shadowtex0` 相同/为空（见第 10 节）。
- `noisetex` 可用 `texture.noise=<path>` 替换成自己的图。
- `colorimgN` 在 OptiFine 上只支持前 6 个（0–5）；Iris 支持全部（1.20.1 的 1.6.x 为 16 个）。

### 4.7 属性（非 uniform，但经常与 uniform 混用）

| 名称 | 类型 | 含义 | 可用阶段 |
|---|---|---|---|
| `mc_Entity` | vec2 | 方块 ID + render type | terrain / water / shadow 的**顶点**阶段 |
| `mc_midTexCoord` | vec2 | 精灵中心 UV | 方块类 gbuffers 顶点阶段 |
| `at_tangent` | vec4 | 切线 + 手性 | 所有 gbuffers / shadow 顶点阶段 |
| `at_midBlock` | vec3 | 方块中心偏移（1/64 格） | 方块类 gbuffers 顶点阶段 |
| `at_velocity` | vec3 | 上一帧顶点偏移 | 实体类顶点阶段 |
| `vaPosition` / `vaColor` / `vaNormal` / `vaUV0` / `vaUV1` / `vaUV2` | — | 核心属性名（1.17+） | 顶点阶段 |

`mc_Entity` 的细节（官方）：

- x 分量是 `block.properties` 里 `block.<ID> = ...` 分配的值；未分配为 `-1`。
- y 分量：`1` 表示流体（水、岩浆等），`-1` 表示其它方块。
- 没有 `block.properties` 时会退回到 1.13 之前的数字 ID —— **不要在新包里依赖这个 legacy 行为**。
- ID 是 16 位有符号（-32768..32767）；Iris 1.3 之前是无符号，未分配方块会给 65535。

---

## 5. 缓冲区（buffers）

### 5.1 `DRAWBUFFERS` 与 `RENDERTARGETS`

| 指令 | 形式 | 位置 | 可引用下标 | 说明 |
|---|---|---|---|---|
| `DRAWBUFFERS` | `/* DRAWBUFFERS:XYZ */` | `.fsh` 任意位置 | **0–9** | 旧式；`colortex10+` 无法绑定 |
| `RENDERTARGETS` | `/* RENDERTARGETS: X,Y,Z */` | `.fsh` 任意位置（建议独占一行） | 0–15（1.20.1 Iris） | 新式；推荐 |

规则（官方）：

- 必须是**多行注释** `/* ... */`，不能用 `//`；`RENDERTARGETS` 建议单独一行。
- 列表顺序决定 GLSL 输出变量的 `location`：`/* RENDERTARGETS: 0,3,7 */` 时 `location=0`→colortex0，`location=1`→colortex3，`location=2`→colortex7。
- 三种写法都可用：
  - 旧版：`gl_FragData[i]`
  - 130+：`out vec4 outColorN;`（N = 列表下标）
  - 330+：`layout(location = N) out vec4 name;`
- **声明了但未写入的附件会收到垃圾数据**。分支里一定要给所有输出赋值。
- 没有指令时，默认绑定前 8 个附件（顺序 0..7）。
- gbuffers / deferred / composite 同时最多写 8 个附件（OptiFine 文档明确；Iris 未在该页给出上限，但受驱动限制）。

### 5.2 colortex 的默认行为

| 项目 | 默认值 | 可否修改 |
|---|---|---|
| 数量 | 16 个（`colortex0..15`） | Iris 1.10.5 起 32 个（与本篇 1.20.1/1.6.x 无关） |
| 格式 | `RGBA`（多数机器上是 `RGBA8`） | `const int colortexNFormat = ...;` |
| 尺寸 | 显示分辨率 | `size.buffer.colortexN = <w> <h>`（整数像素 / 浮点屏幕比例；改后 gbuffers 不能写它） |
| 清屏 | 每帧清 | `const bool colortexNClear = false;` |
| 清屏色 | colortex0 = 当前雾色（alpha 1）；colortex1 = 白；其余 = 0 | `const vec4 colortexNClearColor = vec4(...);` |
| mipmap | 无 | `const bool colortexNMipmapEnabled = true;`（写在 composite/deferred/final/prepare 的 fsh） |
| 翻转 | 每帧/每 pass 双缓冲 | `flip.<program>.<buffer> = <true\|false>` |

**双缓冲（ping-pong）机制**（OptiFine 文档描述，Iris 相同）：

- 每个 colortex 实际有 A/B 两份。
- gbuffers 读 main、写 main（且不要同时读写同一个 buffer）。
- deferred/composite 读 main、写 alt；pass 结束后把写过的 buffer 翻转，使下一个 pass 能读到它。
- `deferred_pre` / `composite_pre` 是虚拟程序，用来在 pass 前手动翻转。

### 5.3 声明缓冲区格式 / 清屏 / mipmap

这些「常量」不是 GLSL 语法，**必须放在块注释里**（或先 `#define` 同名标识符），否则编译报错。Iris 文档的示例：

```glsl
/*
const int colortex0Format = RGB16;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA8;
const int colortex5Format = R32F;

const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const bool colortex5Clear = false;         // 跨帧保留（历史/累积缓冲）

const bool colortex2MipmapEnabled = true;  // 放在 composite*.fsh 里
*/
```

注意：

- `format` / `Clear` / `ClearColor` 只需在**任意一个** shader 文件里出现一次。
- `MipmapEnabled` 只在 `composite.fsh` / `deferred.fsh` / `final.fsh` / `prepare.fsh` 的片元阶段有效，并会在该程序前重新生成 mip 链。
- `colortex0/1` 的清屏色有特殊默认值（见上表），不要以为它们一定是黑的。
- 声明 `gdepth` 且格式为 RGBA 时，Iris 会把 `colortex1` 升级为 `RGBA32F`（legacy 行为）。

### 5.4 完整的多缓冲 gbuffers 示例

`gbuffers_terrain.fsh`（输出 albedo + 法线 + 光照图坐标 + 材质 ID）：

```glsl
#version 330 compatibility

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D normals;
uniform sampler2D specular;
uniform float alphaTestRef;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewNormal;        // 由 vsh 传入，已变换到视图空间
in vec2 midTexCoord;

// 写 4 个附件：0,1,2,3
/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outLight;
layout(location = 3) out vec4 outMaterial;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;

    if (albedo.a < alphaTestRef) discard;

    vec4 normalTex = texture(normals, texcoord);   // RGB = 法线，A = 高度
    vec4 specTex   = texture(specular, texcoord);  // labPBR 数据

    outAlbedo   = albedo;
    outNormal   = vec4(normalize(viewNormal), normalTex.a);
    outLight    = vec4(lmcoord, 0.0, 1.0);
    outMaterial = specTex;
}
```

对应的 `gbuffers_terrain.vsh`：

```glsl
#version 330 compatibility

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;
uniform mat3 normalMatrix;
uniform vec3 chunkOffset;      // vaPosition 是区块局部坐标，必须加它

in vec3 vaPosition;
in vec3 vaNormal;
in vec2 vaUV0;
in ivec2 vaUV2;
in vec4 vaColor;
in vec2 mc_midTexCoord;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 viewNormal;
out vec2 midTexCoord;

void main() {
    // 地形顶点是区块局部坐标：先加 chunkOffset 再做模型/视图/投影变换
    gl_Position = gbufferProjection * gbufferModelView * vec4(vaPosition + chunkOffset, 1.0);

    texcoord     = (gl_TextureMatrix[0] * vec4(vaUV0, 0.0, 1.0)).xy;
    lmcoord      = vec2(vaUV2) / 255.0;
    glcolor      = vaColor;
    viewNormal   = normalize(normalMatrix * vaNormal);
    midTexCoord  = mc_midTexCoord;
}
```

（`gl_ProjectionMatrix` / `gl_ModelViewMatrix` 在 `330 compatibility` 下可用；若改用 `330 core`，需要自己组合 `gbufferProjection * gbufferModelView`。）

### 5.5 自定义图像 / SSBO（Iris 扩展）

`shaders.properties`：

```properties
# 半分辨率、RGBA32F、每帧清空的自定义图像
image.cimage1 = cSampler1 rgba rgba32f float true true 0.5 0.5

# 不用覆盖已有 sampler 的自定义纹理
customTexture.colortex7 = textures/noise.png
```

语法（Iris 文档）：

```
image.<imageName> = <samplerName> <format> <internalFormat> <pixelType> <clearEachFrame> <isRelative> <x> <y> <z>
```

- 需要 `CUSTOM_IMAGES` 特性标志；需要 GL 4.2+（macOS 不支持）。
- 写入用 `imageStore`，读取可 `imageLoad` 或用 `<samplerName>` 采样。
- Iris 1.6.4 起最多 16 个自定义图像（之前 8 个）。
- **OptiFine 没有 `image` 指令**（Iris 专有）。

---

## 6. `shaders.properties` 全字段

文件位置：`shaders/shaders.properties`。键名大小写敏感，一行一个 `key=value`，`#` 开头是注释。

### 6.1 设置界面：`screen` / `sliders` / `profile`

| 字段 | 形式 | 作用 | 依据 |
|---|---|---|---|
| `screen` | `screen = <list_of_options>` | 指定主「光影设置」界面显示哪些元素；元素可以是选项名、`[子界面]`、`<profile>`（切换预设的按钮）、`*`（其余未列出的选项）、空项（占位） | Iris shader_settings |
| `screen.<name>` | `screen.<name> = <option1> <option2> ...` | 定义子界面包含哪些选项 | Iris shader_settings |
| `screen.<name>.columns` | `screen.<name>.columns = <2\|3>` | 子界面列数 | Iris shader_settings |
| `sliders` | `sliders = <opt1> <opt2> ...` | 把数值选项以滑块呈现 | Iris shader_settings |
| `profile.<name>` | `profile.<name> = <option>=<value> ...` | 预设配置 | Iris shader_settings |
| `profile.<name>.enabled` | 布尔表达式 | 是否显示该预设 | Iris shader_settings（语法以该页为准） |

选项本身来自代码里的 `const`（带方括号注释即成为可调项）：

```glsl
const int shadowMapResolution = 2048;   // [1024 2048 4096]
const float shadowDistance      = 128.0; // [64.0 128.0 256.0]
const bool  enableBloom         = true;  // [true false]
```

### 6.2 程序开关 / 顺序

| 字段 | 形式 | 作用 | 依据 |
|---|---|---|---|
| `program.enabled` | `program.<program>.enabled = <bool_expr>` | 按选项启用/禁用某个程序；`<program>` 可含维度目录，如 `world0/composite2` | Iris ordering |
| `shadow.enabled` | `shadow.enabled = <true\|false>` | 强制开关阴影 pass（Iris 专有） | Iris ordering |
| `shadowTerrain` | `shadowTerrain = <true\|false>` | 是否在阴影 pass 渲染 solid/cutout 地形 | Iris ordering |
| `shadowTranslucent` | `shadowTranslucent = <true\|false>` | 是否渲染半透明地形 | Iris ordering |
| `shadowEntities` | `shadowEntities = <true\|false>` | 是否渲染实体 | Iris ordering |
| `shadowPlayer` | `shadowPlayer = <true\|false>` | 是否渲染玩家 | Iris ordering |
| `shadowBlockEntities` | `shadowBlockEntities = <true\|false>` | 是否渲染方块实体 | Iris ordering |
| `particles.ordering` | `particles.ordering = <mixed\|after\|before>` | 粒子相对 deferred 的顺序（Iris 专有） | Iris ordering |
| `particles.before.deferred` | `particles.before.deferred = <true\|false>` | 上一项的 legacy 版本（OptiFine 支持） | Iris ordering |
| `separateEntityDraws` | `true` / `false` | 半透明实体/方块实体延后到 deferred 之后，走 `gbuffers_entities_translucent` / `gbuffers_block_translucent`（Iris 专有；文档注明新版 Iris 中该特性已损坏，不要依赖） | Iris ordering |
| `skipAllRendering` | 布尔 | 跳过全部世界渲染（调试用） | Iris ordering |

### 6.3 混合 / alpha test / 缩放

| 字段 | 形式 | 作用 | 依据 |
|---|---|---|---|
| `blend.<program>` | `blend.<program> = <off\|src dst srcA dstA>` | 覆盖某程序的混合模式 | Iris rendering |
| `blend.<program>.<buffer>` | 同上 | 对单个颜色附件分别设置 | Iris rendering |
| `alphaTest.<program>` | `alphaTest.<program> = <off\|func ref>` | 覆盖 alpha test（cutout 程序） | Iris rendering |
| `scale.<program>` | `scale.<program> = <scale>` 或 `= <scale> <offsetX> <offsetY>` | 仅对 composite-style 程序（composite/deferred/prepare 等）改视口；取 0.0–1.0，**不改变输出缓冲分辨率** | Iris rendering |
| `size.buffer.<buffer>` | `size.buffer.colortexN = <w> <h>` | 改 colortex 分辨率：整数按像素、浮点按屏幕比例（`0.75 0.25`）；改过尺寸的 buffer 不能再被 gbuffers 写入 | Iris rendering |
| `flip.<program>.<buffer>` | `flip.<program>.<buffer> = <true\|false>` | 控制 ping-pong 翻转 | Iris rendering |

`blend` 的四个参数对应 `SRC_ALPHA, ONE_MINUS_SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA` 这类枚举名；`off` 表示关闭混合。

### 6.4 视效开关（`features`）

| 字段 | 取值 | 作用 | 依据 |
|---|---|---|---|
| `clouds` | `fast` / `fancy` / `off` | 覆盖原版云设置 | Iris features |
| `sun` | `true` / `false` | 是否在 `gbuffers_skytextured` 画太阳 | Iris features |
| `moon` | `true` / `false` | 是否画月亮 | Iris features |
| `sky` | `true` / `false` | 是否画原版天空盘/地平线/虚空（**Iris 专有**） | Iris features |
| `stars` | `true` / `false` | 是否画星星（**Iris 专有**） | Iris features |
| `underwaterOverlay` | `true` / `false` | 水下贴图叠加 | Iris features |
| `vignette` | `true` / `false` | 原版暗角 | Iris features |
| `oldHandLight` | `true` / `false` | 旧版手持光源（默认 `true`，兼容老包） | Iris features |
| `oldLighting` | `true` / `false` | 原版方向性明暗（默认 `false`） | Iris features |
| `separateAo` | `true` / `false` | 把 AO 从 rgb 移到 a 通道 | Iris features |
| `weather` | `<geometry> <splash>` | 分别开关雨雪几何与溅射粒子（**Iris 专有**，需特性标志） | Iris features |
| `supportsColorCorrection` | `true` / `false` | 由光影自己做色彩空间转换（**Iris 1.6.4+**） | Iris features |
| `endFlashShadows` | `true` / `false` | 末地闪光投影（1.21.9 内容，1.20.1 无意义） | Iris features |

**已知 bug**：Iris 文档写明 `separateAo` 只有在阴影 pass 开启时才生效。

### 6.5 剔除 / 深度

| 字段 | 形式 | 作用 | 依据 |
|---|---|---|---|
| `backFace.<layer>` | `backFace.solid` / `backFace.cutout` / `backFace.cutoutMipped` / `backFace.translucent` = `<true\|false>` | 按渲染层开关背面剔除（默认开启） | Iris rendering |
| `frustum.culling` | `frustum.culling = <true\|false>` | 视锥剔除 | Iris rendering |
| `occlusion.culling` | `occlusion.culling = <true\|false>` | 遮挡剔除（只影响 gbuffers 主 pass；Iris 专有） | Iris rendering |
| `shadow.culling` | `shadow.culling = <true\|false\|reversed>` | 阴影 pass 的剔除；`reversed` 为 Iris 专有（`voxelDistance` 以内不剔除） | Iris rendering |
| `rain.depth` | `rain.depth = <true\|false>` | 雨是否写深度 | Iris rendering |
| `beacon.beam.depth` | `beacon.beam.depth = <true\|false>` | 信标光柱是否写深度 | Iris rendering |

### 6.6 你问题里提到、但**没有**官方依据的字段

| 字段 | 结论 |
|---|---|
| `shadowMapResolution` | **不是 `shaders.properties` 字段**。Iris 文档把它定义为 GLSL 常量 `const int shadowMapResolution = ...;`。旧 OptiFine 的 properties 是否也认同名键：**未验证** |
| `shadowMap` | 在 Iris 当前文档中查不到；`shadowMap` 是常量/概念名而非属性。**未验证** |
| `shadowFilter` | 同上，查不到。**未验证** |
| `particles`（裸字段） | 只有 `particles.ordering` / `particles.before.deferred`；裸 `particles=...` **未验证** |
| `beaconBeam` | 只有 `beacon.beam.depth`；裸 `beaconBeam=...` **未验证** |
| `renderTargets` | Iris/OptiFine 的附件输出由 GLSL 里的 `/* RENDERTARGETS: ... */` 决定，**没有** `renderTargets` 属性（未验证其存在） |
| `culling`（裸字段） | 只有 `frustum.culling` / `occlusion.culling` / `shadow.culling`；裸 `culling` **未验证** |
| `fog`（裸字段） | Iris 文档的 `shaders.properties` 索引里没有 `fog` 属性；雾由代码处理。**未验证** |

> 结论：写包时**不要**凭记忆往 `shaders.properties` 里加这些键；写了也不会报错，但很可能完全不生效（properties 里未知键通常被忽略）。

### 6.7 一个完整的 `shaders.properties` 示例

```properties
# =========================================================
# 设置界面
# =========================================================
screen = <profile> [basic] [effects]
screen.basic.columns = 2
screen.basic = SHADOW_RES shadowDistance enableBloom ENABLE_SSAO
screen.effects = BLOOM_STRENGTH TONEMAP_MODE VIGNETTE_STRENGTH
sliders = SHADOW_RES shadowDistance BLOOM_STRENGTH VIGNETTE_STRENGTH

profile.Low = SHADOW_RES=0 shadowDistance=64.0 enableBloom=false ENABLE_SSAO=false
profile.Medium = SHADOW_RES=1 shadowDistance=128.0 enableBloom=true ENABLE_SSAO=true
profile.High = SHADOW_RES=2 shadowDistance=256.0 enableBloom=true ENABLE_SSAO=true

# =========================================================
# 程序开关
# =========================================================
program.composite6.enabled = ENABLE_SSAO
program.deferred.enabled = true
program.composite12.enabled = !LOW_END

# =========================================================
# 混合 / alpha test / 缩放
# =========================================================
blend.gbuffers_water = SRC_ALPHA ONE_MINUS_SRC_ALPHA ONE ONE_MINUS_SRC_ALPHA
blend.composite4 = off
alphaTest.gbuffers_terrain = GREATER 0.1
alphaTest.gbuffers_entities = GREATER 0.1
scale.composite3 = 0.5
size.buffer.colortex7 = 0.5 0.5

# =========================================================
# 视效
# =========================================================
clouds = off
sun = true
moon = true
sky = true
stars = true
underwaterOverlay = false
vignette = false
oldLighting = false
oldHandLight = false
separateAo = true
weather = true true

# =========================================================
# 剔除
# =========================================================
frustum.culling = true
occlusion.culling = true
shadow.culling = true
rain.depth = false
beacon.beam.depth = true

# =========================================================
# 自定义纹理 / 图像（Iris 专有）
# =========================================================
texture.composite.colortex4 = texture/noise.png
texture.noise = texture/noise.png
customTexture.godraysMask = texture/godrays_mask.png
image.cimage1 = cSampler1 rgba rgba32f float true true 0.5 0.5
```

注意：

- `screen` 里引用的大小写必须与 `const` 选项名完全一致；未在代码里定义的选项不会显示。子界面在 `screen` 里写作 `[名字]`，`<profile>` 是内建的预设切换按钮。
- `profile` 里的选项值必须是**字符串**还是数字，取决于选项类型；数值型直接写数字即可（以上为示例）。也可在预设里写 `!program.composite12` 关闭某程序。
- `alphaTest` 的函数名在 Iris 文档里是**大写枚举**（`NEVER` / `LESS` / `EQUAL` / `LEQUAL` / `GREATER` / `NOTEQUAL` / `GEQUAL` / `ALWAYS`）；老 OptiFine 文档常用小写写法，跨平台包建议以对应版本文档为准。
- `blend.<program>` 只能写 `off` 或四个混合因子（`ZERO` / `ONE` / `SRC_ALPHA` / `ONE_MINUS_SRC_ALPHA` / …），**没有 `on`**。
- `weather = ...`、`image.` 等依赖 Iris 特性标志（如 `GEOMETRY` / `CUSTOM_IMAGES`），没有标志时写了也不生效。

---

## 7. OptiFine 与 Iris 差异表

| 能力 | OptiFine 1.20.1 | Iris 1.20.1（1.6.x） | 说明 |
|---|---|---|---|
| 平台 | Forge / 独立 | Fabric / Quilt（Forge 需 Oculus） | Iris 官方 FAQ |
| 加载 OptiFine 光影包 | 是 | 是（目标是兼容） | Iris 定位即「兼容 OptiFine 包」 |
| `gbuffers_entities_glowing` | 支持 | **不识别该文件** | Iris gbuffers 文档明说 |
| `gbuffers_line` | 文档未列 | 文档列出 | 老包一般用 `gbuffers_basic` 兜底 |
| `gbuffers_terrain_solid/cutout` 拆分 | 文档标注「未使用」 | 文档列为 Iris 额外程序 | 1.6.x 是否可用**未验证** |
| `gbuffers_particles` 等拆分 | 无 | 有（1.7+ 文档） | 1.20.1 是否支持**未验证** |
| compute shader（`.csh`） | 支持（`#version 430`） | 支持，且可在 composite-style 里与顶点阶段同 pass | Iris 支持 `_a`..`_z` 多个 compute |
| `setup` pass | 无 | 有（compute-only） | Iris 文档 |
| `begin` pass | 无 | 有 | Iris 文档 |
| 细分着色器 `.tcs/.tes` | 文档未提 → 视为不支持（**未验证**） | 支持（仅 gbuffers，需标志） | Iris overview |
| `image.<name>` 自定义图像 | 无 | 有（GL 4.2+，最多 16 个） | Iris 专有 |
| `customTexture.<name>` | 无 | 有 | Iris 专有（可避免覆盖原 sampler） |
| SSBO | 无 | 有 | Iris 专有 |
| `colorimgN` 写入范围 | 仅 colortex0–5 | colortex0–15（1.6.x） | Iris colortex 文档 |
| `colortex` 数量 | 16 | 16（1.6.x） | 1.10.5+ 才到 32 |
| `RENDERTARGETS` | 支持 | 支持 | 两者都认 |
| `DRAWBUFFERS` | 支持（0–9） | 支持（0–9） | 两者都认，但不推荐 |
| 程序后缀 | `deferred1..15`、`composite1..15`、`shadowcomp1..15` | 支持到 1–99 | Iris 文档 |
| `shaders.properties` | 基础字段 + `particles.before.deferred` | 额外：`sky`、`stars`、`weather`、`shadow.enabled`、`particles.ordering`、`program.enabled` | 见第 6 节来源 |
| 自定义纹理格式 | `.png` / `.jpg` | **仅 `.png`** | Iris custom_textures 文档 |
| `separateAo` | 支持 | 支持，但**阴影关闭时无效（已知 bug）** | Iris features |
| macOS | 可用（OpenGL） | 无 compute / 无 custom image（无 GL 4.3/4.2） | Iris macOS 页 |
| 资源包特性（CEM/CTM/自定义天空盒等） | 内置 | 需另装 Entity Model Features / Continuity 等 | 生态差异，非光影管线本身 |

**跨加载器写作策略**：

1. 只用 `shadow` + OptiFine 时代的 gbuffers 名字 + `RENDERTARGETS`。
2. 需要 Iris 专有能力时，用特性标志/宏做条件编译，并在 OptiFine 上降级。
3. 不要在 OptiFine 包里引用 `colorimg8+`、`image.*`、`customTexture.*`。
4. 不要假设 `gbuffers_entities_glowing` 在 Iris 上会被调用。

---

## 8. PBR / labPBR

### 8.1 边界：1.20.1 原版**没有** PBR

- 原版 Minecraft 1.20.1 不支持 PBR 材质，也没有 `_n`/`_s` 的概念。
- PBR 数据完全由**资源包**提供，由**光影**采样。Iris/OptiFine 只是把资源包里带 `_n`/`_s` 后缀的贴图额外打包成两个图集：
  - `uniform sampler2D normals;`
  - `uniform sampler2D specular;`
- 如果资源包没有对应贴图，采样结果是固定值（Iris 文档）：

| 图集 | 缺失时的值（0–255） |
|---|---|
| `normals` | R=127, G=127, B=255, A=255（平坦法线） |
| `specular` | R=0, G=0, B=0, A=0（无高光、无自发光） |

- PBR 贴图的命名：与基础贴图同名，加 `_n` / `_s`（如 `cobblestone.png` → `cobblestone_n.png`、`cobblestone_s.png`）。

### 8.2 labPBR 的通道约定（shaderLABS 标准）

**`_s`（specular）**：

| 通道 | 含义 | 取值 |
|---|---|---|
| R | perceptual smoothness（感知光滑度） | 0–255；转线性粗糙度：`roughness = pow(1.0 - s, 2.0)` |
| G | F0 / 金属 | 0–229：线性 F0（229 ≈ 90%）；230–254：预定义金属；255：用 albedo 当 F0 |
| B | 电介质：孔隙率 / 次表面散射 | 0–64 = porosity；65–255 = SSS（线性） |
| A | 自发光 | 0–254；**255 会被忽略**（不要用 255） |

**`_n`（normal）**：

| 通道 | 含义 |
|---|---|
| RG | 法线 XY，**DirectX 约定（Y 向下）** |
| B | 材质 AO（0 = 全遮蔽，255 = 无遮蔽） |
| A | 高度图（POM 用；0 表示 25% 深度，建议最小 1） |

法线 Z 由 `sqrt(1.0 - dot(n.xy, n.xy))` 重建。

### 8.3 在 shader 里解码 labPBR

```glsl
// 可用于 gbuffers_terrain / gbuffers_water / gbuffers_entities（需要 normals、specular 图集）
uniform sampler2D normals;
uniform sampler2D specular;

vec3 decodeNormal(vec4 nTex) {
    vec2 xy = nTex.xy * 2.0 - 1.0;     // [0,1] → [-1,1]
    vec3 n  = vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
    return normalize(n);
}

void decodeLabPBR(vec4 sTex, out float roughness, out float f0, out float emission) {
    float smoothness = sTex.r;                       // perceptual
    roughness = pow(1.0 - smoothness, 2.0);          // 线性粗糙度

    float g = sTex.g * 255.0;
    if (g >= 230.0) {
        // 预定义金属：这里只是占位，真实实现要查表或用 albedo 当 F0
        f0 = 1.0;
    } else {
        f0 = sTex.g;                                  // 已经是线性 0..0.9
    }

    emission = sTex.a >= 254.0 / 255.0 ? 1.0 : sTex.a;
}
```

### 8.4 资源包侧需要配合什么

| 需求 | 资源包侧 | 光影侧 |
|---|---|---|
| 法线 | 提供 `_n` 贴图（DirectX Y-） | 采样 `normals`，重建 Z、做 TBN |
| 粗糙度/金属 | 提供 `_s` 贴图（labPBR 通道） | 采样 `specular`，解码 |
| 自发光 | `_s` 的 A 通道 | 乘到最终颜色 |
| POM/视差 | `_n` 的 A 通道（高度） | 在 gbuffers 里做视差偏移（需要 `at_tangent`/`at_midBlock`） |
| 声明格式 | `texture.properties` 写 `format=lab-pbr/1.3` | 可用宏 `MC_TEXTURE_FORMAT_LAB_PBR` / `MC_TEXTURE_FORMAT_LAB_PBR_1_3` 判断 |

`texture.properties` 放在资源包根目录（不是 `shaders/`）：

```properties
format=lab-pbr/1.3
```

Iris 文档提示：写稿时仅支持 labPBR 1.3，写其它版本可能出错。

### 8.5 与 Forge 模组的关系

- 模组新增的方块/实体只要走原版 `RenderType` 与图集，就能被光影像素级地按 `_n`/`_s` 处理——前提是资源包为这些模组贴图也提供了 `_n`/`_s`。
- 模组自建的自定义 RenderType/直接 GL 绘制**不会**自动进入 gbuffers 的图集采样，需要自己写兼容（见第 11 节）。
- 光影关闭时，`_n`/`_s` 完全被忽略，资源包仍能正常显示（只是没有 PBR 效果）。

---

## 9. 性能

### 9.1 先算清楚数量级

| 项目 | 计算 | 结论 |
|---|---|---|
| 阴影贴图像素数 | `N²` | 1024²=1.05M，2048²=4.19M（4×），4096²=16.8M（16×） |
| 1080p 全屏 pass | 1920×1080 | 2.07M 像素/趟 |
| 半分辨率（`scale=0.5`） | 0.25× 像素 | 一次 0.52M，等于省 75% 的片元调用 |
| 每像素 1 次 2D 采样 | 约 4 字节/样本（RGBA8） | 1080p 一趟 ≈ 8.3 MB 读带宽（未计缓存命中） |
| PCF 16 taps | 16× 阴影采样 | 阴影采样成本 ≈ 16 倍单次；2048² 地图 + 16 taps 是常见瓶颈 |
| composite 10 趟全屏 | 10×2.07M | 20.7M 片元调用/帧 |

结论：**阴影分辨率与全屏 pass 数量**是最容易失控的两项；纹理采样数和 PCF taps 次之。

### 9.2 可量化的调优清单

| # | 手段 | 量化效果 | 代价/注意 |
|---|---|---|---|
| 1 | `shadowMapResolution` 2048 → 1024 | 阴影像素数降到 1/4 | 阴影边缘变糙；远景漏光 |
| 2 | `shadowMapResolution` 4096 → 2048 | 降到 1/4 | 一般画质几乎无感 |
| 3 | PCF taps 32 → 8 | 阴影采样降到 1/4 | 需要更好的降噪/PCSS |
| 4 | `scale.compositeN = 0.5` | 该 pass 片元调用降到 1/4 | 半分辨率模糊，需上采样 |
| 5 | 把雾/Bloom 放半分辨率 | 同上 | 边缘光晕可能外扩 |
| 6 | 删除无用的 `composite` 趟 | 每删一趟省 2.07M 片元调用（1080p） | 检查中间缓冲依赖 |
| 7 | 合并相邻的全屏 pass | 少一次读写往返 | 代码耦合变高 |
| 8 | `colortex` 格式降精度（RGBA16F → RGBA8） | 带宽减半 | 高动态范围会截断 |
| 9 | 关闭不必要的 mipmap | 省 mip 生成 | 模糊采样质量下降 |
| 10 | 减少 `discard` | 保住 early-z | cutout 无法避免 |
| 11 | 早退：天空像素不做光照 | 天空占比大时收益明显 | 需要正确的天空判定 |
| 12 | 循环用编译期常量上界 | 驱动可展开 | 动态循环在部分驱动上很慢 |
| 13 | 避免在片元里做矩阵求逆 | 每像素 64 次乘法级开销 | 用 CPU 端 uniform |
| 14 | 用 `textureLod`/显式 LOD 控制采样 | 减少 cache miss | 可能闪烁 |
| 15 | 阴影只渲染必要几何（`shadowTranslucent=false`） | 省一整类 draw | 水面无影子 |
| 16 | `shadowDistance` 256 → 128 | 阴影相机覆盖体积减 8 倍（三维） | 远处无影子 |

### 9.3 常见「隐形」开销

- **每帧重建全屏缓冲**：`size.buffer` 改尺寸会让 gbuffers 无法写入，且每帧分配可能触发驱动重分配。
- **`colortex` 双缓冲**：每个附件实际占 2 份显存；16 个 RGBA16F 全分辨率在 1080p 下约 `16×2×1920×1080×8 B ≈ 531 MB`（粗算，未计 mipmap）。
- **`imageLoad/imageStore`**：绕过缓存，随机访问非常慢；只在确实需要任意写时用。
- **compute 的 work group 过大/过小**：`local_size` 与 `workGroupsRender` 不匹配会导致大量空转。
- **`#include` 膨胀**：展开后代码变长会增加编译时间和寄存器压力（Iris 会写入 `patched_shaders`，可检查实际代码量）。
- **uniform 分支**：`if (uniformBool)` 在所有像素上一致，通常能被优化；但若分支内含大量采样，部分驱动仍会执行两支（可用 `#if` 宏替代）。

---

## 10. 调试与报错

### 10.1 Iris 的官方调试手段

| 手段 | 操作 | 说明 |
|---|---|---|
| 错误界面 | 光影编译失败时，Iris 直接在游戏内显示错误文本 | 官方文档：debug mode 下会「directly display any shader compilation errors」 |
| Debug Mode | **按住 `ctrl` + `D`，然后重启游戏** | Iris 官方文档明确写的快捷键；不是「重载光影」 |
| 展开后的源码 | 查看 `.minecraft/patched_shaders/` | Iris 会把 `#include` 展开、补丁后的代码写到这里；报错行号对应这些文件，不是你的原文件 |
| 关闭 no-error-context | 编辑 `.minecraft/config/sodium-options.json`，把 `use_no_error_g_l_context` 设为 `false` | 官方文档：某些 AMD 驱动开 debug mode 会 GLFW 报错 |
| 图形调试器 | RenderDoc / Nsight；可用 GFX-Debuggers mod 注入 | 官方文档给了 Windows/Linux 两种注入方式 |
| 日志 | `logs/latest.log` | 见 10.2 |

OptiFine 侧：官方文档有「Debug shaders」开关（旧名 internal shaders），会把内部/调试着色器输出用于排查；**具体转储路径与行为以对应 OptiFine 版本为准（未验证）**。普通玩家不要开。

### 10.2 `logs/latest.log` 搜索建议

不同版本措辞不同，下面给的是**搜索片段**而不是保证存在的原文（措辞未逐一验证）：

| 搜索片段 | 可能含义 |
|---|---|
| `shader` / `Shader` | 光影加载相关的一切 |
| `Failed to compile` / `compile error` | GLSL 编译失败 |
| `link` / `linker` | 程序链接失败（varying 不匹配常见） |
| `iris` / `Iris` | Iris 自己的初始化/警告 |
| `OptiFine` | OptiFine 版本与兼容警告 |
| `GL_INVALID` / `error` | GL 调用错误 |
| `Exception` / `Crash` | Java 侧异常（模组冲突居多） |

排查顺序：

1. 先看有没有编译/链接错误（`patched_shaders` 定位行号）。
2. 没有编译错误但画面黑 → 看 `RENDERTARGETS`、`final` 是否在执行、是否 `discard` 掉了全部像素。
3. 有 Java 异常 → 先怀疑模组冲突（第 11 节），再看光影。

### 10.3 常见 GLSL 错误

| 现象 | 根因 | 处理 |
|---|---|---|
| `version '330' is not supported` | 驱动/上下文版本低，或用了 core 特性 | 降到 `#version 120`，或改用兼容写法 |
| `'texture' : reserved keyword` | 在 330 里用 `texture` 当采样器名 | 改名 `gtexture` |
| `gl_FragColor undeclared` | 330 里没有 `gl_FragColor` | 声明 `layout(location=0) out vec4` |
| `varying mismatch` / link error | 顶点 `out` 与片元 `in` 名字/类型不一致 | 逐字对齐；整数加 `flat` |
| `uniform not found`（location = -1） | uniform 未被使用，被编译器优化掉 | 正常现象；确保代码真的读了它 |
| 输出全黑 | `RENDERTARGETS` 与实际写入不匹配；或写了没绑定的附件 | 检查下标映射与 `location` |
| 画面花屏/闪烁 | 绑定了附件但某些分支没写 | 所有路径都给输出赋值 |
| `shadowtex1` 全白/全黑 | 半透明几何未写阴影、或阴影 pass 被关闭 | 检查 `shadowTranslucent`、`shadow.enabled` |
| 阴影错误但深度正常 | `shadowtex0` 与 `shadowtex1` 用混 | `shadowtex1` 不含半透明；用 `shadowtex0` 做遮挡测试 |
| `depthtex1` 早期读到垃圾 | 在不透明 gbuffers 里读 `depthtex1` | 只在 `deferred` 及之后读 |
| `colortex0` 在 gbuffers 采到图集 | gbuffers 阶段 0–3 不绑定 | 用 `colortex4..7` 传数据 |
| 深度写入后 early-z 失效 | `gl_FragDepth` 被写、或大量 `discard` | 只在必要时写深度 |
| `const int colortex0Format = ...` 报错 | 格式名不是 GLSL 标识符 | 放进块注释，或先 `#define` |
| 编译通过但程序不执行 | 文件被 fallback 覆盖、或 `program.enabled` 关掉 | 检查文件名拼写与 properties |

### 10.4 二分定位到某个 pass

思路：让管线逐步「退化」，观察画面在哪一步坏掉。

1. **只留 gbuffers**：删掉/改名所有 `deferred*`、`composite*`，保留 `final` 直接输出 `colortex0`。如果正常 → 问题在后处理。
2. **逐个加回**：`deferred` → `composite` → `composite1` → …，每次只加一个。
3. **用 `program.enabled` 关单个程序**（Iris）：

```properties
program.composite3.enabled = false
```

4. **用 `scale` 缩小可疑 pass**：`scale.composite3 = 0.25`，若画面出现小块异常区域，说明问题在该 pass 的 UV/坐标计算。
5. **把中间缓冲可视化**：在 `final` 里临时输出 `colortexN`，确认数据在哪一步变脏。

### 10.5 深度 / 模板（stencil）注意事项

- `depthtex0/1/2` 的格式是 `DEPTH24_STENCIL8` 或 `DEPTH32F_STENCIL8`（**驱动相关**，Iris 文档）。
- 同一个附件带 stencil 位，但**官方文档没有说明 stencil 的写入/读取语义**；依赖 stencil 做「选中轮廓」等效果属于**未验证**用法，不要在生产包中依赖。
- `gl_FragDepth` 必须所有路径赋值，否则结果未定义（Khronos 规范）。

---

## 11. 与 Forge 1.20.1 模组的交叉问题

### 11.1 装哪一套

| 组合 | 是否可行 | 说明 |
|---|---|---|
| Forge + OptiFine | 可行 | OptiFine 有 Forge 1.20.1 版 |
| Forge + Oculus + Embeddium | 可行 | Iris 官方 FAQ：Forge 用 Oculus（非官方移植），Oculus 需要 Embeddium |
| Forge + Oculus + Rubidium | **高风险** | Rubidium 是过时的 Sodium 移植；CurseForge FAQ 提示可能需要手动删除 |
| Forge + Iris（Fabric 版） | 不可行 | Iris 不支持 Forge |
| Fabric + Iris + Sodium | 可行 | 官方组合 |
| 同时装 OptiFine 与 Oculus | **不可行** | 两套光影加载器互相覆盖渲染管线 |

### 11.2 模组自定义渲染为什么会「不被光影处理」

光影的 gbuffers 只接管**原版 RenderType** 的绘制。模组如果：

- 用 `RenderType.create(...)` 自建 RenderType（自定义 shader state / 自定义顶点格式）；
- 直接 `RenderSystem` 设置着色器并 `BufferBuilder` 立即绘制；
- 在 `RenderLevelStageEvent` 的错误阶段绘制（例如在 `AFTER_LEVEL` 之后画世界几何）；

那么这些几何通常：

| 症状 | 原因 |
|---|---|
| 光影开启时消失 | 绘制发生在 `final` 之后，被全屏 pass 覆盖 |
| 显示但没有光影/不受光 | 没走 gbuffers，没写入 colortex/深度 |
| 不投射阴影 | 没在 `shadow` pass 里绘制 |
| 深度冲突/闪烁 | 自建 RenderType 的深度状态与光影假设不一致 |
| 与半透明排序冲突 | 自定义 RenderType 的 blend/排序不受 `particles.ordering` 控制 |

**可操作建议**：

1. 优先使用原版 `RenderType`（`solid`、`cutout`、`cutoutMipped`、`translucent`），让光影自动接管。
2. 自定义 RenderType 时，尽量复用原版的 shader state（`RenderStateShard`），不要自定义 GLSL。
3. 需要在光影下正确显示的几何，必须画在**世界渲染阶段**内（Forge 的 `RenderLevelStageEvent` 的 `AFTER_SOLID_BLOCKS` / `AFTER_TRANSLUCENT_BLOCKS` 等），不要拖到 GUI 阶段。
4. 需要在阴影里出现的几何，确认它会进入 `shadow` pass（原版 RenderType 会自动进入）。
5. 提供「光影关闭」的回退路径：光影关闭时你的自定义渲染要能正常工作（见 11.4）。

### 11.3 RenderType / 缓冲区层面的具体冲突

- **顶点格式不同**：光影的 gbuffers 期望原版属性（`vaPosition`、`vaColor`、`vaNormal`、`vaUV0`、`vaUV2`、`mc_Entity` 等）。自定义格式缺少 `mc_Entity` 时，`gbuffers_terrain` 里读到的值是未定义的。
- **`BufferBuilder` 的 `endVertex` 顺序**：属性顺序必须与 `VertexFormat` 完全一致，否则数据错位（这类问题在光影开启时更明显，因为光影会读更多属性）。
- **`RenderSystem.setShaderTexture`**：光影下 `gtexture` 绑定由图集管理；手动绑定任意纹理可能采不到预期内容。
- **深度状态**：自建 RenderType 若关闭深度写入，光影的 `depthtex` 会缺这块几何。

### 11.4 光影关闭时的回退

| 检查点 | 做法 |
|---|---|
| 是否装了光影加载器 | 不能假设一定装了；Forge 侧可能是 OptiFine 或 Oculus，也可能都没有 |
| 光影是否启用 | OptiFine 有 `Config.isShaders()`（以对应版本 API 为准）；Iris 有 v0 API（`IrisApi`）；Oculus 的等价 API **未验证**，可用反射或读配置兜底 |
| 渲染路径 | 自定义渲染需要两条路径：光影开启（走原版 RenderType/世界阶段）与关闭（可直接画） |
| 视觉一致性 | 光影关闭时不要依赖 `colortex`/`shadowtex` 等只有光影才存在的资源 |

> 注意：不要在模组里硬编码「有光影」；玩家可能只装了 Embeddium（纯优化，无光影）。

### 11.5 兼容性检查清单（Forge 1.20.1）

| 检查 | 说明 |
|---|---|
| 只保留一套光影加载器 | OptiFine **或** Oculus，不要同时 |
| Sodium 系只保留一个 | Embeddium **或** Rubidium，不要同时 |
| FRAPI 类 mod | 需要 Indium（Fabric）/ Embeddium 的对应支持；缺失会崩 |
| 区块渲染注入类 mod | 必须明确支持 Sodium/Embeddium，否则渲染错乱 |
| 光影包与游戏版本 | 1.20.1 包不一定兼容 1.20.4；看发布页的 game version |
| Oculus 与 Iris 包格式 | Oculus 跟随 Iris 版本，Iris 1.7+ 的包特性在旧 Oculus 上可能不支持 |
| 崩溃报告 | 先看 `logs/latest.log` 与 `crash-reports/`，确认是 GL 错误还是 Java 异常 |

---

## 12. 坑表

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 光影包放进 `shaderpacks/` 但列表里不显示 | 压缩包结构不对（`shaders/` 不在 zip 根）或放进了 `resourcepacks/` | 确认 zip 内第一层是 `shaders/`；确认目录是 `shaderpacks/` |
| 2 | 进游戏直接红字报错 | GLSL 编译/链接失败 | 看错误文本 + `patched_shaders` 对应行；先降到最小包 |
| 3 | 画面全黑但天空正常 | `final` 没输出 / `RENDERTARGETS` 写错附件 | 检查 `final` 的输出与 `colortex` 编号映射 |
| 4 | 画面全黑且天空也黑 | `gbuffers` 全部 `discard` 或 `alphaTestRef` 用错 | 临时去掉 `discard`；检查 `alphaTest.gbuffers_*` |
| 5 | 方块有颜色但完全不受光 | 只写了颜色，没写法线/光照图；或 deferred 没读对应附件 | 检查 `RENDERTARGETS` 数量与 deferred 的采样 |
| 6 | 阴影整片全白/全黑 | `shadowtex1` 为空；或阴影 pass 未执行 | 用 `shadowtex0` 验证；检查 `shadow.enabled`/`shadowTranslucent` |
| 7 | 阴影边缘锯齿严重 | 分辨率低 + 无 PCF | 提高 `shadowMapResolution` 或加 PCF/PCSS |
| 8 | 阴影有明显漏光/条纹 | 阴影偏移（shadow acne）或法线偏移不足 | 加 bias、法线偏移；`shadowIntervalSize` 调整 |
| 9 | 半透明水面把阴影投满 | 用 `shadowtex0` 做遮挡测试 | 改用 `shadowtex1`（不含半透明） |
| 10 | 手上的物品在光影下错位 | 手部有额外变换，`gbufferModelViewInverse` 使用不当 | 手部单独处理；注意 `gbuffers_hand` 的模型视图 |
| 11 | 地形在世界坐标采样时错位 | 忘了加 `chunkOffset` | `worldPos = vaPosition + chunkOffset` 再变换 |
| 12 | 采样 `colortex0` 得到方块图集 | gbuffers 阶段 0–3 不绑定 | 改用 `colortex4..7` 或推迟到 deferred |
| 13 | 改了 `colortex` 尺寸后地形不显示 | `size.buffer` 改尺寸会让 gbuffers 无法写入 | 只对后处理缓冲改尺寸 |
| 14 | 格式声明报「RGBA16F 未定义」 | 管线常量不在块注释里 | 放进 `/* ... */`，且独占一行 |
| 15 | `separateAo` 开了没效果 | Iris 已知 bug：阴影关闭时无效 | 开启阴影 pass 再测 |
| 16 | Iris 上 `gbuffers_entities_glowing` 不生效 | Iris 不识别该文件 | 逻辑合并进 `gbuffers_entities` |
| 17 | 包在 OptiFine 正常、Iris 黑屏 | 用了 Iris 专有/或反之（`#version`、`image`、`customTexture`） | 按第 7 节差异表降级 |
| 18 | 开光影后模组机器不显示 | 自定义 RenderType 不在 gbuffers 管线内 | 改用原版 RenderType 或世界渲染阶段 |
| 19 | 开光影后模组 GUI/全息投影被覆盖 | 绘制发生在 `final` 之后 | 提前到世界渲染阶段；GUI 用原版绘制 |
| 20 | Oculus + Rubidium 崩溃 | 两套 Sodium 移植冲突 | 删 Rubidium，换 Embeddium |
| 21 | 同时装 OptiFine 与 Oculus 崩溃 | 两套光影加载器冲突 | 只保留一套 |
| 22 | 换分辨率后光影模糊/错位 | 缓冲尺寸固定（`size.buffer`）或 `viewWidth/Height` 用错 | 检查 `size.buffer` 与 UV 计算 |
| 23 | 修改包后游戏里还是旧效果 | 只改了 zip 外的副本，或游戏缓存 | 确认改的是实际加载的文件；重启游戏 |
| 24 | 编译通过但某个 pass 完全不跑 | 文件名拼错（如 `composite1` 写成 `composite_1`） | 严格按 `<program><suffix>` 命名 |
| 25 | `uniform` 读取恒为 0 | 被编译器优化掉（未使用） | 让它在代码里真实参与运算 |

---

## 13. 来源

以下为撰写时实际访问/检索到的官方或准官方页面（按主题分组）。第三方站点（CurseForge 文件页、Modrinth、embeddium.org 等）仅用于版本号交叉验证，已在正文标注可信度。

### Iris 官方文档（shaders.properties）

- 程序总览与执行顺序：<https://shaders.properties/current/reference/programs/overview/>
- `gbuffers` 程序表 / fallback / Iris 额外程序：<https://shaders.properties/current/reference/programs/gbuffers/>
- `shadow` 程序：<https://shaders.properties/current/reference/programs/shadow/>
- `colortex`（16 个、格式、清屏、翻转、别名）：<https://shaders.properties/current/reference/buffers/colortex/>
- `depthtex`：<https://shaders.properties/current/reference/buffers/depthtex/>
- `shadowtex`（`shadowtex0/1`、硬件采样）：<https://shaders.properties/current/reference/buffers/shadowtex/>
- `noisetex`：<https://shaders.properties/current/reference/buffers/noisetex/>
- 图集与 `gtexture` / `normals` / `specular`：<https://shaders.properties/current/reference/buffers/atlases/>
- 自定义纹理（`texture.<stage>.<buffer>`、`customTexture`、PBR `_s`）：<https://shaders.properties/current/reference/buffers/custom_textures/>
- 自定义图像 `image.<name>`：<https://shaders.properties/current/reference/buffers/custom_images/>
- `RENDERTARGETS`：<https://shaders.properties/current/reference/constants/rendertargets/>
- `DRAWBUFFERS`：<https://shaders.properties/current/reference/constants/drawbuffers/>
- 缓冲格式 `const int <buffer>Format`：<https://shaders.properties/current/reference/constants/buffer_format/>
- 缓冲清屏 `const bool <buffer>Clear`：<https://shaders.properties/current/reference/constants/buffer_clear/>
- 清屏色 `const vec4 <buffer>ClearColor`：<https://shaders.properties/current/reference/constants/buffer_clear_color/>
- colortex mipmap：<https://shaders.properties/current/reference/constants/colortex_mipmaps/>
- `shadowMapResolution`：<https://shaders.properties/current/reference/constants/shadowmapresolution/>
- 属性总览（兼容/核心属性对照）：<https://shaders.properties/current/reference/attributes/overview/>
- `mc_Entity`：<https://shaders.properties/current/reference/attributes/mc_entity/>
- `at_tangent`：<https://shaders.properties/current/reference/attributes/at_tangent/>
- uniforms 总览：<https://shaders.properties/current/reference/uniforms/overview/>
- 玩家状态 uniforms（`isEyeInWater` 等）：<https://shaders.properties/current/reference/uniforms/status/>
- `shaders.properties` 总览：<https://shaders.properties/current/reference/shadersproperties/overview/>
- 设置界面 / `screen` / `sliders` / `profile`：<https://shaders.properties/current/reference/shadersproperties/shader_settings/>
- 程序顺序 / `program.enabled` / `particles.ordering`：<https://shaders.properties/current/reference/shadersproperties/ordering/>
- 渲染字段（`alphaTest`/`blend`/`scale`/`size.buffer`/`flip`/culling）：<https://shaders.properties/current/reference/shadersproperties/rendering/>
- 视效字段（`clouds`/`sun`/`moon`/`oldLighting`/`separateAo` 等）：<https://shaders.properties/current/reference/shadersproperties/features/>
- 自定义 uniform/variable：<https://shaders.properties/current/reference/shadersproperties/custom_uniforms/>
- `block.properties`（ID 分配、render layer）：<https://shaders.properties/current/reference/miscellaneous/block_properties/>
- 调试（`ctrl`+`D`、`patched_shaders`、RenderDoc/Nsight）：<https://shaders.properties/current/reference/miscellaneous/debugging_shaders/>
- PBR 标准（labPBR / oldPBR、`texture.properties`）：<https://shaders.properties/current/how-to/pbr_standards/>
- 入门教程（gbuffers 与 `#version 330 compatibility` 写法）：<https://shaders.properties/current/guides/your-first-shaderpack/2_gbuffers/>
- 入门教程（deferred 光照 / 从深度重建）：<https://shaders.properties/current/guides/your-first-shaderpack/3_deferred_lighting/>

### OptiFine 官方文档（OptiDocs）

- 开发总览（文件扩展名、compute、attributes、block render layers）：<https://optifine.readthedocs.io/shaders_dev.html>
- Color attachments（`DRAWBUFFERS`/`RENDERTARGETS`、8 个上限、ping-pong）：<https://optifine.readthedocs.io/shaders_dev/color_attachments.html>
- 格式列表：<https://optifine.readthedocs.io/shaders_dev/formats.html>
- 程序表（含 `gbuffers_entities_glowing`、`gbuffers_item`）：<https://optifine.readthedocs.io/shaders_dev/programs.html>
- 设置界面与可识别 const 选项：<https://optifine.readthedocs.io/shaders_dev/options.html>
- 光影安装与调试着色器说明：<https://optifine.readthedocs.io/shaders.html>
- 纹理自定义（`texture.<stage>.<name>`）：<https://optifine.readthedocs.io/shaders_dev/textures.html>

### labPBR / shaderLABS

- LabPBR Material Standard（通道定义、金属编码）：<https://wiki.shaderlabs.org/wiki/LabPBR_Material_Standard>

### 版本与平台

- Iris 官网：<https://www.irisshaders.dev/>
- CurseForge：Iris 1.6.17 for 1.20.1：<https://www.curseforge.com/minecraft/mc-mods/irisshaders/files/5095005>
- Modrinth：Iris 1.6.9+1.20.1（changelog 提到 Sodium 0.5.3）：<https://modrinth.com/mod/iris/version/1.6.9+1.20.1>
- CurseForge 博客：Iris FAQ（Forge 用 Oculus、Sodium 是必需依赖、Embeddium 取代 Rubidium）：<https://blog.curseforge.com/iris-shaders-frequently-asked-questions/>
- OptiFine 下载页（1.20.1 HD U I6）：<https://optifine.net/adloadx?f=OptiFine_1.20.1_HD_U_I6.jar>

### 交叉验证（第三方，正文已标注「未验证」）

- Oculus 1.20.1-1.8.0 的文件列表：<https://www.curse-forge.ru/modi/oculus/versions/1.20.1/>
- Embeddium 与 Oculus 的 1.20.1 组合说明：<https://embeddium.org/best-embeddium-oculus-settings-shaders/>

---

## 附录 A：本文中标注「未验证」的条目汇总

| 条目 | 位置 | 说明 |
|---|---|---|
| Oculus `1.20.1-1.8.0` 的精确版本 | 0.3 版本矩阵 | 仅第三方站点列出，未在 CurseForge 官方页逐条核实 |
| Embeddium 1.20.1 的具体版本号 | 0.3 版本矩阵 | 未核实，按 game version 过滤 |
| Iris 1.6.x 是否支持 `gbuffers_terrain_solid` / `gbuffers_terrain_cutout` | 2.3 | 文档内容基于 Iris 1.7/1.8 时代 |
| Iris 1.6.x 是否支持 `gbuffers_particles` 等新增程序 | 2.3 / 第 7 节 | 同上 |
| `gbuffers_terrain_cutout_mip` 是否存在 | 2.3 | 两份官方程序表均未列出 |
| OptiFine 1.20.1 是否接受 `#version 330 compatibility` | 3.2 | 官方文档未给出明确支持范围 |
| OptiFine 是否支持 `.tcs`/`.tes` | 3.1 / 第 7 节 | OptiFine 文档只列 4 种扩展名 |
| `shadowMapResolution` / `shadowMap` / `shadowFilter` 作为 `shaders.properties` 键 | 6.6 | 官方文档中是 GLSL 常量或查不到 |
| 裸 `particles` / `beaconBeam` / `renderTargets` / `culling` / `fog` 字段 | 6.6 | 官方文档索引中不存在 |
| `depthtex` 的 stencil 语义 | 10.5 | 文档只给出格式，未给读写语义 |
| Iris 配置文件精确文件名 | 0.4 | 随版本变化，未核实 |
| Oculus 的「光影是否启用」API | 11.4 | 未验证类名/包名 |
| `logs/latest.log` 的具体错误措辞 | 10.2 | 不同版本措辞不同 |
| OptiFine debug shaders 的转储路径 | 10.1 | 官方文档未给路径 |
