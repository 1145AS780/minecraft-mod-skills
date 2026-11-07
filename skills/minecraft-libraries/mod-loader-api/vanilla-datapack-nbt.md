# 原版命令、数据包与 NBT（1.20.1 / 1.21.1）

本文件是纯原版（不依赖插件、模组）的命令、数据包与 NBT 参考。重点覆盖 **1.20.1** 与 **1.21.1** 两个版本，凡两版存在差异处都显式标注 `1.20.1:` / `1.21.1:`。命令语法以 1.21.1（即 1.21 系列首个正式版）为准；1.20.1 与之相同处不再重复标注。

约定：

- 示例中的命名空间统一用 `myns`，实际使用时替换成自己的命名空间。
- 代码块内命令**不带**前导 `/`，可直接粘进 `.mcfunction`；聊天栏执行时补 `/`。
- 标注 `snbt` 的代码块是 NBT 文本（SNBT），写进命令时通常要放在 `{...}` 参数位置。

---

## 1. pack_format 与版本对照

`pack_format` 写在 `pack.mcmeta` 的 `pack.pack_format`。资源包和数据包各自维护一套编号，**同一个版本上两个编号通常不同**。

| 版本 | 数据包 format | 资源包 format | 备注 |
|---|---|---|---|
| 1.20 / 1.20.1 | 15 | 15 | 两套编号在此版本恰好相同 |
| 1.20.2 | 18 | 18 | 新增 `supported_formats`、`overlays` |
| 1.20.3 / 1.20.4 | 26 | 22 | 编号开始分叉 |
| 1.20.5 / 1.20.6 | 41 | 32 | 物品数据改为 DataComponents，冲击最大 |
| 1.21 / 1.21.1 | 48 | 34 | 本库重点版本 |
| 1.21.2 / 1.21.3 | 57 | 42 | |
| 1.21.4 | 61 | 46 | |
| 1.21.5 | 71 | 55 | `equipment` 合并实体装备字段 |

要点：

- 编号只用于“兼容性判定”，不会检查文件内容。编号不匹配时数据包/资源包会标红、提示“不兼容”，但多数情况下仍能强制加载。
- 1.20.2 起，`supported_formats` 可以声明一段区间，让一个包同时被多个版本接受。
- 1.21.9 起 `supported_formats` 被 `min_format` / `max_format` 取代，`pack_format` 变为可选。**1.20.1 与 1.21.1 都不要写 `min_format`。**

### 1.1 `pack.mcmeta` 基本写法

```json
{
  "pack": {
    "pack_format": 48,
    "description": "myns 数据包（1.21.1）"
  }
}
```

1.20.1 的同一份文件把 `pack_format` 改成 `15` 即可。

### 1.2 `description` 是 JSON 文本组件

`description` 接受文本组件（字符串、对象或数组），因此可以带颜色：

```json
{
  "pack": {
    "pack_format": 48,
    "description": [
      {"text": "myns", "color": "gold", "bold": true},
      {"text": " · 数据包 1.21.1", "color": "gray"}
    ]
  }
}
```

1.20.1 同样支持文本组件，写法完全一致。

### 1.3 `supported_formats`（1.20.2 起）

三种等价写法，`min_inclusive` / `max_inclusive` 指 pack_format 的编号区间：

```json
{
  "pack": {
    "pack_format": 48,
    "description": "myns",
    "supported_formats": {"min_inclusive": 48, "max_inclusive": 61}
  }
}
```

```json
{
  "pack": {
    "pack_format": 48,
    "description": "myns",
    "supported_formats": [48, 61]
  }
}
```

```json
{
  "pack": {
    "pack_format": 48,
    "description": "myns",
    "supported_formats": 48
  }
}
```

规则：

- `supported_formats` 必须**包含** `pack_format` 声明的那个编号，否则包会被判为不兼容。
- 只有 1.20.2 及以上认识这个字段；1.20.1 会忽略它，只读 `pack_format`。
- 区间只表示“能加载”，不代表内容真的兼容。1.20.5 的物品组件、1.21 的目录单数化都不是区间能解决的。

### 1.4 一个 `pack.mcmeta` 如何同时服务资源包与数据包

一个 `pack.mcmeta` 里只有**一个** `pack_format` 字段，游戏不会为资源包和数据包分别读两个值。所以“同时写两个值”的正确做法是：用 `pack_format` 锚定一个编号，用 `supported_formats` 把另一个编号也包进区间。

```json
{
  "pack": {
    "pack_format": 34,
    "description": "myns 资源包 + 数据包（1.21.1）",
    "supported_formats": {"min_inclusive": 34, "max_inclusive": 48}
  }
}
```

- 资源包加载器按 34（资源包 format）判定，落在 `34..48` 内，兼容。
- 数据包加载器按 48（数据包 format）判定，同样落在区间内，兼容。
- 1.20.1 不存在这个矛盾：资源包与数据包编号都是 15，单个 `pack_format: 15` 两边都认。
- 1.20.2 / 1.20.4 上编号相同（18 / 18、22 / 26 除外，1.20.4 已分叉），1.20.4 起同样建议用区间写法。

### 1.5 `overlays`（1.20.2 起，可选）

一份包内放多套目录，按版本切换，避免维护多个 zip：

```json
{
  "pack": {
    "pack_format": 48,
    "description": "myns",
    "overlays": {
      "entries": [
        {"directory": "overlay_1_20", "formats": {"min_inclusive": 15, "max_inclusive": 15}}
      ]
    }
  }
}
```

`directory` 只允许 `a-z`、`0-9`、`_`、`-`、`.`。该目录里同样放 `data/`，`pack.mcmeta` 与 `pack.png` 在其中会被忽略。

### 1.6 放置位置

- 存档数据包：`.minecraft/saves/<world>/datapacks/<name>/`（文件夹或 zip）。
- 服务器数据包：`<server>/world/datapacks/`。
- 资源包：`.minecraft/resourcepacks/`（客户端）。
- 数据包目录根部必须有 `pack.mcmeta`，否则不被识别为数据包。

## 2. 数据包目录结构

数据包里的路径由“文件夹名 + 文件名”直接决定注册名：`data/myns/function/hello.mcfunction` → `myns:hello`；`data/myns/recipe/demo.json` → `myns:demo`。子目录同样参与命名：`data/myns/function/util/msg.mcfunction` → `myns:util/msg`。

### 2.1 1.20.1（除 `tags/` 的子类外全部复数）

```text
myns-datapack-1_20_1/
├── pack.mcmeta
├── pack.png                     (可选)
└── data/
    ├── myns/
    │   ├── advancements/        advancement/*.json
    │   ├── recipes/             recipe/*.json
    │   ├── loot_tables/         loot_table/*.json
    │   ├── predicates/          predicate/*.json
    │   ├── item_modifiers/      item_modifier/*.json
    │   ├── functions/           *.mcfunction
    │   ├── structures/          *.nbt
    │   ├── damage_type/         damage_type/*.json
    │   ├── tags/
    │   │   ├── functions/       function 标签
    │   │   ├── items/           item 标签
    │   │   ├── blocks/          block 标签
    │   │   ├── entity_types/    entity_type 标签
    │   │   ├── fluids/          fluid 标签
    │   │   └── game_events/     game_event 标签
    │   ├── dimension/           自定义维度 json
    │   ├── dimension_type/      维度类型 json
    │   └── worldgen/
    │       ├── biome/
    │       ├── configured_feature/
    │       ├── placed_feature/
    │       ├── noise/
    │       ├── noise_settings/
    │       ├── density_function/
    │       ├── configured_carver/
    │       ├── processor_list/
    │       ├── template_pool/
    │       ├── structure/
    │       └── structure_set/
    └── minecraft/
        └── tags/
            └── functions/
                ├── load.json
                └── tick.json
```

注意 1.20.1 的错位：**内容目录是复数（`functions`/`recipes`/`tags/items`），而注册表类目录已经是单数（`dimension`、`dimension_type`、`worldgen/*`）**。迁移时不要一把梭全改。

### 2.2 1.21.1（内容目录全部单数）

```text
myns-datapack-1_21_1/
├── pack.mcmeta
├── pack.png                     (可选)
└── data/
    ├── myns/
    │   ├── advancement/         advancement/*.json
    │   ├── recipe/              recipe/*.json
    │   ├── loot_table/          loot_table/*.json
    │   ├── predicate/           predicate/*.json
    │   ├── item_modifier/       item_modifier/*.json
    │   ├── function/            *.mcfunction
    │   ├── structure/           *.nbt
    │   ├── enchantment/         enchantment/*.json
    │   ├── damage_type/         damage_type/*.json
    │   ├── tags/
    │   │   ├── function/        function 标签
    │   │   ├── item/            item 标签
    │   │   ├── block/           block 标签
    │   │   ├── entity_type/     entity_type 标签
    │   │   ├── fluid/           fluid 标签
    │   │   ├── game_event/      game_event 标签
    │   │   ├── enchantment/     enchantment 标签
    │   │   └── damage_type/     damage_type 标签
    │   ├── dimension/
    │   ├── dimension_type/
    │   └── worldgen/
    │       ├── biome/
    │       ├── configured_feature/
    │       ├── placed_feature/
    │       ├── noise/
    │       ├── noise_settings/
    │       ├── density_function/
    │       ├── configured_carver/
    │       ├── processor_list/
    │       ├── template_pool/
    │       ├── structure/
    │       └── structure_set/
    └── minecraft/
        └── tags/
            └── function/
                ├── load.json
                └── tick.json
```

`tags/<注册表名>` 里的注册表名在 1.21.1 一律单数，且与注册表 ID 一致（`item`、`block`、`entity_type`、`enchantment`、`damage_type`……）。

### 2.3 目录单复数迁移表

| 1.20.1 | 1.21.1 |
|---|---|
| `data/<ns>/functions/` | `data/<ns>/function/` |
| `data/<ns>/advancements/` | `data/<ns>/advancement/` |
| `data/<ns>/recipes/` | `data/<ns>/recipe/` |
| `data/<ns>/loot_tables/` | `data/<ns>/loot_table/` |
| `data/<ns>/predicates/` | `data/<ns>/predicate/` |
| `data/<ns>/item_modifiers/` | `data/<ns>/item_modifier/` |
| `data/<ns>/structures/` | `data/<ns>/structure/` |
| `data/<ns>/tags/functions/` | `data/<ns>/tags/function/` |
| `data/<ns>/tags/items/` | `data/<ns>/tags/item/` |
| `data/<ns>/tags/blocks/` | `data/<ns>/tags/block/` |
| `data/<ns>/tags/entity_types/` | `data/<ns>/tags/entity_type/` |
| `data/<ns>/tags/fluids/` | `data/<ns>/tags/fluid/` |
| `data/<ns>/tags/game_events/` | `data/<ns>/tags/game_event/` |
| `data/<ns>/tags/damage_type/`（1.19.4 起即为单数） | 同名单数 |

只改目录、不改 `pack_format`，结果是函数“静默不加载”：`/reload` 不报错，`/function myns:xxx` 却提示找不到。

### 2.4 命名空间与路径规则

- 命名空间：`a-z0-9._-`，习惯全小写。
- 路径段：`a-z0-9._-/`，**不允许大写**。`Ruby.json` 在 Windows 上能存在，但游戏按小写注册，命令里调用会失败。
- 文件扩展名固定：函数 `.mcfunction`，结构 `.nbt`，其余 `.json`。
- 覆盖原版：把同名文件放进 `data/minecraft/` 下即可覆盖，例如 `data/minecraft/tags/function/tick.json`。

### 2.5 哪些内容 `/reload` 能热更新

`/reload` 会重读：函数、标签、进度、配方、战利品表、谓词、物品修饰器、结构模板、附魔定义。不会重读：维度与维度类型（`dimension`/`dimension_type`）、大部分 `worldgen`、`pack.mcmeta` 的 `overlays` 判定。改这些要退出重进世界或重启服务器。

## 3. 函数（.mcfunction）

函数是每行一条命令的纯文本文件，路径即函数名。`data/myns/function/hello.mcfunction` → `myns:hello`；`data/myns/function/util/msg.mcfunction` → `myns:util/msg`。

### 3.1 语法规则

```mcfunction
# 注释行：行首（允许前置空格/制表符）是 #
# 空行会被忽略

say 第一行
# 命令前不要加斜杠，加了会报“未知命令”
execute as @a at @s run particle minecraft:flame ~ ~1 ~

# 单行过长可用行尾反斜杠续行（反斜杠必须是该行最后一个非空白字符）
# 注意：续行是 1.20.2（23w31a）才加入的，1.20.1 不支持，必须一行写完
give @s minecraft:diamond_sword[minecraft:custom_name='{"text":"Excalibur"}',\
minecraft:enchantments={levels:{"minecraft:sharpness":5}}]
```

要点：

- 每行一条命令，行首行尾空白会被裁掉；单行长度没有 32500 字符的命令方块限制。
- 非宏行在加载/`/reload` 时就被解析；**任何一行语法错误会导致整个文件加载失败**（`/reload` 会报错并指出行号）。
- 一个函数内的所有命令在**同一 tick** 内顺序执行完。
- 函数继承调用者的执行上下文（执行者、位置、朝向、维度、anchor）；函数内 `execute` 修改的上下文**不会**延续到下一行。
- 权限：单人/LAN 世界按权限等级 2 执行；服务器受 `server.properties` 的 `function-permission-level` 限制（默认 2）。
- 单次函数链条执行的命令总数受 `gamerule maxCommandChainLength` 限制（默认 65536，1.20.1 与 1.21.1 相同）。

`execute` 修改上下文不跨行的例子：

```mcfunction
# 假设玩家在 y=64
teleport @s ~ ~5 ~
setblock ~ ~-1 ~ minecraft:emerald_block
# 上面这行仍以“函数执行时的位置”为准（y=64 附近），不是传送后的位置
execute at @s run setblock ~ ~-1 ~ minecraft:diamond_block
# 加了 execute at @s 才用传送后的位置
```

### 3.2 函数标签（`tags/function/*.json`）

```json
{
  "values": [
    "myns:load/init",
    "myns:util/hello"
  ]
}
```

- 路径写成 `myns:xxx`，**不带 `.json`、不带 `function/` 前缀**。
- 调用标签：`function #myns:group`。标签内的函数按 `values` 顺序执行，同名函数只执行一次。
- 支持 `{"id": "myns:util/hello", "required": false}` 形式，文件不存在时不报错（工程里常用它做“可选钩子”）。
- 标签也能被 `execute if function #myns:group` 调用（1.20.3+）。

### 3.3 `#minecraft:load` 与 `#minecraft:tick`

两个特殊标签，名字在 1.20.1 与 1.21.1 **都是** `minecraft:load` / `minecraft:tick`，只有目录名变了：

| | 1.20.1 | 1.21.1 |
|---|---|---|
| 目录 | `data/minecraft/tags/functions/` | `data/minecraft/tags/function/` |
| 文件名 | `load.json` / `tick.json` | `load.json` / `tick.json` |
| 引用 | `#minecraft:load` / `#minecraft:tick` | 同左 |

1.20.1：

```json
{
  "values": ["myns:init"]
}
```

放在 `data/minecraft/tags/functions/load.json`。

1.21.1：

```json
{
  "values": ["myns:init"]
}
```

放在 `data/minecraft/tags/function/load.json`。文件内容一模一样，**只有目录名不同**。

行为：

- `#minecraft:load`：世界加载、服务器启动、`/reload` 后执行一次。此时玩家还没进入世界，`@a`/`@p` 选不到人，`tellraw`/`title` 不会有任何显示。
- `#minecraft:tick`：每个 tick 开头执行一次。重逻辑不要直接放这里，用 `schedule` 或计分板节流（见第 9 节）。
- 执行顺序（同一 tick 内）：进度奖励函数 → 附魔效果函数 → `#minecraft:tick` → `schedule` 到期函数 → 命令方块/玩家命令。

### 3.4 返回值：`return`

```mcfunction
# 1.20.1 只有 return <整数>
return 1
return 0
```

1.21.1（也是 1.20.3+）完整形式：

```mcfunction
return 5
return fail
return run function myns:check
```

- `return <value>`：以成功结束函数，返回值为该整数。
- `return fail`：以失败结束，返回值 0。**1.20.1 没有 `fail` 子命令**（1.20.3 才加）。
- `return run <command>`：执行命令，把该命令的 `success`/`result` 作为函数的成功性与返回值。**1.20.1 没有 `return run`**（1.20.2 短暂加入、1.20.3 重新加入）。
- 函数没有执行到 `return` 时是 void：`execute store result ... run function` 不会覆盖目标值。
- `return` 还能截断一个已经分叉的 `execute`，只执行第一个分支——常用来做“只执行一次”：

```mcfunction
execute as @e[type=minecraft:zombie,sort=nearest,limit=1] at @s if block ~ ~-1 ~ minecraft:grass_block run return run teleport @s 0 64 0
```

### 3.5 宏函数（1.20.2 起；1.20.1 不支持）

行首 `$` 标记宏行，`$(key)` 在调用时替换：

```mcfunction
# data/myns/function/msg.mcfunction
$tellraw @a {"text":"$(msg)"}
$give @s $(item) $(count)
```

```mcfunction
# 直接传 SNBT 复合标签（注意必须有 with）
function myns:msg with {msg:"hello",item:"minecraft:diamond",count:3}

# 从 storage / 方块实体 / 实体取参数（路径必须是单个复合标签）
function myns:msg with storage myns:args
```

关键限制：

- 只要文件里存在宏行，**不带参数**的 `function myns:msg` 就会失败（宏行解析不出来）。
- 参数键名只允许 `a-z A-Z 0-9 _`。
- 少传一个用到的键 → 整个函数不执行（不是只跳过那一行）。
- 字符串值插入时**不带引号**；数字值不带类型后缀（`10b` → `10`）；列表/复合标签按 SNBT 原样插入。
- 正因为不带引号，`$say $(msg)` 里传 `hello world` 会变成 `say hello world`（正常），但传 `a,b` 就可能改变参数切分——需要引号时自己在宏行里写 `"$(msg)"`。

宏的典型用法（见第 10 节完整示例）：

```mcfunction
$summon minecraft:$(type) ~ ~1 ~ {Tags:["spawned"],CustomName:'{"text":"$(name)"}'}
```

### 3.6 函数内的 `execute` 链

```mcfunction
# 给所有在线玩家脚下的方块换成金块
execute as @a at @s run setblock ~ ~-1 ~ minecraft:gold_block

# 只对 Survival 玩家生效
execute as @a[gamemode=survival] at @s run effect give @s minecraft:regeneration 5 0 true

# 先筛选再执行：注意 if 子命令必须放在 run 之前
execute as @a if score @s coins matches 10.. run tellraw @s {"text":"你有 10 个以上硬币"}

# 存储命令结果到计分板
execute store result score @s hp run data get entity @s Health

# 嵌套：每个玩家各自找一个最近的僵尸并造成伤害
execute as @a at @s run execute as @e[type=minecraft:zombie,distance=..5,limit=1,sort=nearest] run damage @s 4 minecraft:generic
```

⚠️ 常见错误：`execute as @a run execute if score ...` 这种写法本身没错，但把 `if` 放在 `run` 之后就是另一条命令了；条件必须写在 `run` 之前。

## 4. 命令速查

下面每条命令给“语法 + 示例”。语法以 1.21.1 为准；1.20.1 有差异处单独标注。

### 4.1 `execute` 全部子命令

完整语法树（Java 版，1.21.1）：

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
execute ... (if|unless) ...  -> [execute]
execute ... run <command>
```

#### 上下文修改类

| 子命令 | 语法 | 说明 |
|---|---|---|
| `align` | `align <axes>` | 把执行位置的指定轴向下取整，`axes` 是 `x`/`y`/`z` 的任意组合 |
| `anchored` | `anchored <eyes\|feet>` | 设置 anchor。**1.20.1 与 1.21.1 都是 `eyes`/`feet` 两个值，无变化** |
| `as` | `as <targets>` | 换执行者（改变 `@s`），不改位置/朝向/维度 |
| `at` | `at <targets>` | 换位置/朝向/维度，不改执行者 |
| `facing` | `facing <pos>` / `facing entity <targets> <eyes\|feet>` | 设置朝向 |
| `in` | `in <dimension>` | 换维度，相对坐标按维度缩放换算（主世界↔下界 8:1） |
| `on` | `on <relation>` | 按关系换执行者：`attacker`、`controller`、`leasher`、`origin`、`owner`、`passengers`、`target`、`vehicle` |
| `positioned` | `positioned <pos>` / `positioned as <targets>` / `positioned over <world_surface\|motion_blocking\|motion_blocking_no_leaves\|ocean_floor>` | 只改位置 |
| `rotated` | `rotated <yaw> <pitch>` / `rotated as <targets>` | 只改朝向 |
| `summon` | `summon <entity>` | 在执行位置生成实体，并把它设为执行者（1.19.4+） |

示例：

```mcfunction
# 对齐到整数方块坐标
execute align xyz run summon minecraft:armor_stand ~ ~ ~

# 从眼睛位置发射粒子（anchored 决定 ^ ^ ^ 的原点）
execute as @a at @s anchored eyes run particle minecraft:flame ^ ^ ^2 0 0 0 0 1

# 把执行者换成“骑在船上的玩家”
execute as @e[type=minecraft:boat] on passengers run give @s minecraft:fishing_rod

# 把执行者换成“正在拴着猫的实体”
execute as @e[type=minecraft:cat] on leasher run damage @s 2 minecraft:generic

# 朝向某点，然后沿视线前进 1 格（不改朝向）
execute as @e at @s facing 0 64 0 run teleport @s ^ ^ ^1

# 跨维度执行：先切维度，再按该维度坐标定位
execute in minecraft:the_nether positioned as @s run tp ~ ~ ~

# 用 heightmap 定位到地表上方一格
execute positioned over world_surface run summon minecraft:marker ~ ~ ~

# summon 后直接操作新实体
execute summon minecraft:sheep run tag @s add demo
```

`on` 的关系值含义：

- `attacker`：最近 5 秒内伤害过当前执行者的实体。
- `controller`：正在骑乘并控制当前执行者的实体。
- `leasher`：用拴绳牵着当前执行者的实体。
- `origin`：召唤出当前执行者的实体（箭的射手、TNT 的点火者）。
- `owner`：可驯服动物的主人。
- `passengers`：直接骑在当前执行者背上的实体（可能多个，会分叉）。
- `target`：当前执行者正在攻击的目标。
- `vehicle`：当前执行者骑着的实体。

#### 条件类 `if` / `unless`

| 形式 | 语法 | 版本 |
|---|---|---|
| biome | `if biome <pos> <biome>` | 1.19.3+，两版都有 |
| block | `if block <pos> <block>` | 两版都有；`<block>` 支持方块标签 `#minecraft:logs` 与状态 `minecraft:oak_stairs[facing=east]` |
| blocks | `if blocks <start> <end> <destination> (all\|masked)` | 两版都有；体积上限 32768 格 |
| data | `if data block <pos> <path>` / `if data entity <target> <path>` / `if data storage <id> <path>` | 两版都有 |
| dimension | `if dimension <dimension>` | 1.19.4+，两版都有 |
| entity | `if entity <targets>` | 两版都有 |
| function | `if function <function>` | **1.20.3+，1.20.1 没有** |
| items | `if items block <pos> <slots> <item_predicate>` / `if items entity <target> <slots> <item_predicate>` | **1.20.5+，1.20.1 没有** |
| loaded | `if loaded <pos>` | 1.19.4+，两版都有 |
| predicate | `if predicate <id>` | 两版都有 |
| score | `if score <target> <obj> (<\|<=\|=\|>=\|>) <source> <srcObj>` / `if score <target> <obj> matches <range>` | 两版都有 |

示例：

```mcfunction
# 方块条件（带方块状态）
execute if block ~ ~-1 ~ minecraft:oak_stairs[facing=east] run say 朝东的台阶

# 方块标签
execute if block ~ ~-1 ~ #minecraft:logs run say 站在原木上

# 区域比对：源区域与目标区域逐格相同才算通过
execute if blocks ~ ~ ~ ~4 ~4 ~4 ~10 ~ ~ all run say 两片区域完全一致

# 实体数据：判断玩家是否手持物品（SelectedItem 存在即通过）
execute if data entity @s SelectedItem run say 手里有东西

# 精确匹配：根节点复合标签，任何没写到的键都不参与比较
execute if data entity @s {OnGround:1b} run say 站在地上

# 谓词文件
execute if predicate myns:is_raining run weather clear

# 函数返回值（1.20.3+）
execute if function myns:check run say 检查通过

# 物品条件（1.20.5+）：主手拿着钻石剑
execute if items entity @s weapon.mainhand minecraft:diamond_sword run say 拿着钻石剑

# 槽位范围与物品标签：头盔栏有任意金质装备
execute if items entity @s armor.head minecraft:golden_helmet run say 金头盔

# 位置是否已加载
execute if loaded ~ ~ ~ run setblock ~ ~ ~ minecraft:stone

# 计分板比较
execute if score @s coins >= @s target_coins run say 达标
execute unless score @s coins matches 0.. run say 有硬币
```

#### `store` 类

| 目标 | 语法 |
|---|---|
| block | `store (result\|success) block <pos> <path> <byte\|short\|int\|long\|float\|double> <scale>` |
| bossbar | `store (result\|success) bossbar <id> (value\|max)` |
| entity | `store (result\|success) entity <target> <path> <type> <scale>` |
| score | `store (result\|success) score <targets> <objective>` |
| storage | `store (result\|success) storage <id> <path> <type> <scale>` |

```mcfunction
# 把命令返回值写进计分板
execute store result score @s money run data get entity @s XpLevel

# 写进 storage，倍率 100 并四舍五入为 int
execute store result storage myns:stats kills int 100 run scoreboard players get @s kills

# 写进 bossbar 的 value
execute store result bossbar myns:boss value run scoreboard players get @s boss_hp

# 只关心成败（1/0）
execute store success score @s ok run function myns:check
```

注意：

- `result` 是命令的返回值（数量、坐标等），`success` 是成功计数（通常 0/1）。写入时先乘以 `scale`，再转换成目标类型（`int` 会截断小数）。
- `store ... entity` 不能写玩家 NBT（和 `data` 命令一样，玩家数据只读）。
- 一个 `execute` 分叉出多个分支时，每个分支都会写一次同一个存储点，最终留下最后执行的那个分支的值。

### 4.2 `data`：读写 NBT

```text
data get (block <pos>|entity <target>|storage <id>) [<path>] [<scale>]
data merge (block <pos>|entity <target>|storage <id>) <nbt>
data modify (block <pos>|entity <target>|storage <id>) <path> (set|merge|append|prepend|insert <index>) ...
data remove (block <pos>|entity <target>|storage <id>) <path>
```

`modify` 的来源有三种写法：

- `... from (block <pos>|entity <target>|storage <id>) <path>`
- `... string (block <pos>|entity <target>|storage <id>) <path> [<start>] [<end>]`（按字符截取字符串）
- `... value <snbt>`

`set`/`merge`/`append`/`prepend`/`insert <index>` 这五个动作都能配上面三种来源。

示例：

```mcfunction
# 读取
data get entity @s Health
data get entity @s SelectedItem
data get entity @s ActiveEffects[0].id
data get block ~ ~ ~ Items
data get storage myns:data counter

# 写入复合标签（会覆盖同名键）
data merge entity @s {NoGravity:1b,Invulnerable:1b}
data merge storage myns:data {counter:0,name:"unknown"}

# 单值写入
data modify entity @s CustomName set value '{"text":"Bob","color":"gold"}'
data modify storage myns:data counter set value 42

# 列表操作
data modify entity @s Tags append value "demo"
data modify entity @s Tags prepend value "first"
data modify storage myns:list items insert 0 value "head"
data modify storage myns:list items append from storage myns:other items

# 拷贝：把主手物品的自定义数据拷到 storage（1.21.1 路径；1.20.1 写 SelectedItem.tag.CustomModelData）
data modify storage myns:tmp hand set from entity @s SelectedItem.components."minecraft:custom_data"

# 删除
data remove entity @s Tags[0]
data remove storage myns:data temp
```

#### NBT 路径语法

路径由 `.` 分隔的节点组成，节点有五种：

| 节点写法 | 选中什么 | 示例 |
|---|---|---|
| `name` | 复合标签里的同名子标签 | `Health`、`Inventory` |
| `"带空格的名字"` | 需要转义时用引号 | `"A crazy name!"` |
| `[index]` | 列表/数组的第 index 个元素，负数为倒数 | `Inventory[0]`、`Tags[-1]` |
| `[]` | 列表/数组的**全部**元素（多选） | `ActiveEffects[]` |
| `[{k:v}]` | 列表中满足匹配的复合元素（多选） | `Inventory[{id:"minecraft:diamond"}]` |
| `{k:v}` | 根节点匹配（只能放开头） | `{Invisible:1b}.id` |
| `name{k:v}` | 名为 name 且满足匹配的复合标签 | `Item{id:"minecraft:diamond"}` |

组合示例：

```text
Inventory[{id:"minecraft:diamond"}].components."minecraft:custom_data".owner
ActiveEffects[0].id
Items[].count
foo.bar[0]."A [crazy name]!".baz
```

限制：

- `data get` 要求最终只选中**一个**标签；`data get ... Inventory[]` 会报“路径选中多个标签”。
- `data modify` 允许多选，一次改多个；`data remove` 也允许多选。
- 没有 `[[...]]` 这种双重方括号语法；`[]` 后面可直接跟 `[{...}]`（写法 `Items[][{}]` 或 `Items.[].[{}]` 都合法）。
- 1.20.5 起物品在 NBT 里是 `{id, count, components}`；组件键里有冒号，路径里必须加引号：`.components."minecraft:custom_name"`。1.20.1 对应的是 `.tag.display.Name`。

### 4.3 `scoreboard`、`team`、`tag`

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
scoreboard players display name|numberformat ...
```

`<criteria>` 常用：`dummy`、`trigger`、`deathCount`、`playerKillCount`、`totalKillCount`、`health`、`food`、`air`、`armor`、`xp`、`level`、`teamkill.<color>`。自定义逻辑一律用 `dummy`。

`<op>`：`=`、`+=`、`-=`、`*=`、`/=`、`%=`、`<`、`>`（把较小/较大值写入目标）、`><`（交换）。

```mcfunction
# 初始化
scoreboard objectives add coins dummy {"text":"金币","color":"gold"}
scoreboard objectives add hp dummy
scoreboard objectives setdisplay sidebar coins
scoreboard objectives setdisplay list coins

# 读写
scoreboard players set @s coins 100
scoreboard players add @s coins 5
scoreboard players remove @s coins 3
scoreboard players get @s coins
scoreboard players reset @s coins

# 运算：@s 的 coins 变成 coins 与 bonus 的和
scoreboard players operation @s coins += @s bonus
# 取两者最小值
scoreboard players operation @s coins < @s cap
# 乘法
scoreboard players operation @s coins *= #const multiplier

# 常量：以 # 开头的“虚拟玩家”不需要真实实体
scoreboard players set #const multiplier 2
```

1.20.1 与 1.21.1 的 `scoreboard` 语法基本一致；差异只在 `display`/`numberformat` 这些 1.20.3+ 才有的子命令（1.20.1 不支持 `scoreboard players display`）。

队伍：

```text
team add <name> [<displayName>]
team remove <name>
team empty <name>
team join <name> [<members>]
team leave <members>
team list [<name>]
team modify <name> <option> <value>
team modify <name> prefix|suffix <text>
team modify <name> color <color>
team modify <name> friendlyFire <true|false>
team modify <name> seeFriendlyInvisibles <true|false>
team modify <name> nametagVisibility <always|hideForOtherTeams|hideForOwnTeam|never>
team modify <name> collisionRule <always|never|pushOtherTeams|pushOwnTeam>
```

```mcfunction
team add red {"text":"红队","color":"red"}
team modify red color red
team modify red prefix {"text":"[红] ","color":"red"}
team join red @a[team=]
# 让红队成员之间不互相伤害
team modify red friendlyFire false
team list red
```

`tag`（实体标签，与“标签文件”不是一回事）：

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

### 4.4 生成、传送、朝向、骑乘、旁观

```text
summon <entity> [<pos>] [<nbt>]
teleport <targets> <location>
teleport <targets> <destination>
teleport <targets> <location> <rotation>
teleport <targets> <location> facing <entity> <eyes|feet>
teleport <targets> <location> facing <pos>
tp ...（与 teleport 完全相同，是别名）

rotate <target> <yaw> <pitch>
ride <target> mount <vehicle>
ride <target> dismount
spectate <target> [<player>]
```

版本说明：`teleport` 自 1.13 起是正式名，`tp` 一直保留为别名，**1.20.1 和 1.21.1 都能用 `tp`**；`rotate`、`ride` 自 1.19.4 起可用，两版都有。

```mcfunction
summon minecraft:zombie ~ ~1 ~ {Tags:["demo"],NoAI:1b,CustomName:'{"text":"Bob"}'}
# 掉落物：1.20.1 用 Count:1b，1.21.1 用小写 count
summon minecraft:item ~ ~ ~ {Item:{id:"minecraft:diamond",Count:1b}}
summon minecraft:item ~ ~ ~ {Item:{id:"minecraft:diamond",count:1}}

# 展示实体（1.21.1 的物品栈写法；1.20.1 把 item 换成 {id,Count}）
summon minecraft:item_display ~ ~ ~ {item:{id:"minecraft:diamond",count:1},transformation:{scale:[2.0f,2.0f,2.0f]}}

teleport @s 100 64 100
teleport @s ~ ~10 ~
teleport @a[team=red] 0 100 0 90 0
tp @s @e[type=minecraft:armor_stand,limit=1,sort=nearest]
teleport @s ^ ^ ^3

rotate @s 90 0
rotate @e[type=minecraft:armor_stand] 45 10

ride @s mount @e[type=minecraft:pig,limit=1,sort=nearest]
ride @s dismount

spectate @e[type=minecraft:zombie,limit=1] @s
spectate @s
```

1.20.1 与 1.21.1 的 `summon <entity> [<pos>] [<nbt>]` 语法相同；区别在 NBT 内容（1.21.1 的物品字段是 `{id,count,components}`，`item_display` 的 `item` 字段同理）。

### 4.5 物品与玩家属性

```text
give <targets> <item> [<count>]
clear <targets> [<item>] [<maxCount>]
item replace (block <pos>|entity <targets>) <slot> with <item> [<count>]
item replace (block <pos>|entity <targets>) <slot> from (block <pos>|entity <targets>) <slot> [<modifier>]
item modify (block <pos>|entity <targets>) <slot> <modifier>
enchant <targets> <enchantment> [<level>]
effect give <targets> <effect> [<seconds>] [<amplifier>] [<hideParticles>]
effect clear <targets> [<effect>]
attribute <target> <attribute> get [<scale>]
attribute <target> <attribute> base get [<scale>]
attribute <target> <attribute> base set <value>
attribute <target> <attribute> modifier add <id> <value> (add_value|add_multiplied_base|add_multiplied_total)
attribute <target> <attribute> modifier remove <id>
attribute <target> <attribute> modifier value get <id> [<scale>]
damage <target> <amount> [<damageType>] [at <pos>|by <entity> [from <cause>]]
kill <targets>
```

槽位名（`item` 命令）：实体用 `weapon.mainhand`、`weapon.offhand`、`armor.head`（`armor.chest`、`armor.legs`、`armor.feet`、1.21 的 `armor.body`）、`hotbar.0`–`hotbar.8`、`inventory.0`–`inventory.26`、`container.0`–`container.26`（马/驮箱）、`horse.armor`、`horse.saddle`、`villager.0`–`villager.2`；方块用 `container.0`–`container.26`（箱子）、`weapon`、`armor.*` 等。

```mcfunction
give @s minecraft:diamond 3
give @s minecraft:diamond_sword[minecraft:custom_name='{"text":"Excalibur","color":"gold"}']
clear @s
clear @s minecraft:diamond 0

item replace entity @s weapon.mainhand with minecraft:diamond_sword
item replace entity @s armor.head with minecraft:golden_helmet
item replace block ~ ~ ~ container.0 with minecraft:stone 16
item replace entity @s weapon.offhand from entity @s weapon.mainhand
item modify entity @s weapon.mainhand myns:add_ruby

enchant @s minecraft:sharpness 5
effect give @s minecraft:speed 30 1 true
effect give @a minecraft:regeneration 10 2
effect clear @s minecraft:poison

attribute @s minecraft:generic.max_health base set 40
attribute @s minecraft:generic.attack_damage base get
attribute @s minecraft:generic.movement_speed modifier add myns:fast 0.1 add_multiplied_base
attribute @s minecraft:generic.movement_speed modifier remove myns:fast

damage @s 4 minecraft:generic
damage @e[type=minecraft:zombie,limit=1] 6 minecraft:player_attack by @s
kill @e[type=minecraft:zombie,tag=demo]
```

版本差异：

- `attribute ... modifier add`：**1.20.1 是 `modifier add <uuid> <name> <value> <operation>`**（UUID 加名字两个参数）；**1.21.1 简化为 `modifier add <id> <value> <operation>`**，只有一个命名空间 ID。
- `attribute ... base reset` 是 1.21.4 才加入的，1.20.1 与 1.21.1 都没有。
- 属性 ID 在 1.21.1 仍是 `minecraft:generic.max_health` 这类带 `generic.` 前缀的写法；1.21.2 起才改成 `minecraft:max_health`。
- `damage` 的伤害类型是资源位置（如 `minecraft:generic`、`minecraft:player_attack`、`minecraft:magic`），1.20.1 与 1.21.1 一致。
- `enchant` 的附魔 ID 在 1.21 里也可写成 `minecraft:sharpness`；1.20.1 同样接受带命名空间的写法。

### 4.6 方块操作：`setblock` / `fill` / `clone` / `place`

```text
setblock <pos> <block> [destroy|keep|replace]
fill <from> <to> <block> [destroy|hollow|keep|outline|replace] [<filter>]
clone <begin> <end> <destination> [replace|masked] [normal|force|move] [<filter>]
place template <template> [<pos>] [<rotation>] [<mirror>] [<integrity>] [<seed>]
place feature <feature> [<pos>]
place jigsaw <pool> <target> <max_depth> [<pos>]
place structure <structure> [<pos>]
fillbiome <from> <to> <biome>
```

```mcfunction
setblock ~ ~-1 ~ minecraft:stone
setblock ~ ~ ~ minecraft:oak_stairs[facing=east,half=bottom]
setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b,id:"minecraft:diamond",count:3}]} replace
setblock ~ ~ ~ minecraft:air destroy

fill ~ ~ ~ ~5 ~5 ~5 minecraft:glass
fill ~ ~ ~ ~5 ~5 ~5 minecraft:air replace minecraft:stone
fill ~ ~ ~ ~5 ~5 ~5 minecraft:oak_planks hollow
fill ~ ~ ~ ~5 ~5 ~5 minecraft:stone outline

clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~
clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~ masked
clone ~ ~ ~ ~5 ~5 ~5 ~ ~10 ~ force move

place template myns:house ~ ~ ~ 0 none 1.0 0
place feature minecraft:forest_rock ~ ~ ~
place structure minecraft:village_plains ~ ~ ~
fillbiome ~ ~ ~ ~16 ~ ~ minecraft:plains
```

要点：

- `fill`/`clone` 单次最多 32768 格，超出直接失败。
- `clone` 的 `filter` 参数是方块谓词，配合 `masked` 使用；`force` 会覆盖目标区域原有方块，`move` 会清空源区域。
- **Java 版没有 `/structure` 命令**（`structure save/load/delete` 是基岩版）。Java 里保存结构用结构方块，加载用 `place template`。
- `place template` 的 `<template>` 指 `data/<ns>/structure/*.nbt`，写 `myns:house`，不带 `.nbt`。

### 4.7 战利品：`loot`

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

四个 target 的含义：

| target | 作用 |
| --- | --- |
| `give <targets>` | 把掉落物直接塞进玩家背包（放不下就掉地上） |
| `insert <target> <slot>` | 插入指定容器槽位（`container.0`、`weapon.mainhand` 等） |
| `spawn <targetPos>` | 在世界上生成掉落物实体 |
| `replace (block|entity) ... <slot> [<limit>]` | **替换**该槽位原有物品；`<limit>` 限制填几个槽 |

```mcfunction
# 直接发奖励给玩家，战利品表在 data/myns/loot_table/rewards/common.json
loot give @s loot myns:rewards/common

# 往当前脚下掉一堆战利品
loot spawn ~ ~1 ~ loot minecraft:chests/simple_dungeon

# 模拟"杀死这只僵尸"的掉落
loot give @s loot minecraft:entities/zombie

# 让玩家用主手工具挖脚下这块方块，得到该方块的掉落
loot give @s mine ~ ~-1 ~ mainhand

# 把战利品放进箱子第 0 格（会先清空该格）
loot replace block ~ ~ ~ container.0 loot myns:chests/food 1

# 钓鱼战利品表
loot spawn ~ ~ ~ fish minecraft:gameplay/fishing ~ mainhand
```

要点：

- `<loot_table>` 写命名空间路径，**不带 `.json`**；1.20.1 存在 `data/<ns>/loot_tables/` 下，1.21.1 在 `data/<ns>/loot_table/` 下。
- `loot replace` 的 `<limit>` 是指最多替换几个槽位，超过就继续往后找。
- `loot give` 的掉落物等同于玩家"拾取"，会正常触发拾取统计。

### 4.8 显示、音效与界面

```text
particle <name> [<pos>] [<delta>] [<speed>] [<count>] [normal|force] [<viewers>]
playsound <sound> <source> <targets> [<pos>] [<volume>] [<pitch>] [<minVolume>]
stopsound <targets> [<source>] [<sound>]
title <targets> (title <title>|subtitle <subtitle>|actionbar <actionbar>|clear|reset|times <fadeIn> <stay> <fadeOut>)
tellraw <targets> <message>
bossbar add <id> <name>
bossbar remove <id>
bossbar set <id> (players <players>|visible <visible>|value <value>|max <max>|color (blue|green|pink|purple|red|white|yellow)|style (notched_6|notched_10|notched_12|notched_20|progress)|name <name>)
bossbar get <id> (value|max|players|visible)
worldborder add <distance> [<time>]
worldborder center <pos>
worldborder damage amount <amount>
worldborder damage buffer <distance>
worldborder get
worldborder set <distance> [<time>]
worldborder warning distance <distance>
worldborder warning time <time>
```

`playsound` 的 `source` 只能是 `master`/`music`/`record`/`weather`/`block`/`hostile`/`neutral`/`player`/`ambient`/`voice`（决定玩家的音量滑条）。

```mcfunction
# 粒子：位置、扩散量、速度、数量
particle minecraft:happy_villager ~ ~1 ~ 0.3 0.3 0.3 0 10
particle minecraft:flame ~ ~ ~ 0 0 0 0.05 30 force

# 音效：声音 ID、声道、目标、位置、音量、音调
playsound minecraft:entity.experience_orb.pickup master @s ~ ~ ~ 1 1
playsound minecraft:block.note_block.bell record @a ~ ~ ~ 2 1.2
stopsound @a record

# 标题三件套
title @a times 10 40 20
title @a subtitle {"text":"副标题","color":"gray"}
title @a title {"text":"第三章","bold":true,"color":"gold"}
title @s actionbar {"text":"HP 12/20","color":"red"}
title @a clear

# 富文本
tellraw @a [{"text":"["},{"text":"系统","color":"gold"},{"text":"] 欢迎回来，","color":"white"},{"selector":"@s","color":"aqua"}]
tellraw @a {"text":"点击领取","color":"green","clickEvent":{"action":"run_command","value":"/function myns:reward"}}

# Boss 血条
bossbar add myns:raid {"text":"袭击进度","color":"red"}
bossbar set myns:raid max 100
bossbar set myns:raid value 40
bossbar set myns:raid color red
bossbar set myns:raid style notched_10
bossbar set myns:raid players @a
bossbar set myns:raid visible true
bossbar remove myns:raid

# 世界边界
worldborder center 0 0
worldborder set 200 30
worldborder add -50 60
worldborder damage amount 0.5
worldborder damage buffer 5
worldborder warning distance 10
worldborder get
```

要点：

- `bossbar` 的 `<id>` 是自定义命名空间 ID（`myns:raid`），**不是**物品或实体 ID；1.20.1 与 1.21.1 语法一致。
- `title` 的 `times` 单位是 tick，三个数是"淡入/停留/淡出"。
- `worldborder set` 是**改到**目标直径，`worldborder add` 是在当前直径上**加减**；`<time>` 单位是秒。
- `particle` 的 `<count>` 是粒子数，`<speed>` 是扩散速度；`normal` 只有附近玩家能看见，`force`（旧名 `force`/`reduced` 里现在只有 `normal|force`）对所有玩家可见。
- JSON 文本组件里 `clickEvent` 的 `run_command` 值**必须带 `/`**，这句话在函数与告示牌里都一样。

### 4.9 世界、时间、规则与数据包管理

```text
time add <time>
time query (daytime|gametime|day)
time set (day|noon|night|midnight|<time>)

weather (clear|rain|thunder) [<duration>]
difficulty [peaceful|easy|normal|hard]
gamerule <rule> [<value>]

forceload add <from> [<to>]
forceload remove <from> [<to>]
forceload query [<pos>]

spreadplayers <center> <spreadDistance> <maxRange> <respectTeams> <targets>

schedule function <function> <time> [append|replace]
schedule clear <function>
function <name> [<arguments>]

reload
datapack disable <name>
datapack enable <name> [first|last|before <existing>|after <existing>]
datapack list [available|enabled]

advancement grant <targets> <advancement>
advancement revoke <targets> <advancement>
recipe give <players> <recipe>
recipe take <players> <recipe>
xp add <targets> <amount> [points|levels]
xp set <targets> <amount> [points|levels]
xp query <targets> (points|levels)
```

`<advancement>` 可以是 `everything`，或 `only <advancement> <criterion>`；`<recipe>` 可以是 `*`（全部）。

```mcfunction
time set day
time add 1200
time query daytime

weather clear 1000
weather rain
weather thunder 300

difficulty hard
gamerule doDaylightCycle false
gamerule keepInventory true
gamerule randomTickSpeed 3
gamerule doFireTick false

forceload add ~ ~ ~16 ~16
forceload query
forceload remove ~ ~ ~16 ~16

spreadplayers 0 0 10 40 false @a

schedule function myns:tick_1s 20t append
schedule function myns:boss_spawn 5s replace
schedule clear myns:tick_1s

function myns:daily_reward
reload
datapack list
datapack disable "file/myns.zip"

advancement grant @s everything
advancement grant @s only myns:story/root first_mob
advancement revoke @a only minecraft:story/mine_diamond

recipe give @s *
recipe take @s myns:ruby_sword

xp add @s 10 levels
xp add @a 5 points
xp set @s 0 points
xp query @s levels
```

要点与版本差异：

- `gamerule` 的规则名大小写敏感：`doDaylightCycle`、`doFireTick`、`keepInventory`、`randomTickSpeed`、`doMobSpawning`、`doEntityDrops`、`mobGriefing`、`naturalRegeneration`、`doInsomnia`、`commandBlockOutput`、`logAdminCommands`、`sendCommandFeedback`。写错名字只会提示"未知规则"，不会报语法错。
- `schedule function` 的时间写法两种：`20` 是 20 tick，`20t` 也是 tick，`5s` 是 5 秒，`1d` 是 1 天。1.20.1 就支持 `s`/`d` 单位。
- `schedule` 的第三个参数 `append|replace` 决定同名函数已有任务时是排队还是替换；**1.20.1 就有**。
- **`random` 命令是 1.20.2 才加入的，1.20.1 没有**。1.21.1 用法：`random value <range> [<sequence>]`（返回一个值到 `execute store`）与 `random roll <range> [<sequence>]`（只发随机数结果到聊天栏）。`<range>` 写 `1..6` 或 `5`。
- `datapack enable` 的 `<name>` 是 `datapack list` 输出的名字，通常形如 `file/myns`（文件夹）或 `file/myns.zip`；带斜杠或空格时用引号。
- `spreadplayers` 的 `respectTeams` 是布尔：`true` 保证同队玩家不被拆开；`<spreadDistance>` 是玩家间最小间距，`<maxRange>` 是离中心的最大半径。

## 5. 目标选择器（Target Selectors）

### 5.1 六个选择器变量

| 变量 | 选中谁 | 备注 |
| --- | --- | --- |
| `@p` | 最近的玩家 | 从命令执行位置算距离 |
| `@r` | 随机一名玩家 | 配合 `type=` 可随机非玩家实体，但不推荐 |
| `@a` | 所有存活的玩家 | 已死亡但未重生的玩家不算 |
| `@e` | 所有已加载的实体 | **性能最差**，必须配 `type=` 或距离限制 |
| `@s` | 执行者自己 | 若执行者是命令方块/服务器，则什么都选不到 |
| `@n` | 最近的实体 | **1.21（24w21a）加入，1.20.1 没有**；就是"最近的实体"，包含非玩家 |

历史提示：`@n` 之前，取"最近的实体"要用 `@e[sort=nearest,limit=1]`。

### 5.2 参数总表（Java 版）

| 参数 | 写法 | 含义 |
| --- | --- | --- |
| `x` `y` `z` | `x=10,y=64,z=-20` | 改变"距离计算原点"，**不会**改变命令执行位置 |
| `distance` | `distance=..5`、`distance=3..10` | 球壳距离范围（省略 `x/y/z` 时以执行位置为原点） |
| `dx` `dy` `dz` | `dx=5,dy=3,dz=5` | 以 `x/y/z` 为起点的长方体体积；只写 `dx` 就是沿 x 的线段 |
| `type` | `type=minecraft:zombie`、`type=!minecraft:player`、`type=#minecraft:raiders` | 实体类型，支持反选与标签 |
| `name` | `name=Steve`、`name=!Steve` | 实体显示名（自定义名），不支持通配符 |
| `tag` | `tag=quest_started`、`tag=!done` | 实体 `Tags` 列表成员，可重复写多个（同时满足） |
| `team` | `team=red`、`team=!red` | 队伍名；`team=`（空）表示无队伍 |
| `gamemode` | `gamemode=creative`、`gamemode=!survival` | 仅玩家 |
| `level` | `level=10`、`level=30..` | 仅玩家，经验等级 |
| `limit` | `limit=3`、`limit=-2` | 取前 N 个；**负数表示"排除前 N 个"** |
| `sort` | `sort=nearest`、`sort=furthest`、`sort=random`、`sort=arbitrary` | 排序方式，默认 `arbitrary` |
| `scores` | `scores={kills=5,deaths=0..3}` | 计分板分数范围，多个键是"与" |
| `nbt` | `nbt={OnGround:1b}`、`nbt=!{NoAI:1b}` | 实体 NBT 匹配 |
| `predicate` | `predicate=myns:is_day` | 数据包谓词 |
| `advancements` | `advancements={minecraft:story/root=true}` | 玩家进度是否完成；`{...=false}` 表示未完成 |
| `x_rotation` | `x_rotation=0..90` | 俯仰角范围，**Java 1.13 起就是这个名字** |
| `y_rotation` | `y_rotation=-45..45` | 偏航角范围（-180..180，南方为 0） |

```mcfunction
# 最近的玩家
say @p 你好

# 10 格内的所有僵尸
execute as @e[type=minecraft:zombie,distance=..10] run say 发现僵尸

# 半径 5 到 15 球壳内的所有实体，按最近排序取 1 个
execute as @e[distance=5..15,sort=nearest,limit=1] run tp @s ~ ~10 ~

# 队伍为 red 且分数 kills>=5 的玩家
give @a[team=red,scores={kills=5..}] minecraft:diamond

# 反选：不是玩家、不是掉落物
kill @e[type=!minecraft:player,type=!minecraft:item]

# 类型标签（标签在 data/minecraft/tags/entity_type/ 里定义）
execute as @e[type=#minecraft:raiders] run say 袭击者

# 只选主世界玩家（1.19.4+ 可以用 execute in 过滤维度，选择器本身没有维度参数）
execute in minecraft:overworld as @a run say 在主世界

# 带自定义名或标签的实体
execute as @e[tag=quest_npc,name="Bob"] run say 找到 Bob

# NBT 过滤：站地上的僵尸
execute as @e[type=minecraft:zombie,nbt={OnGround:1b}] run say 落地僵尸

# 进度过滤：完成过石头的玩家
tellraw @a[advancements={minecraft:story/mine_stone=true}] {"text":"你挖过石头"}

# 谓词过滤
execute as @a[predicate=myns:in_raid] run effect give @s minecraft:regeneration 5 1 true

# 视角过滤
execute as @a[x_rotation=45..90] run say 你在低头
```

### 5.3 语义细节（踩坑高发区）

- **`limit` 与 `sort` 的组合**：先按 `sort` 排序，再取 `limit`。写 `limit=1` 而不写 `sort`，`sort` 默认 `arbitrary`——结果"看起来随机"，**必须显式写 `sort=nearest`** 才能稳定取最近那个。
- **`limit` 为负**：`limit=-1` 表示"排除排序后的前 1 个"，常用于 `@a[limit=-1]`（除自己外的所有玩家，但要配合 `sort`）。
- **`dx/dy/dz` 是体积不是距离**：`dx=5` 且不写 `dy/dz` 时是 x 方向 5 格的线段；想选方块范围必须写全三个。
- **`x/y/z` 只改距离原点**：`@e[x=10,y=64,z=10,distance=..5]` 里命令仍在执行者所在位置运行，但距离按 (10,64,10) 算。
- **`nbt` 只匹配实体自身 NBT**：不能用来匹配背包里的物品；匹配物品用 `predicate` 或 `execute if items`。
- **选择器没有 `items`/`hasitem` 参数**：Java 版判物品用 `execute if items`（1.20.5+）或自定义 `predicate`；`hasitem` 是基岩版的。
- **`@e` 必须带 `type=` 或体积/距离限制**：全图 `@e` 每 tick 执行会严重掉 TPS，1.21.1 里实体多的存档能直接卡死。
- **`name=` 区分大小写且匹配显示名**：给实体 `CustomName` 后再用 `name=`，不是匹配实体类型名。
- **`@s` 在函数里依赖上下文**：由 `execute as ... run function ...` 进入的上下文里 `@s` 才是那个实体；直接 `/function` 手动跑时 `@s` 是执行命令的玩家。

## 6. SNBT 与 NBT 结构

### 6.1 SNBT 类型后缀

命令里写的不是二进制 NBT，而是 **SNBT**（Stringified NBT）。数字的类型**由后缀决定**，少了后缀就是 `int`。

| 类型 | 写法 | 说明 |
| --- | --- | --- |
| Byte | `1b`、`-5b`、`1B` | 小写 `b`/大写 `B` 都行 |
| Short | `1s`、`1S` | |
| Int | `1`、`-200` | **不带后缀**，默认就是它 |
| Long | `1L`、`1l` | `L` 必须大写或小写 `l`（小写易看成 1，建议大写） |
| Float | `1.5f`、`1.5F` | |
| Double | `1.5d`、`1.5` | 带小数点且无后缀即为 double |
| String | `"abc"` 或 `'abc'` | 双引号/单引号等价，见 6.2 |
| List | `[1,2,3]`、`["a","b"]` | 元素类型必须一致 |
| Compound | `{k:v, k2:v2}` | |
| ByteArray | `[B;1b,2b]` | 分号紧跟在 `B` 后 |
| IntArray | `[I;1,2,3]` | |
| LongArray | `[L;1L,2L]` | |
| 布尔 | `1b` / `0b` | NBT 没有 bool，布尔就是 byte |

```mcfunction
# 全部类型各来一个
data merge storage myns:test {b:1b,s:1s,i:1,l:1L,f:1.5f,d:1.5d,str:"hi",list:[1,2,3],arr:[I;1,2,3],flag:1b}

# 类型写错的典型例子：
# {Count:1}   -> 写成了 int，而 1.20.1 的 Count 要求 byte，会报错
# {Count:1b}  -> 正确
```

### 6.2 字符串与转义

- 双引号字符串里：`\"` 表示引号、`\\` 表示反斜杠。**没有** `\n`（SNBT 字符串不能含换行）。
- 单引号字符串里：`\'` 表示单引号、`\\` 表示反斜杠。
- JSON 文本组件本身含大量双引号，所以放进 SNBT 时**外层用单引号**最省事：

```mcfunction
give @s minecraft:paper{display:{Name:'{"text":"卷轴","color":"yellow"}'}}
```

- 中文、空格在双引号/单引号里都不需要额外处理；但**不加引号**的字符串只能含 `[a-zA-Z0-9._+-]`，所以键名/枚举值一般不加引号。

### 6.3 物品 NBT：1.20.1 与 1.21.1

先分清两种场合，很多"写错 NBT"其实是用错了场合：

**A. 命令里的物品参数**（`give`/`item`/`setblock` 里的 `<item>`）——1.20.1 直接写 `物品ID{<tag 内容>}`，**没有 `tag:` 外壳**：

```mcfunction
give @s minecraft:diamond_sword{display:{Name:'{"text":"Excalibur","color":"gold"}',Lore:['{"text":"第一行"}','{"text":"第二行"}']},Enchantments:[{id:"minecraft:sharpness",lvl:5}],Unbreakable:1b}
give @s minecraft:paper{display:{Name:'{"text":"卷轴"}'}}
```

**B. 嵌在别的 NBT 里的物品**（箱子 `Items`、实体 `HandItems`、漏斗等）——这里是完整的"物品栈"结构：`id` + `Count` + `tag`：

```mcfunction
setblock ~ ~ ~ minecraft:chest{Items:[{Slot:0b,id:"minecraft:diamond",Count:3b},{Slot:1b,id:"minecraft:golden_apple",Count:1b,tag:{display:{Name:'{"text":"金苹果"}'}}}]} replace
summon minecraft:zombie ~ ~ ~ {HandItems:[{id:"minecraft:iron_sword",Count:1b,tag:{Enchantments:[{id:"minecraft:sharpness",lvl:3}]}},{}]}
```

**1.21.1 的同一件事**（`tag` 被 `components` 取代，`Count` 变成小写 `count`，且**不带 `b` 后缀**，因为它是 int）：

```mcfunction
# 命令里的物品参数：方括号组件语法
give @s minecraft:diamond_sword[custom_name='{"text":"Excalibur","color":"gold"}',lore=['{"text":"第一行"}','{"text":"第二行"}'],enchantments={levels:{"minecraft:sharpness":5}},unbreakable={}]

# 嵌在 NBT 里的物品栈
setblock ~ ~ ~ minecraft:chest{Items:[{slot:0,item:{id:"minecraft:diamond",count:3}},{slot:1,item:{id:"minecraft:golden_apple",count:1,components:{"minecraft:custom_name":'{"text":"金苹果"}'}}}]} replace
summon minecraft:zombie ~ ~ ~ {HandItems:[{id:"minecraft:iron_sword",count:1,components:{"minecraft:enchantments":{levels:{"minecraft:sharpness":3}}}},{}]}
```

对照表：

| 1.20.1 | 1.21.1 | 说明 |
| --- | --- | --- |
| 物品 ID + `{tag 内容}` | 物品 ID + `[组件]` | 命令参数 |
| `Count:2b` | `count:2` | 小写、int、无后缀 |
| `tag:{...}` | `components:{...}` | 嵌在 NBT 里时 |
| `display:{Name:...}` | `minecraft:custom_name` | 组件 |
| `display:{Lore:[...]}` | `minecraft:lore` | 组件 |
| `Enchantments:[{id,lvl}]` | `minecraft:enchantments={levels:{id:lvl}}` | 键值改成 map |
| `AttributeModifiers:[...]` | `minecraft:attribute_modifiers={modifiers:[...]}` | |
| `Unbreakable:1b` | `minecraft:unbreakable={}` | 1.21.1 里是空复合标签 |
| `HideFlags:63` | 各组件自带的 `show_in_tooltip` | `HideFlags` 已删除 |
| 无 | `minecraft:item_name` / `minecraft:rarity` / `minecraft:tool` | 新增 |

注意：箱子 `Items` 里的槽位键在 1.20.1 是 `Slot:0b`（大写 S、Byte），在 1.21.1 是 `slot:0`（小写、int），并且外层多了 `item:{}`——这是 1.20.5 引入 `minecraft:container` 组件时一起改的，**两版写法不能混**。

### 6.4 实体 NBT 常用键

以下键 1.20.1 与 1.21.1 共通（大小写敏感）：

| 键 | 类型 | 含义 |
| --- | --- | --- |
| `Pos` | double list[3] | 绝对坐标 |
| `Motion` | double list[3] | 速度向量，单位 格/tick |
| `Rotation` | float list[2] | `[yaw, pitch]` |
| `OnGround` | byte | 是否在地面 |
| `NoGravity` | byte | 不受重力/漂浮 |
| `Invulnerable` | byte | 免疫伤害（仍会被虚空/`kill` 干掉） |
| `Silent` | byte | 不发声 |
| `NoAI` | byte | 停掉 AI（怪物不动、不攻击） |
| `Glowing` | byte | 发光轮廓（队伍颜色） |
| `Tags` | string list | 自定义标签，供 `tag=` 选择器 |
| `CustomName` | string（内含 JSON） | 显示名，**值本身是 JSON 字符串** |
| `CustomNameVisible` | byte | 名字始终可见 |
| `PersistenceRequired` | byte | 不自然消失 |
| `Health` | float | 当前血量 |
| `FallDistance` | float | 下落距离 |
| `Fire` | short | 剩余燃烧 tick |
| `Air` | short | 剩余氧气 tick |
| `HandItems` / `ArmorItems` | 物品栈 list | 主/副手、四件盔甲（**1.21.5 起合并成 `equipment`**） |
| `HandDropChances` / `ArmorDropChances` | float list | 掉落概率 |
| `attributes` / `Attributes` | 复合标签 list | 属性修正，**两版键名与内部字段有差异，见下方警告** |
| `DeathLootTable` | string | 死亡掉落表 ID |
| `DeathLootTableSeed` | long | 掉落表随机种子 |
| `ActiveEffects` | 复合标签 list | 药水效果（`{Id:1b,Amplifier:0b,Duration:200,ShowParticles:1b}`） |

```mcfunction
# 生成一个只会站着挨打的假人（自定义名 + 标签 + 无重力 + 不消失）
summon minecraft:armor_stand ~ ~ ~ {CustomName:'{"text":"训练假人","color":"gray"}',CustomNameVisible:1b,Tags:["training_dummy"],NoGravity:1b,Invulnerable:1b,PersistenceRequired:1b,Marker:0b}

# 生成一只静止的僵尸，手里拿剑
summon minecraft:zombie ~ ~ ~ {NoAI:1b,Tags:["demo_mob"],HandItems:[{id:"minecraft:iron_sword",Count:1b},{}],PersistenceRequired:1b}

# 修改现有实体的 NBT
data merge entity @e[type=minecraft:zombie,limit=1,sort=nearest] {NoAI:1b,CustomName:'{"text":"标本"}'}

# 读一个键
data get entity @s Pos
data get entity @s Health
```

**属性 NBT 的版本警告**：1.20.1 的属性修正是 `Attributes:[{Name:"minecraft:generic.max_health",Base:20.0d,Modifiers:[...]}]`；从 1.21 起属性相关 NBT 的键名被统一成小写并调整了内部结构，**不要直接把 1.20.1 的 `Attributes`/`Name`/`Base` 抄到 1.21.1**。写之前先用 `data get entity @e[type=minecraft:zombie,limit=1]` 打印一只同类实体的真实结构，照着改。

**`equipment` 不要乱用**：`HandItems`/`ArmorItems`/`body_armor_item` 是在 **1.21.5（25w03a）** 才合并为 `equipment` 的。1.20.1 与 1.21.1 都必须用 `HandItems`/`ArmorItems`。

## 7. 1.21.1 物品组件（Data Components）

### 7.1 语法位置

组件出现在两个地方，写法不同：

1. **命令的物品参数**（`item_stack`）：`物品ID[组件=值,组件=值]`。组件 ID 的命名空间可省略（`custom_name` 等同于 `minecraft:custom_name`），值是 SNBT。
2. **NBT 里的物品栈**：`{id:"...",count:1,components:{"minecraft:custom_name":'...'}}`。这里组件 ID **必须写全**（带 `minecraft:`），且因为键含冒号必须加引号。

要在物品谓词（`clear`、`execute if items`）里测试组件，用 `物品ID[组件]`（存在）、`物品ID[!组件]`（不存在）、`物品ID[组件=值]`（精确匹配）。

### 7.2 常用组件速查（1.21.1）

| 组件 | 值 | 作用 | 1.20.1 对应 |
| --- | --- | --- | --- |
| `custom_name` | 文本组件（JSON 字符串） | 自定义名，**可在铁砧上改名** | `display.Name` |
| `item_name` | 文本组件 | 默认名，改名后仍显示 | 无 |
| `lore` | 文本组件列表 |  lore 行 | `display.Lore` |
| `enchantments` | `{levels:{附魔:等级},show_in_tooltip:bool}` | 附魔，影响实际效果 | `Enchantments` |
| `stored_enchantments` | 同 `enchantments` | 存进附魔书的附魔 | `StoredEnchantments` |
| `attribute_modifiers` | `{modifiers:[{type,id,amount,operation,slot}],show:bool}` | 属性修正 | `AttributeModifiers` |
| `custom_model_data` | int（1.21.1） | 资源包模型选择 | `CustomModelData` |
| `unbreakable` | `{}`（1.21.1 是空复合标签） | 不可损坏 | `Unbreakable:1b` |
| `damage` | int | 已损失耐久 | `Damage` |
| `max_damage` | int | 最大耐久 | 无 |
| `max_stack_size` | int（1..99） | 最大堆叠 | 无 |
| `rarity` | `common`/`uncommon`/`rare`/`epic` | 稀有度（名字颜色） | `display` 里靠颜色凑 |
| `food` | `{nutrition,saturation,can_always_eat,eat_seconds}` | 可食用 | 只有原版食物能吃 |
| `tool` | `{rules:[...],default_mining_speed,damage_per_block}` | 挖掘速度与可挖方块 | 无 |
| `can_break` | 方块谓词列表 | 冒险模式可破坏 | `CanDestroy` |
| `can_place_on` | 方块谓词列表 | 冒险模式可放置 | `CanPlaceOn` |
| `container` | `[{slot:0,item:{id,count}}]` | 潜影盒/桶内的内容物 | `BlockEntityTag.Items` |
| `profile` | `{name,id,properties}` 或玩家名 | 头颅皮肤 | `SkullOwner` |
| `dyed_color` | `{rgb:int}`（1.21.1） | 皮甲/皮革染色 | `display.color` |
| `map_id` | int | 地图编号 | `map` |
| `fireworks` | `{flight_duration,explosions:[...]}` | 烟花参数 | `Fireworks` |
| `banner_patterns` | `[{pattern,color}]` | 旗帜图案 | `BlockEntityTag.Patterns` |
| `base_color` | 染料颜色名 | 盾牌/旗帜底色 | `BlockEntityTag.Base` |
| `trim` | `{pattern,材料}` | 盔甲纹饰 | `Trim` |
| `potion_contents` | `{potion:"..."}` 或 `{custom_effects:[...]}` | 药水内容 | `Potion`/`CustomPotionEffects` |
| `writable_book_content` | `{pages:[...]}` | 书与笔内容 | `pages` |
| `written_book_content` | `{pages:[...],title,author}` | 成书内容 | `title`/`author`/`pages` |
| `note_block_sound` | 音效 ID | 头颅放置时的音符盒音色 | 无 |

### 7.3 完整示例

```mcfunction
# 一把"史诗剑"：自定义名 + lore + 附魔 + 属性 + 不可损坏 + 模型数据
give @s minecraft:diamond_sword[custom_name='{"text":"逐暗者","color":"gold","italic":false}',lore=['{"text":"第一把亲手铸的剑","color":"gray","italic":false}'],enchantments={levels:{"minecraft:sharpness":5,"minecraft:unbreaking":3},show_in_tooltip:true},attribute_modifiers={modifiers:[{type:"minecraft:generic.attack_damage",id:"myns:blade_bonus",amount:2.0,operation:"add_value",slot:"mainhand"}],show:true},unbreakable={},custom_model_data=7]

# 带耐久损耗与最大堆叠
give @s minecraft:diamond_pickaxe[damage=120,max_damage=1561,rarity="epic"]

# 一摞只能堆 16 个的物品
give @s minecraft:ender_pearl[max_stack_size=16]

# 冒险模式可挖/可放（1.21.1 写法：外层 predicates）
give @s minecraft:stone_pickaxe[can_break={predicates:[{blocks:"minecraft:diamond_ore"}]}]
give @s minecraft:oak_planks[can_place_on={predicates:[{blocks:"minecraft:sandstone"}]}]

# 食物：4 点饥饿、0.3 饱和度、随时可吃、1.6 秒吃完
give @s minecraft:cookie[food={nutrition:4,saturation:0.3,can_always_eat:true,eat_seconds:1.6}]

# 自定义工具：对所有镐可挖方块速度 1.2，不挖掘伤害
give @s minecraft:stick[tool={rules:[{blocks:"#minecraft:mineable/pickaxe",speed:1.2,correct_for_drops:true}],default_mining_speed:1.0,damage_per_block:1}]

# 潜影盒预装物品（container 组件）
give @s minecraft:shulker_box[container=[{slot:0,item:{id:"minecraft:diamond",count:3}},{slot:1,item:{id:"minecraft:bread",count:5}}]]

# 玩家头颅（皮肤名）
give @s minecraft:player_head[profile={name:"Notch"}]

# 染色皮甲
give @s minecraft:leather_chestplate[dyed_color={rgb:16711680},custom_name='"红皮甲"']

# 带纹饰的盔甲
give @s minecraft:diamond_chestplate[trim={pattern:"coast",material:"gold"}]

# 药水
give @s minecraft:potion[potion_contents={potion:"minecraft:strong_healing"}]

# 书与笔 / 成书
give @s minecraft:writable_book[writable_book_content={pages:["第一页","第二页"]}]
give @s minecraft:written_book[written_book_content={pages:["第一章","第二章"],title:"野外笔记",author:"Steve"}]

# 旗帜图案
give @s minecraft:black_banner[banner_patterns=[{pattern:"triangle_top",color:"red"},{pattern:"cross",color:"white"}]]

# 测试组件（用于 clear / execute if items）
clear @s minecraft:diamond_sword[custom_name]
execute if items entity @s weapon.mainhand minecraft:diamond_sword[enchantments] run say 这把剑有附魔
execute if items entity @s weapon.mainhand minecraft:diamond_sword[!unbreakable] run say 这把剑能坏
```

### 7.4 与 1.20.1 `{tag:{...}}` 的逐项对照

| 需求 | 1.20.1 | 1.21.1 |
| --- | --- | --- |
| 自定义名 | `{display:{Name:'{"text":"剑"}'}}` | `[custom_name='{"text":"剑"}']` |
| Lore | `{display:{Lore:['{"text":"a"}']}}` | `[lore=['{"text":"a"}']]` |
| 附魔 | `{Enchantments:[{id:"minecraft:sharpness",lvl:5}]}` | `[enchantments={levels:{"minecraft:sharpness":5}}]` |
| 附魔书 | `{StoredEnchantments:[...]}` | `[stored_enchantments={levels:{...}}]` |
| 属性 | `{AttributeModifiers:[{AttributeName:"generic.attack_damage",Amount:2.0,Operation:0,UUID:[I;...],Slot:"mainhand"}]}` | `[attribute_modifiers={modifiers:[{type:"minecraft:generic.attack_damage",amount:2.0,operation:"add_value",slot:"mainhand",id:"myns:xxx"}]}]` |
| 不掉耐久 | `{Unbreakable:1b}` | `[unbreakable={}]` |
| 已损耗 | `{Damage:120}` | `[damage=120]` |
| 模型数据 | `{CustomModelData:7}` | `[custom_model_data=7]` |
| 可破坏 | `{CanDestroy:["minecraft:diamond_ore"]}` | `[can_break={predicates:[{blocks:"minecraft:diamond_ore"}]}]` |
| 可放置 | `{CanPlaceOn:["minecraft:sandstone"]}` | `[can_place_on={predicates:[{blocks:"minecraft:sandstone"}]}]` |
| 隐藏提示 | `{HideFlags:63}` | 各组件自带 `show_in_tooltip:false` |
| 容器内容 | `{BlockEntityTag:{Items:[{Slot:0b,id:"minecraft:diamond",Count:3b}]}}` | `[container=[{slot:0,item:{id:"minecraft:diamond",count:3}}]]` |
| 头颅皮肤 | `{SkullOwner:"Notch"}` | `[profile={name:"Notch"}]` |
| 药水 | `{Potion:"minecraft:healing"}` | `[potion_contents={potion:"minecraft:healing"}]` |
| 书页 | `{pages:["a","b"],title:"t",author:"a"}` | `[written_book_content={pages:["a","b"],title:"t",author:"a"}]` |

### 7.5 组件的几个硬规则

- **组件 ID 大小写全小写**：`CustomName` 是错的，`custom_name` 才对。
- **`components` 是唯一入口**：嵌在 NBT 里不能再写 `tag:{}`；写了 `tag` 的物品在 1.20.5+ 会被判为无效物品（放不下、读不出）。
- **删除/清空组件**：命令参数里写不存在组件即不添加；要在数据包层面"删掉某组件"可以用 `item modify` 配合 `minecraft:remove_custom_data` 之类的物品修饰器，或用 `data remove` 删 `components."minecraft:xxx"`。
- **`count` 与 `Count`**：命令参数里不写数量（数量是 `give` 的 `<count>`）；NBT 里 1.20.1 是 `Count:1b`，1.21.1 是 `count:1`。
- **`custom_model_data` 是 int**：1.21.1 里就是 `custom_model_data=7`；1.21.4 起变成 `{floats:[...],strings:[...],colors:[...]}` 复合标签，别把新写法套到 1.21.1 上。
- **`unbreakable` 是 `{}` 不是 `1b`**：1.21.1 里写成 `unbreakable={}`；1.21.5 起才又变回布尔。
- **`can_break`/`can_place_on` 的层数**：1.21.1 需要外层 `predicates`；如果你用的版本报"结构不符"，说明该版本已简化为 `{blocks:[...]}`，改成 `can_break={blocks:["minecraft:diamond_ore"]}` 即可。
- **`food` 的 `eat_seconds` 在 1.21.1 里属于 `food`**；1.21.5 起被拆到 `consumable` 组件，`food` 只剩营养值三件套。

## 8. 常用数据包 JSON

所有 JSON 都是**严格 JSON**（不能有注释、不能有尾逗号），根节点必须是对象或数组；文件路径即注册名，**不写 `.json` 后缀**去引用。

### 8.1 配方 `recipe`

**有序合成**（2×2，四个铁锭合成铁块）：

```json
{
  "type": "minecraft:crafting_shaped",
  "pattern": [
    "XX",
    "XX"
  ],
  "key": {
    "X": {
      "item": "minecraft:iron_ingot"
    }
  },
  "result": {
    "item": "minecraft:iron_block",
    "count": 1
  }
}
```

`pattern` 里每个字符都要在 `key` 里有对应项；空格表示空位；`pattern` 最多 3 行、每行最多 3 字符。

**无序合成**：

```json
{
  "type": "minecraft:crafting_shapeless",
  "ingredients": [
    { "item": "minecraft:iron_block" },
    { "item": "minecraft:flint" }
  ],
  "result": {
    "item": "minecraft:flint_and_steel",
    "count": 1
  }
}
```

**熔炉 / 高炉 / 烟熏炉 / 营火**：

```json
{
  "type": "minecraft:smelting",
  "ingredient": { "item": "minecraft:raw_iron" },
  "result": "minecraft:iron_ingot",
  "experience": 0.7,
  "cookingtime": 200
}
```

把 `smelting` 换成 `blasting`（高炉）、`smoking`（烟熏炉）、`campfire_cooking`（营火）即可；`cookingtime` 是 tick。

**切石机**：

```json
{
  "type": "minecraft:stonecutting",
  "ingredient": { "item": "minecraft:stone" },
  "result": "minecraft:stone_stairs",
  "count": 1
}
```

**锻造台（1.20 起的两种）**：

```json
{
  "type": "minecraft:smithing_transform",
  "template": { "item": "minecraft:netherite_upgrade_smithing_template" },
  "base": { "item": "minecraft:diamond_sword" },
  "addition": { "item": "minecraft:netherite_ingot" },
  "result": {
    "item": "minecraft:netherite_sword"
  }
}
```

```json
{
  "type": "minecraft:smithing_trim",
  "template": { "item": "minecraft:coast_armor_trim_smithing_template" },
  "base": { "item": "minecraft:diamond_chestplate" },
  "addition": { "item": "minecraft:gold_ingot" }
}
```

要点：

- 1.20.1 与 1.21.1 的配方 JSON **结构基本一致**；1.21.1 额外允许把 `{"item":"minecraft:iron_ingot"}` 简写成 `"minecraft:iron_ingot"`（1.21.2 起才全面简写，1.21.1 保守起见仍写对象形式）。
- `tag` 作为材料：`{ "tag": "minecraft:planks" }`，标签必须存在，否则加载报错。
- 1.20.1 放在 `data/<ns>/recipes/`，1.21.1 放在 `data/<ns>/recipe/`。
- 配方名冲突会覆盖原版配方（同 ID）；新增配方推荐用自己命名空间。

### 8.2 战利品表 `loot_table`

```json
{
  "type": "minecraft:chest",
  "pools": [
    {
      "rolls": 1,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:diamond",
          "weight": 1,
          "functions": [
            {
              "function": "minecraft:set_count",
              "count": { "min": 1, "max": 3 }
            }
          ]
        },
        {
          "type": "minecraft:item",
          "name": "minecraft:bread",
          "weight": 5,
          "functions": [
            { "function": "minecraft:set_count", "count": 4 }
          ]
        }
      ]
    }
  ]
}
```

- `type` 可选 `minecraft:generic`（默认）、`chest`、`entity`、`fishing`、`advancement_reward`、`gift`、`empty` 等，决定随机种子行为。
- `rolls` 可写整数，也可写 `{ "min": 1, "max": 3 }`。
- 常用函数：`set_count`、`set_name`（`"name": '{"text":"..."}'`）、`set_nbt`（1.20.1）/`set_components`（1.20.5+）、`enchant_randomly`、`enchant_with_levels`、`looting_enchant`、`set_loot_table`。
- `"name"` 在 1.20.1 可用 `{"item":"minecraft:diamond"}` 或字符串；写成 `{ "name": "minecraft:diamond" }` 也行。

### 8.3 进度 `advancement`

```json
{
  "display": {
    "icon": { "item": "minecraft:diamond" },
    "title": "第一颗钻石",
    "description": "挖到第一颗钻石",
    "frame": "task",
    "show_toast": true,
    "announce_to_chat": true,
    "hidden": false
  },
  "criteria": {
    "got_diamond": {
      "trigger": "minecraft:inventory_changed",
      "conditions": {
        "items": [
          { "items": [ "minecraft:diamond" ] }
        ]
      }
    }
  },
  "requirements": [
    [ "got_diamond" ]
  ]
}
```

- `frame` 三选一：`task`、`goal`、`challenge`。
- `criteria` 的键名任意，`requirements` 用"或/与"组合（外层数组是"或"，内层是"与"）；不写 `requirements` 则要求全部完成。
- `parent` 指向父进度（如 `"minecraft:story/root"`），不写就是根进度；根进度建议加 `"background": "minecraft:textures/block/stone.png"`。
- 常用触发器：`minecraft:inventory_changed`、`minecraft:player_killed_entity`、`minecraft:location`、`minecraft:tick`、`minecraft:impossible`（只能由 `/advancement grant` 触发）。
- 1.20.1 与 1.21.1 格式相同，只是目录 `advancements/` → `advancement/`。

### 8.4 谓词 `predicate`

```json
{
  "condition": "minecraft:entity_properties",
  "entity": "this",
  "predicate": {
    "type": "minecraft:player",
    "nbt": "{Tags:[\"in_raid\"]}"
  }
}
```

- 谓词就是一个 `{"condition": ...}` 对象，返回真假；多条判断用 `minecraft:all_of` / `minecraft:any_of` 的 `terms` 数组组合。
- 常用条件：`minecraft:entity_properties`、`minecraft:entity_scores`、`minecraft:location_check`、`minecraft:random_chance`（`{"chance": 0.3}`）、`minecraft:inverted`、`minecraft:all_of`、`minecraft:any_of`、`minecraft:time_check`、`minecraft:weather_check`。
- 用在选择器 `predicate=myns:xxx` 与 `execute if predicate myns:xxx` 里，值是路径，不带 `.json`。

### 8.5 物品修饰器 `item_modifier`

文件内容可以是一个函数对象，也可以是函数数组：

```json
[
  {
    "function": "minecraft:set_components",
    "components": {
      "minecraft:custom_model_data": 8
    }
  },
  {
    "function": "minecraft:set_count",
    "count": 3
  }
]
```

```json
{
  "function": "minecraft:set_components",
  "components": {
    "minecraft:custom_name": { "text": "强化剑", "color": "aqua" }
  }
}
```

- 1.20.1 用 `minecraft:set_nbt`（`"tag": "{CustomModelData:8}"`）+ `minecraft:set_name`（`"name": "{\"text\":\"强化剑\"}"`）；1.20.5+ 用 `minecraft:set_components`，`custom_name` 的值可以直接写文本组件对象。
- `item modify entity @s weapon.mainhand myns:add_ruby` 就是调用 `data/myns/item_modifier/add_ruby.json`（1.20.1 是 `item_modifiers/`）。

### 8.6 标签 `tags`

```json
{
  "values": [
    "minecraft:stone",
    "minecraft:deepslate",
    "myns:ruby_ore"
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

- 引用别的标签要在前面加 `#`：`"#minecraft:planks"`。
- `"replace": true` 表示**替换**原版同名标签内容（危险，会顶掉原版数据），默认 `false` 是"追加"。
- 1.20.1 路径 `data/<ns>/tags/items/ruby_ores.json`，1.21.1 是 `data/<ns>/tags/item/ruby_ores.json`；`blocks`→`block`、`entity_types`→`entity_type`、`functions`→`function` 同理。

### 8.7 维度与维度类型（最小可用示例）

`data/myns/dimension_type/overworld_like.json`：

```json
{
  "ultrawarm": false,
  "natural": true,
  "piglin_safe": false,
  "respawn_anchor_works": false,
  "bed_works": true,
  "has_raids": true,
  "has_skylight": true,
  "has_ceiling": false,
  "coordinate_scale": 1.0,
  "ambient_light": 0.0,
  "logical_height": 384,
  "min_y": -64,
  "height": 384,
  "infiniburn": "#minecraft:infiniburn_overworld",
  "effects": "minecraft:overworld",
  "monster_spawn_light_level": 0,
  "monster_spawn_block_light_limit": 0
}
```

`data/myns/dimension/overworld_like.json`：

```json
{
  "type": "myns:overworld_like",
  "generator": {
    "type": "minecraft:noise",
    "settings": "minecraft:overworld",
    "biome_source": {
      "type": "minecraft:multi_noise",
      "preset": "minecraft:overworld"
    }
  }
}
```

要点：

- 这两个文件在 1.20.1 与 1.21.1 **目录名都是单数**（`dimension/`、`dimension_type/`），从 1.16 起就是这样，两版一致。
- `height` 与 `min_y` 必须匹配：`min_y >= -2032`、`height` 是 16 的倍数，且 `min_y + height <= 2032`；`logical_height` 不能超过 `height`。
- `dimension` 的 `type` 必须指向已存在的 dimension_type ID。
- 维度文件本身不需要额外注册；用 `/execute in myns:overworld_like run ...` 或 `/tp` 里写 `myns:overworld_like` 就能验证是否加载成功。

## 9. 初始化模式与全局变量

### 9.1 标准三件套结构

```
data/myns/function/
├── init.mcfunction        # 首次加载时执行一次（初始化）
├── load.mcfunction        # 每次 reload 都执行（幂等操作）
└── tick.mcfunction        # 每 tick 执行（要有节流）
```

`data/minecraft/tags/function/load.json`：

```json
{
  "values": [
    "myns:load"
  ]
}
```

`data/myns/function/load.mcfunction`：

```mcfunction
# 幂等：重复执行不会报错、不会叠加
scoreboard objectives add myns.data dummy
scoreboard objectives add myns.timer dummy
scoreboard players set #const myns.data 0
scoreboard players set #tick myns.timer 0

# 只做一次的重活放到 init，靠一个标记位判断
execute unless score #initialized myns.data matches 1 run function myns:init
```

`data/myns/function/init.mcfunction`：

```mcfunction
# 首次初始化：只在第一次 load 时跑
gamerule doDaylightCycle true
gamerule keepInventory true
forceload add ~ ~ ~32 ~32
bossbar add myns:main {"text":"进度"}
bossbar set myns:main max 10
data merge storage myns:vars {initialized:1b,count:0,last_player:""}
scoreboard players set #initialized myns.data 1
tellraw @a {"text":"[myns] 数据包已初始化","color":"green"}
```

### 9.2 `#tick` 的节流写法

每 tick 都跑重逻辑会掉 TPS。用"计数器 + `matches` 判断"最简单：

`data/myns/function/tick.mcfunction`：

```mcfunction
# 每 tick 自增，到 20 就归零并执行"每秒逻辑"
scoreboard players add #tick myns.timer 1
execute if score #tick myns.timer matches 20.. run function myns:second
execute if score #tick myns.timer matches 5 run function myns:fast
```

`matches 5` 只在计数正好为 5 的那一 tick 成立；写成 `matches 5..` 则会从 5 开始每 tick 都触发——这是最常见的节流失效原因。

`data/myns/function/second.mcfunction`：

```mcfunction
scoreboard players set #tick myns.timer 0
execute as @a at @s run function myns:player_tick
```

如果不想占 tick 标签，改用 `schedule` 自循环做定时：

```mcfunction
# 在 load.mcfunction 里启动
schedule function myns:tick_1s 20t replace
```

`data/myns/function/tick_1s.mcfunction`：

```mcfunction
execute as @a at @s run function myns:player_tick
schedule function myns:tick_1s 20t replace
```

`schedule` 自循环的好处是不占用 tick 标签、频率精确；坏处是 `/reload` 后已排队的任务会清空——所以要在 `load.mcfunction` 里重新 `schedule function myns:tick_1s 20t replace`。

### 9.3 `data storage` 做全局变量

命令存储是一个"没有实体、没有方块"的 NBT 容器，最合适放全局状态：

```mcfunction
# 初始化
data merge storage myns:vars {count:0,total:0,flag:0b,name:""}

# 写入（把命令结果存进去，类型 int）
execute store result storage myns:vars count int 1 run scoreboard players get #kills myns.data

# 读取判断
execute if data storage myns:vars {flag:1b} run say 标记为真

# 直接把常量写进去
data modify storage myns:vars flag set value 1b
data modify storage myns:vars name set value "Steve"

# 读出来打印
data get storage myns:vars
data get storage myns:vars.count
```

几种 `store` 目标的差异：

| 目标 | 范围 | 典型用途 |
| --- | --- | --- |
| `bossbar <id> value` | 0..max | 显示进度 |
| `entity <target> <path> <type> <scale>` | 该 NBT 节点类型 | 写到实体 NBT |
| `block <pos> <path> <type> <scale>` | 方块实体 NBT | 写入告示牌/箱子 |
| `score <targets> <objective>` | int | 计分板变量 |
| `storage <id> <path> <type> <scale>` | 指定类型 | 全局变量 |

`<type>` 是 `byte`/`short`/`int`/`long`/`float`/`double`，写入时**必须指定**。

### 9.4 scoreboard 作为变量系统的坑

- 计分板分数上限是 **-2^31 ~ 2^31-1**，溢出会回绕。
- 虚拟玩家名以 `#` 开头（如 `#tick`）不会出现在侧边栏，也不会被 `@a` 选中——但它们**确实占用分数**，长期运行要记得清理。
- `execute if score #a myns.data = #b myns.data` 是"两个分数相等"的正确写法；不能写 `matches #b`。
- `scoreboard players operation` 可以做加减乘除和比较赋值，是纯数据包唯一的"算术"手段（1.20.2 起才有 `random`）：

```mcfunction
scoreboard players operation #a myns.data += #b myns.data
scoreboard players operation #a myns.data *= #mod myns.data
scoreboard players operation #a myns.data -= #const myns.data
```

## 10. 宏函数完整示例

### 10.1 宏文件

`data/myns/function/spawn_mob.mcfunction`（**每一行用到的宏都要以 `$` 开头**）：

```mcfunction
$summon $(type) $(x) $(y) $(z) {NoAI:1b,PersistenceRequired:1b,CustomName:'{"text":"$(name)"}',Tags:["$(tag)"]}
$tellraw @a {"text":"已生成 $(name)","color":"gray"}
```

### 10.2 三种调用方式

```mcfunction
# 1. 内联复合标签
function myns:spawn_mob with {type:"minecraft:zombie",x:100,y:64,z:100,name:"守卫甲",tag:"npc"}

# 2. 从命令存储取（适合参数动态变化的场合）
data merge storage myns:args {type:"minecraft:zombie",x:100,y:64,z:100,name:"守卫乙",tag:"npc"}
function myns:spawn_mob with storage myns:args
```

三种 `with` 来源都可以：`{...}`（内联）、`storage <id> <path>`、`entity <target> <path>`（取实体 NBT 里的某个复合标签，例如 `with entity @s SelectedItem`）。传进去的复合标签里键名必须与宏变量完全对应，多一个少一个都不影响，但用到的变量缺失时该行会被跳过。

### 10.3 宏函数里用 `return`

```mcfunction
# data/myns/function/give_reward.mcfunction
$give @s minecraft:$(item) $(count)
$return 1
```

```mcfunction
# 调用并用返回值判断
execute store result score #ok myns.data run function myns:give_reward with {item:"diamond",count:3}
execute if score #ok myns.data matches 1 run say 发放成功
```

宏函数在**没有传参**时：所有 `$` 行都会因为缺失变量而整条跳过（不是只跳过这一行），所以可以用"可选参数"的技巧——把可选项单独写一行宏。

### 10.4 宏的限制

- 参数名只能是 `a-zA-Z0-9_`，不能有小数点或冒号。
- 替换是**纯文本**：字符串不带引号、数字不带类型后缀。所以传 `"hello"` 会变成 `hello`；传 `"a b"` 变成两个参数——需要引号时自己在宏行里写 `"$(msg)"`。
- 宏行里的 `$(变量)` 不能嵌套、不能做运算；要算术请先用 `scoreboard` 算好再传。
- 宏函数**不能被 `#minecraft:tick` 标签直接引用**（缺参数会在执行时报错），必须由普通函数用 `function ... with` 调。
- 1.20.1 **没有**宏函数；1.20.2 起才加入。

## 11. 坑与排查清单

1. **`pack_format` 不匹配**：日志里出现 `Incompatible pack format` / 数据包列表里显示红色。1.20.1 数据包要 `15`，1.21.1 要 `48`。`supported_formats` 只能"声明兼容"，不会让游戏真的认识新格式的字段。
2. **目录单复数**：1.20.1 是 `functions/`、`recipes/`、`loot_tables/`、`advancements/`、`predicates/`、`item_modifiers/`、`tags/functions/`；1.21.1 全部单数。放错目录**不会报错**，只是内容静默不加载。
3. **`values` 里不要写 `.json`**：`"myns:load"` 而不是 `"myns:load.json"`。
4. **JSON 语法**：尾逗号、`//` 注释、单引号字符串都会让整个文件加载失败；日志通常只指出文件名（函数报错会给行号，JSON 多数不给具体行），用编辑器的 JSON 校验更快。
5. **`#tick` 里放重逻辑**：`execute as @e ...` 每 tick 全图扫描是 TPS 杀手；用 `distance`、`type`、`limit`、`schedule` 节流。
6. **`execute if data` 与 `data get` 的差别**：`if data` 只返回成功/失败（用于条件判断）；`data get` 会把值打印到聊天栏并可 `store result`。想"取值"必须用 `data get` + `execute store`。
7. **`@e` 不带 `type`**：1.21.1 里 `@e` 包含船、盔甲架、掉落物、经验球、TNT，漏写 `type=` 容易误伤。
8. **NBT 类型后缀缺失**：`Count:1`（int）与 `Count:1b`（byte）在 1.20.1 里不是一回事；`Health:20`（int）会让实体血量变成 0 或报错，写 `20.0f`/`20.0d`。
9. **1.21 组件替代 tag**：`give @s diamond_sword{display:{Name:...}}` 在 1.21.1 里不会被识别——必须写 `[custom_name=...]`；`tag:{}` 出现在 NBT 里也会让物品变成"无效物品"。
10. **`data modify` 的路径写错会静默无事**：路径不存在时 `data modify ... set` 什么也不做，不报错。先用 `data get` 确认父节点存在。
11. **`fill`/`clone` 体积上限 32768**，`setblock` 里的方块状态写错（`facing=east`）会让整条命令失败而不是只改一部分。
12. **函数里的相对坐标**：`~ ~ ~` 相对"执行位置"，不是相对玩家。`execute as @p at @s run ...` 才是"以玩家位置执行"。
13. **`/reload` 不会重载函数标签之外的东西**：`data storage` 内容、已排队的 `schedule` 任务、`bossbar` 状态在 reload 后需要重新初始化（所以 `load.mcfunction` 里要写 `schedule` 与 `bossbar add`）。
14. **世界生成文件（`worldgen/*`）改动后必须新建世界**：`/reload` 不会重新生成已存在的区块，测试时要 `/tp` 到未加载区域或开新存档。

## 12. 参考来源

- Minecraft Wiki — Commands：<https://minecraft.wiki/w/Commands>
- Minecraft Wiki — Commands/execute：<https://minecraft.wiki/w/Commands/execute>
- Minecraft Wiki — Commands/data：<https://minecraft.wiki/w/Commands/data>
- Minecraft Wiki — Commands/item：<https://minecraft.wiki/w/Commands/item>
- Minecraft Wiki — Commands/loot：<https://minecraft.wiki/w/Commands/loot>
- Minecraft Wiki — Commands/place：<https://minecraft.wiki/w/Commands/place>
- Minecraft Wiki — Commands/function、Commands/return、Commands/schedule、Commands/random、Commands/recipe、Commands/attribute
- Minecraft Wiki — Data pack：<https://minecraft.wiki/w/Data_pack>
- Minecraft Wiki — Function (Java Edition)：<https://minecraft.wiki/w/Function_(Java_Edition)>
- Minecraft Wiki — NBT path：<https://minecraft.wiki/w/NBT_path>
- Minecraft Wiki — NBT format / Entity format：<https://minecraft.wiki/w/NBT_format>、<https://minecraft.wiki/w/Entity_format>
- Minecraft Wiki — Data component format：<https://minecraft.wiki/w/Data_component_format>
- Minecraft Wiki — Target selectors：<https://minecraft.wiki/w/Target_selectors>
- Minecraft Wiki — Pack format、pack.mcmeta
- Mojang 1.21 更新日志（数据包 pack_format 48 / 资源包 34）

