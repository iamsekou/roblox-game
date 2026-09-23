# Builds the lobby bubble portraits from art/reference/* using portraits.csv (crop box + bubble colours).
# Output: art/portraits/silhouette/<id>.png (512x512, the in-game style since 2026-09-23) or, with
# -Style color, the original full-colour art/portraits/<id>.png. Each folder gets a _contact_sheet.png.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools/portraits/make-portraits.ps1 [-Style color]
param([ValidateSet("silhouette", "color")] [string]$Style = "silhouette")
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here "..\..")
$refDir = Join-Path $repo "art\reference"
$outDir = Join-Path $repo "art\portraits"
if ($Style -eq "silhouette") { $outDir = Join-Path $outDir "silhouette" }
New-Item -ItemType Directory -Force $outDir | Out-Null

if (-not ("PortraitMaker" -as [type])) {
    Add-Type -Path (Join-Path $here "PortraitMaker.cs") -ReferencedAssemblies PresentationCore, WindowsBase, System.Xaml
}

function Num($value, $fallback) { if ($value) { [int]$value } else { $fallback } }

$made = @()
foreach ($row in Import-Csv (Join-Path $here "portraits.csv")) {
    $c1 = $row.centerRGB.Split(" ") | ForEach-Object { [byte]$_ }
    $c2 = $row.edgeRGB.Split(" ") | ForEach-Object { [byte]$_ }
    $out = Join-Path $outDir ($row.id + ".png")
    [PortraitMaker]::Render((Join-Path $refDir $row.source), $out, [int]$row.cropX, [int]$row.cropY, [int]$row.side,
        $c1[0], $c1[1], $c1[2], $c2[0], $c2[1], $c2[2], [int]$row.tolerance, [single]$row.closeRadius, ($Style -eq "silhouette"),
        ($row.dropChair -eq "1"), (Num $row.seedX -1), (Num $row.seedY -1), [single](Num $row.cleanRadius 0))
    $made += $out
    Write-Output ("made " + $row.id)
}
[PortraitMaker]::ContactSheet([string[]]$made, (Join-Path $outDir "_contact_sheet.png"), 5)
Write-Output "contact sheet written"
