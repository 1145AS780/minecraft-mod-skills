# 本地反编译环境（核对真实 API）

写注册、事件、网络或 mixin 代码前，若方法签名不确定，先在本机源码里核对，不要凭记忆编造 API。

## 两套 MDK 一览

| 项 | NeoForge | Forge |
|---|---|---|
| 项目路径 | `<NeoForge 项目根>` | `<Forge 项目根>` |
| MC / loader | 1.21.1 / NeoForge 21.1.264 | 1.20.1 / Forge 47.4.10 |
| 构建插件 | ModDevGradle 2.0.148 | ForgeGradle 6 |
| Java | 21（`<JDK 21 安装目录>`） | 17（`<JDK 17 安装目录>`） |
| 映射 | official (Mojmap) + Parchment 2024.11.17 | official (Mojmap) |
| `GRADLE_USER_HOME` | `<gradle-home>` | `<gradle-home>` |
| 反编译现状 | 已有现成反编译源码 jar | 只有映射后的二进制 jar，需用 Vineflower 反编译 |

系统的默认 `java` 不一定是所需版本，Gradle 与 `jar` 命令都要显式指定 JDK，否则可能出现 class 版本或找不到命令的问题：

```powershell
$env:JAVA_HOME = '<JDK 21 安装目录>'   # NeoForge
$env:JAVA_HOME = '<JDK 17 安装目录>'   # Forge（必须 17）
$JAR = '<JDK 21 安装目录>\bin\jar.exe'  # jar 未加入 PATH，用绝对路径
```

## NeoForge 1.21.1：直接用现成源码

Minecraft（含 NeoForge 补丁）的反编译源码已在 NFRT 缓存里，共 6320 个 `.java`：

```
<gradle-home>\caches\neoformruntime\intermediate_results\sourcesAndCompiledWithNeoForge_eddf48f9e0c6f926c948cb2834b22c11960dbfa3_output.jar
```

NeoForge 自身 API 源码（956 个 `.java`，`net/neoforged/**`）：

```
<gradle-home>\caches\modules-2\files-2.1\net.neoforged\neoforge\21.1.264\cf05631ad77db59cf409d78796e4574773310353\neoforge-21.1.264-sources.jar
```

缓存被清理后用命令重新定位（文件名带哈希，不能写死）：

```powershell
Get-ChildItem '<gradle-home>\caches\neoformruntime\intermediate_results' -Filter 'sourcesAndCompiledWithNeoForge_*_output.jar' |
  Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
Get-ChildItem '<gradle-home>\caches\modules-2\files-2.1\net.neoforged\neoforge\21.1.264' -Recurse -Filter '*-sources.jar' |
  Select-Object -ExpandProperty FullName
```

查类 / 取单个文件（不要整包解压，解压后 6000+ 文件检索很慢）：

```powershell
& $JAR tf $NFRT | Where-Object { $_ -like 'net/minecraft/world/item/ItemStack.java' }
& $JAR xf $NFRT net/minecraft/world/item/ItemStack.java    # 解压到当前目录
```

重新生成源码（源码 jar 丢失时）：

```powershell
cd '<NeoForge 项目根>'
.\gradlew.bat createMinecraftArtifacts
```

该任务由 ModDevGradle 调用 NFRT 产出 Minecraft/NeoForge 工件，**没有 `genSources`**（NeoGradle 的写法在 ModDevGradle 里不存在）。其它可用任务：`neoForgeIdeSync`、`runClient`、`runServer`、`runData`、`downloadAssets`。

注意：这个源码 jar 里 Minecraft 是 `.java`，NeoForge 的实现类多为 `.class`（补丁源码另见上面的 `-sources.jar`）；参数名只做了部分 Parchment 映射，看到 `p_XXXXXX_` 属正常。

## Forge 1.20.1：映射二进制 + Vineflower 反编译

ForgeGradle 6 **没有 `genSources`**。首次 `build` 或 `genIntellijRuns` 会下载 userdev 并完成映射，产出映射后的二进制 jar：

```
<gradle-home>\caches\forge_gradle\minecraft_user_repo\net\minecraftforge\forge\1.20.1-47.4.10_mapped_official_1.20.1\forge-1.20.1-47.4.10_mapped_official_1.20.1.jar
```

映射后的二进制 jar 里有 `ItemStack`、`Level` 等 official 名类（9723 个条目），但**不含 `.java`**，必须自己反编译：

```powershell
cd '<Forge 项目根>'
.\gradlew.bat build          # 触发下载 + 映射；只需跑一次
```

反编译单个类（推荐，快且输出小）：

```powershell
$MAP = '<gradle-home>\caches\forge_gradle\minecraft_user_repo\net\minecraftforge\forge\1.20.1-47.4.10_mapped_official_1.20.1\forge-1.20.1-47.4.10_mapped_official_1.20.1.jar'
$VF  = '<gradle-home>\caches\modules-2\files-2.1\org.vineflower\vineflower\1.10.1\4f48c5947b21f9ebc743e7c80215ee839d3dc668\vineflower-1.10.1.jar'
$tmp = "$env:TEMP\mcdec"
New-Item -ItemType Directory -Force -Path "$tmp\in" | Out-Null
Push-Location "$tmp\in"
& $JAR xf $MAP net/minecraft/world/item/ItemStack.class
Pop-Location
& '<JDK 21 安装目录>\bin\java.exe' -jar $VF -dgs=1 "$tmp\in" "$tmp\out"
```

产物：`$tmp\out\net\minecraft\world\item\ItemStack.java`。已实测该方法可还原 1.20.1 的 `getOrCreateTag()`、`getTag()`、`getItem()` 等签名。

整包反编译（几分钟、上 GB 磁盘，只在需要大面积检索时用）：

```powershell
& '<JDK 21 安装目录>\bin\java.exe' -jar $VF -dgs=1 $MAP "$env:TEMP\mcdec-forge-all"
```

Forge 自身 API 源码（666 个 `.java`，`net/minecraftforge/**`，已随 userdev 下载）：

```
<gradle-home>\caches\forge_gradle\maven_downloader\net\minecraftforge\forge\1.20.1-47.4.10\forge-1.20.1-47.4.10-sources.jar
```

定位命令：

```powershell
Get-ChildItem '<gradle-home>\caches\forge_gradle' -Recurse -Filter '*_mapped_official_*.jar' | Select-Object -ExpandProperty FullName
Get-ChildItem '<gradle-home>\caches\forge_gradle' -Recurse -Filter 'forge-*-sources.jar' | Select-Object -ExpandProperty FullName
```

## 核对流程

1. 先确认平台与版本，选对缓存（1.21.1 NeoForge 或 1.20.1 Forge），不要拿 1.21.1 源码核对 1.20.1 代码。
2. 定位类：`jar tf` 过滤包名，确认类与方法确实存在。
3. 只解压或反编译目标类（1–3 个），在 `$env:TEMP` 下操作，不要污染 MDK 源码树。
4. 记录真实签名（参数类型、返回类型、是否 `static`、是否 `@Deprecated`），再写最小示例。
5. 查完删临时目录；需要长期保留则放在 MDK 目录外，并在回复中说明路径。

## 使用约束

- 源码只用于核对签名与行为，**不要把 Mojang 反编译源码整段复制进交付物、技能文档或用户项目**；示例代码要自己写。
- 不要把反编译产物放进 `src/main/java`，也不要提交到 git。
- 反编译结果不保证 100% 可编译（lambda、内部类、泛型擦除会有噪声）；以签名和方法体逻辑为准。
- 版本对不上时（例如 1.20.1 结构里出现 DataComponents），说明拿错了缓存目录，回到第 1 步。