# WebSocket 桥：远程操控与截图验收

`<bridge-dir>/` 是本仓库内的独立 Forge 1.20.1 模组（modId `<bridge-modid>`，Forge 47.4.10，official mappings）。它把 Minecraft 暴露成一条本地 WebSocket 通道，让脚本/AI 执行命令、查询状态、模拟玩家输入并截图。

## 1. 构建与启动

```powershell
# 构建（产物 build/libs/<archivesName>-<version>.jar，reobf/SRG，可直接放入 mods/）
cd <bridge-dir>
.\gradlew.bat build

# 专用服 / 开发客户端
.\gradlew.bat runServer
.\gradlew.bat runClient
```

配置：`run/config/<bridge-modid>-common.toml` 的 `[bridge]` 段

```toml
enabled = true
host = "127.0.0.1"
port = 25566
token = ""            # 留空时自动生成 48 位 hex 并写入 run/config/<bridge-modid>.token
allowRemote = false   # false 时强制绑定回环地址
requestTimeoutMs = 30000
```

启动日志：`[<bridge-modid>] WebSocket bridge listening on ws://127.0.0.1:25566 (context=...)`。
游戏内命令 `/<bridge-modid> status|token|restart`（权限 2）。

## 2. 连接与协议

```text
ws://127.0.0.1:25566/?token=<token>
# token 也可用 Authorization: Bearer <token> 或 X-Bridge-Token 头
```

- 握手校验 `Upgrade: websocket` / `Sec-WebSocket-Version: 13`；token 错误返回 401，非 Upgrade 返回 426。
- 连接后服务端主动发 `hello`：`{"event":"hello","protocol":1,"mod":"<bridge-modid>","version":"1.0.0","context":"client|integrated_server|dedicated_server","capabilities":[...]}`
- 请求必须带 `id`；响应 `{"id","ok":true,"result":{...},"elapsedMs":N}` 或 `{"id","ok":false,"error":"..."}`。

请求类型：

| type | 关键参数 | 说明 |
| --- | --- | --- |
| `ping` | – | `{serverTime, uptimeMs}` |
| `capabilities` | – | 当前 context 与能力表 |
| `command` | `command`, `asPlayer?` | 服务端执行并捕获命令输出；纯客户端远程服时仅转发 |
| `state` | `radius?`, `asPlayer?` | 维度/时间/玩家列表（pos、yaw、pitch、生命、饥饿、物品栏、效果、gameMode、onGround） |
| `entities` | `radius`, `entityType?`, `limit?` | 附近实体；类型过滤用 `entityType`（不是 `type`，`type` 是请求类型字段） |
| `block` | `x,y,z` | 方块 id、properties、isAir、destroySpeed、blockEntity |
| `chat` | `message` | 服务端广播 / 客户端发送聊天 |
| `input` | `op`, … | 见下节，仅客户端可用 |
| `screenshot` | – | `{format:"png",width,height,bytes,base64}`，仅客户端可用 |
| `perception` | `radius?`, `maxBlocks?`, `attackRange?`, `fov?`, `screenshot?` | 文本化感知 +（可选）截图，同一响应返回，仅客户端可用，见第 3 节 |
| `detect` | `preset?`, `conditions?[]`, `radius?` | 单次条件检测：预设或自定义条件，返回逐条结果 + 上下文，仅客户端可用，见第 4 节 |
| `keys` | `filter?`, `modOnly?`, `pressedOnly?`, `key?` | 列出全部按键映射（含其它模组注册的键），见第 9 节 |
| `scan` | `radius?`, `fov?`, `category?`, `limit?`, `lineOfSight?`, `chat?` | 视野锥内生物扫描 |
| `block_search` | `block`, `radius?`, `limit?`, `chat?` | 按方块 id 查最近位置 |
| `path` / `waypoint` | `action`, `target?`, `x/y/z?`, `entityId?`, `follow?` / `name` | A* 寻路与坐标点记录 |
| `lock` / `combat` / `aim` | `entityId?`, `category?`, `radius?`, … | 锁定、自动打怪、单次瞄准 |
| `hotbar` / `inventory` / `container` | `action`, … | 快捷栏换位、背包查询、容器开/取/放 |
| `fish` / `build` / `gather` / `farm` | `action`, … | 自动钓鱼、搭桥搭塔、采集与农事 |
| `explore` | `action`（biome/biomes/block/entity/mark/marks/clear/scan） | 结构化探索与区域缓存 |
| `craft` / `smelt` / `trade` / `anvil` | `action`, … | 合成、熔炼、村民交易、铁砧（阻塞到完成） |
| `macro` / `loop` | `action`（run/stop/status）, `steps[]`, `intervalTicks?` | 宏序列与定时循环 |
| `wait` | `ms` | 最多 600000 |
| `script` | `steps`, `delayMs?`, `stopOnError=true` | 顺序执行；步骤可写 `command` / `action` / `delay` / 嵌套 `script`，`repeat` 1..1000，嵌套深度 ≤ 8 |

`input` 的 `op`：

| op | 参数 | 说明 |
| --- | --- | --- |
| `key` | `name`, `down` | 单键按下/释放（forward/back/left/right/jump/sneak/sprint/attack/use/drop/inventory） |
| `keys` | `keys[]`, `down` | 批量按键 |
| `move` | `keys[]` 或 `direction`, `ms` | 非阻塞：按下后由 tick 定时释放 |
| `hold` | `keys[]` 或 `direction`, `ms`（1–600000，默认 1000）, `hand?` | 非阻塞：一次按下整组键并到点一起释放，`use`/`attack` 按“真按住”驱动，见下 |
| `look` | `yaw`, `pitch`, `relative?` | 直接设置/叠加视角 |
| `attack` | `entityId` | 攻击实体 |
| `use` | `hand?` | 使用手持物品 |
| `mine` | `x,y,z`, `face?`, `timeoutMs?` | 阻塞到方块变空气或超时 |
| `place` | `x,y,z`（被点击的方块）, `face`, `hand?` | 落点 = 该方块沿 face 的相邻格 |
| `select_slot` | `slot` 0..8 | 切换快捷栏并同步服务端 |
| `drop` | `all?` | 丢弃 |
| `stop` | – | 释放所有按键并取消挖掘 |

### hold：长按组合键（连续操作）

一次请求按下整组键，到 `ms` 后由 tick 一起释放；`use` / `attack` 不写进 KeyMapping 的普通按下，而是按“真按住鼠标”驱动：

```json
{"id":"h1","type":"input","op":"hold","keys":["sprint","forward"],"ms":1500}
{"id":"h2","type":"input","op":"hold","keys":["use","sprint","forward"],"ms":1200}
{"id":"h3","type":"input","op":"hold","direction":"forward","keys":["sneak"],"ms":800}
{"id":"h4","type":"input","op":"hold","keys":["attack"],"ms":3000}
```

响应：`{op:"hold", keys:[...], ms, use, attack, started:true}`。

- **use（右键）**：整个持续期把真实 `keyUse` 映射按下（关键：`LocalPlayer` 在 `keyUse` 抬起时会立刻 `releaseUsingItem`，只调 `gameMode.useItem` 而不按映射，`perception.player.usingItem` 会一直是 false）。同时开始一次 `useItem`，之后每 250 ms 在“未处于使用中”时补一次，覆盖连续放方块；到点释放映射并 `releaseUsingItem`。
- **attack（左键）**：每个 tick 检查 `getAttackStrengthScale ≥ 0.95` 且准星是实体，则对该实体 `attack` + 挥手，等价于按住左键自动攻击（约 1 秒 1.5 刀，铁剑 6 伤害），不需要再逐刀发 `attack`。
- 其余键（forward/back/left/right/jump/sneak/sprint）走普通 KeyMapping 按下，与 `move` 相同。
- `stop` 会同时结束 hold 并释放 `keyUse`/物品使用；新的 `hold` 会覆盖旧的 hold。
- **原版语义**：使用物品期间疾跑会被原版取消、移动速度降到约 20%，所以 `["use","sprint","forward"]` 的实测结果是 `usingItem=true, sprinting=false` 且缓慢前进——这不是 hold 失效。

### 操作归属：指令外的操作默认为用户操作

只有经由 WebSocket 请求（`input`、`command`、`script`、第 9 节客户端能力层）发出的动作才算 AI 操作；世界里其它一切变化——键鼠移动/攻击、聊天或手动输入命令、暂停或切窗、手动挖放/开箱/合成——**一律默认是用户（人类）在操作**，不要当成桥接的执行结果。

- 发现位置、朝向、背包、目标与 AI 预期不符（yaw 突然变化、`path`/`combat` 被中断、物品栏多出东西、界面被打开）时：先停掉自动流程（`input.op=stop`、`unlock`、`macro stop`），再重新 `state`/`perception`/`detect` 对齐，不要按旧状态继续推进。
- 需要独占操作时把 `inputLock = true`（`run/config/<bridge-modid>-common.toml` 配置项，或 `input.op=lock` / `/<bridge-modid> lock`）：锁定期间物理键鼠被吞掉，仅保留 Esc / F3 / 聊天键供用户自行解锁。
- 用户接管过之后，不要把自己没发过的结果当成自己的战果/进度上报；交接用 `chat` 留痕。

## 3. perception：文本化感知 + 截图

给“没有图形能力”的 AI 用：一次请求同时返回当前视野的可读文本与同一帧 PNG，避免文本与画面错位。

```json
{"id":"p1","type":"perception","radius":8,"maxBlocks":48,
 "attackRange":4.0,"fov":110,"screenshot":true}
```

| 参数 | 默认 | 范围 | 说明 |
| --- | --- | --- | --- |
| `radius` | 8 | 1–24 | 可视方块搜索半径（球面距离） |
| `maxBlocks` | 96 | 1–512 | 返回方块上限，按距离由近到远截断；总数另给 `visibleBlockTotal` |
| `attackRange` | 3.0 | 0.5–16 | 攻击范围内生物距离 |
| `fov` | 110 | 20–170 | 水平视角锥（全角）。默认 110 才接近 16:9 屏幕实际横向视野 |
| `screenshot` | false | – | true 时在同一 `result` 里附 `screenshot` 对象 |

响应结构：

```text
{dimension, gameTime, radius, fov, attackRange,
 player{name,dimension,pos,blockPos,eyePos,look,yaw,pitch,onGround,sprinting,sneaking,
        inWater,usingItem,health,maxHealth,food,air,gameMode,selectedSlot},
 crosshair{type:"block|entity|miss|none", distance,
           block 分支: pos,block,face,isAir,destroySpeed
           entity 分支: entity{…}},
 visibleBlocks[{pos,block,distance,solid}], visibleBlockTotal,
 inventoryBlocks[{slot,item,count,name,hotbar,selected,offhand}], inventoryBlockTotal,
 attackableEntities[{id,uuid,type,name,pos,distance,lineOfSight,aimYaw,aimPitch,
                     health,maxHealth,hostile,category}], attackableCount,
 screenshot{format,width,height,bytes,base64}   // 仅在 screenshot=true 时
}
```

- `visibleBlocks`：视角锥（`dot >= cos(fov/2)`）+ 非空气 + `level.clip(... OUTLINE)` 首命中必须是自身 → 真实可见、未被遮挡；按距离升序。
- `inventoryBlocks`：只列 `BlockItem`（快捷栏 0–8、主背包 9–35、副手 40），`hotbar`/`selected`/`offhand` 便于直接选槽放置。
- `attackableEntities`：`LivingEntity && alive && !spectator` 且距离 ≤ `attackRange`；`hostile` 取 `Enemy` 接口，`aimYaw/aimPitch` 可直接喂给 `input.look`，`lineOfSight` 判断能否直接攻击。
- `crosshair` 直接读 `mc.hitResult`，与玩家看到的准星一致。

## 4. detect：单次条件检测

一次请求回答“现在是否满足某组条件”，不订阅、不轮询；适合放在自动战斗/挖矿/撤退逻辑的判断点前。

```json
{"id":"d1","type":"detect","preset":"threat"}
{"id":"d2","type":"detect","conditions":["health<=10","block_below=air"]}
{"id":"d3","type":"detect","preset":"lava","radius":4}
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `preset` | – | 预设名；与 `conditions` 至少给一个，两者同时给时条件合并 |
| `conditions` | – | 字符串数组，写法 `名称 运算符 值`，空格会被忽略：`health<=10`、`block_below=air` |
| `radius` | 8 | 1–24，决定 `hostiles`/`entities`/`hazards`/`water` 的球面搜索半径 |

运算符 `<= >= < > = !=`；布尔与文本条件只支持 `=`、`!=`。

预设：

| preset | 等价条件 | 含义 |
| --- | --- | --- |
| `threat` | `nearest_hostile<=8` | 半径内有敌对生物（`Enemy`） |
| `low_health` | `health<=10` | 生命值 ≤ 10 |
| `fall_risk` | `air_below>=3` | 脚下 3 格内无实心方块 |
| `night` | `night=true` | 世界时间落在 13000–23000 |
| `lava` | `hazards>=1` | 半径内有岩浆/火/灵魂火/岩浆块 |
| `water` | `water>=1` | 半径内有水 |
| `inventory_full` | `empty_slots<=0` | 主背包 36 格没有空格 |
| `durability` | `durability<=20` | 主手可损坏物品剩余耐久 ≤ 20 |
| `target` | `crosshair!=miss` | 准星指向方块或实体 |

数值条件：

| 名称 | 含义 |
| --- | --- |
| `health` / `max_health` / `health_ratio` | 当前生命 / 上限 / 比例 0–1 |
| `food` / `air` | 饥饿值 / 氧气值 |
| `hostiles` / `nearest_hostile` / `hostiles_in_los` | 半径内敌对数量 / 最近敌对距离（无则 999）/ 视线内敌对数量 |
| `entities` / `players` | 半径内实体数 / 世界玩家数 |
| `air_below` | 脚下到第一个实心方块的空气格数（封顶 32） |
| `light` / `day_time` | 脚下方块最大亮度 / 当日时间 0–23999 |
| `empty_slots` / `durability` | 主背包空格（36 格）/ 主手剩余耐久 |
| `hazards` / `water` | 半径内危险方块数 / 水方块数 |

关键字条件（`actual` 为布尔或文本）：

| 名称 | 取值示例 |
| --- | --- |
| `night` / `day` / `raining` / `thundering` | `night=true` |
| `on_ground` / `in_water` / `in_lava` | `on_ground=false` |
| `block_below` | `block_below=air`、`block_below=grass_block`（`minecraft:` 前缀可省） |
| `crosshair` / `target_block` | `crosshair!=miss`、`target_block=minecraft:stone` |
| `has_effect` / `has_item` | `has_effect=minecraft:strength`、`has_item=minecraft:dirt` |

响应结构：

```text
{preset|null, ok, passed, total, radius,
 checks[{condition, op, expected, kind:"number|keyword", actual, ok, note?}],
 context{player{name,pos,yaw,pitch,health,maxHealth,food,air,onGround,inWater,inLava,
               usingItem,gameMode},
         threat{count, nearestDistance, nearest{id,type,health,maxHealth,hostile,
                lineOfSight,pos,aimYaw,aimPitch}},
         below{block, airDistance}, light, dayTime, isDay, raining, thundering, dimension,
         crosshair{type:"block|entity|miss", block?/face?/entityId?/entityType?/distance?}}}
```

- `ok` = 所有条件同时成立；`passed`/`total` 给出逐条计数。`threat=true` 表示“有威胁”，`false` 表示“安全”。
- 边界语义：`nearest_hostile` 在半径内无敌对时为 `999`（`<=` 类条件自然不成立）；`durability=-1` 表示主手不是可损坏物品，该条件恒为 false 并附 `note`。
- `night/day` 用 `dayTime % 24000`（13000–23000 为夜），不吃客户端延迟的天空亮度，`/time set night` 1–2 秒内可见。
- **世界必须先 tick**：窗口失焦弹出“游戏菜单”会暂停单机世界，命令照常执行但方块/时间不会同步到客户端，`detect` 会读到旧世界。先关掉菜单（ESC）并保持窗口焦点，或把 `run/options.txt` 的 `pauseOnLostFocus` 设为 `false`。
- 改世界（`setblock`/`summon`/`time set`）后先等 800–1500 ms 再 `detect`；用相对坐标 `~ ~ ~` 时注意它相对的是服务端玩家位置。
- `asPlayer` 只换执行锚点与实体上下文（`@s`、`~ ~ ~`），**不提权**：玩家不是 OP 时，`time set`/`summon`/`effect`/`kill` 这类需要权限 2 的命令会被 Brigadier 直接从命令树里过滤，返回“未知或不完整的命令”。改世界建议不传 `asPlayer`（控制台权限 4），必须用 `@s` 时先 `op <玩家>`。
- 实测（quickplay=<test-world>）：`threat` 无怪 false → 召唤尸壳/史莱姆后 true（5.15/6.16，史莱姆走 `Enemy` 计入敌对）；`radius:32` 被夹到 24、`hostiles` 3 → 9；`block_below=grass_block` true；`health<=10` false（20.0）；`night` 白天 false → `time set night` 后 true（dayTime 13980）；`hazards` 0 → 1（放岩浆后）；`water` 0 → 46（放水源后）；`has_effect=resistance`、`has_item=stone` true；空手 `durability` false + note；空背包 `empty_slots<=0` 36 false；`look 0 90` 低头后 `target` true（`crosshair=block`/`grass_block`，`target_block=minecraft:grass_block` true）；`detect nope` 返回 `invalid condition`。

## 5. 能力矩阵

`input` / `screenshot` / `perception` / `detect` 以及第 9–10 节的客户端能力层（`keys`、`scan`、`path`、`combat`、`hotbar`、`fish`、`explore`、`macro`、`craft` …）只在有游戏客户端时出现：

| context | command/state/block/entities/chat | input | screenshot | perception | detect |
| --- | --- | --- | --- | --- | --- |
| `dedicated_server` | 是 | 否 | 否 | 否 | 否 |
| `integrated_server`（单人） | 是 | 是 | 是 | 是 | 是 |
| `client`（连远程服） | 是（命令转发，无输出） | 是 | 是 | 是 | 是 |

没有客户端时 `hello.capabilities` 不含上述能力，请求会返回 `client is not in a world`。

## 6. 验收脚本

| 脚本 | 内容 | 实测 |
| --- | --- | --- |
| `.autopilot/ws-test/InputScreenshotTest.java` | 基础 21 项：capabilities、look 绝对/相对、select_slot、move、jump、mine、2 张截图、stop、ping | 21 passed / 0 failed |
| `.autopilot/ws-test/InputScreenshotScenarioTest.java` | 连续场景 45 项：四向转身、边走边截图、冲刺、冲刺跳跃、连挖 3 格、回填方块、8 连发流水线、script 组合、错误恢复、停止稳定性、4 张截图 | 45 passed / 0 failed |
| `.autopilot/ws-test/PerceptionLoopTest.java` | 1 Hz 感知循环 60 tick / 28 项：60 帧“文本感知 + 截图”同包、节奏误差、转身/移动后的可视集合变化、背包方块与选槽、准星方块与 `block` 一致、僵尸召唤/瞄准/攻击掉血、与 `state` 位置朝向一致 | 28 passed / 0 failed |
| `.autopilot/ws-test/CombatPerceptionTest.java` | 1 Hz 战斗循环 75 tick：5 格接近→瞄准→4 刀击杀；AI 僵尸主动伤害玩家→治疗→击杀；三目标最近优先与轮换；石墙 LOS 阻断→拆除后击杀；全程只用文本感知 | 45 passed / 0 failed |
| `.autopilot/ws-test/HoldInputTest.java` | 长按组合键 21 项：`hold sprint+forward` 疾跑并到点全释放（无漂移）、盾牌 `hold use` 真正进入 `usingItem` 并在到点解除、`use+sprint+forward` 组合（原版会暂停疾跑）、`hold attack` 对准星实体自动连击致死、`stop` 中断长按 | 21 passed / 0 failed |

```powershell
# 客户端必须已进世界、窗口未暂停；token 自动从 <bridge-dir>/run/config/<bridge-modid>.token 读取
java .autopilot\ws-test\InputScreenshotTest.java
java .autopilot\ws-test\InputScreenshotScenarioTest.java
java .autopilot\ws-test\PerceptionLoopTest.java
java .autopilot\ws-test\CombatPerceptionTest.java
java .autopilot\ws-test\HoldInputTest.java
```

退出码 0 = 全部通过。截图输出到 `.autopilot/ws-test/out/`。也可传 `[token] [port]` 两个参数覆盖默认值。

`PerceptionLoopTest` 每 tick 的产物：

```text
.autopilot/ws-test/out/loop/
  tick-0000.json   # perception 原始响应（含 base64 截图）
  tick-0000.png    # 同一帧截图（已解码）
  …
  senses.log       # 每行一个 tick 的纯文本摘要，供无图形 AI 直接读
  summary.json     # ticks/pass/fail/skip/visibleBlockTicks/validScreenshots/failures
```

`senses.log` 单行格式：

```text
[tick 000] pos=(x,y,z) yaw= pitch= ground= hp= food= | crosshair=<miss|block@…|entity type#id>
  | visible=<返回数>/<总数> [block@(x,y,z) d=…, …] | blocks=<背包方块总数> [slot*:item xN, …]
  | mobs=<数量> [type#id d=… hp=a/b los=… aim=(yaw,pitch), …] | shot=<w>x<h> <bytes>B sha=<sha12>
```

循环脚本启动后会先 `command difficulty easy`（否则和平难度会秒清敌对生物），并在每 tick 前后执行时间线动作（转身/前进/给物品/选槽/俯视/召唤/瞄准/攻击/抬头）。测试期间**不要动游戏窗口鼠标**，否则 yaw/pitch 会被真实鼠标事件覆盖。

`CombatPerceptionTest` 每 tick 的产物与文本行：

```text
.autopilot/ws-test/out/combat/
  combat-0000.json  # perception 原始响应（含 base64 截图）
  combat-0000.png   # 同一帧截图
  combat.log        # 每行一个 tick 的纯文本战斗观察
  summary.json      # ticks/pass/fail/skip/damagedByMob/screenshotBytesTotal/hits/failures
```

```text
[combat 07] pos=(x,y,z) yaw= pitch= hp=20.0/20 ground= | crosshair=<miss|block@…|entity type#id d=>
  | blocks=<背包方块数> | mobs=<数量> [type#id d= hp= hostile= los= aim=(yaw,pitch), …] | shot=<w>x<h> <bytes>B
```

战斗脚本的 preflight：`difficulty easy`、`time set 13000` + 停止昼夜循环（防僵尸白天燃烧）、`doMobSpawning false`、`mobGriefing false`、`naturalRegeneration false`（保证掉血断言不被自然回血掩盖）、`doImmediateRespawn true`（意外死亡立刻复活而不是卡死亡界面）、`gamemode survival`、`clear`、`effect clear`、回满血与饱食度、清场（`kill @e[type=!minecraft:player,type=!touhou_little_maid:maid]`：杀掉除玩家与车万女仆外的所有实体，避免误杀 TLM 女仆/测试用人形）。每 tick 只做一个战斗动作（移动/瞄准/攻击），攻击间隔 1 s 保证铁剑满蓄力。

`HoldInputTest` 产物：

```text
.autopilot/ws-test/out/hold/
  hold-00.json   # 每次观察的 perception 原始响应
  hold.log       # 每行一次观察：pos/yaw/pitch/hp/sprint/using/crosshair/mobs
  summary.json   # pass/fail/failures
```

```text
[hold 07 combo      ] pos=(x,y,z) yaw= pitch= hp=20.0 sprint=false using=true crosshair=miss mobs=0
```

### 交互式 Python 控制台

`.autopilot/ws-test/bridge_console.py` 是零依赖（纯标准库，自带 WebSocket 客户端）的 REPL，用命令行直接操控角色：

```powershell
python .autopilot\ws-test\bridge_console.py                  # 自动读 <bridge-dir>/run/config/<bridge-modid>.token
python .autopilot\ws-test\bridge_console.py --port 25566 --token <token>
python .autopilot\ws-test\bridge_console.py --commands .autopilot\ws-test\console-cmds.txt   # 批量执行后退出
python .autopilot\ws-test\bridge_console.py --json --fail-fast --commands plan.txt            # 供 AI/脚本调用
```

```text
mc> sense                      # 一行文本感知；sense --shot 同时存截图
mc> watch 5                    # 连续 5 秒、每秒感知一次
mc> hold use sprint forward 1200   # 长按右键+疾跑+前进 1.2 秒
mc> hold attack 3000              # 按住左键自动连击准星实体
mc> fight 20                   # 自动战斗 20 秒：最近敌对→瞄准→走近/出刀
mc> look at 42                 # 看向 attackableEntities 里的 #42
mc> detect threat              # 单次检测：预设 threat（也可 low_health/fall_risk/night/lava/target…）
mc> detect health<=10 block_below=air   # 自定义条件，可加 --radius=4
mc> wait 800                   # 等 0.8 秒（改世界后等方块/时间同步到客户端）
mc> cmd time set night         # 直接执行服务端命令
mc> shot demo.png              # 截图存到 .autopilot/ws-test/out/console/
mc> raw {"type":"capabilities"}   # 任意请求透传
mc> help / quit
```

坑：

- 截图字段是 `screenshot.base64`（不是 `data`），`state` 的时间字段是 `dayTime`/`gameTime`。
- `hold` 立即返回，紧接着 `sense` 往往看不到位移；要看效果用 `watch` 或隔几百毫秒再感知。
- 控制台是同步的：每条命令等响应完成才返回，`fight` 内部自己按 0.8 s 节奏循环。
- **给 AI 用 `--json`**：stdout 只有 NDJSON，一行一条 `{"cmd":..., "ok":true, ...}`；`[push] hello` 等推送改走 stderr。`sense` 附带 `line/player/crosshair/mobs/shot`，`hold` 附带 `keys/ms/use/attack`，`detect` 附带 `passed/total/checks/context`，`fight` 附带 `event/target/distance/kills`，失败行是 `{"cmd":..., "ok":false, "error":...}`。
- **退出码**：批量模式任一条失败即返回 1；加 `--fail-fast` 遇首个失败立即停止并返回 1；交互模式有失败也返回 1。实测 `--json` 6 行输出全部可解析，失败/继续/中断三条路径退出码均正确。
- 也可以不经过控制台，直接 `from bridge_console import WebSocket, Bridge, read_token`，在 Python 里发任意请求（`bridge.request({"type":"perception",...})`），适合把感知循环写进自己的 Agent。

## 7. 客户端联调配方（已验证）

```powershell
# 1) 复制一份世界给客户端 quickPlay（服务端 world 结构可直接作为单人存档）
Copy-Item -Recurse <bridge-dir>\run\world <bridge-dir>\run\saves\<test-world>
Remove-Item <bridge-dir>\run\saves\<test-world>\session.lock

# 2) 用 Gradle 属性传世界名（无需改 build.gradle，脚本已内置 quickplay 支持）
cd <bridge-dir>
.\gradlew.bat runClient -Pquickplay=<test-world> --console=plain

# 3) 若实例脚本没有 -Pquickplay，再临时在 client { args '--quickPlaySingleplayer', '<test-world>' }，测完还原

# 4) 等 run/logs/latest.log 出现下面两行（注意用时间戳确认是本次启动的新日志）
#    [<bridge-modid>] WebSocket bridge listening on ws://127.0.0.1:25566 (context=integrated_server)
#    Dev joined the game

# 5) 跑验收脚本
java .autopilot\ws-test\InputScreenshotScenarioTest.java

# 6) 收尾：结束客户端进程、还原 build.gradle、删除 saves/<test-world>、确认 25566 已关闭
```

注意：`latest.log` 会保留上一次运行内容，判断“就绪”不能只 grep 关键字，要配合日志时间戳或端口探测。

## 8. 已验证结论与坑

- **yaw 归一化**：客户端 `look yaw=270` 后，服务端 `state` 读到 `-90`；`180` 读到 `-180`。断言必须用角度差（折到 ±180），不要用绝对值。
- **Base64 转义**：模组用 Gson 默认 HTML-safe 输出，base64 里的 `=` 会变成 `\u003d`。不要用正则抓 base64，用正经 JSON 解析（测试脚本内置极简解析器）。
- **服务端状态有延迟**：挖掘在客户端预测完成，立刻查 `block` 可能还是旧方块；等待 300–500 ms 再查。
- **截图**：`NativeImage.asByteArray()` 就是 PNG 字节；`bytes` 与解码长度一致；分辨率为窗口大小（dev 下常见 854x480）。
- **暂停会吞输入**：单人打开暂停菜单时 `input` 不生效（look 仍会改字段）。测试失败时先检查窗口焦点与暂停状态。
- **`move` 非阻塞**：响应立即返回，按键由 tick 定时释放；要验证位移必须 `delay` 后查 `state`。
- **挖掘/放置距离**：受原版 4.5 格触及距离限制；`place` 点击的 anchor 必须在触及范围内。
- **回填方块**：需要快捷栏 0–8 有可放置方块物品；脚本会自动在物品栏里找 dirt/stone/cobblestone 等，找不到就 SKIP。
- **`stop` 语义**：释放所有模拟按键、取消挖掘任务；可用于每轮测试之间的清场。
- **脚本能力**：`script` 内 `action` 会规范化为 `input` 的 `op`；`delay` 步上限 600000 ms；`stopOnError=true` 时首个失败即停止。
- **资源占用**：截图单帧约 115–220 KB（base64 后更大），一次请求一帧，不要高频轮询截图。
- **`fov` 必须按屏幕比例给**：默认 110（水平全角）才接近 16:9 实际视野；用 70 时平地平视 `visibleBlocks` 为空（近处地面在 40–55° 下方，远处又被遮挡）。俯视时数量明显变多。
- **可视 = 视角锥 ∩ 未被遮挡**：`visibleBlocks` 用 `level.clip` 首命中判定，隔着墙的方块不会返回；`visibleBlockTotal` 是截断前总数，`maxBlocks` 只影响输出条数。
- **`entities` 类型过滤字段是 `entityType`**：曾经误用 `type` 会与请求类型键冲突（重复键被解析器覆盖），表现为 `unknown request type: minecraft:zombie`。
- **和平难度会秒清敌对生物**：quickPlay 世界默认 peaceful，`summon zombie` 虽回成功但实体立刻消失；循环前先 `command difficulty easy`（或 creative）。
- **1 Hz 调度**：用 `nextAt = max(nextAt + 1s, now + 200ms)` 而非 `sleep(1s)`，避免慢 tick 累积漂移；实测 min 999 / avg 1000 / max 1002 ms。
- **文本与截图同帧**：`perception.screenshot=true` 时两者在同一次客户端线程调用内采集；分开调用 `perception` + `screenshot` 会错开若干帧，不要用于精确对齐。
- **`command` 不要自己拼引号**：`jsonEscape()` 已经返回带引号的字符串，写成 `\"command\":\"` + jsonEscape(...) + `\"` 会得到 `""difficulty easy""`，服务端报 `MalformedJsonException ... path $.command`（且错误响应没有 `id`，旧脚本会误报 `unexpected response id: null`）。
- **WS 客户端要容忍无 id 推送**：`hello` 没有 `id`，处理请求响应时必须循环丢弃不匹配的帧（打印 `[WS PUSH]`）而不是直接抛异常。
- **战斗前必须回满血**：`gamemode survival` 不会重置血量，上一轮被打到 15 点会连锁导致本轮 AI 僵尸把人打死；preflight 补 `effect give <name> minecraft:instant_health 1 4` + `saturation`，并加 `gamerule doImmediateRespawn true` 兜底（否则会卡在死亡界面，后续所有场景全失败）。
- **僵尸攻击间隔约 1 s**：站在 AI 僵尸旁边最多 8 tick 就会被连击约 6 次（easy 每刀 2.5），所以“观察被伤害”要一检测到掉血就立刻治疗，不要固定等满 8 tick；治疗前给 `resistance 4 2` 可避免同一秒又挨刀导致断言取样抖动。
- **治疗断言看“相对于受伤值是否上升”**：客户端血量同步有延迟，且治疗当秒可能又挨刀，不要断言必须回满 20。
- **放墙挡视线要用 `Math.floor` 落格**：`Math.round(x + dx/len*2)` 在 x≈5.5 时会落到 6，整面墙偏离视线（LOS 仍为 true、准星 miss）；用 `floor` 落在射线所在方块，并额外用 `block` 请求确认 `minecraft:stone` 真的放下去了。
- **长按右键必须真按 `keyUse` 映射**：只调 `gameMode.useItem` 时 `LocalPlayer` 下一 tick发现 `keyUse` 是抬起的就立刻 `releaseUsingItem`，表现为 `usingItem` 永远 false（盾牌/弓/食物都这样）；`hold use` 的做法是持续按住映射，到点再释放。
- **使用物品时原版会取消疾跑**：`hold ["use","sprint","forward"]` 实测 `usingItem=true, sprinting=false`，只能缓慢前进（约 20% 速度）；不要把它当成 hold 失效。
- **`hold attack` 不需要逐刀请求**：调度器按攻击冷却（`getAttackStrengthScale ≥ 0.95`）自动攻击准星实体，3 s 长按实测 4 刀击杀 20 HP 僵尸；逐刀 `attack` 反而容易空刀。
- **`item replace ... weapon.mainhand` 放的是当前选中槽**：先 `select_slot 0` 再替换（或直接用 `hotbar.0`），否则再切槽会把物品切走，`hold use` 拿着空手什么也不会发生（盾牌测试踩过）。
- **每刀只掉 ~0.94 血 = 空手伤害**：铁剑满蓄力应掉 5.9–6.0，若日志里僵尸每次只减 0.94 且 10 刀不死，说明主手是空的（上面那条槽位问题），不是伤害结算被模组压制；脚本里用 `inventory` 请求校验 `selectedSlot` 上的物品再开打。

## 9. 客户端能力层（寻路 / 战斗 / 自动化 / 合成 / 探索 / 宏）

全部为顶层请求 `{"type":"...", ...}`，仅客户端 context 可用；`script` 步骤里同样可写。
`craft` / `smelt` / `trade` / `anvil` 会**阻塞到完成**（几十秒），不要放进 `macro` 的 `steps`。

### 9.1 keys：查按键（含其它模组）

`filter?`（匹配 name/action/category/key）、`modOnly?`、`pressedOnly?`、`key?`（按字面键过滤）、`limit?`（默认 200）、`chat?`。
每条返回 `name`、`action`（翻译名）、`category`、`categoryLabel`、`mod`、`key`（`key.keyboard.*`）、`keyLabel`、`keyCode`、`keyType`。
典型用法：`{"type":"keys","filter":"map"}` 找到打开地图/界面的键，再 `{"type":"input","op":"press","key":"<key>","ms":120}` 模拟按下。

### 9.2 scan / block_search

- `scan`：`radius` 1–48（默认 16）、`fov` 10–180（默认 110，水平全角）、`category`（`all`/`hostile`/`passive`/`player`/`other`；`monster`→hostile，`neutral`/`friendly`/`animal`→passive）、`limit` 1–128、`lineOfSight`、`chat`。返回 `count/total/truncated/entities[]`，实体含 `id/type/name/category/distance/angle/lineOfSight/aimYaw/aimPitch/bearing/health`。
- `block_search`：`block`（可省 `minecraft:`）、`radius` 1–32、`limit` 1–32、`chat`。返回 `found/returned/blocks[]{pos,distance,offset}`，按距离升序。

### 9.3 path / waypoint：A* 寻路与坐标点

`path` 的 `action`：

| action | 参数 | 说明 |
| --- | --- | --- |
| `start` / `goto` | `target`（`coords`/`entity`/`crosshair`）, `x/y/z` 或 `entityId`, `follow?`, `distance?`, `sprint?`, `smooth?`, `turnSpeed?`, `swim?`, `jump?`, `chat?`, `maxNodes?`, `segment?` | 无 `target` 时：有 `x` 则按坐标，否则用准星目标 |
| `cancel` / `stop` | – | 立即停止并释放移动键 |
| `status`（默认） | – | `active/status/goal/distance/segmentGoal/index/nodes/stuckTicks/follow/pos` |

`follow=true` 需要 `target=entity` 或准星指向实体，会保持 `distance` 跟随。1–2 格台阶自动跳，落差自动落下，水面自动游。

`waypoint`：`action=save`（`name` 必填，可带 `x/y/z`，默认玩家脚下）、`goto`（`name`）、`list`、`clear`（`name?` 省略则清空）。保存时记录维度，跨维度 `goto` 会报错。

### 9.4 lock / combat / aim：锁定与自动战斗

`{"type":"combat", "entityId":123}` 或 `{"type":"combat","category":"hostile","radius":32}`。
`action` 可显式给：`lock`（只锁定/瞄准，不自动攻击）、`combat`/`start`/`attack`、`unlock`/`stop`、`aim`（单次对准）、`status`。

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `smooth` / `turnSpeed` | true / 25 | 每 tick 限速转向（度/tick） |
| `attackRange` | 3.0 | 0.5–6.0 |
| `intervalMs` | 250 | 攻击最小间隔 |
| `weapon` | true | 自动把背包里的剑/斧换到主手 |
| `kite` / `kiteDistance` | false / 2.0 | 太近时后退拉开 |
| `retreatHealth` | 0 | 低于该生命值停手（0 关闭） |
| `eat` / `eatBelow` | false / 18 | 低饥饿自动进食（副手或快捷栏食物） |
| `shield` | false | 空闲时举盾格挡 |
| `ranged` / `rangedRange` / `chargeTicks` | false / 24 / 20 | 用弓弩蓄力射击 |
| `chat` | false | 聊天栏播报状态 |

命中判定：距离 ≤ `attackRange`、视线命中、攻击冷却 `≥0.95`。目标死亡/丢失自动 `stop`。

### 9.5 hotbar / inventory / container：物品与容器

- `hotbar`：`action=list`（默认）、`swap`（`from` 0–40 或 `item`，`to`/`hotbar` 0–8）、`select`（`slot` 0–8）。`swap` 要求当前在玩家背包界面，内部用 `ClickType.SWAP` + 2 tick 节流。
- `inventory`：`action=list`、`find`（`item`，返回每槽位置与 `total`）。
- `container`：`action=open`（`x/y/z` 或 `block`+`radius` 自动找容器方块的 `container`）、`read`（遍历容器侧槽位，带 `slotId`）、`take`（`all` 或 `item` 或容器槽 `slot`，shift 移入背包）、`put`（玩家侧槽，shift 移入容器）、`close`。

### 9.6 fish / build / gather / farm：自动化

- `fish`：`start`（需要有鱼竿）、`stop`、`status`；`timeoutTicks` 默认 2400。咬钩判定为“浮标相对基准下沉 > 0.1”。
- `build`：`start`（`mode=bridge|tower`、`block?`、`blocks` 上限默认 64）、`stop`、`status`。
- `gather`：`mine`（默认；`block`/`blocks[]`/`tag`，`tag` 支持 `logs/leaves/flowers/crops/saplings`）、`chop`（等价 `tag=logs`）、`items`（拾取掉落物）、`status`、`stop`；`radius` 1–16、`count`/`limit` 上限、`walk` 默认 true（远处目标先寻路）。
- `farm`：`harvest`（默认）、`plant`（目标耕地，需要种子）、`bonemeal`（未成熟作物 + 骨粉）、`status`、`stop`。

所有 Job 都是后台 tick 驱动：请求立即返回，用 `status` 轮询，或 `macro` 的 `await=automation` 等待。

### 9.7 explore：结构化探索

| action | 参数 | 说明 |
| --- | --- | --- |
| `biome` | `biome`, `radius` 16–1024, `step` 4–32 | 环形采样找最近同名群系（最多 6000 采样） |
| `biomes` | `radius`, `step` | 矩形采样统计 top 群系 |
| `block` | `block`, `radius` 1–64, `limit` | 大范围找方块 |
| `entity` | `entity`, `radius` 1–128, `limit` | 找实体 |
| `mark` | `label`, `x/y/z?` | 记录坐标点 |
| `marks` / `clear` | `scope=marks|regions|all` | 列出/清空 |
| `scan` | `radius` 4–48 | 统计区域方块，缓存到 `REGIONS`（key = 区块 32×32） |

### 9.8 craft / smelt / trade / anvil：合成类

统一 `action=start|status|stop`、`timeoutTicks`（默认 400）。返回用库存 diff 给出 `gained`/`lost`，`result` 可校验期望产物。

- `craft`：`source=auto|player|table`、`grid`（长度 9（3×3）或 4（2×2），空格 null）、`amount` 1–8。
- `smelt`：`input` 必填、`fuel?`（默认按 coal/charcoal/coal_block/planks/log/stick/blaze_rod 查找）、`waitTicks` 默认 240；自动找熔炉/高炉/烟熏炉。
- `trade`：`entityId?` 或 `radius`（最近村民）、`offer`（索引）、`count`。
- `anvil`：`left` 必填、`right?`、`name?`。

### 9.9 macro / loop：宏序列与定时循环

```json
{"type":"macro","steps":[
  {"type":"path","action":"start","x":10,"y":64,"z":10},
  {"type":"gather","action":"chop","count":8,"await":"automation","delayTicks":5},
  {"type":"hotbar","action":"swap","item":"minecraft:bread","to":0}
]}
```

- 步骤可写任意顶层请求；`delayTicks` 在该步后等待；`await`（`path`/`mine`/`automation`/`craft`/`combat`）+ `awaitTimeout`（tick，默认 600）先等子系统结束再继续。
- `{"type":"loop","steps":[...],"intervalTicks":20,"maxRuns":0}` 循环执行，`maxRuns=0` 无限；`{"type":"loop","action":"status"}` 查状态，`action=stop` 停止。
- 宏在客户端 tick 里逐步执行，单步异常默认停止（`stopOnError=true`）。

### 9.10 已知边界

- 所有 Job 状态机只在 `ClientTickEvent.END` 推进；暂停菜单（窗口失焦）会冻结，验证时保持窗口焦点。
- 扫描/寻路/采集默认 16 格量级，别一次给 `explore` 半径 1024 又要求 `biomes` 每 4 格采样（会卡主线程数秒）。
- `container take/put` 依赖服务端菜单同步，连续点击已按 2 tick 节流；读到的槽位以 `slotId` 为准，不要自己推算。
