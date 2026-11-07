param(
    [int]$TimeoutSeconds = 240,
    [int]$ReadyGraceSeconds = 10,
    [int]$PollSeconds = 2,
    [string]$RepoRoot,
    [string]$JavaHome = $env:JAVA_HOME_17,
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
            throw "找不到仓库根（需同时含 gradlew.bat 与 settings.gradle）；用 -RepoRoot 指定"
        }
        $dir = $parent
    }
}

$root = Resolve-RepoRoot -Start $RepoRoot
$logDir = Join-Path $root ".autopilot\logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Path $logDir -Force
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = Join-Path $logDir ("client-{0}.summary.txt" -f $stamp)
$outLog = Join-Path $logDir ("client-{0}.out.log" -f $stamp)
$errLog = Join-Path $logDir ("client-{0}.err.log" -f $stamp)
$latest = Join-Path $root "run\logs\latest.log"

if (-not $JavaHome) {
    throw "未指定 JDK 17：设置环境变量 JAVA_HOME_17，或用 -JavaHome 传入 JDK 17 安装目录"
}
if (-not (Test-Path -LiteralPath (Join-Path $JavaHome "bin\java.exe"))) {
    throw "JDK 17 缺失：$JavaHome（PATH 上的 java 不保证是 17，不能用于 Forge 1.20.1）"
}
$env:JAVA_HOME = $JavaHome
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = Join-Path $HOME ".gradle" }

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

Write-Host ("[run-client] root={0}" -f $root)
Write-Host ("[run-client] jdk={0}" -f $env:JAVA_HOME)
Write-Host ("[run-client] latest.log={0}" -f $latest)
Write-Host ("[run-client] summary={0}" -f $summary)
Write-Host ("[run-client] timeout={0}s readyGrace={1}s" -f $TimeoutSeconds, $ReadyGraceSeconds)

$gradlew = Join-Path $root "gradlew.bat"
if ($PlanOnly) {
    Write-Host ("[run-client] plan: cd `"{0}`" ; `"{1}`" runClient --console=plain" -f $root, $gradlew)
    exit 0
}

$startPos = 0L
if (Test-Path -LiteralPath $latest) { $startPos = (Get-Item -LiteralPath $latest).Length }

$cmd = '"{0}" runClient --console=plain' -f $gradlew
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmd) -WorkingDirectory $root -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
Write-Host ("[run-client] pid={0}" -f $proc.Id)

$startedAt = Get-Date
$deadline = $startedAt.AddSeconds($TimeoutSeconds)
$status = "timeout"
$seenReady = ""
$seenCrash = ""
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
    ("latestLog={0}" -f $latest),
    ("outLog={0}" -f $outLog),
    ("errLog={0}" -f $errLog),
    ("jdk={0}" -f $env:JAVA_HOME)
)
$lines | Set-Content -LiteralPath $summary -Encoding UTF8

Write-Host ("[run-client] status={0} elapsed={1}s exit={2}" -f $status, $elapsed, $exitCode)
Write-Host ("[run-client] summary -> {0}" -f $summary)
if ($seenCrash) { Write-Host ("[run-client] 崩溃标记：{0}" -f $seenCrash) }

switch ($status) {
    "ready" { exit 0 }
    "exited-ok" { exit 0 }
    "crashed" { exit 2 }
    "exited-error" { exit 4 }
    default { exit 3 }
}