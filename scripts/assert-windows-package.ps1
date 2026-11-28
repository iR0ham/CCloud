#Requires -Version 7.0
<#
    Asserts that a staged Windows package can start on a clean machine and that
    its legal files are the canonical repository bytes.

    ccloud.exe and its plugin DLLs import the three MSVC runtime DLLs, but
    `flutter build windows` does not copy them; libmpv and data/app.so are the
    other files whose absence leaves the app windowless or unable to play. The
    portable and the compatibility package are both checked with this script so
    they cannot silently diverge.

    Existence alone does not prove the shipped notices: bundle-msvc-runtime.ps1
    copies the legal files over whatever the build tree already held, so a stale
    or edited copy would still pass a Test-Path check. Every staged legal file is
    therefore also compared by SHA-256 against the repository canonical copy, the
    same evidence class the Android APK and webOS IPK assertions provide.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageDir
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $PackageDir).Path
$runtimeFiles = @(
    'ccloud.exe',
    'flutter_windows.dll',
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'libmpv-2.dll',
    'data\app.so'
)
# Repository-relative paths, identical inside the staged package. This is the
# layout bundle-msvc-runtime.ps1 creates: three documents at the package root and
# the whole Legal/ tree (status file plus ten license texts) below it.
$legalFiles = @(
    'NOTICE',
    'THIRD_PARTY_NOTICES.md',
    'SOURCES.md',
    'Legal\DISTRIBUTION_STATUS.md',
    'Legal\licenses\MIT-code3-dev-CCloud.txt',
    'Legal\licenses\MIT-media_kit.txt',
    'Legal\licenses\MIT-famelack-data.txt',
    'Legal\licenses\OFL-1.1-Vazirmatn.txt',
    'Legal\licenses\Unlicense-iptv-org.txt',
    'Legal\licenses\BSD-3-Clause-ANGLE.txt',
    'Legal\licenses\GPL-2.0.txt',
    'Legal\licenses\GPL-3.0.txt',
    'Legal\licenses\LGPL-2.1.txt',
    'Legal\licenses\LGPL-3.0.txt'
)
$required = $runtimeFiles + $legalFiles
$missing = @($required | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $root $_))
})
if ($missing.Count -gt 0) {
    throw "Package is incomplete ($root): $($missing -join ', ')"
}

# The canonical copies live in the checkout this script was called from, not in
# the package: scripts/ is a direct child of the repository root, so the parent of
# $PSScriptRoot is the same tree bundle-msvc-runtime.ps1 staged from.
$canonicalRoot = Split-Path -Parent $PSScriptRoot
$mismatched = @()
$compared = 0
foreach ($file in $legalFiles) {
    $canonical = Join-Path $canonicalRoot $file
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "Canonical legal file is missing from the checkout: $canonical"
    }
    $canonicalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonical).Hash
    $packagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $file)).Hash
    if ($canonicalHash -ne $packagedHash) {
        $mismatched += ('{0}: package {1} != canonical {2}' -f $file, $packagedHash, $canonicalHash)
    }
    $compared += 1
}
if ($mismatched.Count -gt 0) {
    foreach ($detail in $mismatched) {
        Write-Host ("::error::staged legal file is not byte-equal to the canonical copy: {0}" -f $detail)
    }
    throw ("Legal byte-equality failed for {0} staged file(s): {1}" -f `
        $mismatched.Count, ($mismatched -join ', '))
}

Write-Host "Package contains the exe, Flutter DLL, MSVC runtime, libmpv, data/app.so and canonical legal files: $root"
Write-Host "Legal files are SHA-256 byte-equal to the canonical repository copies ($compared compared): $canonicalRoot"
Get-ChildItem -LiteralPath $root -File | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.Name)
}
