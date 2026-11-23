#Requires -Version 7.0
<#
    Builds the Windows installer from an already staged release folder.

    The staged folder must contain ccloud.exe, the Flutter/libmpv DLLs and the
    three MSVC runtime DLLs (the CI workflow adds them). Inno Setup is looked up
    in the usual install locations and, when missing, installed with Chocolatey
    as a best effort. If no compiler can be found the step says so and exits 0:
    a missing Inno Setup must not hide the portable build, but the log marks the
    installer as skipped.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$AppVersion
)

$ErrorActionPreference = 'Stop'

function Set-StepOutput {
    param([string]$Name, [string]$Value)
    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
}

function Find-Iscc {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

$source = (Resolve-Path -LiteralPath $ReleaseDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $source 'ccloud.exe'))) {
    throw "ccloud.exe is missing from $source"
}

$out = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputDir))
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

$iss = Join-Path (Split-Path -Parent $PSScriptRoot) 'installer\ccloud.iss'
if (-not (Test-Path -LiteralPath $iss)) {
    throw "Inno Setup script not found at $iss"
}

$iscc = Find-Iscc
if (-not $iscc) {
    Write-Host 'Inno Setup is not installed; trying Chocolatey (best effort).'
    try {
        choco install innosetup -y --no-progress
        $iscc = Find-Iscc
    }
    catch {
        Write-Host "Chocolatey install failed: $($_.Exception.Message)"
    }
}

if (-not $iscc) {
    Write-Host '::warning::Inno Setup is unavailable on this runner; the Windows installer was skipped.'
    Set-StepOutput 'created' 'false'
    exit 0
}

Write-Host "Using Inno Setup compiler: $iscc"
# The install test falls back to /CURRENTUSER when the machine-wide install is
# refused, and that switch only exists from Inno Setup 6.3 - so record which
# compiler actually produced the package instead of making anyone guess.
try {
    $isccVersion = (Get-Item -LiteralPath $iscc).VersionInfo
    Write-Host ("ISCC version: file '{0}' product '{1}'" -f
        $isccVersion.FileVersion, $isccVersion.ProductVersion)
}
catch {
    Write-Host "ISCC version could not be read: $($_.Exception.Message)"
}
Write-Host "Source: $source"
Write-Host "Output: $out"
& $iscc "/DSourceDir=$source" "/DOutputDir=$out" "/DAppVersion=$AppVersion" $iss
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$setup = Get-ChildItem -LiteralPath $out -Filter 'CCloud-*-setup.exe' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) {
    throw "ISCC reported success but no setup executable exists in $out"
}

Write-Host ("Installer: {0} ({1} bytes)" -f $setup.FullName, $setup.Length)
Set-StepOutput 'created' 'true'
Set-StepOutput 'path' $setup.FullName
exit 0
