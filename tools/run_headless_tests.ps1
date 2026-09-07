[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GodotExe,

    [Parameter(Mandatory = $false)]
    [switch]$SelfTestFailure,

    [Parameter(Mandatory = $false)]
    [switch]$SelfTestCompileFailure
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Stop-WithUsageError {
    param([string]$Message)

    [Console]::Error.WriteLine("Headless test launcher error: $Message")
    exit 2
}

function Resolve-ConfiguredGodotPath {
    param(
        [string]$Candidate,
        [string]$SourceLabel
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        Stop-WithUsageError "$SourceLabel points to a missing or non-file Godot executable: $Candidate"
    }

    return (Resolve-Path -LiteralPath $Candidate).Path
}

$resolvedGodot = Resolve-ConfiguredGodotPath -Candidate $GodotExe -SourceLabel '-GodotExe'
if ($null -eq $resolvedGodot) {
    $resolvedGodot = Resolve-ConfiguredGodotPath -Candidate $env:GODOT_BIN -SourceLabel 'GODOT_BIN'
}

if ($null -eq $resolvedGodot) {
    foreach ($commandName in @('godot', 'godot4')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $resolvedGodot = $command.Source
            if ([string]::IsNullOrWhiteSpace($resolvedGodot)) {
                $resolvedGodot = $command.Path
            }
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedGodot)) {
    Stop-WithUsageError 'Godot was not found. Pass -GodotExe, set GODOT_BIN, or add godot/godot4 to PATH.'
}

$logDirectory = Join-Path $projectRoot '.godot\test-logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logPath = Join-Path $logDirectory "headless-tests-$timestamp-$PID.log"

$godotArguments = @(
    '--headless',
    '--log-file', $logPath,
    '--path', $projectRoot,
    '--script', 'res://tests/run_all.gd'
)
if ($SelfTestFailure) {
    $godotArguments += @('--', '--self-test-failure')
}
if ($SelfTestCompileFailure) {
    if (-not $SelfTestFailure) {
        $godotArguments += '--'
    }
    $godotArguments += '--self-test-compile-failure'
}

Write-Output "Project root: $projectRoot"
Write-Output "Godot executable: $resolvedGodot"
Write-Output "Godot log: $logPath"

& $resolvedGodot @godotArguments
$godotExitCode = $LASTEXITCODE
exit $godotExitCode
