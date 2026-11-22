#Requires -Version 7.0
<#
    Asserts that a staged Windows package can start on a clean machine.

    ccloud.exe and its plugin DLLs import the three MSVC runtime DLLs, but
    `flutter build windows` does not copy them; libmpv and data/app.so are the
    other files whose absence leaves the app windowless or unable to play. The
    portable and the compatibility package are both checked with this script so
    they cannot silently diverge.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageDir
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $PackageDir).Path
$required = @(
    'ccloud.exe',
    'flutter_windows.dll',
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'libmpv-2.dll',
    'data\app.so'
)
$missing = @($required | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $root $_))
})
if ($missing.Count -gt 0) {
    throw "Package is incomplete ($root): $($missing -join ', ')"
}

Write-Host "Package contains the exe, Flutter DLL, MSVC runtime, libmpv and data/app.so: $root"
Get-ChildItem -LiteralPath $root -File | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.Name)
}
