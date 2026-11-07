param(
    [string]$RepoRoot,
    [string]$InstancePath = "$env:APPDATA\.minecraft\versions\1.20.1-forge",
    [int]$TailLines = 200,
    [int]$MaxFrames = 10,
    [string]$OwnPackage = "",
    [int]$FreshMinutes = 30,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Start)
    $dir = if ($Start) { (Resolve-Path -LiteralPath $Start).Path } else { (Get-Location).Path }
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $dir "gradlew.bat")) -and
            (Test-Path -LiteralPath (Join-Path $dir "settings.gradle"))) {
            return $dir
        }
        $parent = [IO.Path]::GetDirectoryName($dir)
        if (-not $parent -or $parent -eq $dir) {
            throw "找不到仓库根（需同时含 gradlew.bat 与 settings.gradle）；用 -RepoRoot 指定"
        }
        $dir = $parent
    }
}

function Get-NewestFile {
    param([string]$Dir, [string]$Filter)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    $f = Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

function Get-Tail {
    param([string]$Path, [int]$Count)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-Content -LiteralPath $Path -Tail $Count -ErrorAction SilentlyContinue)
}

$root = Resolve-RepoRoot -Start $RepoRoot
$logDir = Join-Path $root ".autopilot\logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Path $logDir -Force
}

$devLog = Join-Path $root "run\logs\latest.log"
$devCrashDir = Join-Path $root "run\crash-reports"
$instLog = Join-Path $InstancePath "logs\latest.log"
$instCrashDir = Join-Path $InstancePath "crash-reports"

$buildLog = Get-NewestFile -Dir $logDir -Filter "build-*.log"
$clientSummary = Get-NewestFile -Dir $logDir -Filter "client-*.summary.txt"
$pcl2Summary = Get-NewestFile -Dir $logDir -Filter "pcl2-*.summary.txt"
$clientErr = Get-NewestFile -Dir $logDir -Filter "client-*.err.log"
$pcl2Err = Get-NewestFile -Dir $logDir -Filter "pcl2-*.err.log"

$devCrash = Get-NewestFile -Dir $devCrashDir -Filter "crash-*.txt"
$instCrash = Get-NewestFile -Dir $instCrashDir -Filter "crash-*.txt"
$newestCrash = $null
foreach ($c in @($devCrash, $instCrash)) {
    if (-not $c) { continue }
    if (-not $newestCrash -or (Get-Item -LiteralPath $c).LastWriteTime -gt (Get-Item -LiteralPath $newestCrash).LastWriteTime) {
        $newestCrash = $c
    }
}
$freshCrash = $null
if ($newestCrash) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $newestCrash).LastWriteTime).TotalMinutes
    if ($age -le $FreshMinutes) { $freshCrash = $newestCrash }
}

$evidence = @()
if ($buildLog) {
    $evidence += [pscustomobject]@{ Source = "build.log"; Path = $buildLog; Lines = @(Get-Content -LiteralPath $buildLog -ErrorAction SilentlyContinue) }
}
if ($freshCrash) {
    $evidence += [pscustomobject]@{ Source = "crash-report"; Path = $freshCrash; Lines = @(Get-Content -LiteralPath $freshCrash -ErrorAction SilentlyContinue) }
}
foreach ($pair in @(@{ N = "client.err.log"; P = $clientErr }, @{ N = "pcl2.err.log"; P = $pcl2Err })) {
    if (-not $pair.P -or -not (Test-Path -LiteralPath $pair.P)) { continue }
    $age = ((Get-Date) - (Get-Item -LiteralPath $pair.P).LastWriteTime).TotalMinutes
    if ($age -gt $FreshMinutes) { continue }
    $evidence += [pscustomobject]@{ Source = $pair.N; Path = $pair.P; Lines = Get-Tail -Path $pair.P -Count $TailLines }
}
if ($devLog -and (Test-Path -LiteralPath $devLog)) {
    $evidence += [pscustomobject]@{ Source = "run/latest.log"; Path = $devLog; Lines = Get-Tail -Path $devLog -Count $TailLines }
}
if ($instLog -and (Test-Path -LiteralPath $instLog)) {
    $evidence += [pscustomobject]@{ Source = "instance/latest.log"; Path = $instLog; Lines = Get-Tail -Path $instLog -Count $TailLines }
}

$rules = @(
    @{ P = 'cannot find symbol'; C = '编译期'; F = '缺 import、方法名/签名与 1.20.1 不符、拼写错误；用 official 映射核对方法名并检查 import' },
    @{ P = 'package [\w.]+ does not exist'; C = '编译期'; F = '依赖未声明或 jar 不在 libs/；核对 build.gradle 的 compileOnly/implementation 与文件存在' },
    @{ P = 'incompatible types'; C = '编译期'; F = 'RegistryObject<T> 当 T 用或泛型推断错误；取 .get()，显式写泛型' },
    @{ P = 'non-static method .* cannot be referenced'; C = '编译期'; F = '在静态上下文调用实例方法；改为实例字段或事件对象调用' },
    @{ P = 'duplicate class'; C = '编译期'; F = '遗留入口类未删；只保留一个 @Mod 主类' },
    @{ P = 'unmappable character'; C = '编译期'; F = '源码编码非 UTF-8；把文件另存为 UTF-8（build.gradle 已设 options.encoding=UTF-8）' },
    @{ P = "Plugin \[id: 'net\.minecraftforge\.gradle'\] was not found"; C = '构建配置'; F = '插件缺版本号；补 id 后的 version 区间' },
    @{ P = 'Could not find or load main class GradleWrapperMain'; C = '环境'; F = 'wrapper jar 缺失；重新生成 wrapper，或改用本机 Gradle' },
    @{ P = 'Could not resolve net\.minecraftforge:forge'; C = '依赖/网络'; F = 'Maven 不可达；检查代理与 settings.gradle 仓库，不要改代码' },
    @{ P = 'Failed to get asset|failed to download or validate'; C = '依赖/网络'; F = '资源 CDN 不可达/超时；重跑任务或配代理，不改代码（downloadAssets 失败不是模组问题）' },
    @{ P = 'UnsupportedClassVersionError'; C = '环境'; F = '用 JDK 8/11 编译或运行；JAVA_HOME 必须钉到 JDK 17' },
    @{ P = 'Mod loading has failed'; C = '模组加载期'; F = '主类构造器抛异常；按依赖顺序排列注册/网络/配置调用，构造器内不访问未注册对象' },
    @{ P = 'Failed to create mod'; C = '模组加载期'; F = '主类构造器抛异常；同上，先查注册顺序与静态初始化' },
    @{ P = 'Registration of impl channels is locked'; C = '模组加载期'; F = '首个 tick 才建 SimpleChannel；改到模组构造器初始化频道' },
    @{ P = 'Duplicate registry entry|already registered'; C = '模组加载期'; F = '同一注册名注册两次；删除重复 DeferredRegister 或重复 register' },
    @{ P = 'Missing texture|FileNotFoundException: .*\.png'; C = '资源'; F = '资源路径/文件名不匹配；核对 assets/<modid>/textures 与模型 json 的 texture 字段' },
    @{ P = 'Unable to load model'; C = '资源'; F = '模型 json 语法或父模型路径错误；父模型用 minecraft:item/generated，纹理名与文件名一致' },
    @{ P = 'Cannot get config value before config is loaded'; C = '模组加载期'; F = '静态初始化里读配置；改为运行期读取或加默认值兜底' },
    @{ P = 'NoSuchFieldError: [A-Z_]+'; C = '映射/部署'; F = '发布 jar 未 reobf；用 reobfAddonJar 重建后再同步到 mods' },
    @{ P = 'NoSuchMethodError'; C = '映射/部署'; F = '依赖版本不匹配或用了错误映射的 jar；dev 必须用 named jar，不能用 SRG 发布版' },
    @{ P = 'ResolutionException'; C = '部署'; F = 'JPMS 拆分包冲突；把与库同包的自带类移到自有命名空间并同步 import' },
    @{ P = 'NoClassDefFoundError'; C = '部署'; F = '运行 mods 缺依赖库，或引用了不含该类的副本 jar；核对 mods 里实际加载的 jar' },
    @{ P = 'Exception in server tick loop'; C = '运行期'; F = 'tick 处理器抛异常；定位本模组帧，对实体集合做快照遍历，避免边遍历边删' },
    @{ P = 'ConcurrentModificationException'; C = '运行期'; F = '遍历中修改实体/列表；用 new ArrayList<>(list) 或收集后统一处理' },
    @{ P = 'OutOfMemoryError'; C = '运行期'; F = '单次生成实体过多；加硬上限/分批生成，检查 tick 内生成数量' },
    @{ P = 'IllegalStateException: .*level is null'; C = '运行期'; F = '实体未加入世界就访问 level()；延迟到 tick 或入世界事件后再处理' },
    @{ P = 'ClassCastException'; C = '运行期'; F = '未做 instanceof 判断；命中/交互入口先判类型' },
    @{ P = 'GLFW error|Failed to create window|Pixel format'; C = '环境'; F = '显卡驱动/远程桌面/无显示环境；不改模组逻辑，改用 runServer 验证服务端' },
    @{ P = 'OutOfMemoryError: Metaspace'; C = '环境'; F = '反复热重载/依赖过多；重启 Gradle daemon，必要时加大 org.gradle.jvmargs' }
)

$hits = @()
foreach ($ev in $evidence) {
    foreach ($rule in $rules) {
        $matched = @($ev.Lines | Where-Object { $_ -match $rule.P })
        if ($matched.Count -gt 0) {
            $hits += [pscustomobject]@{
                Source   = $ev.Source
                Category = $rule.C
                Pattern  = $rule.P
                Count    = $matched.Count
                Sample   = ("{0}" -f $matched[0]).Trim()
                Fix      = $rule.F
            }
        }
    }
}

$frames = @()
foreach ($ev in $evidence) {
    foreach ($line in $ev.Lines) {
        if ($OwnPackage -and $line -match ('^\s+at ' + [regex]::Escape($OwnPackage))) { $frames += ("{0}  |  {1}" -f $ev.Source, $line.Trim()) }
    }
}
$frames = @($frames | Select-Object -First $MaxFrames)

$firstException = @()
$firstExceptionSource = ""

$buildEv = @($evidence | Where-Object { $_.Source -eq "build.log" } | Select-Object -First 1)
if ($buildEv.Count -gt 0) {
    $wwIdx = -1
    for ($i = 0; $i -lt $buildEv[0].Lines.Count; $i++) {
        if ($buildEv[0].Lines[$i] -match '\* What went wrong:') { $wwIdx = $i; break }
    }
    if ($wwIdx -ge 0) {
        $end = [Math]::Min($wwIdx + 12, $buildEv[0].Lines.Count - 1)
        for ($i = $wwIdx; $i -le $end; $i++) { $firstException += $buildEv[0].Lines[$i] }
        $firstExceptionSource = "build.log（* What went wrong:）"
    }
}

if ($firstException.Count -eq 0) {
    $headerRegex = '^(Caused by: )?[A-Za-z_$][\w.$]*(Exception|Error)(:|\s|$)|^Exception in thread'
    foreach ($ev in $evidence) {
        $idx = -1
        for ($i = 0; $i -lt $ev.Lines.Count; $i++) {
            if ($ev.Lines[$i] -match $headerRegex) { $idx = $i; break }
        }
        if ($idx -ge 0) {
            $firstExceptionSource = $ev.Source
            $end = [Math]::Min($idx + 8, $ev.Lines.Count - 1)
            for ($i = $idx; $i -le $end; $i++) { $firstException += $ev.Lines[$i] }
            break
        }
    }
}

$fatalCount = 0
$errorCount = 0
foreach ($ev in $evidence) {
    if ($ev.Source -notmatch 'latest\.log') { continue }
    $fatalCount += @($ev.Lines | Where-Object { $_ -match '\bFATAL\b' }).Count
    $errorCount += @($ev.Lines | Where-Object { $_ -match '\bERROR\b' }).Count
}

$buildOutcome = "n/a"
if ($buildLog) {
    $buildLines = (Get-Content -LiteralPath $buildLog -ErrorAction SilentlyContinue)
    if (@($buildLines | Where-Object { $_ -match 'BUILD SUCCESSFUL' }).Count -gt 0) { $buildOutcome = "SUCCESSFUL" }
    elseif (@($buildLines | Where-Object { $_ -match 'BUILD FAILED' }).Count -gt 0) { $buildOutcome = "FAILED" }
}

$clientStatus = "n/a"
if ($clientSummary) {
    $s = @(Get-Content -LiteralPath $clientSummary | Where-Object { $_ -match '^status=' } | Select-Object -First 1)
    if ($s) { $clientStatus = ($s[0] -replace '^status=', '') }
}
$pcl2Status = "n/a"
if ($pcl2Summary) {
    $s = @(Get-Content -LiteralPath $pcl2Summary | Where-Object { $_ -match '^status=' } | Select-Object -First 1)
    if ($s) { $pcl2Status = ($s[0] -replace '^status=', '') }
}

$status = "clean"
if ($hits.Count -gt 0) { $status = $hits[0].Category }
elseif ($freshCrash) { $status = "crash-report" }
elseif ($fatalCount -gt 0) { $status = "log-fatal" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $OutputPath) { $OutputPath = Join-Path $logDir ("diagnosis-{0}.md" -f $stamp) }

function Format-FileInfo {
    param([string]$Path)
    if (-not $Path) { return "无" }
    if (-not (Test-Path -LiteralPath $Path)) { return ("{0}（不存在）" -f $Path) }
    $f = Get-Item -LiteralPath $Path
    return ("{0}（{1} B，{2}）" -f $Path, $f.Length, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# 诊断报告 $stamp")
$md.Add("")
$md.Add("Status: $status")
$md.Add("")
$md.Add("## 判定规则")
$md.Add("")
$md.Add("- ``clean`` 需同时满足：无规则命中、无 ${FreshMinutes} 分钟内的崩溃报告、日志尾部无 ``FATAL``。")
$md.Add("- ``ERROR`` 行只作需关注项列出，不单独把状态打成非 clean（第三方模组常刷 ERROR）。")
$md.Add("- 本模组帧按 ``-OwnPackage`` 指定的包前缀匹配；未指定时不收集自有帧。")
$md.Add("")
$md.Add("## 运行摘要")
$md.Add("")
$md.Add("| 项 | 值 |")
$md.Add("| --- | --- |")
$md.Add("| 仓库根 | $root |")
$md.Add("| JAVA_HOME | $env:JAVA_HOME |")
$md.Add("| 最新构建日志 | $(Format-FileInfo -Path $buildLog) |")
$md.Add("| 构建结果 | $buildOutcome |")
$md.Add("| 客户端摘要 | $(Format-FileInfo -Path $clientSummary) |")
$md.Add("| 客户端状态 | $clientStatus |")
$md.Add("| PCL2 摘要 | $(Format-FileInfo -Path $pcl2Summary) |")
$md.Add("| PCL2 状态 | $pcl2Status |")
$md.Add("| dev latest.log | $(Format-FileInfo -Path $devLog) |")
$md.Add("| 实例 latest.log | $(Format-FileInfo -Path $instLog) |")
$md.Add("| 最新崩溃报告 | $(Format-FileInfo -Path $newestCrash) |")
$md.Add("| 日志尾部 ERROR 行 | $errorCount |")
$md.Add("| 日志尾部 FATAL 行 | $fatalCount |")
$md.Add("")
$md.Add("## 错误分类")
$md.Add("")
if ($hits.Count -eq 0) {
    $md.Add("无命中。")
} else {
    $md.Add("| 分类 | 来源 | 命中数 | 样例 |")
    $md.Add("| --- | --- | --- | --- |")
    foreach ($h in $hits) {
        $sample = $h.Sample -replace '\|', '/'
        if ($sample.Length -gt 120) { $sample = $sample.Substring(0, 120) + "..." }
        $md.Add("| $($h.Category) | $($h.Source) | $($h.Count) | ``$sample`` |")
    }
}
$md.Add("")
$md.Add("## 首个异常")
$md.Add("")
if ($firstException.Count -eq 0) {
    $md.Add("无异常行。")
} else {
    $md.Add("来源：$firstExceptionSource")
    $md.Add("")
    $md.Add('```text')
    foreach ($l in $firstException) { $md.Add($l) }
    $md.Add('```')
}
$md.Add("")
$md.Add("## Frames In This Mod")
$md.Add("")
if ($frames.Count -eq 0) {
    $md.Add("空")
} else {
    $md.Add('```text')
    foreach ($f in $frames) { $md.Add($f) }
    $md.Add('```')
}
$md.Add("")
$md.Add("## 修复建议")
$md.Add("")
if ($hits.Count -eq 0) {
    $md.Add("按 error-triage 第 7 节继续回归：``build.ps1 -Task compileJava`` → ``run-client.ps1`` → 本脚本复检。")
} else {
    $seen = @{}
    foreach ($h in $hits) {
        if ($seen.ContainsKey($h.Fix)) { continue }
        $seen[$h.Fix] = $true
        $md.Add(("- [{0}] {1}" -f $h.Category, $h.Fix))
    }
}
$md.Add("")
$md.Add("下一站：``references/error-triage.md`` 第 2–4 节（症状→根因→修复对照表）。")

$md | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host ("[diagnostics] status={0}" -f $status)
Write-Host ("[diagnostics] hits={0} frames={1} build={2} client={3}" -f $hits.Count, $frames.Count, $buildOutcome, $clientStatus)
Write-Host ("[diagnostics] report -> {0}" -f $OutputPath)

if ($status -eq "clean") { exit 0 }
exit 1