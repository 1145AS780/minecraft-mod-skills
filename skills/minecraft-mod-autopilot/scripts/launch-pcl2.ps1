param(
    [int]$TimeoutSeconds = 300,
    [int]$ReadyGraceSeconds = 10,
    [int]$PollSeconds = 2,
    [string]$InstancePath = "$env:APPDATA\.minecraft\versions\1.20.1-forge",
    [string]$LaunchScript,
    [string]$RepoRoot,
    [switch]$KeepRunning,
    [switch]$PlanOnly
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
            return (Get-Location).Path
        }
        $dir = $parent
    }
}

function Find-LaunchScript {
    param([string]$Instance, [string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "指定的启动脚本不存在：$Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $candidates = @(
        (Get-ChildItem -LiteralPath $Instance -Filter "启动*.bat" -File -ErrorAction SilentlyContinue),
        (Get-ChildItem -LiteralPath (Join-Path $Instance "mods") -Filter "启动*.bat" -File -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ }
    if ($candidates.Count -gt 0) {
        return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    if ($env:PCL_LAUNCHER -and (Test-Path -LiteralPath $env:PCL_LAUNCHER)) { return $env:PCL_LAUNCHER }
    $anyBat = @(Get-ChildItem -LiteralPath $Instance -Filter "*.bat" -File -ErrorAction SilentlyContinue)
    if ($anyBat.Count -gt 0) {
        return ($anyBat | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    throw "在 $Instance 下找不到启动脚本（启动*.bat / LatestLaunch.bat）；用 -LaunchScript 指定"
}

if (-not (Test-Path -LiteralPath $InstancePath)) { throw "实例目录不存在：$InstancePath" }
$instance = (Resolve-Path -LiteralPath $InstancePath).Path
$script = Find-LaunchScript -Instance $instance -Explicit $LaunchScript

$root = Resolve-RepoRoot -Start $RepoRoot
$logDir = Join-Path $root ".autopilot\logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Path $logDir -Force
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = Join-Path $logDir ("pcl2-{0}.summary.txt" -f $stamp)
$outLog = Join-Path $logDir ("pcl2-{0}.out.log" -f $stamp)
$errLog = Join-Path $logDir ("pcl2-{0}.err.log" -f $stamp)
$latest = Join-Path $instance "logs\latest.log"
$crashDir = Join-Path $instance "crash-reports"

$batLines = @(Get-Content -LiteralPath $script -ErrorAction SilentlyContinue)
$cdLine = @($batLines | Where-Object { $_ -match 'cd\s+/D\s+"' } | Select-Object -First 1)
$hasQuickPlay = @($batLines | Where-Object { $_ -match '--quickPlaySingleplayer' }).Count -gt 0

Write-Host ("[pcl2] instance={0}" -f $instance)
Write-Host ("[pcl2] launch={0}" -f $script)
Write-Host ("[pcl2] latest.log={0}" -f $latest)
Write-Host ("[pcl2] summary={0}" -f $summary)
Write-Host ("[pcl2] timeout={0}s readyGrace={1}s" -f $TimeoutSeconds, $ReadyGraceSeconds)
if ($cdLine) {
    if ($cdLine -notmatch [regex]::Escape($instance)) {
        Write-Host ("[pcl2] 警告：脚本工作目录与实例不一致 -> {0}" -f $cdLine.Trim())
    }
}
if (-not $hasQuickPlay) {
    Write-Host "[pcl2] 提示：启动脚本未含 --quickPlaySingleplayer，需人工进世界后才能做世界内验收"
}
if (-not (Test-Path -LiteralPath (Join-Path $instance "mods"))) {
    Write-Host "[pcl2] 警告：实例下没有 mods 目录"
}

$readyMarkers = @(
    "Sound engine started",
    "Narrator library for x64 successfully loaded",
    "OpenAL initialized"
)
$crashMarkers = @(
    "Crash report",
    "Mod loading has failed",
    "A fatal error has been detected",
    "Exception in server tick loop",
    "Failed to create window"
)

if ($PlanOnly) {
    Write-Host ("[pcl2] plan: cd `"{0}`" ; cmd /c `"{1}`"" -f ([IO.Path]::GetDirectoryName($script)), $script)
    exit 0
}

$startPos = 0L
if (Test-Path -LiteralPath $latest) { $startPos = (Get-Item -LiteralPath $latest).Length }

$crashBefore = @{}
if (Test-Path -LiteralPath $crashDir) {
    foreach ($f in Get-ChildItem -LiteralPath $crashDir -Filter "crash-*.txt" -File -ErrorAction SilentlyContinue) {
        $crashBefore[$f.Name] = $true
    }
}

$proc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", ('"{0}"' -f $script)) -WorkingDirectory ([IO.Path]::GetDirectoryName($script)) -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
Write-Host ("[pcl2] pid={0}" -f $proc.Id)

$startedAt = Get-Date
$deadline = $startedAt.AddSeconds($TimeoutSeconds)
$status = "timeout"
$seenReady = ""
$seenCrash = ""
$newCrash = ""
$readyAt = $null
$lastRead = $startPos

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    if (Test-Path -LiteralPath $latest) {
        $len = (Get-Item -LiteralPath $latest).Length
        if ($len -gt $lastRead) {
            $fs = [IO.File]::Open($latest, 'Open', 'Read', 'ReadWrite')
            try {
                $null = $fs.Seek($lastRead, 'Begin')
                $reader = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                $chunk = $reader.ReadToEnd()
            } finally {
                $fs.Dispose()
            }
            $lastRead = $len
            foreach ($m in $readyMarkers) {
                if (-not $seenReady -and $chunk.Contains($m)) { $seenReady = $m; $readyAt = Get-Date }
            }
            foreach ($m in $crashMarkers) {
                if (-not $seenCrash -and $chunk.Contains($m)) { $seenCrash = $m }
            }
        }
    }

    if (Test-Path -LiteralPath $crashDir) {
        foreach ($f in Get-ChildItem -LiteralPath $crashDir -Filter "crash-*.txt" -File -ErrorAction SilentlyContinue) {
            if (-not $crashBefore.ContainsKey($f.Name)) { $newCrash = $f.FullName; break }
        }
    }

    if ($newCrash) { $status = "crashed"; break }
    if ($seenCrash) { $status = "crashed"; break }
    if ($seenReady -and ((Get-Date) - $readyAt).TotalSeconds -ge $ReadyGraceSeconds) { $status = "ready"; break }
    if ($proc.HasExited) {
        $status = if ($proc.ExitCode -eq 0) { "exited-ok" } else { "exited-error" }
        break
    }
    if ((Get-Date) -gt $deadline) { $status = "timeout"; break }
}

$elapsed = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
$exitCode = "running"
if ($proc.HasExited) {
    try {
        $ec = $proc.ExitCode
        $exitCode = if ($null -eq $ec) { "unknown" } else { $ec }
    } catch { $exitCode = "unknown" }
}

if (-not $KeepRunning -and -not $proc.HasExited) {
    try { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null } catch { }
    try { $proc.WaitForExit(5000) | Out-Null } catch { }
    $exitCode = "killed"
}

$lines = @(
    ("status={0}" -f $status),
    ("elapsed={0}s" -f $elapsed),
    ("exitCode={0}" -f $exitCode),
    ("readyMarker={0}" -f $seenReady),
    ("crashMarker={0}" -f $seenCrash),
    ("newCrashReport={0}" -f $newCrash),
    ("instance={0}" -f $instance),
    ("launchScript={0}" -f $script),
    ("latestLog={0}" -f $latest),
    ("outLog={0}" -f $outLog),
    ("errLog={0}" -f $errLog)
)
$lines | Set-Content -LiteralPath $summary -Encoding UTF8

Write-Host ("[pcl2] status={0} elapsed={1}s exit={2}" -f $status, $elapsed, $exitCode)
Write-Host ("[pcl2] summary -> {0}" -f $summary)
if ($newCrash) { Write-Host ("[pcl2] 新崩溃报告：{0}" -f $newCrash) }
if ($seenCrash) { Write-Host ("[pcl2] 崩溃标记：{0}" -f $seenCrash) }

switch ($status) {
    "ready" { exit 0 }
    "exited-ok" { exit 0 }
    "crashed" { exit 2 }
    "exited-error" { exit 4 }
    default { exit 3 }
}