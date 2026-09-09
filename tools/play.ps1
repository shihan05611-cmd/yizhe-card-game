[CmdletBinding()]
param(
    [switch]$HeadlessSmoke
)

$ErrorActionPreference = 'Stop'
$buildRoot = Split-Path -Parent $PSCommandPath
$enginePath = Join-Path $buildRoot 'Godot.exe'
$packPath = Join-Path $buildRoot 'YizheCardGame.pck'
$logsPath = Join-Path $buildRoot 'logs'

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Portable engine is missing: $enginePath"
}
if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    throw "Game pack is missing: $packPath"
}

New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logsPath "play-$timestamp.log"
$godotArgs = @('--main-pack', $packPath, '--log-file', $logPath)
if ($HeadlessSmoke) {
    $godotArgs = @('--headless') + $godotArgs + @('--quit-after', '3')
}

$argumentLine = ($godotArgs | ForEach-Object { '"{0}"' -f ($_ -replace '"', '\"') }) -join ' '
if (-not $HeadlessSmoke) {
    Start-Process -FilePath $enginePath -ArgumentList $argumentLine | Out-Null
    Write-Output "Game started. Log: $logPath"
    return
}

$process = Start-Process -FilePath $enginePath -ArgumentList $argumentLine -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Godot exited with $($process.ExitCode). See $logPath"
}

$logText = Get-Content -Raw -LiteralPath $logPath -ErrorAction SilentlyContinue
$unexpectedErrors = @(
    $logText -split "`r?`n" | Where-Object {
        (
            $_ -match 'SCRIPT ERROR|Parse Error|Failed loading resource|Cannot load' -or
            ($_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store')
        )
    }
)
if ($unexpectedErrors.Count -gt 0) {
    throw "Portable smoke found a startup error. See $logPath"
}
Write-Output "Portable main-pack smoke passed: $logPath"
