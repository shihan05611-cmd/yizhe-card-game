[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Resolve-ConfiguredGodotPath {
    param([string]$Candidate, [string]$SourceLabel)

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
    if ($null -ne $resolved) { return $resolved }

    $resolved = Resolve-ConfiguredGodotPath -Candidate $env:GODOT_BIN -SourceLabel 'GODOT_BIN'
    if ($null -ne $resolved) { return $resolved }

    foreach ($commandName in @('godot', 'godot4')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            $candidate = if ([string]::IsNullOrWhiteSpace($command.Source)) { $command.Path } else { $command.Source }
            $resolved = Resolve-ConfiguredGodotPath -Candidate $candidate -SourceLabel "PATH ($commandName)"
            if ($null -ne $resolved) { return $resolved }
        }
    }

    $downloadsCandidate = Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
    if (Test-Path -LiteralPath $downloadsCandidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $downloadsCandidate).Path
    }
    throw 'Godot was not found. Pass -GodotExe, set GODOT_BIN, add godot/godot4 to PATH, or install Godot 4.7.1 under your Downloads folder.'
}

$resolvedGodot = Resolve-GodotExecutable
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectRoot 'dist\web'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
if (-not $outputRoot.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must stay inside this project: $projectRoot"
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$godotIgnorePath = Join-Path $outputRoot '.gdignore'
Set-Content -LiteralPath $godotIgnorePath -Value '; Generated Web export output; do not import as project resources.' -Encoding Ascii
Get-ChildItem -LiteralPath $outputRoot -File -Filter '*.import' -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath (Join-Path $outputRoot 'export.log') -Force -ErrorAction SilentlyContinue
$logRoot = Join-Path $projectRoot '.godot\export-logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$entryPoint = Join-Path $outputRoot 'index.html'
$exportLog = Join-Path $logRoot 'web-export.log'
& $resolvedGodot --headless --path $projectRoot --log-file $exportLog --export-release 'Web' $entryPoint
if ($LASTEXITCODE -ne 0) {
    throw "Web export failed. See $exportLog"
}

$requiredFiles = @('index.html', 'index.js', 'index.wasm', 'index.pck')
$missingFiles = $requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $outputRoot $_) -PathType Leaf) }
if ($missingFiles.Count -gt 0) {
    throw "Web export is incomplete. Missing: $($missingFiles -join ', '). See $exportLog"
}

Get-ChildItem -LiteralPath $outputRoot -File | Select-Object Name, Length
Write-Output "Web build created: $outputRoot"
Write-Output "Export log: $exportLog"
Write-Output 'Serve this directory through HTTP(S); do not open index.html with file://.'
