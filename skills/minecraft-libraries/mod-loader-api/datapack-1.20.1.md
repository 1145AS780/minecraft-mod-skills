# 原版数据包参考（Minecraft Java 1.20.1）

> **本文只覆盖 Java 版 1.20.1 的数据包（data pack）。**
> 1.20.2+ 的**函数宏**（`$` 行、`function ... with`）、1.20.5+ 的**物品组件**（DataComponents、`item_stack[a=b]` 语法）、1.21 的**目录单数化**、1.21 的 `@n` 选择器、1.21.5 的 `equipment` 槽位，以及 `/return run`、`/random`、`/execute if function`、`/execute if items` 等后续版本新增的命令，**都不在本文范围内**，文中出现时只作为“不要照抄”的反面参照。
>
> 约定：
> - 示例命名空间统一用 `myns`，落地时替换成自己的命名空间。
> - 代码块里的命令**不带前导 `/`**，可直接粘进 `.mcfunction`；在聊天栏执行时才补 `/`。
> - 命令里 `{...}` 参数是 NBT/SNBT 文本；引号与类型后缀规则见 §13.5。
> - 文末 §14 列出实际参考的官方页面，以及哪些结论来自旧技能文档、哪些来自官方页面。

**当前状态**：本文件为 1.20.1 专用参考，与 `forge-1.20.1.md`（模组 API）互补；数据包内容不依赖 Forge/Fabric/NeoForge 任何 API。

---

## 0. 版本与 pack_format 速查

### 0.1 1.20.1 的硬数字

| 项 | 1.20.1 的值 | 说明 |
|---|---|---|
| 数据包 `pack_format` | **15** | 写在 `pack.mcmeta` 的 `pack.pack_format` |
| 资源包 `pack_format` | **15** | 1.20.1 恰好数据/资源同号 |
| 内容目录 | **复数** | `functions/`、`recipes/`、`loot_tables/`、`advancements/`、`predicates/`、`item_modifiers/`、`structures/`、`tags/functions/`、`tags/items/` … |
| 注册表类目录 | **单数** | `dimension/`、`dimension_type/`、`worldgen/*`、`damage_type/`、`trim_material/`、`trim_pattern/` |
| 函数宏 | **无** | 1.20.2（23w31a）才加入 |
| 物品组件 | **无** | 物品数据仍是 NBT/SNBT，命令里写 `物品ID{tag内容}` |
| `/execute if function` | **无** | 1.20.3+ |
| `/execute if items` | **无** | 1.20.5+ |
| `@n` 选择器 | **无** | 1.21（24w21a）加入 |
| `random` 命令 | **无** | 1.20.2 加入 |
| `/return run` / `return fail` | **无** | 1.20.2/1.20.3 才有；1.20.1 只有 `return <整数>` |
| `show_notification`（配方） | **未验证** | 见 §7 说明 |

> 一句话记忆：**1.20.1 的数据包是“旧目录 + 旧 NBT + 无宏”的组合**。任何 `$(...)`、`[...]` 组件、`function/` 单数目录出现在 1.20.1 包里都是错的。

### 0.2 与相邻版本的对照（仅作对照，不要照抄）

| 版本 | 数据包 format | 与 1.20.1 的关键差异 |
|---|---|---|
| 1.20 / 1.20.1 | **15** | 本文基准 |
| 1.20.2 | 18 | 新增 `supported_formats`、`overlays`；新增函数宏；`/random`；`/return run`（短暂） |
| 1.20.3 / 1.20.4 | 26 | 编号与资源包分叉（资源 22）；`/return fail`、`/execute if function` |
| 1.20.5 / 1.20.6 | 41 | 物品改为 DataComponents；`set_nbt`→`set_components`；`/execute if items`；`loot function` 字段体系开始大改 |
| 1.21 / 1.21.1 | 48 | 目录全部单数化（`function/`、`recipe/`…）；`@n`；附魔数据驱动 |
| 1.21.5 | 71 | `equipment` 合并实体装备字段；`/item` 槽位新增 `equipment.*` |

要点：

- `pack_format` **只用于兼容性判定**，不校验内容。写错编号时数据包在列表里标红/提示“不兼容”，但仍可能被强制加载——于是出现“能加载但什么都不生效”的假象。
- 1.20.1 **没有** `supported_formats`（1.20.2+）。写了会被忽略，不要写。
- 1.20.1 **没有** `min_format` / `max_format`（25w31a 之后才有），**绝对不要写**。
- 1.20.1 的 `pack.mcmeta` 也不支持 `overlays`（1.20.2+）。

---

## 1. 数据包是什么、与原版/模组的关系

### 1.1 定义

数据包是一个**文件夹或 `.zip`**，根目录必须有 `pack.mcmeta`。游戏按“命名空间 + 注册表名 + 路径”把里面的 JSON/`.mcfunction`/`.nbt` 注册进对应的注册表。

- 一个文件 = 一个注册项。`data/myns/recipes/ruby_sword.json` 注册为配方 `myns:ruby_sword`。
- 路径里的子目录参与 ID：`data/myns/functions/util/msg.mcfunction` → `myns:util/msg`。
- 引用时**永远不带扩展名**：`function myns:util/msg`、`loot give @s loot myns:rewards/common`。

### 1.2 与原版的关系

- 原版自身的内容（配方、战利品表、进度、标签、世界生成）也是用**内置数据包**（built-in datapack）定义的。`data/minecraft/` 下的同名文件会**覆盖**原版。
- 覆盖原版是“替换”而不是“合并”：你写 `data/minecraft/recipes/diamond_sword.json`，原版那把剑的配方就没了，只剩你的版本。
- 想“追加”而不是“覆盖”，要改**标签**（`tags/items/...`）或在原标签里追加值，而不是覆盖配方文件。

### 1.3 与模组的关系

| 场景 | 数据包能做什么 | 边界 |
|---|---|---|
| 纯原版玩法 | 配方、战利品、进度、函数、标签、世界生成 | 不能新增方块/物品/实体**类型** |
| 模组 + 数据包 | 给模组注册的物品/方块/实体写配方、标签、战利品 | 模组必须先把注册名暴露出来；数据包不认识未注册的 ID |
| Forge 模组自带数据 | 模组 jar 内可放 `data/<modid>/...`，由 Forge 作为 `ModDataPack` 注入 | 这属于模组打包，不属于本文的“原版数据包”；调试时两者常同时生效，注意覆盖顺序 |

> 数据包**不能**新增注册表条目以外的游戏逻辑（比如新 GUI、新免疫规则）。需要新内容类型 → 写模组；需要新玩法编排 → 数据包 + 命令。

### 1.4 安装路径（只列确定路径）

| 场景 | 路径 | 说明 |
|---|---|---|
| 单人存档 | `.minecraft/saves/<world>/datapacks/<packname>/` | 文件夹或 `<packname>.zip` 均可 |
| 单人存档（zip） | `.minecraft/saves/<world>/datapacks/<packname>.zip` | zip 根目录里直接是 `pack.mcmeta` + `data/` |
| 专用服务器 | `<server>/world/datapacks/<packname>/` | 世界目录名取决于 `level-name`，默认 `world` |
| 新建世界时预装 | 世界创建界面的“数据包”按钮拖入 | 只影响该世界 |
| 模组/整合包全局 | **不写** | 1.20.1 原版没有“全局数据包”目录；网上常见的 `config/...` 说法属于模组加载器行为，不在本文范围 |

要点：

- 路径必须是**世界存档内**的 `datapacks/`，不是 `.minecraft/datapacks/`（后者不存在）。
- zip 的目录结构必须“扁平”：`pack.mcmeta` 在 zip 根，不能多套一层文件夹。
- 数据包根目录没有 `pack.mcmeta` → 游戏完全不识别，`/datapack list` 里也看不到。
- 服务器上改数据包文件后要 `/reload` 或重启；只改文件不 reload，游戏仍用内存里的旧数据。

---

## 2. `pack.mcmeta` 全字段与最小示例

### 2.1 1.20.1 可用字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `pack.pack_format` | int | 是 | 1.20.1 填 **15** |
| `pack.description` | 字符串 / 文本组件 | 是 | 数据包列表里显示的文字；支持 JSON 文本组件（颜色、粗体等） |
| `pack.description` 为数组 | 数组 | 否 | 文本组件数组，逐段拼接显示 |
| `pack.filter` | 对象 | 否 | 1.19 起存在：按 `namespace`/`path` 正则屏蔽低优先级包里的文件；1.20.1 可用，但**未在本文示例中验证** |
| `pack.supported_formats` | — | — | **1.20.2+，1.20.1 不要写** |
| `pack.overlays` | — | — | **1.20.2+，1.20.1 不要写** |
| `pack.min_format` / `max_format` | — | — | **25w31a+，绝对不要写** |

> `description` 在 1.20.1 是**必填**（缺失会导致包被判无效/显示异常）。`pack.png` 是可选的图标，放在包根目录。

### 2.2 最小可用示例

`pack.mcmeta`：

```json
{
  "pack": {
    "pack_format": 15,
    "description": "myns 数据包（1.20.1）"
  }
}
```

带颜色的 `description`（1.20.1 同样支持文本组件）：

```json
{
  "pack": {
    "pack_format": 15,
    "description": [
      { "text": "myns", "color": "gold", "bold": true },
      { "text": " · 1.20.1 数据包", "color": "gray" }
    ]
  }
}
```

### 2.3 常见错误

| 写法 | 结果 | 修正 |
|---|---|---|
| `"pack_format": 15` 放在根对象（不在 `pack` 里） | 包无效 | 必须嵌在 `"pack"` 下 |
| `"pack_format": 48` | 列表里标红“不兼容” | 1.20.1 改回 15 |
| 加了 `"supported_formats": [15, 18]` | 1.20.1 忽略该字段，不报错也不生效 | 删掉 |
| JSON 里有 `//` 注释或尾逗号 | 解析失败，包不出现 | 用严格 JSON |
| 文件编码为 UTF-8 with BOM | 部分版本解析失败 | 存成 **UTF-8 无 BOM** |

## 3. 完整目录树

### 3.1 1.20.1 的注册目录全集

```text
myns-datapack-1_20_1/
├── pack.mcmeta                     # 必需
├── pack.png                        # 可选，数据包列表图标
└── data/
    ├── myns/                       # 你的命名空间
    │   ├── functions/              # .mcfunction 函数
    │   ├── recipes/                # 配方 json
    │   ├── loot_tables/            # 战利品表 json
    │   ├── advancements/           # 进度 json
    │   ├── predicates/             # 谓词 json
    │   ├── item_modifiers/         # 物品修饰器 json
    │   ├── structures/             # .nbt 结构文件
    │   ├── damage_type/            # 伤害类型（单数，1.19.4+）
    │   ├── trim_material/          # 盔甲纹饰材料（单数，1.19.4+）
    │   ├── trim_pattern/           # 盔甲纹饰图案（单数，1.19.4+）
    │   ├── dimension/              # 维度（单数）
    │   ├── dimension_type/         # 维度类型（单数）
    │   ├── worldgen/
    │   │   ├── biome/
    │   │   ├── configured_feature/
    │   │   ├── placed_feature/
    │   │   ├── configured_carver/
    │   │   ├── noise/
    │   │   ├── noise_settings/
    │   │   ├── density_function/
    │   │   ├── multi_noise_biome_source_parameter_list/
    │   │   ├── processor_list/
    │   │   ├── template_pool/
    │   │   ├── structure/
    │   │   ├── structure_set/
    │   │   ├── flat_level_generator_preset/
    │   │   └── world_preset/
    │   └── tags/
    │       ├── functions/          # 函数标签（复数）
    │       ├── blocks/             # 方块标签
    │       ├── items/              # 物品标签
    │       ├── entity_types/       # 实体类型标签
    │       ├── fluids/             # 流体标签
    │       ├── game_events/        # 游戏事件标签
    │       ├── damage_type/        # 伤害类型标签（单数）
    │       ├── point_of_interest_type/
    │       ├── cat_variant/
    │       ├── instrument/
    │       └── worldgen/
    │           ├── biome/
    │           ├── structure/
    │           ├── feature/
    │           ├── flat_level_generator_preset/
    │           └── world_preset/
    └── minecraft/                  # 覆盖原版时用
        └── tags/
            └── functions/
                ├── load.json
                └── tick.json
```

**单复数对照（1.20.1 最容易写错的地方）**：

| 复数（内容目录，1.20.1） | 单数（注册表目录，1.20.1） |
|---|---|
| `functions/` | `dimension/`、`dimension_type/`、`damage_type/`、`trim_material/`、`trim_pattern/` |
| `recipes/`、`loot_tables/`、`advancements/`、`predicates/`、`item_modifiers/` | `worldgen/*` 全部子目录 |
| `structures/` | `tags/damage_type/` |
| `tags/functions/`、`tags/blocks/`、`tags/items/`、`tags/entity_types/`、`tags/fluids/`、`tags/game_events/` | `tags/point_of_interest_type/`、`tags/cat_variant/`、`tags/instrument/` |

记忆法：**“旧注册表（1.13 时代）在 tags 下用复数；1.18.2 之后新增的注册表用注册表本名（多为单数）”**。`worldgen/*` 从 1.16.2 起就是单数。

### 3.2 一个可运行的最小包

`myns_hello/` 目录：

```text
myns_hello/
├── pack.mcmeta
└── data/
    ├── myns/
    │   ├── functions/
    │   │   ├── init.mcfunction
    │   │   └── hello.mcfunction
    │   └── recipes/
    │       └── ruby_block.json
    └── minecraft/
        └── tags/
            └── functions/
                └── load.json
```

`pack.mcmeta`：

```json
{
  "pack": {
    "pack_format": 15,
    "description": "最小可运行包"
  }
}
```

`data/myns/functions/init.mcfunction`：

```mcfunction
scoreboard objectives add myns.data dummy
tellraw @a {"text":"[myns] 已加载","color":"green"}
```

`data/myns/functions/hello.mcfunction`：

```mcfunction
say 你好，1.20.1 数据包
```

`data/minecraft/tags/functions/load.json`：

```json
{
  "values": [
    "myns:init"
  ]
}
```

`data/myns/recipes/ruby_block.json`：

```json
{
  "type": "minecraft:crafting_shaped",
  "pattern": [
    "XXX",
    "XXX",
    "XXX"
  ],
  "key": {
    "X": { "item": "minecraft:redstone" }
  },
  "result": {
    "item": "minecraft:redstone_block",
    "count": 1
  }
}
```

验证：

```mcfunction
reload
function myns:hello
datapack list
```

预期：聊天栏出现“[myns] 已加载”与“你好，1.20.1 数据包”；`/datapack list` 里能看到 `file/myns_hello`。

---

## 4. 命名空间、加载顺序、reload 与 datapack 命令

### 4.1 命名空间与路径规则

| 规则 | 说明 |
|---|---|
| 命名空间字符集 | `a-z`、`0-9`、`_`、`-`、`.`；习惯全小写 |
| 路径字符集 | 同上，另允许 `/` |
| **不允许大写** | `Ruby.json` 在 Windows 上能存在，但游戏按小写注册，`/function myns:Ruby` 会失败 |
| 扩展名 | 函数 `.mcfunction`、结构 `.nbt`、其余 `.json` |
| 引用格式 | `namespace:path`，**不带扩展名**、不带 `data/`、不带注册表目录名 |
| 子目录 | 直接进 ID：`functions/util/msg.mcfunction` → `myns:util/msg` |

### 4.2 加载顺序

- 多个数据包同时启用时，**列表里越靠上优先级越高**；高优先级包的同名文件覆盖低优先级包。
- 原版内置包永远在最底层。
- 标签是例外：`replace: false`（默认）时高优先级包的内容**追加**到低优先级包，而不是覆盖（详见 §5）。
- `pack.mcmeta` 的 `filter` 可以按路径正则屏蔽低优先级包的文件（1.19+，**未在 1.20.1 实测**）。

### 4.3 `/reload`

```mcfunction
reload
```

- `reload` 会重读：函数、函数标签与所有注册表标签、进度、配方、战利品表、谓词、物品修饰器、结构模板、伤害类型、纹饰定义。
- `reload` **不会**重读：已生成的区块、`dimension`/`dimension_type`/大部分 `worldgen`（这些属于“动态注册表”，需要退出世界重进或重启服务器）、`data storage` 里的值、已排队的 `schedule` 任务、`bossbar` 状态。
- `reload` 失败时**整套改动都不生效**，游戏继续用上一次成功的快照（1.16 起的行为）。所以“reload 没报错但也没生效”通常是 reload 成功、文件放错目录。
- 函数语法错误会在 reload 时指出文件名与行号；JSON 错误多数只给文件名，定位靠编辑器校验。

### 4.4 `/datapack` 子命令（1.20.1 确定存在）

```text
datapack list [available|enabled]
datapack enable <name> [first|last|before <existing>|after <existing>]
datapack disable <name>
```

| 子命令 | 说明 |
|---|---|
| `list` | 列出全部已发现的数据包；`available` 只列未启用的，`enabled` 只列已启用的 |
| `enable` | 启用；`first`/`last` 决定插到列表最前/最后，`before`/`after` 按另一个包定位 |
| `disable` | 停用 |

`<name>` 用 `list` 输出里的名字，形如 `file/myns_hello`（文件夹）或 `file/myns_hello.zip`；含空格/斜杠时必须加双引号：

```mcfunction
datapack list
datapack disable "file/myns_hello"
datapack enable "file/myns_hello" first
datapack enable "file/myns_hello" after "file/vanilla"
```

### 4.5 `--pack` 启动参数（1.20.1 确定存在）

服务端启动参数：

```text
--pack <path>
```

- 作用：把指定路径的数据包**作为默认启用的包**加入世界（路径可为文件夹或 zip）。
- 与 `--safeMode` 配合可在排障时只加载原版数据。
- 客户端启动器（如官方启动器）没有对等的 `--pack` 参数；单人调试请直接放到存档 `datapacks/`。

### 4.6 世界创建时的数据包

- 1.19.3 起，创建世界界面的“更多 → 数据包”可以拖入 zip/文件夹，**新世界一生成就带上**。
- 世界已存在时只能手动放进 `saves/<world>/datapacks/`，再用 `/reload` 或 `/datapack enable`。

## 5. 标签 tags

### 5.1 JSON 结构与三种写法

标签文件统一放在 `data/<ns>/tags/<标签类型目录>/<path>.json`，ID 为 `#<ns>:<path>`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `replace` | bool | 否 | 默认 `false`（追加到低优先级包）；`true` 表示**完整替换**同名标签 |
| `values` | 数组 | 是 | 元素可以是字符串 ID、`#` 开头的子标签、或带 `id`/`required` 的对象 |
| `values[].id` | 字符串 | — | 元素 ID（同样支持 `#` 前缀） |
| `values[].required` | bool | 否 | 默认 `true`；设为 `false` 时该条目缺失**不报错**（1.16.2 起就支持，1.20.1 可用） |

三种写法：

```json
{
  "values": [
    "minecraft:stone",
    "minecraft:deepslate",
    "#minecraft:logs"
  ]
}
```

```json
{
  "replace": true,
  "values": [
    "minecraft:diamond_sword"
  ]
}
```

```json
{
  "values": [
    "myns:ruby",
    { "id": "myns:sapphire", "required": false }
  ]
}
```

`required: false` 的正确语义：**只跳过这一条**，标签整体仍然成立。常用于“模组/其他包可能提供该 ID，也可能没有”的场景。

### 5.2 1.20.1 的标签类型目录全表

| 目录（1.20.1） | 标签 ID 前缀 | 状态 | 典型用途 |
|---|---|---|---|
| `tags/blocks/` | `#ns:path` | 存在 | 方块行为、`execute if block`、配方 |
| `tags/items/` | `#ns:path` | 存在 | 物品分组、配方材料、`clear` 谓词 |
| `tags/entity_types/` | `#ns:path` | 存在 | `type=#ns:xxx`、生物行为 |
| `tags/fluids/` | `#ns:path` | 存在 | 流体行为、`in` 判定 |
| `tags/game_events/` | `#ns:path` | 存在 | 监守者/幽匿感测体忽略某些事件 |
| `tags/functions/` | `#ns:path` | 存在 | 函数组、`#minecraft:load`/`#minecraft:tick` |
| `tags/damage_type/` | `#ns:path` | 存在（1.19.4+） | 伤害免疫、`damage_type_properties` 判定 |
| `tags/point_of_interest_type/` | `#ns:path` | 存在 | 村民职业方块分组 |
| `tags/cat_variant/` | `#ns:path` | 存在 | 猫的变种分组 |
| `tags/instrument/` | `#ns:path` | 存在（1.19.3+，**未在 1.20.1 实测**） | 山羊角乐器分组 |
| `tags/worldgen/biome/` | `#ns:path` | 存在 | 生物群系分组 |
| `tags/worldgen/structure/` | `#ns:path` | 存在 | 结构分组（探险地图、结构集） |
| `tags/worldgen/feature/` | `#ns:path` | 存在 | 地物分组 |
| `tags/worldgen/flat_level_generator_preset/` | `#ns:path` | 存在 | 超平坦预设 |
| `tags/worldgen/world_preset/` | `#ns:path` | 存在 | 世界预设 |
| `tags/banner_pattern/` | — | **不存在** | 旗帜图案在 1.20.5 才数据驱动 |
| `tags/painting_variant/` | — | **不存在** | 画变种在 1.21 才数据驱动 |
| `tags/enchantment/` | — | **不存在** | 附魔在 1.21 才数据驱动 |
| `tags/item`、`tags/block`、`tags/function` … | — | **不存在（单数）** | 单数是 1.21 的写法，1.20.1 会静默不加载 |

> 以上三个“不存在”的项是常见误导：网上很多教程写 `data/<ns>/tags/banner_pattern/`，在 1.20.1 里放进去只会静默无效。

### 5.3 常用示例

**给原版方块标签追加内容**（放到 `data/myns/tags/blocks/ruby_ores.json`，引用为 `#myns:ruby_ores`）：

```json
{
  "replace": false,
  "values": [
    "minecraft:stone",
    "minecraft:deepslate"
  ]
}
```

**在命令里直接用标签**：

```mcfunction
execute if block ~ ~-1 ~ #myns:ruby_ores run say 站在红宝石矿上
fill ~ ~ ~ ~5 ~5 ~5 minecraft:air replace #minecraft:logs
```

**物品标签**（`data/myns/tags/items/ruby_tools.json`）：

```json
{
  "values": [
    "myns:ruby_sword",
    "myns:ruby_pickaxe",
    "myns:ruby_axe"
  ]
}
```

```mcfunction
clear @s #myns:ruby_tools
give @s #myns:ruby_tools
```

> `clear` 接受物品标签作物品谓词；**`give` 是否接受 `#标签` 未在 1.20.1 实测**，需要批量发放时请用函数逐条 `give`，不要依赖标签一次给全组。

**实体类型标签**（`data/myns/tags/entity_types/npcs.json`）：

```json
{
  "values": [
    "minecraft:villager",
    "minecraft:zombie_villager",
    { "id": "minecraft:warden", "required": false }
  ]
}
```

```mcfunction
execute as @e[type=#myns:npcs] run say 找到一个 NPC
```

**流体标签**（`data/myns/tags/fluids/hot.json`）：

```json
{
  "values": [
    "minecraft:lava",
    "minecraft:flowing_lava"
  ]
}
```

**游戏事件标签**（`data/myns/tags/game_events/quiet.json`）：

```json
{
  "values": [
    "minecraft:step",
    "minecraft:swim"
  ]
}
```

**函数标签**（`data/myns/tags/functions/group.json`，引用为 `#myns:group`）：

```json
{
  "values": [
    "myns:util/hello",
    "myns:util/bye"
  ]
}
```

```mcfunction
function #myns:group
```

- 标签内的函数按 `values` 顺序执行；同名函数在一次标签调用中**只执行一次**。
- `function #myns:group` 是 1.20.1 唯一能“调用一组函数”的方式；`execute if function` 不存在（1.20.3+）。

**伤害类型标签**（1.20.1 存在，`data/myns/tags/damage_type/is_magic_custom.json`）：

```json
{
  "values": [
    "minecraft:magic",
    "minecraft:indirect_magic",
    "myns:ruby_beam"
  ]
}
```

**生物群系标签**（`data/myns/tags/worldgen/biome/cold.json`）：

```json
{
  "values": [
    "minecraft:snowy_plains",
    "minecraft:ice_spikes",
    "#minecraft:is_taiga"
  ]
}
```

### 5.4 标签的优先级与覆盖

- 高优先级包的 `replace: false` → 内容**追加**到低优先级结果之后（顺序 = 包的加载顺序）。
- 高优先级包的 `replace: true` → **截断**所有低优先级贡献，只用本文件内容。
- 子标签递归展开；**循环引用会导致加载失败**。
- 想“只追加不覆盖原版”，千万不要写 `replace: true`；想“只保留自己的内容”，才写 `true`。
- 原版关键标签如果被 `replace: true` 清空，可能直接导致世界加载失败（例如 `#minecraft:logs` 被清空后部分配方/方块行为异常）。

## 6. 函数 functions（`.mcfunction`）

### 6.1 文件规则

| 规则 | 1.20.1 的行为 |
|---|---|
| 路径即函数名 | `data/myns/functions/hello.mcfunction` → `myns:hello` |
| 每行一条命令 | 行首行尾空白被裁掉；空行忽略 |
| 前导 `/` | **不要写**，写了会报“未知命令” |
| 注释 | 行首（允许前置空格/制表符）写 `#`；**不支持行尾注释** |
| 单行长度 | 不受命令方块的 32500 字符限制；但**不支持续行**（`\` 续行是 1.20.2 的 23w31a 才有） |
| 加载时机 | 非宏函数在加载/`/reload` 时整文件解析；**任何一行语法错 → 整个文件加载失败**，reload 会报文件名与行号 |
| 执行粒度 | 一个函数内所有命令在**同一 tick** 内顺序执行完 |
| 上下文 | 继承调用者的执行者/位置/朝向/维度/anchor；**行与行之间不保留 `execute` 改动** |
| 权限 | 单人/LAN 按权限等级 2；服务器受 `server.properties` 的 `function-permission-level`（默认 2）限制 |
| 命令总数上限 | 单次命令链受 `gamerule maxCommandChainLength` 限制，默认 65536 |
| 返回值 | 1.20.1 只有 `return <整数>`；`return run` / `return fail` **不存在** |
| 宏 | **不存在**。`$` 开头、`$(var)`、`function ... with` 全部是 1.20.2+ |

> 1.20.1 写长命令只能真的一行写完。把长 `tellraw`/`summon` 拆成多条短命令，或者用 `data storage` 分步拼装。

### 6.2 最小函数与注释

```mcfunction
# data/myns/functions/demo/basic.mcfunction
# 这是注释；空行下面这行是空行

say 第一行
scoreboard players add @s myns.data 1
```

```mcfunction
function myns:demo/basic
```

### 6.3 上下文不跨行（最常见的误解）

```mcfunction
# 假设函数由玩家在 y=64 执行
teleport @s ~ ~5 ~
setblock ~ ~-1 ~ minecraft:emerald_block
# ↑ 仍以“函数开始时的位置”为准（y=64 附近），不是传送后的 y=69

execute at @s run setblock ~ ~-1 ~ minecraft:diamond_block
# ↑ 加了 execute at @s 才使用传送后的位置
```

同理，`execute as @e[...] run ...` 里 `@s` 只在那个 `execute` 的 `run` 内有效。

### 6.4 `execute` 完整语法（1.20.1）

```text
execute ... align <axes> -> execute
execute ... anchored <eyes|feet> -> execute
execute ... as <targets> -> execute
execute ... at <targets> -> execute
execute ... facing (<pos>|entity <targets> <eyes|feet>) -> execute
execute ... in <dimension> -> execute
execute ... on <relation> -> execute
execute ... positioned (<pos>|as <targets>|over <heightmap>) -> execute
execute ... rotated (<yaw> <pitch>|as <targets>) -> execute
execute ... store (result|success) (block <pos> <path> <type> <scale>|bossbar <id> (value|max)|entity <target> <path> <type> <scale>|score <targets> <objective>|storage <id> <path> <type> <scale>) -> execute
execute ... summon <entity> -> execute
execute ... (if|unless) ... -> [execute]
execute ... run <command>
```

#### 上下文修改类

| 子命令 | 语法 | 说明 |
|---|---|---|
| `align` | `align <axes>` | 把执行位置按指定轴向下取整；`axes` 是 `x`/`y`/`z` 的任意组合，如 `align xyz`、`align xz` |
| `anchored` | `anchored <eyes\|feet>` | 设置 `^ ^ ^` 的原点；1.20.1 只有这两个值 |
| `as` | `as <targets>` | 换执行者（改 `@s`），**不改**位置/朝向/维度 |
| `at` | `at <targets>` | 换位置/朝向/维度，**不改**执行者 |
| `facing` | `facing <pos>` / `facing entity <targets> <eyes\|feet>` | 设置朝向 |
| `in` | `in <dimension>` | 换维度；相对坐标按维度缩放换算（主世界↔下界 8:1） |
| `on` | `on <relation>` | 按关系换执行者，见下表 |
| `positioned` | `positioned <pos>` / `positioned as <targets>` / `positioned over <heightmap>` | 只改位置 |
| `rotated` | `rotated <yaw> <pitch>` / `rotated as <targets>` | 只改朝向（yaw 单位为度，-180..180） |
| `summon` | `summon <entity>` | 在执行位置生成实体并把**新实体设为执行者**（1.19.4+，1.20.1 可用） |

`positioned over` 的 heightmap 取值（1.20.1）：

| 值 | 含义 |
|---|---|
| `world_surface` | 最高非空气方块之上 |
| `ocean_floor` | 海底（含水面以下） |
| `motion_blocking` | 最高能阻挡移动的方块之上 |
| `motion_blocking_no_leaves` | 同上，但忽略树叶 |

`on` 的关系值：

| 值 | 选中谁 |
|---|---|
| `attacker` | 最近 5 秒内伤害过当前执行者的实体 |
| `controller` | 正在骑乘并控制当前执行者的实体 |
| `leasher` | 用拴绳牵着当前执行者的实体 |
| `origin` | 召唤出当前执行者的实体（箭的射手、TNT 的点火者） |
| `owner` | 可驯服动物的主人 |
| `passengers` | 直接骑在当前执行者背上的实体（可能多个，会分叉） |
| `target` | 当前执行者正在攻击的目标 |
| `vehicle` | 当前执行者骑着的实体 |

#### 条件类 `if` / `unless`（1.20.1 存在的全集）

| 形式 | 语法 | 备注 |
|---|---|---|
| biome | `if biome <pos> <biome>` | 1.19.3+，1.20.1 可用 |
| block | `if block <pos> <block>` | 支持方块标签 `#minecraft:logs` 与状态 `minecraft:oak_stairs[facing=east]` |
| blocks | `if blocks <start> <end> <destination> (all\|masked)` | 区域比对；体积上限 32768 |
| data | `if data block <pos> <path>` / `if data entity <target> <path>` / `if data storage <id> <path>` | 也接受根复合标签精确匹配 |
| dimension | `if dimension <dimension>` | |
| entity | `if entity <targets>` | |
| loaded | `if loaded <pos>` | 该位置所在区块是否已加载 |
| predicate | `if predicate <id>` | 数据包谓词（§10） |
| score | `if score <target> <obj> (<=|>=|=|<|>) <source> <srcObj>` / `if score <target> <obj> matches <range>` | |

**1.20.1 不存在**：`if function`（1.20.3+）、`if items`（1.20.5+）。判断“手里有没有某物品”只能用 `if data entity @s SelectedItem` 或谓词/`clear` 计数技巧。

#### `store` 类

| 目标 | 语法 | 用途 |
|---|---|---|
| `block` | `store (result\|success) block <pos> <path> <byte\|short\|int\|long\|float\|double> <scale>` | 写入方块实体 NBT |
| `bossbar` | `store (result\|success) bossbar <id> (value\|max)` | 写进 bossbar |
| `entity` | `store (result\|success) entity <target> <path> <type> <scale>` | 写入实体 NBT（**玩家 NBT 只读，会失败**） |
| `score` | `store (result\|success) score <targets> <objective>` | 写进计分板（int） |
| `storage` | `store (result\|success) storage <id> <path> <type> <scale>` | 写进命令存储 |

- `result` = 命令返回值（数量/坐标等）；`success` = 成功计数（通常 0/1）。
- 写入顺序：先乘 `scale`，再转成目标类型；`int` 会截断小数。

### 6.5 `execute` 实战示例

```mcfunction
# 1. 把每个玩家脚下的方块换成金块
execute as @a at @s run setblock ~ ~-1 ~ minecraft:gold_block

# 2. 只对生存模式玩家给再生
execute as @a[gamemode=survival] at @s run effect give @s minecraft:regeneration 5 0 true

# 3. 先筛选再执行：if 必须在 run 之前
execute as @a if score @s coins matches 10.. run tellraw @s {"text":"你有 10 个以上硬币"}

# 4. 把玩家等级写进计分板
execute store result score @s myns.level run data get entity @s XpLevel

# 5. 每个玩家找最近的僵尸并造成伤害
execute as @a at @s run execute as @e[type=minecraft:zombie,distance=..5,sort=nearest,limit=1] run damage @s 4 minecraft:generic

# 6. 对齐到整数方块坐标后放盔甲架
execute align xyz run summon minecraft:armor_stand ~ ~ ~

# 7. 从眼睛位置发射粒子（anchored 决定 ^ ^ ^ 原点）
execute as @a at @s anchored eyes run particle minecraft:flame ^ ^ ^2 0 0 0 0 1

# 8. 把执行者换成船上乘客
execute as @e[type=minecraft:boat] on passengers run give @s minecraft:fishing_rod

# 9. 沿视线前进 1 格
execute as @e at @s facing 0 64 0 run teleport @s ^ ^ ^1

# 10. 跨维度定位
execute in minecraft:the_nether positioned as @s run tp ~ ~ ~

# 11. 定位到地表上方一格再生成 marker
execute positioned over world_surface run summon minecraft:marker ~ ~ ~

# 12. summon 后直接操作新实体
execute summon minecraft:sheep run tag @s add demo

# 13. 只写成功与否
execute store success score @s myns.ok run function myns:check

# 14. 写进 storage，倍率 100，四舍五入成 int
execute store result storage myns:stats kills int 100 run scoreboard players get @s myns.kills
```

⚠️ 高频错误：`execute as @a run execute if score ...` 这种写法本身没错，但把 `if` 放到 `run` **之后**就是另一条命令了；条件要写在 `run` 之前。`execute` 也不能跨行“续写”。

### 6.6 `#minecraft:load` 与 `#minecraft:tick`

两个特殊函数标签，1.20.1 的目录是 `data/minecraft/tags/functions/`：

`data/minecraft/tags/functions/load.json`：

```json
{
  "values": [
    "myns:init"
  ]
}
```

`data/minecraft/tags/functions/tick.json`：

```json
{
  "values": [
    "myns:tick"
  ]
}
```

| 标签 | 触发时机 | 注意 |
|---|---|---|
| `#minecraft:load` | 世界加载、服务器启动、`/reload` 后各一次 | 此时玩家可能还没进入世界：`@a` 选不到人，`tellraw` 无显示 |
| `#minecraft:tick` | 每个 tick 开头一次 | 重逻辑不要直接放这里，用计分板节流或 `schedule` |

同一 tick 内的大致顺序（1.20.1，**未逐帧验证**）：进度奖励函数 → 附魔效果函数 → `#minecraft:tick` → `schedule` 到期函数 → 命令方块/玩家命令。

### 6.7 节流：不要每 tick 全图扫描

```mcfunction
# data/myns/functions/tick.mcfunction
scoreboard players add #tick myns.timer 1
execute if score #tick myns.timer matches 20 run function myns:second
```

```mcfunction
# data/myns/functions/second.mcfunction
scoreboard players set #tick myns.timer 0
execute as @a at @s run function myns:player_tick
```

- `matches 20` 只在计数正好 20 的那一 tick成立；写 `matches 20..` 会从第 20 tick 起**每 tick**触发 —— 这是“节流没生效”的头号原因。
- 用 `schedule` 自循环更精确，但 `/reload` 会清空已排队任务，必须在 `load.mcfunction` 里重新排。

```mcfunction
# load.mcfunction 里
schedule function myns:tick_1s 20t replace

# tick_1s.mcfunction 里
execute as @a at @s run function myns:player_tick
schedule function myns:tick_1s 20t replace
```

### 6.8 函数里最常用的命令（1.20.1 语法）

#### `function` / `schedule`

```text
function <name>
schedule function <function> <time> [append|replace]
schedule clear <function>
```

```mcfunction
function myns:util/hello
function #myns:group
schedule function myns:tick_1s 20t replace
schedule function myns:boss_spawn 5s append
schedule clear myns:tick_1s
```

- `<time>`：纯数字 = tick；`20t` = tick；`5s` = 5 秒；`1d` = 1 天。1.20.1 就支持 `s`/`d`。
- `append` 排队、`replace` 替换已有同名任务。
- **1.20.1 没有** `function ... with`（宏参数），写了直接语法错误。

#### `tag`（实体标签，和“标签文件”不是一回事）

```text
tag <targets> add <name>
tag <targets> remove <name>
tag <targets> list
```

```mcfunction
tag @s add demo
tag @e[type=minecraft:zombie] add hostile
tag @s remove demo
tag @s list
```

#### `scoreboard`

```text
scoreboard objectives add <name> <criteria> [<displayName>]
scoreboard objectives remove <name>
scoreboard objectives list
scoreboard objectives setdisplay <slot> [<objective>]
scoreboard objectives modify <name> displayname <text>
scoreboard objectives modify <name> renderType (hearts|integer)

scoreboard players set|add|remove <targets> <objective> <score>
scoreboard players get <target> <objective>
scoreboard players reset <targets> [<objective>]
scoreboard players operation <targets> <objective> <op> <source> <sourceObjective>
```

`<criteria>` 常用：`dummy`、`trigger`、`deathCount`、`playerKillCount`、`totalKillCount`、`health`、`food`、`air`、`armor`、`xp`、`level`、`teamkill.<color>`。自定义逻辑一律用 `dummy`。

`<op>`：`=`、`+=`、`-=`、`*=`、`/=`、`%=`、`<`、`>`、`><`（交换）。

```mcfunction
scoreboard objectives add myns.coins dummy {"text":"金币","color":"gold"}
scoreboard objectives add myns.timer dummy
scoreboard objectives setdisplay sidebar myns.coins

scoreboard players set @s myns.coins 100
scoreboard players add @s myns.coins 5
scoreboard players operation @s myns.coins += @s myns.bonus
scoreboard players operation @s myns.coins < @s myns.cap
scoreboard players set #const myns.coins 2
```

> 1.20.1 **没有** `scoreboard players display name|numberformat`（1.20.3+）。分数上限是 int32（±2,147,483,647），溢出会回绕。

#### `data`（读写 NBT）

```text
data get (block <pos>|entity <target>|storage <id>) [<path>] [<scale>]
data merge (block <pos>|entity <target>|storage <id>) <nbt>
data modify (block <pos>|entity <target>|storage <id>) <path> (set|merge|append|prepend|insert <index>) (from (...)|string (...) [<start>] [<end>]|value <snbt>)
data remove (block <pos>|entity <target>|storage <id>) <path>
```

```mcfunction
data get entity @s Health
data get entity @s SelectedItem
data get entity @s Inventory[0]
data get storage myns:vars counter

data merge entity @s {NoGravity:1b,Invulnerable:1b}
data merge storage myns:vars {counter:0,name:"unknown"}

data modify entity @s CustomName set value '{"text":"Bob","color":"gold"}'
data modify storage myns:vars counter set value 42
data modify entity @s Tags append value "demo"
data modify entity @s Tags prepend value "first"
data modify storage myns:list items insert 0 value "head"
data modify storage myns:list items append from storage myns:other items

data remove entity @s Tags[0]
data remove storage myns:vars temp
```

**NBT 路径语法**：

| 节点 | 选中什么 | 示例 |
|---|---|---|
| `name` | 复合标签里的同名子标签 | `Health`、`Inventory` |
| `"带空格的名字"` | 需要引号的名字 | `"A crazy name!"` |
| `[i]` | 列表第 i 个元素（负数为倒数） | `Inventory[0]`、`Tags[-1]` |
| `[]` | 列表的全部元素（多选） | `ActiveEffects[]` |
| `[{k:v}]` | 列表中匹配的复合元素（多选） | `Inventory[{id:"minecraft:diamond"}]` |
| `{k:v}` | 根节点匹配（只能放开头） | `{Invisible:1b}.id` |
| `name{k:v}` | 名为 name 且匹配的复合标签 | `Item{id:"minecraft:diamond"}` |

限制：

- `data get` 最终必须只选中**一个**标签；`data get entity @s Inventory[]` 会报“路径选中多个标签”。
- `data modify`/`data remove` 允许多选，可一次改多个。
- **玩家 NBT 只读**：`data modify entity @s ...`、`store ... entity @s` 都会失败。要改玩家状态用命令（`effect`、`xp`、`give`）。
- 路径不存在时 `data modify ... set` **静默无事**，也不报错；先 `data get` 确认父节点。

#### `summon` / `setblock` / `fill` / `clone` / `place`

```text
summon <entity> [<pos>] [<nbt>]
setblock <pos> <block> [destroy|keep|replace]
fill <from> <to> <block> [destroy|hollow|keep|outline|replace] [<filter>]
clone <begin> <end> <destination> [replace|masked] [normal|force|move] [<filter>]
place template <template> [<pos>] [<rotation>] [<mirror>] [<integrity>] [<seed>]
place feature <feature> [<pos>]
place jigsaw <pool> <target> <max_depth> [<pos>]
place structure <structure> [<pos>]
```

```mcfunction
summon minecraft:zombie ~ ~1 ~ {Tags:["demo"],NoAI:1b,CustomName:'{"text":"Bob"}'}
summon minecraft:item ~ ~ ~ {Item:{id:"minecraft:diamond",Count:1b},PickupDelay:10}

setblock ~ ~-1 ~ minecraft:stone
setblock ~ ~ ~ minecraft:oak_stairs[facing=east,half=bottom]
setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b,id:"minecraft:diamond",Count:3b}]} replace
setblock ~ ~ ~ minecraft:air destroy

fill ~ ~ ~ ~5 ~5 ~5 minecraft:glass
fill ~ ~ ~ ~5 ~5 ~5 minecraft:air replace minecraft:stone
fill ~ ~ ~ ~5 ~5 ~5 minecraft:oak_planks hollow
fill ~ ~ ~ ~5 ~5 ~5 minecraft:stone outline

clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~
clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~ masked
clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~ force move

place template myns:house ~ ~ ~
place feature minecraft:forest_rock ~ ~ ~
place structure minecraft:village_plains ~ ~ ~
```

- `fill`/`clone` 单次最多 32768 格，超出直接失败。
- `<filter>` 是方块谓词，可写 `minecraft:stone` 或 `#minecraft:logs`，只对 `replace`/`masked` 有意义。
- **Java 版没有 `/structure` 命令**（那是基岩版）。保存结构用结构方块，加载用 `place template`。
- `place template` 指向 `data/<ns>/structures/*.nbt`，写 `myns:house`，不带 `.nbt`。

#### `tellraw` / `title` / `playsound` / `particle`

```mcfunction
tellraw @a {"text":"Hello","color":"gold"}
tellraw @a [{"text":"["},{"text":"系统","color":"gold"},{"text":"] 欢迎，","color":"white"},{"selector":"@s","color":"aqua"}]
tellraw @a {"text":"点击领取","color":"green","clickEvent":{"action":"run_command","value":"/function myns:reward"}}

title @a times 10 40 20
title @a subtitle {"text":"副标题","color":"gray"}
title @a title {"text":"第三章","bold":true,"color":"gold"}
title @s actionbar {"text":"HP 12/20","color":"red"}
title @a clear

playsound minecraft:entity.experience_orb.pickup master @s ~ ~ ~ 1 1
playsound minecraft:block.note_block.bell record @a ~ ~ ~ 2 1.2
stopsound @a record

particle minecraft:happy_villager ~ ~1 ~ 0.3 0.3 0.3 0 10
particle minecraft:flame ~ ~ ~ 0 0 0 0.05 30 force
```

- `clickEvent.run_command` 的 `value` **必须带 `/`**，在函数里也一样。
- `playsound` 的 `source` 只能是 `master`/`music`/`record`/`weather`/`block`/`hostile`/`neutral`/`player`/`ambient`/`voice`。
- `particle` 的 `normal` 只让附近玩家看到，`force` 所有玩家可见。

#### `effect` / `attribute` / `damage` / `give` / `item`

```text
effect give <targets> <effect> [<seconds>] [<amplifier>] [<hideParticles>]
effect clear <targets> [<effect>]

attribute <target> <attribute> get [<scale>]
attribute <target> <attribute> base get [<scale>]
attribute <target> <attribute> base set <value>
attribute <target> <attribute> modifier add <uuid> <name> <value> <operation>
attribute <target> <attribute> modifier remove <uuid>
attribute <target> <attribute> modifier value get <uuid> [<scale>]

damage <target> <amount> [<damageType>] [at <pos>|by <entity> [from <cause>]]
kill <targets>

give <targets> <item> [<count>]
clear <targets> [<item>] [<maxCount>]
item replace (block <pos>|entity <targets>) <slot> with <item> [<count>]
item replace (block <pos>|entity <targets>) <slot> from (block <pos>|entity <targets>) <slot> [<modifier>]
item modify (block <pos>|entity <targets>) <slot> <modifier>
```

```mcfunction
effect give @s minecraft:speed 30 1 true
effect give @a minecraft:regeneration 10 2
effect clear @s minecraft:poison

attribute @s minecraft:generic.max_health base set 40
attribute @s minecraft:generic.attack_damage base get
attribute @s minecraft:generic.movement_speed modifier add 00000000-0000-0000-0000-000000000001 myns:fast 0.1 add

damage @s 4 minecraft:generic
damage @e[type=minecraft:zombie,limit=1] 6 minecraft:player_attack by @s
kill @e[type=minecraft:zombie,tag=demo]

give @s minecraft:diamond 3
give @s minecraft:diamond_sword{display:{Name:'{"text":"Excalibur","color":"gold"}'},Enchantments:[{id:"minecraft:sharpness",lvl:5}]}
clear @s minecraft:diamond 0

item replace entity @s weapon.mainhand with minecraft:diamond_sword
item replace entity @s armor.head with minecraft:golden_helmet
item replace block ~ ~ ~ container.0 with minecraft:stone 16
item replace entity @s weapon.offhand from entity @s weapon.mainhand
item modify entity @s weapon.mainhand myns:add_ruby
```

**1.20.1 的 `attribute` 与 1.21 不同**：

| 项 | 1.20.1 | 1.21+ |
|---|---|---|
| `modifier add` | `<uuid> <name> <value> <operation>` | `<id> <value> <operation>` |
| operation 名 | `add` / `multiply` / `multiply_base`（**1.20.1 未实测**，写前先在游戏里 tab 补全确认） | `add_value` / `add_multiplied_base` / `add_multiplied_total` |
| `base reset` | 不存在（1.21.4+） | 存在 |
| 属性 ID | `minecraft:generic.max_health` 这类带 `generic.` 前缀 | 1.21.2 起改为 `minecraft:max_health` |

**`item` 命令的槽位（1.20.1）**：`weapon.mainhand`、`weapon.offhand`、`armor.head`、`armor.chest`、`armor.legs`、`armor.feet`、`hotbar.0`–`hotbar.8`、`inventory.0`–`inventory.26`、`enderchest.0`–`enderchest.26`、`horse.saddle`、`horse.chest`、`horse.armor`、`villager.0`–`villager.2`；方块用 `container.0`–`container.26`。

> **1.20.1 没有 `equipment.chest` 这类槽位**（1.21.5 的 `equipment` 统一槽位），也没有 `armor.body`（1.21 的马铠槽）。写 `equipment.*` 会得到“未知槽位”。

#### `loot`

```text
loot give <targets> <source>
loot insert <target> <slot> <source>
loot spawn <targetPos> <source>
loot replace (block <targetPos>|entity <target>) <slot> <source> [<limit>]

<source> := fish <loot_table> <pos> [<tool>|mainhand|offhand]
          | loot <loot_table>
          | kill <entity>
          | mine <pos> [<tool>|mainhand|offhand]
```

```mcfunction
loot give @s loot myns:rewards/common
loot spawn ~ ~1 ~ loot minecraft:chests/simple_dungeon
loot give @s kill @e[type=minecraft:zombie,limit=1,sort=nearest]
loot give @s mine ~ ~-1 ~ mainhand
loot replace block ~ ~ ~ container.0 loot myns:chests/food 1
loot spawn ~ ~ ~ fish minecraft:gameplay/fishing ~ mainhand
```

- `<loot_table>` 写 ID，不带 `.json`；1.20.1 在 `data/<ns>/loot_tables/` 下。
- `loot ... mine` 用方块自己的战利品表，并模拟“用主手工具挖”。

### 6.9 十个可直接落盘的完整函数

**① 初始化（幂等）**

```mcfunction
# data/myns/functions/load.mcfunction
scoreboard objectives add myns.data dummy
scoreboard objectives add myns.timer dummy
scoreboard objectives add myns.coins dummy
scoreboard players set #tick myns.timer 0
execute unless score #initialized myns.data matches 1 run function myns:init
```

```mcfunction
# data/myns/functions/init.mcfunction
gamerule keepInventory true
gamerule doDaylightCycle true
bossbar add myns:main {"text":"进度"}
bossbar set myns:main max 10
data merge storage myns:vars {initialized:1b,count:0,last:""}
scoreboard players set #initialized myns.data 1
schedule function myns:tick_1s 20t replace
```

**② 每秒循环**

```mcfunction
# data/myns/functions/tick_1s.mcfunction
execute as @a at @s run function myns:player_second
schedule function myns:tick_1s 20t replace
```

**③ 玩家每秒逻辑（带节流标记）**

```mcfunction
# data/myns/functions/player_second.mcfunction
execute if predicate myns:is_raining run effect give @s minecraft:slowness 1 0 true
execute if score @s myns.coins matches 100.. run title @s actionbar {"text":"金币已满","color":"gold"}
```

**④ 发奖励（战利品表 + 音效 + 提示）**

```mcfunction
# data/myns/functions/reward.mcfunction
loot give @s loot myns:rewards/daily
playsound minecraft:entity.player.levelup master @s ~ ~ ~ 1 1
title @s actionbar {"text":"每日奖励已发放","color":"green"}
```

**⑤ 商店购买（计分板判定 + 扣分 + 给物品）**

```mcfunction
# data/myns/functions/shop/buy_diamond.mcfunction
execute if score @s myns.coins matches 10.. run give @s minecraft:diamond 1
execute if score @s myns.coins matches 10.. run scoreboard players remove @s myns.coins 10
execute unless score @s myns.coins matches 10.. run tellraw @s {"text":"金币不足","color":"red"}
```

> 顺序必须是“先判定并发放，最后扣分”；反过来先扣分，后面的 `if score` 就永远不成立。更稳的写法见 ⑥（先拷到临时分数，避免多次读写同一分数）。

**⑥ 带临时变量的购买（正确顺序）**

```mcfunction
# data/myns/functions/shop/buy_diamond_safe.mcfunction
scoreboard players operation #tmp myns.data = @s myns.coins
execute if score #tmp myns.data matches 10.. run scoreboard players remove @s myns.coins 10
execute if score #tmp myns.data matches 10.. run give @s minecraft:diamond 1
execute unless score #tmp myns.data matches 10.. run tellraw @s {"text":"金币不足","color":"red"}
```

**⑦ NPC 对话（tellraw 可点击）**

```mcfunction
# data/myns/functions/npc/talk.mcfunction
tellraw @s [{"text":"[铁匠] ","color":"gold"},{"text":"要买一把剑吗？","color":"white"}]
tellraw @s [{"text":"[购买 10 金币]","color":"green","clickEvent":{"action":"run_command","value":"/function myns:shop/buy_diamond_safe"}},{"text":"  "},{"text":"[离开]","color":"gray","clickEvent":{"action":"run_command","value":"/function myns:npc/bye"}}]
```

**⑧ 生成带自定义名字与装备的 Boss**

```mcfunction
# data/myns/functions/boss/spawn.mcfunction
summon minecraft:zombie ~ ~ ~ {Tags:["myns_boss"],CustomName:'{"text":"腐化守卫","color":"dark_red","bold":true}',CustomNameVisible:1b,PersistenceRequired:1b,NoAI:0b,HandItems:[{id:"minecraft:netherite_sword",Count:1b},{}],ArmorItems:[{},{},{},{id:"minecraft:netherite_helmet",Count:1b}],Health:60.0f,Attributes:[{Name:"minecraft:generic.max_health",Base:60.0d}]}
bossbar add myns:boss {"text":"腐化守卫","color":"red"}
bossbar set myns:boss max 60
bossbar set myns:boss players @a
bossbar set myns:boss visible true
```

**⑨ 区域检测（每秒检测一次，进入时提示）**

```mcfunction
# data/myns/functions/zone/check.mcfunction
execute as @a at @s if entity @s[distance=..0.5] run function myns:zone/inside
```

```mcfunction
# data/myns/functions/zone/inside.mcfunction
execute if entity @s[tag=!myns_in_zone] run title @s actionbar {"text":"进入安全区","color":"aqua"}
execute if entity @s[tag=!myns_in_zone] run tag @s add myns_in_zone
```

**⑩ 清理临时实体**

```mcfunction
# data/myns/functions/cleanup.mcfunction
kill @e[type=minecraft:item,nbt={Age:6000s}]
kill @e[type=minecraft:armor_stand,tag=myns_temp]
tag @a remove myns_temp
```

> 这 10 个函数全部只用 1.20.1 存在的语法；没有宏、没有组件、没有 `return run`。

## 7. 配方 recipes

### 7.1 通用规则

- 路径：`data/<ns>/recipes/<path>.json`，ID `myns:path`。
- `type` **必填**，写全 `minecraft:crafting_shaped` 这类 ID。
- `group` 可选：字符串，只影响配方书里的分组排序，不参与匹配。
- `category` 可选：影响配方书分类与合成台提示；1.20.1 存在（1.19.3 引入），取值随配方类型不同（见各节）。
- 材料（ingredient）在 1.20.1 **必须写成对象**：

```json
{ "item": "minecraft:oak_planks" }
```

```json
{ "tag": "minecraft:planks" }
```

- **不能**写成裸字符串 `"minecraft:oak_planks"`（那是后续版本（1.21.x）才放宽的写法，1.20.1 会解析失败）。
- 配方加载失败不影响其他配方；但 `/reload` 后新配方立即出现在配方书（已解锁状态除外）。
- 移除原版配方：**没有**“删除”语法，只能用一个“永不匹配”的配方覆盖同 ID，或改 `doLimitedCrafting`；更常见的做法是不去动它。

### 7.2 `crafting_shaped`（有序合成）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:crafting_shaped` |
| `pattern` | string[] | 是 | 1–3 行，每行 1–3 个字符；空格表示空位 |
| `key` | object | 是 | 字符 → 材料；**键必须恰好 1 个字符** |
| `result` | object | 是 | `{"item": "...", "count": n}`，`count` 省略为 1 |
| `group` | string | 否 | 配方书分组 |
| `category` | string | 否 | `building`/`equipment`/`misc`/`redstone`（1.20.1 存在） |

```json
{
  "type": "minecraft:crafting_shaped",
  "category": "equipment",
  "group": "ruby_sword",
  "pattern": [
    "  X",
    "  X",
    " XY"
  ],
  "key": {
    "X": { "item": "minecraft:stick" },
    "Y": { "item": "minecraft:diamond" }
  },
  "result": {
    "item": "minecraft:diamond_sword",
    "count": 1
  }
}
```

要点：

- `pattern` 里同一字符在所有行里代表同一种材料；`key` 里没用到的字符会导致加载报错。
- `pattern` 每行长度必须一致、最多 3 行 3 列；空白行/列可以省略，不必写满 3×3。
- 游戏会在 3×3 网格内尝试 pattern 的**所有平移位置**，所以图案在实际摆放中偏一格也能匹配；但**不会镜像**，不对称图案要镜像请再写一个配方。
- 1.20.1 的 `result` 只能写 `item` + `count`，不支持 NBT/组件。

### 7.3 `crafting_shapeless`（无序合成）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:crafting_shapeless` |
| `ingredients` | object[] | 是 | 1–9 个材料对象；顺序无关 |
| `result` | object | 是 | `{"item": "...", "count": n}` |
| `group` | string | 否 | |
| `category` | string | 否 | 同上 |

```json
{
  "type": "minecraft:crafting_shapeless",
  "category": "misc",
  "ingredients": [
    { "item": "minecraft:bowl" },
    { "item": "minecraft:red_mushroom" },
    { "item": "minecraft:brown_mushroom" }
  ],
  "result": {
    "item": "minecraft:mushroom_stew",
    "count": 1
  }
}
```

- 同一种材料写两次就是“需要两个”。
- `ingredients` 里可以混用 `item` 与 `tag`。
- 数量上限 9（3×3）。

### 7.4 `smelting` / `blasting` / `smoking` / `campfire_cooking`

四种“烹饪”字段完全一致，只有 `type`、耗时与经验不同。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:smelting` / `minecraft:blasting` / `minecraft:smoking` / `minecraft:campfire_cooking` |
| `ingredient` | object | 是 | 单个材料对象（**不是数组**） |
| `result` | string / object | 是 | 1.20.1 推荐写字符串 `"minecraft:iron_ingot"`；对象 `{"item":"..."}` 亦可 |
| `experience` | float | 是 | 经验值，如 `0.7` |
| `cookingtime` | int | 是 | 单位 tick：熔炉 200、高炉 100、烟熏炉 100、营火 600 |
| `group` | string | 否 | |
| `category` | string | 否 | `food`/`blocks`/`misc` |

熔炉：

```json
{
  "type": "minecraft:smelting",
  "category": "misc",
  "cookingtime": 200,
  "experience": 0.7,
  "ingredient": { "item": "minecraft:raw_iron" },
  "result": "minecraft:iron_ingot"
}
```

高炉：

```json
{
  "type": "minecraft:blasting",
  "category": "misc",
  "cookingtime": 100,
  "experience": 0.7,
  "ingredient": { "item": "minecraft:raw_iron" },
  "result": "minecraft:iron_ingot"
}
```

烟熏炉：

```json
{
  "type": "minecraft:smoking",
  "category": "food",
  "cookingtime": 100,
  "experience": 0.35,
  "ingredient": { "item": "minecraft:beef" },
  "result": "minecraft:cooked_beef"
}
```

营火：

```json
{
  "type": "minecraft:campfire_cooking",
  "category": "food",
  "cookingtime": 600,
  "experience": 0.35,
  "ingredient": { "item": "minecraft:beef" },
  "result": "minecraft:cooked_beef"
}
```

要点：

- `cookingtime` 写小了会“瞬间熟”，写大了只是慢；不影响正确性。
- 高炉能烧什么**完全由 `blasting` 配方决定**：原版只给矿物/工具/盔甲写了 `blasting` 配方，所以看起来“只能炼这些”；你给任意物品写 `blasting` 配方，它就能在高炉里烧。
- 1.20.1 的 `result` 不支持组件/NBT；带 NBT 的产出要用函数发放（`loot give` / `give`）。

### 7.5 `stonecutting`（切石机）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:stonecutting` |
| `ingredient` | object | 是 | 单个材料 |
| `result` | string | 是 | 产出物品 ID |
| `count` | int | 是 | 产出数量（1–64 语义上） |
| `group` | string | 否 | |

```json
{
  "type": "minecraft:stonecutting",
  "group": "stone_bricks",
  "ingredient": { "item": "minecraft:stone" },
  "result": "minecraft:stone_brick_stairs",
  "count": 1
}
```

```json
{
  "type": "minecraft:stonecutting",
  "ingredient": { "tag": "minecraft:stone_bricks" },
  "result": "minecraft:stone_brick_slab",
  "count": 2
}
```

### 7.6 `smithing_transform`（锻造台：把材料“嵌”进装备）

1.20.1 的锻造台有三格（模板 / 底装 / 添加物），对应 JSON 字段 `template`、`base`、`addition`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:smithing_transform` |
| `template` | object | 是 | 模板材料（如下界合金升级模板） |
| `base` | object | 是 | 被升级的装备 |
| `addition` | object | 是 | 添加物（如净下界合金锭） |
| `result` | object | 是 | `{"item": "...", "count": n}` |

```json
{
  "type": "minecraft:smithing_transform",
  "template": { "item": "minecraft:netherite_upgrade_smithing_template" },
  "base": { "item": "minecraft:diamond_sword" },
  "addition": { "item": "minecraft:netherite_ingot" },
  "result": {
    "item": "minecraft:netherite_sword",
    "count": 1
  }
}
```

```json
{
  "type": "minecraft:smithing_transform",
  "template": { "item": "myns:ruby_upgrade_smithing_template" },
  "base": { "item": "myns:ruby_sword" },
  "addition": { "tag": "myns:ruby_gems" },
  "result": { "item": "myns:ruby_sword_plus" }
}
```

要点：

- `template` 在 1.20.1 **是必填**（1.20 之前没有模板格；把 1.19 的写法搬过来会加载失败）。
- `result` 的 `count` 通常为 1；写大数量会被锻造台按 1 处理（**未实测**）。
- `addition` 用 `tag` 时，所有匹配物品都能升级。
- 升级模板本身是物品（`minecraft:netherite_upgrade_smithing_template`），要自定义模板物品需要模组或资源包。

### 7.7 `smithing_trim`（锻造台：盔甲纹饰）

1.20.1 引入盔甲纹饰，`smithing_trim` 没有 `result`，产出由 `trim_pattern` + `trim_material` 决定。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 是 | `minecraft:smithing_trim` |
| `template` | object | 是 | 纹饰模板物品（如 `minecraft:wayfinder_armor_trim_smithing_template`） |
| `base` | object | 是 | 可纹饰的盔甲（通常用 `#minecraft:trimmable_armor` 标签） |
| `addition` | object | 是 | 纹饰材料（通常用 `#minecraft:trim_materials` 标签） |

```json
{
  "type": "minecraft:smithing_trim",
  "template": { "item": "minecraft:wayfinder_armor_trim_smithing_template" },
  "base": { "tag": "minecraft:trimmable_armor" },
  "addition": { "tag": "minecraft:trim_materials" }
}
```

自定义模板 + 自定义材料：

```json
{
  "type": "minecraft:smithing_trim",
  "template": { "item": "myns:ruby_armor_trim_smithing_template" },
  "base": { "tag": "minecraft:trimmable_armor" },
  "addition": { "item": "myns:ruby" }
}
```

要点：

- `smithing_trim` **没有** `result` 字段；写了会被忽略/报错（**字段残留会加载失败**，别照抄 `smithing_transform`）。
- 纹饰是否显示、什么颜色，由模板的 `trim_pattern` 和材料的 `trim_material` 定义（§12）。
- 基材用 `#minecraft:trimmable_armor` 才能覆盖全部盔甲；硬编码 `minecraft:diamond_chestplate` 只对那一件生效。
- 1.20.1 **没有** `crafting_transmute`（1.21 的合成台染色/复制配方），不要写。

### 7.8 特殊配方（1.20.1 存在，但无法用 JSON 自定义）

`minecraft:crafting_special_*` 系列（如 `crafting_special_armordye`、`crafting_special_bannerduplicate`、`crafting_special_firework_rocket`、`crafting_special_mapcloning`、`crafting_special_repairitem`、`crafting_special_tippedarrow`）由代码实现，**不接受自定义 JSON 字段**。你能做的只有用同名文件覆盖成别的 `type`，或干脆不写。

## 8. 战利品表 loot_tables

### 8.1 路径与根结构

路径：`data/<ns>/loot_tables/<path>.json`，ID `myns:path`。**目录名是复数的 `loot_tables`**（1.21 改为单数 `loot_table`）。

| 根字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `type` | string | 否 | 战利品表类型，默认 `minecraft:generic`；决定可用的上下文参数 |
| `pools` | 数组 | 否 | 奖池列表；为空则不掉落 |
| `functions` | 数组 | 否 | 作用于**最终产出**的函数（在 pools 之后执行） |
| `random_sequence` | string | 否 | 随机序列名；同名的多个表共享随机流（1.20 加入，**未在 1.20.1 实测**） |

### 8.2 战利品表类型（1.20.1）

| `type` | 使用场景 | 可用上下文 |
|---|---|---|
| `minecraft:generic`（默认） | 通用/由 `loot` 命令调用 | 仅参数集，无额外实体/方块 |
| `minecraft:block` | 方块被破坏时 | `block_entity`、`block_state`、`tool`、`this_entity`（若有） |
| `minecraft:entity` | 生物死亡时 | `this_entity`、`killer`、`direct_killer`、`damage_source` |
| `minecraft:chest` | 箱子/容器生成 | `origin`、`this_entity`（打开者） |
| `minecraft:fishing` | 钓鱼 | `this_entity`（浮标）、`tool`、`origin` |
| `minecraft:gift` | 村民“英雄”礼物 | `this_entity`、`origin` |
| `minecraft:barter` | 猪灵以物易物 | `this_entity`（猪灵） |
| `minecraft:advancement_reward` | 进度奖励 | `this_entity`（玩家） |
| `minecraft:command` | `/loot` 指定 | `origin` |
| `minecraft:selector` | `/loot` + 选择器 | `this_entity` |
| `minecraft:empty` | 无上下文 | — |
| `minecraft:archaeology` | 刷子刷可疑方块（1.20 加入） | `this_entity`、`tool`、`origin`（**未在 1.20.1 实测**） |

> `block`/`entity` 这两个类型决定了哪些条件能通过校验（比如 `entity_properties` 需要 `this_entity`）。类型写错时不是“不生效”，而是**加载时校验失败**或运行时条件恒假。

### 8.3 奖池 pools

| 字段 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| `rolls` | 数字提供器 | 是 | — | 抽取次数，可为小数（内部累计取整） |
| `bonus_rolls` | 数字提供器 | 否 | 0 | 额外抽取次数，常用幸运值 |
| `entries` | 数组 | 是 | — | 候选项 |
| `conditions` | 数组 | 否 | — | 整个奖池生效的条件 |

**数字提供器（number provider）的写法**：

```json
1
```

```json
{ "type": "minecraft:constant", "value": 3 }
```

```json
{ "min": 1, "max": 3 }
```

```json
{ "type": "minecraft:uniform", "min": 1, "max": 3 }
```

```json
{ "type": "minecraft:binomial", "n": 5, "p": 0.4 }
```

```json
{
  "type": "minecraft:score",
  "target": { "type": "minecraft:fixed", "name": "#luck" },
  "score": "myns.luck",
  "scale": 1
}
```

> `minecraft:score` 提供器的 `target` 结构**未在 1.20.1 实测**；如果加载报错，改用 `constant`/`uniform`，或在游戏里用 tab 补全确认字段。

- 直接写数字 = 常量；写 `{min,max}` 简写 = uniform。
- `rolls` 支持小数：`2.5` 表示每 2 次必抽、第 3 次 50% 概率。

### 8.4 条目 entries

通用字段（除组合型外都可用）：

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `type` | string | 必填 | 见下表 |
| `weight` | int | 1 | 权重；同一 entries 数组里按权重随机 |
| `quality` | int | 0 | 幸运加成：实际权重 = `weight + quality * luck` |
| `conditions` | 数组 | — | 该条目生效条件 |
| `functions` | 数组 | — | 该条目产出后应用的函数 |

| `type` | 额外字段 | 说明 |
|---|---|---|
| `minecraft:item` | `name`（物品 ID，必填） | 产出 1 个该物品 |
| `minecraft:tag` | `name`（**标签 ID，不带 `#`**）、`expand`（bool，默认 true） | 从标签里随机选一个物品 |
| `minecraft:loot_table` | `name`（另一个战利品表 ID，1.20.1 字段名是 `name`） | 嵌套表 |
| `minecraft:dynamic` | `name`：`contents`（方块实体内容）/`sherds`（陶片） | 动态读取 |
| `minecraft:empty` | 无 | 空；用于“什么都没抽到” |
| `minecraft:alternatives` | `children`（数组） | **第一个条件通过的 child** 生效 |
| `minecraft:sequence` | `children` | 依次执行所有 child（每个都要过条件） |
| `minecraft:group` | `children` | 把多个 child 当作同一“条目组”参与权重 |

> 后续版本对条目类型名和 `name` 字段做过调整（`name` 在 1.20.5 起改为 `value`，`functions` 后来改为 `modifier`）；**1.20.1 请严格用上表**。

### 8.5 条件 conditions（1.20.1）

| `condition` | 字段 | 说明 |
|---|---|---|
| `minecraft:survives_explosion` | 无 | 爆炸破坏时 1/爆炸半径 概率保留（与 TNT 掉落相关） |
| `minecraft:random_chance` | `chance`（0–1） | 概率通过 |
| `minecraft:random_chance_with_looting` | `chance`、`looting_multiplier` | 概率 = chance + looting * multiplier |
| `minecraft:entity_properties` | `entity`（`this`/`killer`/`direct_killer`/...）、`predicate`（实体谓词） | 判定实体属性 |
| `minecraft:entity_scores` | `entity`、`scores`（对象：objective → 整数范围） | 判定计分板 |
| `minecraft:block_state_property` | `block`（方块 ID）、`properties`（状态键值，正则/字符串） | 判定方块状态 |
| `minecraft:match_tool` | `predicate`（物品谓词） | 判定使用的工具 |
| `minecraft:table_bonus` | `enchantment`、`chances`（按等级的概率数组） | 时运类附魔概率表 |
| `minecraft:inverted` | `term` | 取反 |
| `minecraft:any_of` | `terms` | 任一通过（1.20 由 `alternative` 改名） |
| `minecraft:all_of` | `terms` | 全部通过 |
| `minecraft:reference` | `name` | 引用 `predicates/` 里的谓词文件 |
| `minecraft:value_check` | `value`（数字提供器）、`range` | 数值区间判定 |
| `minecraft:time_check` | `value`（0–24000 范围）、`period` | 游戏内时间判定 |

⚠️ 组合条件在 1.19 及更早叫 `minecraft:alternative`；**1.20 起统一为谓词后改名为 `any_of`**。1.20.1 请用 `any_of`/`all_of`；旧名是否仍兼容**未在 1.20.1 实测**。

**实体谓词**（`entity_properties.predicate` 里）常用字段：

```json
{
  "type": "minecraft:player",
  "flags": { "is_sneaking": true },
  "equipment": {
    "mainhand": { "items": ["minecraft:diamond_sword"] }
  },
  "location": {
    "biome": "minecraft:plains",
    "dimension": "minecraft:overworld"
  },
  "effects": { "minecraft:poison": { "amplifier": { "min": 1 } } }
}
```

| 字段 | 说明 |
|---|---|
| `type` | 实体类型 ID，或 `#标签` |
| `nbt` | SNBT 字符串（注意是**字符串**，不是对象） |
| `flags` | `is_on_fire`、`is_sneaking`、`is_sprinting`、`is_swimming`、`is_baby` |
| `equipment` | `mainhand`/`offhand`/`head`/`chest`/`legs`/`feet`，值是物品谓词（**这是实体谓词字段，不是命令槽位**） |
| `location` | `biome`、`dimension`、`structure`、`block`、`fluid`、`light`、`position` |
| `effects` | 状态效果 → `amplifier`/`duration` 区间 |
| `distance` | `{ "absolute": {min,max} }` 等 |
| `player` | 仅玩家：`gamemode`、`level`、`advancements`、`recipes`、`stats` |
| `team` | 队伍名 |
| `vehicle`/`passenger`/`targeted_entity` | 嵌套实体谓词 |

**物品谓词**（`match_tool.predicate`、`equipment.*` 里）：

```json
{
  "items": ["minecraft:diamond_pickaxe"],
  "tag": "minecraft:pickaxes",
  "count": { "min": 1 },
  "durability": { "min": 1 },
  "enchantments": [
    { "enchantment": "minecraft:fortune", "levels": { "min": 3 } }
  ],
  "nbt": "{Damage:0}",
  "potion": "minecraft:strong_healing"
}
```

| 字段 | 说明 |
|---|---|
| `items` | 物品 ID 数组 |
| `tag` | 物品标签（**不带 `#`**） |
| `count` | 整数范围 |
| `durability` | 剩余耐久范围 |
| `enchantments` / `stored_enchantments` | 附魔数组：`enchantment` + `levels`（整数或 `{min,max}`） |
| `nbt` | **SNBT 字符串**，不是对象 |
| `potion` | 药水 ID（仅药水类物品） |

> 同时写多个字段时是 **AND** 关系。

### 8.6 常用函数 functions

| `function` | 关键字段 | 说明 |
|---|---|---|
| `minecraft:set_count` | `count`（数字提供器）、`add`（bool，默认 false） | 设置/增加数量 |
| `minecraft:set_damage` | `damage`（0–1 或数字提供器）、`add` | 设置耐久损耗比例 |
| `minecraft:set_nbt` | `tag`（SNBT **字符串**） | 合并 NBT（1.20.1 专用；1.20.5 换成 `set_components`） |
| `minecraft:set_name` | `name`（字符串或文本组件 JSON）、`entity`（`this`/`killer`） | 设置显示名 |
| `minecraft:set_lore` | `lore`（字符串数组）、`entity` | 设置 lore |
| `minecraft:enchant_randomly` | `enchantments`（附魔 ID 数组，可选） | 随机附魔 |
| `minecraft:enchant_with_levels` | `levels`（数字提供器）、`treasure`（bool） | 按等级附魔 |
| `minecraft:looting_enchant` | `count`（数字提供器）、`limit` | 抢夺加成数量 |
| `minecraft:apply_bonus` | `enchantment`、`formula`、`parameters` | 时运公式 |
| `minecraft:explosion_decay` | 无 | 爆炸衰减 |
| `minecraft:furnace_smelt` | 无 | 按熔炉配方“烧熟”掉落物（**没有** `minecraft:smelt`） |
| `minecraft:copy_name` | `source`（`block_entity`/`this`/`killer`） | 复制名字 |
| `minecraft:copy_nbt` | `source`、`ops`（数组：`source`/`target`/`op`） | 复制 NBT（1.20.1） |
| `minecraft:copy_state` | `block`、`properties`（数组） | 复制方块状态到物品 NBT |
| `minecraft:set_contents` | `entries`（数组） | 写入容器内容（如潜影盒） |
| `minecraft:set_loot_table` | `name`、`seed`、`type`（方块实体类型） | 给方块实体挂战利品表 |
| `minecraft:set_stew_effect` | `effects`（`[{type, duration}]`） | 迷之炖菜效果 |
| `minecraft:set_banner_pattern` | `patterns`、`append` | 旗帜图案 |
| `minecraft:exploration_map` | `destination`、`decoration`、`zoom`、`search_radius`、`skip_existing_chunks` | 探险地图 |
| `minecraft:fill_player_head` | `entity` | 玩家头颅 |
| `minecraft:reference` | `name` | 引用 `item_modifiers/` 文件（1.20 加入） |

`apply_bonus` 的 `formula`：

| formula | parameters | 语义 |
|---|---|---|
| `minecraft:binomial_with_bonus_count` | `extra`、`probability` | 额外掉落次数服从二项分布 |
| `minecraft:uniform_bonus_count` | `bonusMultiplier` | 均匀随机 0..bonusMultiplier*等级 |
| `minecraft:ore_drops` | 无 | 矿物：`1 + rand(0..等级+1)` 倍（时运） |

⚠️ `minecraft:sequence` 作为**函数**是 1.20.2+；1.20.1 想顺序执行多个函数，直接把函数写进 `functions` 数组即可。

### 8.7 示例 1：方块掉落（精准采集 vs 时运）

`data/myns/loot_tables/blocks/ruby_ore.json`：

```json
{
  "type": "minecraft:block",
  "pools": [
    {
      "rolls": 1,
      "bonus_rolls": 0,
      "entries": [
        {
          "type": "minecraft:alternatives",
          "children": [
            {
              "type": "minecraft:item",
              "name": "minecraft:redstone_ore",
              "conditions": [
                {
                  "condition": "minecraft:match_tool",
                  "predicate": {
                    "enchantments": [
                      {
                        "enchantment": "minecraft:silk_touch",
                        "levels": { "min": 1 }
                      }
                    ]
                  }
                }
              ]
            },
            {
              "type": "minecraft:item",
              "name": "minecraft:redstone",
              "functions": [
                {
                  "function": "minecraft:set_count",
                  "count": { "min": 4, "max": 5 }
                },
                {
                  "function": "minecraft:apply_bonus",
                  "enchantment": "minecraft:fortune",
                  "formula": "minecraft:ore_drops"
                },
                {
                  "function": "minecraft:explosion_decay"
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

用它替换某个方块：把文件放到 `data/minecraft/loot_tables/blocks/redstone_ore.json` 即可（**覆盖原版**）。自定义方块（模组方块）则用 `myns:blocks/ruby_ore` 并在方块属性里指定（模组侧工作）。

### 8.8 示例 2：箱子（多奖池 + 空池 + 权重）

`data/myns/loot_tables/chests/supply.json`：

```json
{
  "type": "minecraft:chest",
  "pools": [
    {
      "rolls": { "min": 1, "max": 3 },
      "entries": [
        { "type": "minecraft:item", "name": "minecraft:bread", "weight": 10, "functions": [ { "function": "minecraft:set_count", "count": { "min": 1, "max": 3 } } ] },
        { "type": "minecraft:item", "name": "minecraft:torch", "weight": 8,  "functions": [ { "function": "minecraft:set_count", "count": { "min": 2, "max": 6 } } ] },
        { "type": "minecraft:item", "name": "minecraft:iron_ingot", "weight": 4, "functions": [ { "function": "minecraft:set_count", "count": { "min": 1, "max": 2 } } ] },
        { "type": "minecraft:item", "name": "minecraft:diamond", "weight": 1, "quality": 2 },
        { "type": "minecraft:empty", "weight": 6 }
      ]
    },
    {
      "rolls": 1,
      "conditions": [ { "condition": "minecraft:random_chance", "chance": 0.25 } ],
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:written_book",
          "functions": [
            {
              "function": "minecraft:set_nbt",
              "tag": "{title:\"补给日志\",author:\"myns\",pages:[\"第 3 天：补给耗尽。\"]}"
            }
          ]
        }
      ]
    }
  ]
}
```

用命令往箱子里塞：

```mcfunction
setblock ~ ~ ~ minecraft:chest
loot replace block ~ ~ ~ container.0 loot myns:chests/supply 27
```

### 8.9 示例 3：实体掉落（抢夺 + 条件）

`data/myns/loot_tables/entities/ruby_golem.json`：

```json
{
  "type": "minecraft:entity",
  "pools": [
    {
      "rolls": 1,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:iron_ingot",
          "functions": [
            { "function": "minecraft:set_count", "count": { "min": 2, "max": 4 } },
            { "function": "minecraft:looting_enchant", "count": { "min": 0, "max": 1 } }
          ]
        }
      ]
    },
    {
      "rolls": 1,
      "conditions": [
        {
          "condition": "minecraft:entity_properties",
          "entity": "killer",
          "predicate": { "type": "minecraft:player" }
        }
      ],
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:emerald",
          "functions": [
            { "function": "minecraft:set_count", "count": 1 },
            { "function": "minecraft:explosion_decay" }
          ]
        }
      ]
    }
  ]
}
```

### 8.10 示例 4：任务奖励（`advancement_reward` + 子表 + 修饰器）

`data/myns/loot_tables/rewards/daily.json`：

```json
{
  "type": "minecraft:advancement_reward",
  "pools": [
    {
      "rolls": 2,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:golden_apple",
          "weight": 3,
          "functions": [ { "function": "minecraft:set_count", "count": 1 } ]
        },
        {
          "type": "minecraft:loot_table",
          "name": "myns:rewards/gems",
          "weight": 1
        },
        {
          "type": "minecraft:item",
          "name": "minecraft:experience_bottle",
          "weight": 5,
          "functions": [ { "function": "minecraft:set_count", "count": { "min": 3, "max": 8 } } ]
        }
      ]
    }
  ]
}
```

`data/myns/loot_tables/rewards/gems.json`：

```json
{
  "type": "minecraft:generic",
  "pools": [
    {
      "rolls": 1,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:diamond",
          "weight": 1,
          "quality": 3,
          "functions": [
            {
              "function": "minecraft:set_name",
              "name": { "text": "每日宝石", "color": "aqua", "italic": false }
            },
            {
              "function": "minecraft:enchant_randomly",
              "enchantments": [ "minecraft:unbreaking" ]
            }
          ]
        }
      ]
    }
  ]
}
```

函数发放：

```mcfunction
loot give @s loot myns:rewards/daily
```

### 8.11 调试技巧

| 目的 | 命令 |
|---|---|
| 直接看某表的产出 | `loot give @s loot myns:chests/supply` |
| 模拟挖方块 | `loot give @s mine ~ ~-1 ~ mainhand` |
| 模拟杀实体 | `loot give @s kill @e[type=minecraft:zombie,limit=1]` |
| 填进容器 | `loot replace block ~ ~ ~ container.0 loot myns:chests/supply 27` |
| 看方块实体的表 | `data get block ~ ~ ~ LootTable` |

常见坑：

- 表里 `type` 写成 `minecraft:block`，但用 `loot give @s loot ...` 调用时没有方块上下文 → 条件恒假/直接报错。用 `generic` 做“纯奖励表”。
- `set_nbt` 的 `tag` 必须是**字符串**；写成对象 `{"display":...}` 会解析失败。
- 权重全为 0 或 `entries` 为空 → 什么都不掉，且不报错。
- `/reload` 后战利品表**会**重载；但如果容器已经生成并缓存了 `LootTable`/`LootTableSeed`，内容不会重roll。

## 9. 进度 advancements

### 9.1 路径与根结构

路径：`data/<ns>/advancements/<path>.json`，ID `myns:path`。子目录进 ID，如 `myns:story/ruby`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `parent` | string | 否 | 父进度 ID；省略即为“根进度” |
| `display` | object | 否 | 显示信息；**省略则成为隐藏的技术性进度**（仍会运行、可被引用） |
| `criteria` | object | 是 | 条件名 → 触发器对象；全部满足才完成 |
| `requirements` | array | 否 | 条件分组（见 §9.4） |
| `rewards` | object | 否 | 完成奖励 |
| `sends_telemetry_event` | bool | 否 | **1.20.5+**，1.20.1 不要写 |

### 9.2 `display`

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `icon` | object | 是 | `{"item": "minecraft:stone"}`；**1.20.1 用 `item`，不是 1.20.5+ 的 `id`**；可加 `"nbt":"{...}"` |
| `title` | 文本组件 | 是 | 标题（可为字符串、对象或数组） |
| `description` | 文本组件 | 是 | 描述 |
| `frame` | string | 否 | `task`（默认）/`goal`/`challenge` |
| `background` | string | 否 | **仅根进度**使用；纹理路径如 `minecraft:textures/gui/advancements/backgrounds/stone.png` |
| `show_toast` | bool | 否 | 默认 true；完成时右上角弹窗 |
| `announce_to_chat` | bool | 否 | 默认 true；完成时全服公告 |
| `hidden` | bool | 否 | 默认 false；true 则未完成前在界面中隐藏 |

```json
{
  "display": {
    "icon": {
      "item": "minecraft:diamond",
      "nbt": "{Damage:0}"
    },
    "title": { "text": "红宝石!", "color": "light_purple" },
    "description": { "text": "获得第一颗红宝石", "color": "gray" },
    "frame": "goal",
    "show_toast": true,
    "announce_to_chat": true,
    "hidden": false
  }
}
```

### 9.3 `criteria` 与常用触发器

结构：

```json
{
  "criteria": {
    "任意名字": {
      "trigger": "minecraft:inventory_changed",
      "conditions": {
        "items": [
          { "items": [ "minecraft:diamond" ] }
        ]
      }
    }
  }
}
```

条件名**只是本地标识**，可以叫 `a`/`b`/`any_name`；`requirements` 里引用的就是这些名字。

1.20.1 常用触发器：

| 触发器 | 适用 | 常用 conditions |
|---|---|---|
| `minecraft:impossible` | 永假；只能由 `/advancement grant` 或函数授予 | 无 |
| `minecraft:tick` | 每 tick 检查 | 无 |
| `minecraft:inventory_changed` | 背包变化 | `items`（物品谓词数组）、`slots`（槽位范围） |
| `minecraft:player_killed_entity` | 玩家杀实体 | `entity`（实体谓词）、`killing_blow` |
| `minecraft:entity_killed_player` | 实体杀玩家 | `entity`、`killing_blow` |
| `minecraft:player_hurt_entity` | 玩家伤害实体 | `entity`、`damage` |
| `minecraft:entity_hurt_player` | 玩家受伤 | `damage` |
| `minecraft:consume_item` | 吃/喝 | `item`（物品谓词） |
| `minecraft:enchanted_item` | 附魔 | `item`、`levels` |
| `minecraft:filled_bucket` | 装满桶 | `item` |
| `minecraft:changed_dimension` | 换维度 | `from`、`to` |
| `minecraft:location` | 到达某处 | `player`（含 `location`） |
| `minecraft:slept_in_bed` | 睡觉 | `player` |
| `minecraft:villager_trade` | 与村民交易 | `item`、`villager` |
| `minecraft:bred_animals` | 繁殖 | `parent`、`partner`、`child` |
| `minecraft:used_ender_eye` | 用末影之眼 | `distance` |
| `minecraft:used_totem` | 用图腾 | `item` |
| `minecraft:effects_changed` | 状态效果变化 | `effects` |
| `minecraft:brewed_potion` | 酿造 | `potion` |
| `minecraft:constructed_beacon` | 搭建信标 | `effects` |
| `minecraft:summoned_entity` | 召唤实体 | `entity` |
| `minecraft:placed_block` | 放置方块 | `block`、`location`、`item` |
| `minecraft:nether_travel` | 从下界返回 | `distance` |
| `minecraft:recipe_unlocked` | 解锁配方 | `recipe` |
| `minecraft:item_durability_changed` | 耐久变化 | `item`、`durability`、`delta` |
| `minecraft:hero_of_the_village` | 村庄英雄 | `player` |
| `minecraft:cure_zombie_villager` | 治愈僵尸村民 | `zombie`、`villager` |

> **1.20.5+ 才有**：`kill_mob`、`any_block_placed`、`throw_item`、`recipe_crafted` 等；**1.21+ 才有**：`fall_after_explosion`、`using_item`。这些在 1.20.1 写了会加载失败。

**触发器 conditions 里的实体/物品谓词**与 §8.5 相同，但注意区别：

- 触发器里的 `item` 是**单个物品谓词对象**，如 `{"items": ["minecraft:diamond"]}`，不是数组。
- `inventory_changed.items` 是**物品谓词数组**，每个元素形如 `{"items": ["minecraft:diamond"], "count": {"min": 1}}`。

```json
{
  "conditions": {
    "items": [
      {
        "items": [ "minecraft:diamond" ],
        "count": { "min": 1 }
      }
    ]
  }
}
```

### 9.4 `requirements`

默认：所有 criterion 都完成 → 进度完成。

`requirements` 是“数组的数组”，**内层是 OR，外层是 AND**：

```json
{
  "requirements": [
    [ "a", "b" ],
    [ "c" ]
  ]
}
```

含义：`(a 或 b) 且 c`。

```json
{
  "requirements": [
    [ "get_ruby", "get_sapphire" ]
  ]
}
```

含义：两颗宝石拿到任意一颗即可。

- 漏写某个 criterion 不会报错，但该 criterion 就永远不参与判定；`requirements` 里引用不存在的名字会加载失败。
- 想让进度“只要一个条件”就完成，写成 `[[ "a", "b", "c" ]]`。

### 9.5 `rewards`

| 字段 | 类型 | 说明 |
|---|---|---|
| `recipes` | string[] | 解锁的配方 ID 数组 |
| `loot` | string / string[] | 发放的战利品表 ID（单个或数组） |
| `experience` | int | 发放的经验点数（不是等级） |
| `function` | string | 完成的瞬间执行的函数（1 个） |

```json
{
  "rewards": {
    "recipes": [ "myns:ruby_sword", "myns:ruby_pickaxe" ],
    "loot": [ "myns:rewards/ruby_charm" ],
    "experience": 50,
    "function": "myns:on_ruby_advancement"
  }
}
```

- `loot` 写成数组时会**逐个**生成并掉在玩家脚下（与 `loot give` 一致）。
- `function` 在进度完成、奖励发放的上下文里执行，执行者是玩家、位置是玩家位置。
- 1.20.1 的 `rewards` **没有** `function` 数组写法；多个函数请自己包一层 `function #myns:xxx` 的标签或一个总函数。
- 奖励只发一次；`/advancement revoke` 后再 `grant` 会重发。

### 9.6 完整示例：根进度 + 子进度

`data/myns/advancements/ruby/root.json`（根进度，带背景）：

```json
{
  "display": {
    "icon": { "item": "minecraft:amethyst_shard" },
    "title": { "text": "红宝石之路", "color": "light_purple" },
    "description": { "text": "开始收集红宝石", "color": "gray" },
    "background": "minecraft:textures/gui/advancements/backgrounds/stone.png",
    "frame": "task",
    "show_toast": false,
    "announce_to_chat": false,
    "hidden": false
  },
  "criteria": {
    "joined": {
      "trigger": "minecraft:tick"
    }
  },
  "requirements": [ [ "joined" ] ]
}
```

`data/myns/advancements/ruby/first_gem.json`：

```json
{
  "parent": "myns:ruby/root",
  "display": {
    "icon": { "item": "minecraft:diamond" },
    "title": { "text": "第一颗宝石", "color": "aqua" },
    "description": { "text": "在背包里获得一颗钻石", "color": "gray" },
    "frame": "goal",
    "show_toast": true,
    "announce_to_chat": true
  },
  "criteria": {
    "has_diamond": {
      "trigger": "minecraft:inventory_changed",
      "conditions": {
        "items": [
          {
            "items": [ "minecraft:diamond" ],
            "count": { "min": 1 }
          }
        ]
      }
    }
  },
  "requirements": [ [ "has_diamond" ] ],
  "rewards": {
    "experience": 20,
    "loot": [ "myns:rewards/daily" ],
    "function": "myns:on_first_gem"
  }
}
```

`data/myns/advancements/ruby/kill_boss.json`（击杀 + 维度组合条件）：

```json
{
  "parent": "myns:ruby/first_gem",
  "display": {
    "icon": { "item": "minecraft:netherite_sword" },
    "title": { "text": "守卫终结者", "color": "red", "bold": true },
    "description": { "text": "在下界击杀一只僵尸猪灵", "color": "gray" },
    "frame": "challenge"
  },
  "criteria": {
    "killed": {
      "trigger": "minecraft:player_killed_entity",
      "conditions": {
        "entity": {
          "type": "minecraft:zombified_piglin",
          "location": { "dimension": "minecraft:the_nether" }
        }
      }
    },
    "visited": {
      "trigger": "minecraft:changed_dimension",
      "conditions": { "to": "minecraft:the_nether" }
    }
  },
  "requirements": [ [ "killed" ], [ "visited" ] ],
  "rewards": { "experience": 100 }
}
```

> `requirements` 写成 `[["killed"],["visited"]]` 表示“两个都要”；写成 `[["killed","visited"]]` 则表示“任一即可”。这是 1.20.1 进度最容易被读错的一处。

### 9.7 调试

```mcfunction
advancement grant @s only myns:ruby/first_gem
advancement grant @s until myns:ruby/kill_boss
advancement grant @s from myns:ruby/root
advancement revoke @s only myns:ruby/first_gem
advancement revoke @s everything
```

- `/advancement grant ... only` 只授予该进度本身；`until` 授予该进度及其全部祖先；`from` 授予该进度及其全部后代。
- 测试 `impossible` 进度只能靠命令授予。
- 进度文件报错时通常整棵树无法加载，`/reload` 会报“Failed to load advancement”；先把新文件移出目录做二分定位。

## 10. 谓词 predicates 与物品修饰器 item_modifiers

### 10.1 两者都存在，目录都是复数

| 目录（1.20.1） | ID 示例 | 引用方式 |
|---|---|---|
| `data/<ns>/predicates/` | `myns:is_raining` | `execute if predicate myns:is_raining`、选择器 `predicate=myns:is_raining`、战利品条件 `{"condition":"minecraft:reference","name":"myns:is_raining"}` |
| `data/<ns>/item_modifiers/` | `myns:add_ruby` | `/item modify ... myns:add_ruby`、战利品函数 `{"function":"minecraft:reference","name":"myns:add_ruby"}` |

> 1.21 起目录改为单数 `predicate/`、`item_modifier/`。1.20.1 写单数目录会**静默不加载**。

### 10.2 谓词 JSON 结构

1.20.1 的谓词根字段是 **`condition`**，不是 1.21+ 的 `type`。

| `condition` | 字段 | 说明 |
|---|---|---|
| `minecraft:all_of` | `terms`（数组） | 全部通过 |
| `minecraft:any_of` | `terms` | 任一通过（1.20 由 `alternative` 改名） |
| `minecraft:inverted` | `term` | 取反 |
| `minecraft:random_chance` | `chance`（0–1） | 随机 |
| `minecraft:random_chance_with_looting` | `chance`、`looting_multiplier` | 带抢夺加成的随机 |
| `minecraft:entity_properties` | `entity`、`predicate` | 实体谓词（§8.5） |
| `minecraft:entity_scores` | `entity`、`scores` | 计分板判定 |
| `minecraft:block_state_property` | `block`、`properties` | 方块状态判定（上下文需有方块） |
| `minecraft:match_tool` | `predicate` | 工具判定（上下文需有工具） |
| `minecraft:location_check` | `offsetX`/`offsetY`/`offsetZ`、`predicate` | 位置谓词（生物群系/维度/光照/方块） |
| `minecraft:weather_check` | `raining`、`thundering` | 天气 |
| `minecraft:time_check` | `value`（0–24000 范围或数字）、`period` | 游戏内时间 |
| `minecraft:value_check` | `value`（数字提供器）、`range` | 数值区间 |
| `minecraft:reference` | `name` | 引用另一个谓词文件 |
| `minecraft:table_bonus` | `enchantment`、`chances` | 附魔等级概率表 |

> `minecraft:survives_explosion` 只在战利品上下文有意义；在 `/execute if predicate` 里用它通常恒真/无意义（**未实测**）。

### 10.3 谓词完整示例

`data/myns/predicates/is_raining.json`：

```json
{
  "condition": "minecraft:weather_check",
  "raining": true,
  "thundering": false
}
```

`data/myns/predicates/holding_ruby.json`：

```json
{
  "condition": "minecraft:entity_properties",
  "entity": "this",
  "predicate": {
    "equipment": {
      "mainhand": {
        "items": [ "minecraft:diamond" ],
        "count": { "min": 1 }
      }
    }
  }
}
```

```mcfunction
execute as @a if predicate myns:holding_ruby run say 你主手拿着钻石
execute as @a[predicate=myns:is_raining] run say 下雨了
```

`data/myns/predicates/nether_day.json`（组合：在下界 + 时间 0–12000）：

```json
{
  "condition": "minecraft:all_of",
  "terms": [
    {
      "condition": "minecraft:location_check",
      "predicate": {
        "dimension": "minecraft:the_nether"
      }
    },
    {
      "condition": "minecraft:time_check",
      "value": { "min": 0, "max": 12000 }
    }
  ]
}
```

`data/myns/predicates/rich_or_lucky.json`（任一）：

```json
{
  "condition": "minecraft:any_of",
  "terms": [
    {
      "condition": "minecraft:entity_scores",
      "entity": "this",
      "scores": { "myns.coins": { "min": 100 } }
    },
    {
      "condition": "minecraft:random_chance",
      "chance": 0.1
    }
  ]
}
```

> `entity` 字段的取值是**上下文角色名**：`this`（当前实体）、`killer`、`direct_killer`、`this_entity` 等；不是选择器。写 `@s` 会加载失败。

### 10.4 物品修饰器 JSON 结构

根可以是**单个函数对象**，也可以是**函数数组**：

```json
{
  "function": "minecraft:set_count",
  "count": 3
}
```

```json
[
  { "function": "minecraft:set_count", "count": 3 },
  { "function": "minecraft:set_name", "name": { "text": "补给", "italic": false } }
]
```

字段与战利品表里的 `functions` 完全一致（§8.6），包括 `set_count`、`set_nbt`、`set_name`、`enchant_randomly`、`enchant_with_levels`、`set_damage`、`set_lore`、`set_contents`、`exploration_map`、`copy_name` 等。

### 10.5 物品修饰器完整示例

`data/myns/item_modifiers/add_ruby.json`：

```json
[
  {
    "function": "minecraft:set_count",
    "count": 1,
    "add": true
  },
  {
    "function": "minecraft:set_name",
    "name": {
      "text": "红宝石护符",
      "color": "light_purple",
      "italic": false
    }
  },
  {
    "function": "minecraft:set_lore",
    "lore": [
      { "text": "右键使用", "color": "gray", "italic": true }
    ]
  }
]
```

```mcfunction
give @s minecraft:amethyst_shard
item modify entity @s weapon.mainhand myns:add_ruby
```

`data/myns/item_modifiers/enchant_max.json`：

```json
{
  "function": "minecraft:enchant_with_levels",
  "levels": 30,
  "treasure": true
}
```

```mcfunction
item modify entity @s weapon.mainhand myns:enchant_max
```

`data/myns/item_modifiers/damaged_sword.json`：

```json
[
  {
    "function": "minecraft:set_damage",
    "damage": 0.5
  },
  {
    "function": "minecraft:set_nbt",
    "tag": "{display:{Name:'{\"text\":\"旧剑\",\"color\":\"gray\"}'}}"
  }
]
```

### 10.6 常见错误

| 现象 | 根因 | 处理 |
|---|---|---|
| `execute if predicate` 报“未知谓词” | 文件放在 `predicate/`（单数）或命名空间错 | 改回 `predicates/` |
| 谓词写了 `"type": "minecraft:entity_properties"` | 1.20.1 根字段是 `condition` | 改成 `"condition"` |
| `item modify` 报“未知修饰器” | 文件放在 `item_modifier/` 或 JSON 根不是对象/数组 | 目录复数、根为函数对象或数组 |
| 谓词里 `entity` 写 `@s` | 该字段要角色名 `this`/`killer`/... | 改成 `this` |
| 物品修饰器 `set_nbt` 写对象 | `tag` 必须是 SNBT 字符串 | 加引号转义 |

## 11. 世界生成 worldgen

### 11.1 目录与依赖关系

```text
data/<ns>/
├── dimension_type/<name>.json      → 维度类型
├── dimension/<name>.json           → 维度（引用 dimension_type + generator）
└── worldgen/
    ├── noise_settings/<name>.json         → 噪声设置（地形形状）
    ├── density_function/<name>.json       → 密度函数（可被 noise_router 引用）
    ├── biome/<name>.json                  → 生物群系
    ├── configured_feature/<name>.json     → 已配置地物（“生成什么”）
    ├── placed_feature/<name>.json         → 已放置地物（“在哪、多少次”）
    ├── configured_carver/<name>.json      → 已配置雕刻器
    ├── template_pool/<name>.json          → 拼图池（结构片段）
    ├── processor_list/<name>.json         → 结构处理器
    ├── structure/<name>.json              → 结构
    └── structure_set/<name>.json          → 结构集（分布规则）
```

依赖链：

```text
dimension → dimension_type
dimension → noise_settings → density_function / noise
dimension → biome_source → biome → placed_feature → configured_feature
structure → template_pool → structure .nbt（别忘了这个文件）
structure_set → structure
```

⚠️ **`/reload` 不会重新加载 `dimension`、`dimension_type` 与大部分 `worldgen`**。改完必须退出世界重进或重启服务器；服务器还要重新生成对应区块。

### 11.2 `dimension_type`

`data/myns/dimension_type/ruby.json`：

```json
{
  "ultrawarm": false,
  "natural": true,
  "coordinate_scale": 1.0,
  "has_skylight": true,
  "has_ceiling": false,
  "ambient_light": 0.0,
  "fixed_time": 6000,
  "monster_spawn_light_level": {
    "type": "minecraft:uniform",
    "min_inclusive": 0,
    "max_inclusive": 7
  },
  "monster_spawn_block_light_limit": 0,
  "piglin_safe": false,
  "bed_works": true,
  "respawn_anchor_works": false,
  "has_raids": true,
  "logical_height": 256,
  "min_y": 0,
  "height": 256,
  "infiniburn": "#minecraft:infiniburn_overworld",
  "effects": "minecraft:overworld"
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `ultrawarm` | bool | 水会蒸发、熔岩流动更快（下界类维度） |
| `natural` | bool | 有床/重生点等自然行为；false 时床会爆炸 |
| `coordinate_scale` | double | 与主世界的坐标比例（下界 8.0） |
| `has_skylight` | bool | 是否有天空光照 |
| `has_ceiling` | bool | 是否有基岩天花板 |
| `ambient_light` | float | 环境光 0–1 |
| `fixed_time` | int | 可选；固定时间（0–24000），省略则走昼夜循环 |
| `monster_spawn_light_level` | 数字提供器 | **不是数字！** 常见错误写成 `7`，1.20.1 要 IntProvider |
| `monster_spawn_block_light_limit` | int | 0–15 |
| `piglin_safe` | bool | 猪灵不主动攻击 |
| `bed_works` | bool | 床能否使用 |
| `respawn_anchor_works` | bool | 重生锚能否使用 |
| `has_raids` | bool | 是否触发袭击 |
| `logical_height` | int | 逻辑高度（≤ `height`） |
| `min_y` | int | 最低 Y，必须是 16 的倍数，≥ -2032 |
| `height` | int | 总高度，必须是 16 的倍数，≤ 4064 |
| `infiniburn` | 标签字符串 | 带 `#`，如 `#minecraft:infiniburn_overworld` |
| `effects` | string | `minecraft:overworld` / `the_nether` / `the_end` |

要点：

- `min_y` + `height` 决定建筑上限：`max_y = min_y + height - 1`。
- `has_ceiling: true` 时下界顶部的基岩层才会生成。
- `effects` 决定天空/雾的颜色与音乐，不影响地形。

### 11.3 `dimension`

`data/myns/dimension/ruby.json`：

```json
{
  "type": "myns:ruby",
  "generator": {
    "type": "minecraft:noise",
    "biome_source": {
      "type": "minecraft:fixed",
      "biome": "myns:ruby_biome"
    },
    "settings": "myns:ruby_noise"
  }
}
```

| 字段 | 说明 |
|---|---|
| `type` | 指向 `dimension_type`，`myns:ruby` |
| `generator.type` | `minecraft:noise`（噪声地形）/`minecraft:flat`（超平坦）/`minecraft:debug`（调试） |
| `biome_source.type` | `minecraft:fixed`（单群系）/`minecraft:multi_noise`/`minecraft:the_end`/`minecraft:checkerboard` |
| `settings` | 指向 `worldgen/noise_settings` |

超平坦示例（更容易跑起来）：

```json
{
  "type": "myns:ruby",
  "generator": {
    "type": "minecraft:flat",
    "settings": {
      "biome": "myns:ruby_biome",
      "lakes": false,
      "features": false,
      "layers": [
        { "block": "minecraft:bedrock", "height": 1 },
        { "block": "minecraft:dirt", "height": 3 },
        { "block": "minecraft:grass_block", "height": 1 }
      ],
      "structure_overrides": []
    }
  }
}
```

- 超平坦的 `layers[].height` 是**整数层数**。
- `structure_overrides` 是结构集或结构标签列表。
- 自定义维度要在 `level.dat` 的维度列表中出现才能进入：原版只能靠模组/数据包把 `dimension` 注册进 `worldgen/world_preset` 或服务器 `level.dat`；**纯数据包无法让玩家在生存模式主动前往新维度**，通常要用 `/execute in myns:ruby run tp` 传送。

### 11.4 `biome`

`data/myns/worldgen/biome/ruby_biome.json`：

```json
{
  "temperature": 0.8,
  "downfall": 0.4,
  "has_precipitation": true,
  "effects": {
    "sky_color": 7842047,
    "fog_color": 12638463,
    "water_color": 4159204,
    "water_fog_color": 329011,
    "mood_sound": {
      "sound": "minecraft:ambient.cave",
      "tick_delay": 6000,
      "block_search_extent": 8,
      "offset": 2.0
    }
  },
  "spawners": {
    "monster": [
      { "type": "minecraft:zombie", "weight": 95, "minCount": 1, "maxCount": 4 }
    ],
    "creature": [
      { "type": "minecraft:sheep", "weight": 12, "minCount": 2, "maxCount": 4 }
    ]
  },
  "spawn_costs": {},
  "carvers": {
    "air": [ "minecraft:cave", "minecraft:canyon" ]
  },
  "features": [
    [], [], [], [], [], [], [], [], [], [], []
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `temperature` | float | -2.0 ~ 2.0，影响降水形态与冰冻 |
| `downfall` | float | 0.0 ~ 1.0 |
| `has_precipitation` | bool | **1.19.4+ 的字段名**；1.19 之前是字符串 `precipitation` |
| `effects` | object | `sky_color`、`fog_color`、`water_color`、`water_fog_color`、可选 `mood_sound`、`music`、`additions_sound`、`particle` |
| `spawners` | object | 按生物类别分组：`monster`、`creature`、`ambient`、`axolotls`、`underground_water_creature`、`water_creature`、`water_ambient`、`misc` |
| `spawn_costs` | object | 生物 ID → `{energy_budget, charge}`，控制刷怪密度 |
| `carvers` | object | `air`/`liquid` → 已配置雕刻器数组 |
| `features` | array[11] | **必须是 11 个数组**，对应 11 个生成阶段 |

`features` 的 11 个位置（顺序不能错）：

| 索引 | 阶段 | 典型内容 |
|---|---|---|
| 0 | `raw_generation` | 初始地形（如 `lake` 之外的裸生成） |
| 1 | `lakes` | 湖、熔岩湖 |
| 2 | `local_modifications` | 局部修改（如 `ore` 前的替换） |
| 3 | `underground_structures` | 地下结构 |
| 4 | `surface_structures` | 地表结构 |
| 5 | `strongholds` | 要塞 |
| 6 | `underground_ores` | 矿石 |
| 7 | `underground_decoration` | 地下装饰（紫水晶洞等） |
| 8 | `fluid_springs` | 泉眼 |
| 9 | `vegetal_decoration` | 植被（树、花、草） |
| 10 | `top_layer_modification` | 表层修改（雪、沙） |

> 少写或多写数组 → 生物群系加载失败；元素写 `"myns:ruby_cluster"` 指的是 **placed_feature**，不是 configured_feature。

### 11.5 `configured_feature` 与 `placed_feature`

**已配置地物**决定“生成什么”，**已放置地物**决定“在哪、多少次、什么条件”。

`data/myns/worldgen/configured_feature/ruby_cluster.json`（简单方块）：

```json
{
  "type": "minecraft:simple_block",
  "config": {
    "to_place": {
      "type": "minecraft:simple_state_provider",
      "state": { "Name": "myns:ruby_block" }
    }
  }
}
```

> 上面用了模组方块 `myns:ruby_block` 演示；纯原版请换成 `minecraft:emerald_block` 之类的已存在方块。

`data/myns/worldgen/placed_feature/ruby_cluster_placed.json`：

```json
{
  "feature": "myns:ruby_cluster",
  "placement": [
    { "type": "minecraft:count", "count": 4 },
    { "type": "minecraft:in_square" },
    {
      "type": "minecraft:height_range",
      "height": {
        "type": "minecraft:uniform",
        "min_inclusive": { "absolute": 0 },
        "max_inclusive": { "absolute": 120 }
      }
    },
    { "type": "minecraft:biome" }
  ]
}
```

常用放置修饰器（1.20.1）：

| `type` | 关键字段 | 说明 |
|---|---|---|
| `minecraft:count` | `count`（int 或 IntProvider） | 每区块尝试次数 |
| `minecraft:count_on_every_layer` | `count` | 每层尝试 |
| `minecraft:in_square` | 无 | 在区块内随机 XZ |
| `minecraft:height_range` | `height`（HeightProvider） | Y 范围 |
| `minecraft:heightmap` | `heightmap`（`WORLD_SURFACE_WG` 等） | 贴地表 |
| `minecraft:biome` | 无 | 只在目标群系生成 |
| `minecraft:block_predicate_filter` | `predicate` | 方块条件过滤 |
| `minecraft:random_offset` | `xz_spread`、`y_spread` | 随机偏移 |
| `minecraft:rarity_filter` | `chance` | 1/chance 概率 |
| `minecraft:surface_relative_threshold_filter` | `heightmap`、`min_inclusive`、`max_inclusive` | 相对地表高度过滤 |
| `minecraft:noise_based_count` | `noise_level`、`noise_factor`、`noise_offset`、`noise_to_count_ratio` | 噪声控制密度 |

`count` 在 1.20.1 的写法：

```json
{ "type": "minecraft:count", "count": 10 }
```

```json
{ "type": "minecraft:count", "count": { "type": "minecraft:uniform", "min_inclusive": 1, "max_inclusive": 4 } }
```

`height_range` 的 HeightProvider：

```json
{ "absolute": 64 }
```

```json
{
  "type": "minecraft:uniform",
  "min_inclusive": { "absolute": -64 },
  "max_inclusive": { "absolute": 320 }
}
```

```json
{
  "type": "minecraft:trapezoid",
  "min_inclusive": { "absolute": -64 },
  "max_inclusive": { "absolute": 320 },
  "plateau": 0
}
```

### 11.6 `structure`（拼图结构）

`data/myns/worldgen/structure/ruby_house.json`：

```json
{
  "type": "minecraft:jigsaw",
  "biomes": "#myns:has_structure/ruby_house",
  "step": "surface_structures",
  "spawn_overrides": {},
  "terrain_adaptation": "beard_thin",
  "start_pool": "myns:ruby_house/start_pool",
  "size": 1,
  "start_height": { "absolute": 0 },
  "project_start_to_heightmap": "WORLD_SURFACE_WG",
  "max_distance_from_center": 80,
  "use_expansion_hack": false
}
```

| 字段 | 说明 |
|---|---|
| `biomes` | 允许生成的群系标签，**必须带 `#`** |
| `step` | 生成阶段：`surface_structures`/`underground_structures` 等 |
| `spawn_overrides` | 结构内刷怪覆盖，`{}` 表示不覆盖 |
| `terrain_adaptation` | `none`/`beard_thin`/`beard_box`/`encapsulate` |
| `start_pool` | 起始拼图池 ID |
| `size` | 拼图递归深度（层数） |
| `start_height` | HeightProvider |
| `project_start_to_heightmap` | 可选；贴地表时用 `WORLD_SURFACE_WG` |
| `max_distance_from_center` | 片段离中心的最大水平距离（1–128） |
| `use_expansion_hack` | 是否用扩展 hack（村庄类结构用 true） |

配套群系标签 `data/myns/tags/worldgen/biome/has_structure/ruby_house.json`：

```json
{
  "values": [
    "myns:ruby_biome",
    "minecraft:plains"
  ]
}
```

**没有 `.nbt` 结构文件，结构不会生成**：把建筑用结构方块保存为 `data/myns/structures/ruby_house/house.nbt`。

### 11.7 `template_pool`

`data/myns/worldgen/template_pool/ruby_house/start_pool.json`：

```json
{
  "fallback": "minecraft:empty",
  "elements": [
    {
      "weight": 1,
      "element": {
        "element_type": "minecraft:single_pool_element",
        "location": "myns:ruby_house/house",
        "processors": "minecraft:empty",
        "projection": "rigid"
      }
    }
  ]
}
```

| 字段 | 说明 |
|---|---|
| `fallback` | 拼接失败时回退的池；`minecraft:empty` 表示到此为止 |
| `elements[].weight` | 权重 |
| `element.element_type` | `single_pool_element` / `list_pool_element` / `feature_pool_element` / `empty_pool_element` |
| `location` | 结构 `.nbt` 的 ID（不带 `.nbt`） |
| `processors` | 处理器列表 ID，`minecraft:empty` 表示不处理 |
| `projection` | `rigid`（不随地形变形）/`terrain_matching`（贴合地形） |

### 11.8 `processor_list`

空处理器（最安全的最小写法）：

```json
{
  "processors": []
}
```

规则处理器示例（把石头换成苔石）：

```json
{
  "processors": [
    {
      "processor_type": "minecraft:rule",
      "rules": [
        {
          "location_predicate": {
            "predicate_type": "minecraft:always_true"
          },
          "input_predicate": {
            "predicate_type": "minecraft:block_match",
            "block": "minecraft:stone"
          },
          "output_state": {
            "Name": "minecraft:mossy_stone_bricks"
          }
        }
      ]
    }
  ]
}
```

| 处理器 `processor_type` | 关键字段 | 说明 |
|---|---|---|
| `minecraft:rule` | `rules`（`input_predicate`/`location_predicate`/`output_state`/`output_nbt`） | 按规则替换 |
| `minecraft:block_rot` | `integrity`、`rottable_blocks` | 按完整度随机替换为空气 |
| `minecraft:block_age` | `mossiness` | 变苔石 |
| `minecraft:gravity` | `heightmap`、`offset` | 落地 |
| `minecraft:block_ignored` | 无 | 忽略某方块 |
| `minecraft:fossil` | `fossils`、`max_empty_corners` | 化石 |
| `minecraft:zombie` | 无 | 僵尸化村庄 |

**未在 1.20.1 实测**：`rule` 处理器的 `output_nbt` 字段行为（不同版本对 SNBT 解析要求不同）。

### 11.9 `structure_set`

`data/myns/worldgen/structure_set/ruby_houses.json`：

```json
{
  "structures": [
    { "structure": "myns:ruby_house", "weight": 1 }
  ],
  "placement": {
    "type": "minecraft:random_spread",
    "spacing": 32,
    "separation": 8,
    "salt": 12345,
    "spread_type": "linear"
  }
}
```

| `placement.type` | 关键字段 | 说明 |
|---|---|---|
| `minecraft:random_spread` | `spacing`、`separation`、`salt`、`spread_type`、`frequency` | 网格随机分布 |
| `minecraft:concentric_rings` | `distance`、`spread`、`count`、`preferred_biomes` | 同心环（要塞） |

- `spacing` 必须大于 `separation`。
- `salt` 不同 → 分布不同；同 salt 的两个结构集会重叠。
- `spread_type`：`linear` / `triangular`。

### 11.10 `noise_settings` 与 `density_function`

`noise_settings` 字段（1.20.1）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `sea_level` | int | 海平面 Y |
| `disable_mob_generation` | bool | 关闭自然刷怪 |
| `aquifers_enabled` | bool | 启用含水层 |
| `ore_veins_enabled` | bool | 启用大型矿脉 |
| `legacy_random_source` | bool | 旧版随机源（1.18 前地图用 true） |
| `default_block` | 方块状态 | 默认填充方块 |
| `default_fluid` | 方块状态 | 默认流体 |
| `noise` | object | 噪声采样参数：`{min_y, height, size_horizontal, size_vertical}`（1.18+ 格式） |
| `noise_router` | object | 各密度函数槽位，**必填且字段多** |
| `surface_rule` | object | 表层规则（草/沙/石） |

`noise_router` 的槽位（1.20.1）：`barrier`、`fluid_level_floodedness`、`fluid_level_spread`、`lava`、`temperature`、`vegetation`、`continents`、`erosion`、`depth`、`ridges`、`initial_density_without_jaggedness`、`final_density`。

- 自定义噪声地形最稳的做法：**复制原版 `data/minecraft/worldgen/noise_settings/overworld.json`**，只改 `default_block`/`default_fluid`/`sea_level`，不要手写 `noise_router`。
- 完整手写 `noise_router` 需要十几个密度函数，字段写错就整维度加载失败；本文不提供“保证可加载”的完整噪声示例（**未在 1.20.1 实测**）。

`density_function` 最小示例：

```json
{
  "type": "minecraft:constant",
  "value": -1.0
}
```

```json
{
  "type": "minecraft:y_clamped_gradient",
  "from_y": -64,
  "to_y": 320,
  "from_value": 1.0,
  "to_value": -1.0
}
```

常用密度函数类型：

| `type` | 关键字段 | 说明 |
|---|---|---|
| `minecraft:constant` | `value` | 常量 |
| `minecraft:y_clamped_gradient` | `from_y`、`to_y`、`from_value`、`to_value` | 沿 Y 线性渐变 |
| `minecraft:noise` | `noise`（噪声 ID）、`xz_scale`、`y_scale` | 采样噪声 |
| `minecraft:shifted_noise` | `noise`、`xz_scale`、`y_scale`、`shift_x`、`shift_y`、`shift_z` | 偏移噪声 |
| `minecraft:add` / `mul` / `min` / `max` | `left`、`right`（或 `argument1`/`argument2`） | 二元运算（**字段名未在 1.20.1 逐一验证**） |
| `minecraft:interpolated` | `argument` | 插值 |
| `minecraft:flat_cache` / `cache_2d` / `cache_once` | `argument` | 缓存 |
| `minecraft:blend_density` | `argument` | 新旧地形混合 |
| `minecraft:spline` | `spline` | 样条 |

> 二元运算的 JSON 字段在不同版本里是 `argument1`/`argument2` 还是 `left`/`right` **容易记混**；写之前用 `/reload` 试或对照原版 `worldgen/density_function/*.json`。

### 11.11 世界生成调试

```mcfunction
execute in myns:ruby run tp @s 0 100 0
place structure minecraft:village_plains ~ ~ ~
place jigsaw myns:ruby_house/start_pool minecraft:empty 7 ~ ~ ~
locate structure myns:ruby_house
```

| 现象 | 根因 | 处理 |
|---|---|---|
| 进入维度后掉进虚空 | `noise_router.final_density` 恒为负 | 换用原版 noise_settings 骨架 |
| 结构不生成 | 缺 `.nbt`、`template_pool` ID 错、群系标签不匹配 | 用 `place structure` 手动验证 |
| 生物群系加载失败 | `features` 不是 11 个数组 | 补齐 11 个 `[]` |
| 维度不出现 | 纯数据包无法新增可达维度 | 用 `/execute in <id> run tp`，或做模组 |

## 12. 伤害类型与盔甲纹饰

三个注册表在 1.20.1 都是**单数目录**：`damage_type/`、`trim_material/`、`trim_pattern/`。

### 12.1 `damage_type`

路径：`data/<ns>/damage_type/<name>.json`，ID `myns:ruby_beam`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `message_id` | string | 是 | 死亡消息键的后缀：实际键为 `death.attack.<message_id>`；也用于 `death.attack.<message_id>.player` |
| `exhaustion` | float | 是 | 每次受伤增加的饥饿消耗，通常 `0.1` |
| `scaling` | string | 是 | `never` / `always` / `when_caused_by_player` |
| `effects` | string | 否 | `hurt`（默认）/`thorns`/`drowning`/`burning`/`poking` |
| `death_message_type` | string | 否 | `default`/`fall_variants`/`intentional_game_design` |

```json
{
  "message_id": "ruby_beam",
  "exhaustion": 0.1,
  "scaling": "when_caused_by_player",
  "effects": "hurt",
  "death_message_type": "default"
}
```

使用：

```mcfunction
damage @s 6 myns:ruby_beam
damage @e[type=minecraft:zombie,limit=1] 8 myns:ruby_beam by @s
```

配套语言键（资源包 `assets/myns/lang/zh_cn.json`）：

```json
{
  "death.attack.ruby_beam": "%1$s 被红宝石光束蒸发了",
  "death.attack.ruby_beam.player": "%1$s 被 %2$s 用红宝石光束蒸发了"
}
```

> 缺语言键不会崩，只会显示原始键名。`message_id` 允许带点（如 `myns.ruby_beam`），但习惯用下划线。

伤害类型标签（`data/myns/tags/damage_type/bypasses_armor.json`）：

```json
{
  "values": [
    "myns:ruby_beam",
    "minecraft:magic"
  ]
}
```

原版关键标签：`#minecraft:is_projectile`、`#minecraft:bypasses_armor`、`#minecraft:is_fire`、`#minecraft:is_explosion`、`#minecraft:no_knockback`。给自定义伤害类型打标签，才能被对应免疫/减伤逻辑识别。

### 12.2 `trim_material`

路径：`data/<ns>/trim_material/<name>.json`，ID `myns:ruby`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `asset_name` | string | 是 | 调色板名；纹理路径为 `assets/<ns>/textures/trims/color_palettes/<asset_name>.png` 与 `<asset_name>_dark.png` |
| `description` | 文本组件 | 是 | 鼠标悬停显示的材料名 |
| `ingredient` | string | 是 | 对应的材料物品 ID；`smithing_trim` 的 `addition` 匹配它 |

```json
{
  "asset_name": "ruby",
  "description": { "translate": "trim_material.myns.ruby" },
  "ingredient": "myns:ruby"
}
```

语言键：

```json
{
  "trim_material.myns.ruby": "红宝石材料"
}
```

要点：

- `asset_name` 决定颜色（由纹理调色板决定），与物品 ID 无关；原版如 `asset_name: "quartz"`。
- 材料物品可以不进 `#minecraft:trim_materials`；但 `smithing_trim` 配方里的 `addition` 要能匹配它。
- 1.20.1 **没有** `override_armor_materials`（1.21.5+），别写。

### 12.3 `trim_pattern`

路径：`data/<ns>/trim_pattern/<name>.json`，ID `myns:ruby`。

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `asset_id` | string | 是 | 图案纹理路径：`assets/<ns>/textures/trims/models/armor/<path>.png` 与 `_leggings` 版本 |
| `description` | 文本组件 | 是 | 鼠标悬停显示 |
| `template_item` | string | 是 | 与该图案绑定的纹饰模板物品 ID；`smithing_trim` 用这个物品时应用此图案 |

```json
{
  "asset_id": "myns:ruby",
  "description": { "translate": "trim_pattern.myns.ruby" },
  "template_item": "myns:ruby_armor_trim_smithing_template"
}
```

语言键：

```json
{
  "trim_pattern.myns.ruby": "红宝石纹饰"
}
```

要点：

- `asset_id` 里的命名空间同时决定纹理所在命名空间：`myns:ruby` → `assets/myns/textures/trims/models/armor/ruby.png`。
- 盔甲层纹理与护腿纹理是两张图：`ruby.png`、`ruby_leggings.png`。
- `template_item` 必须是一个**已存在**的物品；纯数据包只能复用原版模板物品，自定义模板物品需要模组或资源包层面新增物品。
- 1.20.1 **没有** `decals` 字段（后续版本加入），写了会被忽略或报错（**未实测**）。

### 12.4 三者如何串起来

```text
smithing_trim 配方
├── template  →  trim_pattern.template_item  →  trim_pattern（图案 + 纹理）
├── base      →  #minecraft:trimmable_armor
└── addition  →  trim_material.ingredient    →  trim_material（颜色调色板）
```

完整链路示例（自定义红宝石纹饰）：

1. `data/myns/trim_pattern/ruby.json`（上例）
2. `data/myns/trim_material/ruby.json`（上例）
3. `data/myns/recipes/ruby_armor_trim.json`：

```json
{
  "type": "minecraft:smithing_trim",
  "template": { "item": "myns:ruby_armor_trim_smithing_template" },
  "base": { "tag": "minecraft:trimmable_armor" },
  "addition": { "item": "myns:ruby" }
}
```

4. 资源包补纹理：`assets/myns/textures/trims/models/armor/ruby.png`、`ruby_leggings.png`、`assets/myns/textures/trims/color_palettes/ruby.png`、`ruby_dark.png`。

> 第 3 步的 `myns:ruby_armor_trim_smithing_template` 若不存在，配方加载失败。纯数据包只能**复用原版模板物品**，否则需要模组新增物品。

### 12.5 常见错误

| 现象 | 根因 | 处理 |
|---|---|---|
| `damage` 报“未知伤害类型” | 文件在 `damage_types/`（多了 s） | 目录是单数 `damage_type/` |
| 死亡消息显示 `death.attack.ruby_beam` | 缺语言键 | 资源包加 `zh_cn.json` |
| 纹饰台无反应 | 模板物品与 `trim_pattern.template_item` 不一致 | 对齐两个 ID |
| 纹饰是黑白/无颜色 | 缺 `color_palettes` 纹理 | 补 `assets/<ns>/textures/trims/color_palettes/<asset_name>.png` |

## 13. 调试与坑表

### 13.1 快速自检清单

1. `pack.mcmeta` 在**包根目录**，`pack_format = 15`。
2. `data/<ns>/functions/`、`recipes/`、`loot_tables/` … 全是**复数**。
3. `.mcfunction` 里没有前导 `/`，没有行尾注释，没有续行。
4. 每个 JSON 都在编辑器里过一遍校验（无尾逗号、无注释、UTF-8 无 BOM）。
5. `/reload` 后看日志第一行错误；修完再 reload，不要叠加多个改动。
6. 用 `/datapack list` 确认包真的被识别，用 `/function` 或 `/loot` 单点验证。

### 13.2 坑表

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 数据包列表里标红/提示“不兼容” | `pack_format` 不是 15 | 改 `pack_format` 为 15；不要写 `supported_formats` |
| 2 | 包完全不出现，`/datapack list` 也看不到 | `pack.mcmeta` 不在根目录；zip 多套了一层目录 | 保证 zip 根就是 `pack.mcmeta` + `data/` |
| 3 | 包能加载，但配方/函数全不生效 | 目录写成单数（`function/`、`recipe/`、`loot_table/`） | 1.20.1 全部改回复数；`tags/functions/` 也是复数 |
| 4 | 文件名大写，命令找不到 | 注册表 ID 只接受小写 | 文件名、目录名、引用全改小写 |
| 5 | `/reload` 报“Failed to load function ... at line N” | 该行语法错；`.mcfunction` 不支持续行 | 把长命令拆短；检查 `execute` 是否跨行 |
| 6 | 函数某行永远不执行 | 上一行 `execute` 的条件不成立，或函数在某行 `return` 了 | 1.20.1 只有 `return <整数>`；检查条件链 |
| 7 | `execute as @e[...] run ...` 里的 `~ ~ ~` 跑到世界原点 | `as` 不改位置，位置仍是执行者的 | 补 `at @s`（顺序 `as ... at @s`） |
| 8 | 传送后再 `setblock ~ ~-1 ~` 位置没变 | 上下文不跨行，第二行用的是函数入口位置 | 第二行加 `execute at @s` |
| 9 | `execute if score ... run` 的判定“总是失败” | 分数在前一行已被扣掉/覆盖 | 先判定后修改，或用 `#tmp` 暂存 |
| 10 | 递归函数把服务器卡死 | 无终止条件的 `function` 自调用，受 `maxCommandChainLength` 限制但会耗尽 tick | 加计数器/条件；或改用 `schedule` 每 tick 一次 |
| 11 | `/reload` 后战利品表还是旧的 | 容器已生成并缓存 `LootTable`/`LootTableSeed`；区块未重载 | 换新容器测试；旧容器需清空重填或重生成区块 |
| 12 | 标签“加了但没生效” | 写了 `replace: true` 把原版内容清空；或目录是单数 | 检查 `replace`；确认 `tags/items/` 等复数目录 |
| 13 | 标签加载失败，整个包不生效 | 子标签循环引用；或 `required: true` 的 ID 不存在 | 用 `{ "id": "...", "required": false }`；检查循环 |
| 14 | `data modify` 明明写了却没变化 | 路径的父节点不存在；`set` 不会自动创建中间层 | 先 `data get` 父节点；必要时 `data merge` 建结构 |
| 15 | `data get entity @s Inventory[]` 报“多个标签” | `data get` 最终只能选一个标签 | 改用 `data get ... Inventory[0]`，或 `data get ... Inventory[{id:"..."}]` |
| 16 | `data modify entity @s ...` 总是失败 | 玩家 NBT 只读 | 用 `effect`/`xp`/`give`/`attribute` 等命令 |
| 17 | SNBT 解析失败 | 字符串里嵌套引号没转义；`set_nbt.tag` 写成对象 | 用单引号包外层、双引号包内层，或反之；`tag` 必须是字符串 |
| 18 | JSON 加载失败但日志只说文件名 | 尾逗号、注释、BOM、中文全角引号 | 用严格 JSON 校验器；存 UTF-8 无 BOM |
| 19 | `UUID` 相关命令报“Invalid UUID” | `/attribute` 的 UUID 参数要标准 UUID 字符串（`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`） | 用 `00000000-0000-0000-0000-000000000001` 这类合法值；同一实体避免重复 UUID |
| 20 | `summon` 的 NBT 不生效 | 1.20.1 用 `物品ID{...}`，不是 `物品ID[...]` 组件语法 | 删掉组件写法，改回 NBT |
| 21 | `give` 的 NBT 丢了 | 命令长度/引号问题；或把 `Count` 写成 `count` | NBT 键区分大小写：`Count`、`Damage`、`display` |
| 22 | 随机结果每次都一样 | `/reload` 后重新播种；测试时固定了 `random_sequence` | 换 `random_sequence` 或多次测试；不要用固定 seed 判断概率 |
| 23 | 服务器时间/天气相关逻辑不触发 | 用 `time_check` 但维度没有昼夜循环（`fixed_time`） | 检查 `dimension_type.fixed_time`；改用计分板计时 |
| 24 | 结构生成了但全是空气 | `.nbt` 保存时选错了角点/结构方块模式 | 用结构方块“保存”模式重新导出，确认 `size` |
| 25 | 自定义维度进不去 | 纯数据包不能新增可从主世界到达的维度 | `/execute in myns:ruby run tp @s 0 100 0`；或做模组 |
| 26 | 进度完成了但奖励没发 | `rewards.function` 指向的函数不存在；或 `loot` 表 ID 错 | `/function` 手动跑一遍；`/loot give` 验证表 |
| 27 | 进度 `requirements` 行为反了 | 内层 OR、外层 AND 记反 | `[["a"],["b"]]` = 都要；`[["a","b"]]` = 任一 |
| 28 | `attribute` 语法报错 | 1.20.1 是 `modifier add <uuid> <name> <value> <op>`，不是 1.21 的 `<id> <value> <op>` | 按 §6.8 的 1.20.1 语法写；operation 用 tab 补全确认 |
| 29 | 1.20.1 里写 `$` 宏行导致整函数失效 | 宏是 1.20.2+ | 删掉所有 `$` 行与 `with` 参数 |
| 30 | 1.20.1 里写 `item[...]` / `set_components` 无效 | 组件是 1.20.5+ | 改回 NBT/`set_nbt` |
| 31 | `@n` 选择器报错 | 1.20.1 没有 `@n` | 用 `@e[limit=1,sort=nearest]` |
| 32 | `/item replace ... equipment.chest` 报未知槽位 | `equipment.*` 是 1.21.5+ | 用 `armor.chest` |
| 33 | `/execute if function` / `if items` 报错 | 1.20.3+/1.20.5+ | 改 `function` + 计分板判定，或 `if data entity` |
| 34 | `/return run` 报错 | 1.20.2+ | 1.20.1 用 `return <整数>` |
| 35 | `/random` 报错 | 1.20.2+ | 用 `execute store result score ... run data get ...` 之类替代，或直接 `loot` 随机 |

### 13.3 `execute` 上下文详解（最高频错误）

```mcfunction
# 错误：以为 as 会把位置也带过去
execute as @e[type=minecraft:zombie] run particle minecraft:flame ~ ~1 ~ 0 0 0 0 1
# 实际：粒子出现在“函数执行者”的位置，而不是每只僵尸的位置

# 正确
execute as @e[type=minecraft:zombie] at @s run particle minecraft:flame ~ ~1 ~ 0 0 0 0 1
```

| 子命令 | 改执行者 | 改位置 | 改朝向 | 改维度 |
|---|---|---|---|---|
| `as` | ✅ | ❌ | ❌ | ❌ |
| `at` | ❌ | ✅ | ✅ | ✅ |
| `positioned` | ❌ | ✅ | ❌ | ❌ |
| `rotated` | ❌ | ❌ | ✅ | ❌ |
| `in` | ❌ | ❌ | ❌ | ✅ |
| `anchored` | ❌ | 改 `^` 原点 | ❌ | ❌ |
| `align` | ❌ | ✅（取整） | ❌ | ❌ |
| `facing` | ❌ | ❌ | ✅ | ❌ |

`at` 会同时设置位置、朝向和维度；`positioned` 只设位置；`rotated` 只设朝向。写 `at @s` 后 `^ ^ ^` 的朝向来自实体视线，写 `positioned as @s` 后朝向仍是原执行者的。

### 13.4 `data modify` 路径实战

```mcfunction
# 给所有僵尸加一个自定义标签
execute as @e[type=minecraft:zombie] run data modify entity @s Tags append value "myns_zombie"

# 把玩家主手物品复制到 storage
data modify storage myns:tmp item set from entity @s SelectedItem
data get storage myns:tmp item

# 从 storage 取字段并写进计分板
execute store result score @s myns.tmp run data get storage myns:tmp item.Count

# 删除列表第 0 项
data remove storage myns:tmp list[0]

# 修改嵌套字段（Parent.Child）
data modify storage myns:tmp data.count set value 5
```

| 需求 | 正确写法 | 错误写法 |
|---|---|---|
| 追加到列表末尾 | `... append value X` | `... set value X`（会覆盖整个列表） |
| 插入到最前 | `... prepend value X` | `... insert -1 value X`（`-1` 不是“末尾”语义，容易越界） |
| 插入到指定位置 | `... insert 0 value X` | `... insert 0 from ...`（`from` 是另一个语法分支，注意顺序） |
| 复制整个复合标签 | `data modify ... set from <source> <path>` | `data modify ... set value {...}`（手写容易漏字段） |
| 只改一个子键 | `data modify ... Settings.big set value 1b` | `data modify ... Settings set value {big:1b}`（会清掉其他键） |

### 13.5 SNBT 引号与转义

```mcfunction
# 外层单引号，内层双引号（最常用）
summon minecraft:zombie ~ ~ ~ {CustomName:'{"text":"Bob","color":"red"}'}

# 外层双引号，内层单引号
summon minecraft:zombie ~ ~ ~ {"CustomName":"{'text':'Bob','color':'red'}"}

# 字符串里要出现同种引号 → 用反斜杠转义
tellraw @a {"text":"他说：\"你好\""}
```

| 规则 | 说明 |
|---|---|
| NBT 字符串可用单/双引号 | 选一种，内部另一种不用转义 |
| JSON 文本组件建议用双引号 | 外层 NBT 用单引号包裹最省事 |
| 反斜杠要成对 | `"\\"` 表示一个反斜杠 |
| 中文可用 | 文件存 UTF-8 无 BOM 即可 |
| `1b`/`1s`/`1L`/`1.0f`/`1.0d` | NBT 类型后缀，别漏；`Count:1` 在 1.20.1 会被当成 int，物品数量要求 byte，可能不生效 |

### 13.6 UUID 与随机

- `/attribute ... modifier add <uuid> ...` 的 UUID 必须是合法 UUID；同一实体上重复 UUID 的行为**未验证**，建议每个 modifier 用不同值。
- 战利品表的随机由世界 seed + 表位置决定；`random_sequence` 让多个表共享序列。测试“概率”时不要只看一次结果。
- `schedule` 队列在 `/reload` 后清空；依赖循环计时的系统必须在 `#minecraft:load` 里重新排。
- `time_check` 用的是**维度内**时间；`fixed_time` 维度里它恒定，相关逻辑会“永远成立/永远不成立”。

### 13.7 性能红线

| 做法 | 代价 | 替代 |
|---|---|---|
| `#minecraft:tick` 里 `@e` 全量扫描 | 每 tick O(实体数) | 用 `execute if entity @e[tag=...]` 先过滤，或用 `schedule` 降频 |
| 每 tick `data get entity @a[...]` | NBT 序列化开销大 | 用计分板缓存 |
| 每 tick `function` 递归 | 命令链爆炸 | 计数到 N 再执行 |
| `fill` 大区域 | 单次 32768 格上限 + 卡顿 | 分帧填充，或用结构 `place template` |
| 大量 `tellraw @a` | 网络包风暴 | 合并成一条多段文本 |

## 14. 来源与核对

### 14.1 实际抓取的官方页面（2026-11-05）

以下页面均以 `?action=raw` 形式抓取正文（wiki 的 `Data pack directory` / `Data pack format` 等模板在 raw 文本里不会展开，因此涉及“某目录在哪个版本改名”的结论以页面正文的“历史”段落与模板参数为准）。

| # | URL | 用途 |
|---|---|---|
| 1 | `https://minecraft.wiki/w/Data_pack?action=raw` | 数据包定义、安装路径、`/datapack` 与 `/reload` 行为、目录结构模板 |
| 2 | `https://minecraft.wiki/w/Pack_format?action=raw` | `pack_format` 机制、1.20.2+ 的 `min_format`/`max_format`、`supported_formats` 的存在性 |
| 3 | `https://minecraft.wiki/w/Loot_table?action=raw` | 战利品表根结构、`type`、pools/entries/functions/conditions 字段与历史改名 |
| 4 | `https://minecraft.wiki/w/Predicate?action=raw` | 谓词文件结构、`condition`→`type` 的改名版本、可用条件类型 |
| 5 | `https://minecraft.wiki/w/Item_modifier?action=raw` | 物品修饰器目录、根结构（对象/数组）、函数列表 |
| 6 | `https://minecraft.wiki/w/Recipe_(Java_Edition)?action=raw` | 配方 JSON 结构、原料/结果写法、1.21.2+ 的字符串原料格式 |
| 7 | `https://minecraft.wiki/w/Tag_(Java_Edition)?action=raw` | 标签目录、`replace`/`values`/`required`（1.16.2 起）、按注册表命名的目录规则 |
| 8 | `https://minecraft.wiki/w/Advancement_definition?action=raw` | 进度根结构、`display.icon`（1.20.5 由 `item` 改 `id`）、criteria/rewards |

中文 wiki 对应页面：

| URL | 状态 |
|---|---|
| `https://zh.minecraft.wiki/w/数据包?action=raw` | 抓取时被机器人校验拦截，**未取得正文**；仅作为人工核对入口 |
| `https://zh.minecraft.wiki/w/标签?action=raw` | 同上，未抓取 |
| `https://zh.minecraft.wiki/w/战利品表?action=raw` | 同上，未抓取 |

### 14.2 结论来源拆分

| 结论 | 来源 |
|---|---|
| `pack_format = 15`（1.20.1） | 旧技能文档与 wiki `Pack_format` 历史表一致；wiki 正文的模板未在 raw 中展开数字 |
| 1.20.2=18、1.20.3/4=26、1.20.5=41、1.21=48 | 旧文档 + wiki `Pack_format` 历史段（模板） |
| 目录在 1.20.1 用复数、1.21 改单数 | wiki `Data_pack` 与 `Tag` 页面的目录模板 + 历史段；旧文档同样如此 |
| 函数宏 1.20.2+、组件 1.20.5+、`@n` 1.21+、`equipment` 槽位 1.21.5+ | wiki 各页历史段 + 旧文档；在文中作为“1.20.1 不存在”的反例 |
| `pack.mcmeta` 只有 `pack_format`/`description` 在 1.20.1 必需 | wiki `Data_pack`；`supported_formats`/`overlays` 明确标为 1.20.2+ |
| 标签 `required` 自 1.16.2 起存在 | wiki `Tag` 页面；**修正了“required 是 1.20.2+”的常见误传** |
| `banner_pattern`/`painting_variant` 标签在 1.20.1 不存在 | wiki `Data_pack` 历史段（分别于 1.20.5/1.21 数据驱动）；**与任务描述中的假设不同，按官方历史更正** |
| 战利品 `functions`、`condition`、条目 `name` 是 1.20.1 的字段名 | wiki `Loot_table` 历史段（1.20.5 起 `name`→`value`，后续 `functions`→`modifier`、`conditions`→`condition`） |
| 谓词 `condition` 是 1.20.1 的字段名 | wiki `Predicate` 历史段（26.3 才改名 `type`） |
| 配方原料在 1.20.1 是 `{"item":...}` 对象 | wiki `Recipe` 页面当前格式对照 + 旧文档；裸字符串是 1.21.2+ |
| `smithing_transform` 需要 `template` | wiki `Recipe` 页面的锻造段 + 1.20 版本变更说明 |
| 进度图标在 1.20.1 用 `icon.item` | wiki `Advancement_definition` 当前 schema 已改为 `id`（1.20.5+），旧文档与 1.20.1 原版文件为 `item` |
| 所有命令语法（`execute`/`data`/`item`/`attribute`/`loot`/`place`） | 旧技能文档骨架 + 逐条对照 1.20.1 命令表；其中 `attribute` 的 operation 名标为未实测 |
| 世界生成字段（dimension_type/biome/structure 等） | 旧文档 + wiki 各 worldgen 页面字段表；**完整 noise_router 未提供可加载示例** |

### 14.3 本文明确标注“未验证/未实测”的条目

| # | 条目 | 位置 | 说明 |
|---|---|---|---|
| 1 | `pack.mcmeta` 的 `filter` 字段 | §2.1 | 1.19+ 存在，但 1.20.1 行为未实测 |
| 2 | `tags/instrument/` 在 1.20.1 的存在性 | §5.2 | 标注“未实测” |
| 3 | 配方 `show_notification` | §0.1、§7 | 常见于 1.20.5+ 教程，1.20.1 未验证 |
| 4 | `smithing_transform` 的 `result.count > 1` 行为 | §7.6 | 未实测，建议恒写 1 |
| 5 | 战利品 `random_sequence` | §8.1 | 1.20 加入，未在 1.20.1 实测 |
| 6 | 战利品类型 `archaeology` | §8.2 | 1.20 加入，未在 1.20.1 实测 |
| 7 | 旧组合条件名 `alternative` 是否仍兼容 | §8.5 | 1.20 已改名 `any_of`；旧名兼容性未实测 |
| 8 | 谓词 `survives_explosion` 在 `execute if predicate` 下 | §10.2 | 语义未实测 |
| 9 | `attribute` 的 operation 名 `add`/`multiply`/`multiply_base` | §6.8 | 版本边界易混，写前用 tab 补全确认 |
| 10 | 规则处理器 `output_nbt` | §11.8 | 未在 1.20.1 实测 |
| 11 | 完整可加载的 `noise_router` 示例 | §11.10 | 明确不提供，避免给出不可加载 JSON |
| 12 | 密度函数二元运算字段名 | §11.10 | `left`/`right` 与 `argument1`/`argument2` 未逐一验证 |
| 13 | `trim_pattern.decals` 在 1.20.1 的行为 | §12.3 | 后续版本字段，写了会怎样未实测 |
| 14 | 同一实体重复使用相同 UUID 的 attribute modifier | §13.6 | 未验证 |
| 15 | `set_name.name` 直接写文本组件对象 | §10.5 | 1.20.1 更常见写法是 JSON 字符串；对象写法未实测 |
| 16 | `commands` 中 `random_sequence` 对测试随机的影响 | §13.6 | 仅作经验说明 |
| 17 | `give @s #物品标签` 是否被 1.20.1 接受 | §5.3 | 标注未实测，建议逐条 `give` |
| 18 | 单 tick 内 `#tick` 与 `schedule` 的精确先后 | §6.6 | 标注“未逐帧验证” |
| 19 | 数字提供器 `minecraft:score` 的 `target` 结构 | §8.3 | 标注未在 1.20.1 实测 |

> 除了上表，本文其余版本判断（目录复数、`pack_format=15`、无宏、无组件、无 `@n`、无 `equipment` 槽位、无 `return run`/`if function`/`if items`/`random`）均按“1.20.1 确定存在/不存在”处理，并在正文中以“1.20.2+/1.20.5+/1.21+/1.21.5+”标明首次出现版本。

### 14.4 建议的交叉核对方式

1. 在游戏里运行 `/version` 看版本，`F3+V` 或 `/version` 可看当前 `pack_format` 期望值。
2. 打开原版数据包（`.minecraft/versions/1.20.1/1.20.1.jar` 内 `data/minecraft/...`）直接对照字段名——这是 1.20.1 最权威的样本。
3. 每次只改一类文件，`/reload` 后确认无报错再继续。
4. 涉及 worldgen 时不要依赖 `/reload`，直接重进世界并新建区块测试。

---

**文档结束。** 本文只覆盖 Java 版 1.20.1 的原版数据包；宏、组件、单数目录、`@n`、`equipment` 槽位等均属后续版本，请勿混用。
