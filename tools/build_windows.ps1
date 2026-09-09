[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Resolve-ConfiguredGodotPath {
    param(
        [string]$Candidate,
        [string]$SourceLabel
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        throw "$SourceLabel points to a missing or non-file Godot executable: $Candidate"
    }
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Resolve-GodotExecutable {
    $resolved = Resolve-ConfiguredGodotPath -Candidate $GodotExe -SourceLabel '-GodotExe'
    if ($null -ne $resolved) {
        return $resolved
    }

    $resolved = Resolve-ConfiguredGodotPath -Candidate $env:GODOT_BIN -SourceLabel 'GODOT_BIN'
    if ($null -ne $resolved) {
        return $resolved
    }

    foreach ($commandName in @('godot', 'godot4')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $candidate = if ([string]::IsNullOrWhiteSpace($command.Source)) { $command.Path } else { $command.Source }
            $resolved = Resolve-ConfiguredGodotPath -Candidate $candidate -SourceLabel "PATH ($commandName)"
            if ($null -ne $resolved) {
                return $resolved
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $downloadsCandidate = Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe'
        if (Test-Path -LiteralPath $downloadsCandidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $downloadsCandidate).Path
        }
    }

    throw 'Godot was not found. Pass -GodotExe, set GODOT_BIN, add godot/godot4 to PATH, or install Godot 4.7.1 under your Downloads folder.'
}

function Resolve-BundledGodotExecutable {
    param([string]$ResolvedGodot)

    $fileName = Split-Path -Leaf $ResolvedGodot
    if ($fileName -notmatch '_console\.exe$') {
        return $ResolvedGodot
    }
    $guiCandidate = Join-Path (Split-Path -Parent $ResolvedGodot) ($fileName -replace '_console\.exe$', '.exe')
    if (Test-Path -LiteralPath $guiCandidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $guiCandidate).Path
    }
    return $ResolvedGodot
}

$resolvedGodot = Resolve-GodotExecutable
$bundleGodot = Resolve-BundledGodotExecutable -ResolvedGodot $resolvedGodot
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectRoot 'build\YizheCardGame'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
if (-not $outputRoot.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must stay inside this project: $projectRoot"
}
$consoleBaseName = [System.IO.Path]::GetFileNameWithoutExtension($bundleGodot)
$consoleExe = Join-Path (Split-Path -Parent $bundleGodot) ($consoleBaseName + '_console.exe')
$exportExe = if (Test-Path -LiteralPath $consoleExe -PathType Leaf) { $consoleExe } else { $resolvedGodot }
$packPath = Join-Path $outputRoot 'YizheCardGame.pck'
$logsPath = Join-Path $outputRoot 'logs'

New-Item -ItemType Directory -Force -Path $outputRoot, $logsPath | Out-Null
$exportLog = Join-Path $logsPath 'export-pack.log'
& $exportExe --headless --path $projectRoot --log-file $exportLog --export-pack 'Windows Portable Pack' $packPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    throw "Pack export failed. See $exportLog"
}

Copy-Item -LiteralPath $bundleGodot -Destination (Join-Path $outputRoot 'Godot.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play.ps1') -Destination (Join-Path $outputRoot 'play.ps1') -Force
$launcherPath = Join-Path $outputRoot '启动游戏.cmd'
$launcherSource = @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1"
'@
Set-Content -LiteralPath $launcherPath -Value $launcherSource -Encoding Ascii

Write-Output "Portable main-pack delivery created: $outputRoot"
Write-Output "Bundled Godot executable: $bundleGodot"
Write-Output "Double-click 启动游戏.cmd, or run .\play.ps1. Logs stay in $logsPath"
