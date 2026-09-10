param(
    [string]$PythonExe = "python.exe",
    [string]$SourceFont = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputFont = Join-Path $projectRoot "assets\fonts\yizhe-ui-subset.ttf"
$downloadedFont = Join-Path $env:TEMP "NotoSansSC-wght.ttf"
$staticFont = Join-Path $env:TEMP "NotoSansSC-Regular.ttf"

if ([string]::IsNullOrWhiteSpace($SourceFont)) {
    $SourceFont = $downloadedFont
    if (-not (Test-Path -LiteralPath $SourceFont)) {
        & curl.exe -fL --retry 3 -o $SourceFont `
            "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
        if ($LASTEXITCODE -ne 0) {
            throw "Could not download Noto Sans SC."
        }
    }
}

& $PythonExe -c "import fontTools"
if ($LASTEXITCODE -ne 0) {
    throw "Python package 'fontTools' is required."
}

$runtimeRoots = @("app", "autoload", "core", "data", "scenes", "systems", "ui") |
    ForEach-Object { Join-Path $projectRoot $_ }
$runtimeFiles = Get-ChildItem $runtimeRoots -Recurse -File |
    Where-Object { $_.Extension -in @(".gd", ".tscn", ".tres") }
$runtimeText = foreach ($file in $runtimeFiles) {
    Get-Content -LiteralPath $file.FullName -Raw
}
$runtimeText += Get-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Raw

$codepoints = [System.Collections.Generic.HashSet[int]]::new()
foreach ($value in 0x20..0x7E) {
    [void]$codepoints.Add($value)
}
foreach ($character in (($runtimeText -join "`n").ToCharArray())) {
    $value = [int]$character
    if ($value -ge 0x20 -and -not ($value -ge 0xD800 -and $value -le 0xDFFF)) {
        [void]$codepoints.Add($value)
    }
}
$unicodeSpec = (($codepoints | Sort-Object | ForEach-Object { "U+{0:X4}" -f $_ }) -join ",")

Remove-Item -LiteralPath $staticFont -Force -ErrorAction SilentlyContinue
& $PythonExe -m fontTools.varLib.instancer $SourceFont "wght=400" --output=$staticFont
if ($LASTEXITCODE -ne 0) {
    throw "Could not instantiate the regular font weight."
}

& $PythonExe -m fontTools.subset $staticFont --output-file=$outputFont `
    --unicodes=$unicodeSpec --layout-features="*" --no-hinting --drop-tables+=DSIG
if ($LASTEXITCODE -ne 0) {
    throw "Could not subset the UI font."
}

$size = (Get-Item -LiteralPath $outputFont).Length
Write-Output "UI font created: $outputFont ($size bytes, $($codepoints.Count) requested code points)"
