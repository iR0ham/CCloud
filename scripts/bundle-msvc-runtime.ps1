#Requires -Version 7.0
<#
    Stages a Flutter Windows release folder for distribution.

    A Flutter ZIP without the MSVC runtime starts and dies with no window:
    msvcp140.dll / vcruntime140.dll / vcruntime140_1.dll are imported by
    ccloud.exe and every plugin DLL, but `flutter build windows` does not copy
    them. This script copies the release output to |PackageDir| and adds the
    three DLLs from the newest Visual Studio redistributable, then fails loudly
    if any of them is missing.

    Both the portable and the compatibility CI package use this one script so
    the two staging paths cannot drift apart.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$PackageDir
)

$ErrorActionPreference = 'Stop'

$source = (Resolve-Path -LiteralPath $ReleaseDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $source 'ccloud.exe'))) {
    throw "ccloud.exe is missing from $source"
}

$dest = $PackageDir
if (-not [System.IO.Path]::IsPathRooted($dest)) {
    $dest = Join-Path (Get-Location).Path $dest
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $source '*') $dest -Recurse -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($file in @('NOTICE', 'THIRD_PARTY_NOTICES.md', 'SOURCES.md', 'Legal\DISTRIBUTION_STATUS.md')) {
    $canonical = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "Canonical legal file is missing: $canonical"
    }
}
$canonicalLicenses = Join-Path $repoRoot 'Legal\licenses'
if (-not (Test-Path -LiteralPath $canonicalLicenses -PathType Container)) {
    throw "Canonical license directory is missing: $canonicalLicenses"
}
foreach ($file in @('NOTICE', 'THIRD_PARTY_NOTICES.md', 'SOURCES.md')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $dest $file) -Force
}
$legalDest = Join-Path $dest 'Legal'
if (Test-Path -LiteralPath $legalDest) {
    Remove-Item -LiteralPath $legalDest -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'Legal') -Destination $legalDest -Recurse -Force

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "vswhere.exe not found at $vswhere"
}
$vs = (& $vswhere -latest -property installationPath).Trim()
if (-not $vs) {
    throw 'vswhere returned no Visual Studio installation'
}

# The redist layout is VC\Redist\MSVC\<version>\x64\Microsoft.VC143.CRT.
# <version> is a directory name (14.38.33135 etc.); Microsoft.VC143.CRT holds
# only DLL files, so it must not be enumerated as a directory and the wildcard
# must sit on the version level, not on the leaf.
$redistRoot = Join-Path $vs 'VC\Redist\MSVC'
if (-not (Test-Path -LiteralPath $redistRoot)) {
    throw "MSVC redistributable folder not found at $redistRoot"
}
$crt = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Where-Object { $_.Name -as [version] } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $crt) {
    throw "No Microsoft.VC143.CRT under $redistRoot"
}
Write-Host "Using CRT redist: $crt"

foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    Copy-Item (Join-Path $crt $dll) $dest -Force
    if (-not (Test-Path -LiteralPath (Join-Path $dest $dll))) {
        throw "$dll is missing from $dest after copying"
    }
}

Write-Host "Staged release files in $dest :"
Get-ChildItem -LiteralPath $dest -File | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.Name)
}
