param(
    [string[]]$Task = @("build"),
    [string]$RepoRoot,
    [string]$JavaHome = $env:JAVA_HOME_17,
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
$gradlew = Join-Path $root "gradlew.bat"
$logDir = Join-Path $root ".autopilot\logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Path $logDir -Force
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tag = (($Task -join "+") -replace '[\\/:*?"<>|]', '_')
$log = Join-Path $logDir ("build-{0}-{1}.log" -f $tag, $stamp)

if (-not $JavaHome) {
    throw "未指定 JDK 17：设置环境变量 JAVA_HOME_17，或用 -JavaHome 传入 JDK 17 安装目录"
}
if (-not (Test-Path -LiteralPath (Join-Path $JavaHome "bin\java.exe"))) {
    throw "JDK 17 缺失：$JavaHome（PATH 上的 java 不保证是 17，不能用于 Forge 1.20.1）"
}
$env:JAVA_HOME = $JavaHome
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = Join-Path $HOME ".gradle" }

Write-Host ("[build] root={0}" -f $root)
Write-Host ("[build] task={0}" -f ($Task -join " "))
Write-Host ("[build] jdk={0}" -f $env:JAVA_HOME)
Write-Host ("[build] log={0}" -f $log)

if ($PlanOnly) {
    Write-Host ("[build] plan: cd `"{0}`" ; `"{1}`" {2} --console=plain" -f $root, $gradlew, ($Task -join " "))
    exit 0
}

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
Push-Location -LiteralPath $root
try {
    & $gradlew @Task --console=plain 2>&1 | Tee-Object -FilePath $log
} finally {
    Pop-Location
    $ErrorActionPreference = $prevEap
}
$code = $LASTEXITCODE

Write-Host ("[build] exit={0}" -f $code)

if ($code -ne 0) {
    $all = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
    $errorLines = @($all | Where-Object { $_ -match '\berror:' } | Select-Object -First 30)
    Write-Host "[build] 失败摘要"
    if ($errorLines.Count -gt 0) {
        Write-Host ("  error: 行 {0} 条（最多显示 30）" -f $errorLines.Count)
        foreach ($line in $errorLines) { Write-Host ("  " + $line.Trim()) }
    } else {
        Write-Host "  无 error: 行，看 FAILURE 段（依赖/网络/插件）"
    }
    $idx = -1
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -match '\* What went wrong:') { $idx = $i; break }
    }
    if ($idx -ge 0) {
        $end = [Math]::Min($idx + 8, $all.Count - 1)
        Write-Host "  What went wrong:"
        for ($i = $idx; $i -le $end; $i++) { Write-Host ("  " + $all[$i]) }
    }
}

exit $code