#Requires -Version 7.0
<#
    Installs the CI-built setup.exe for real, then runs the launch smoke test
    against the INSTALLED copy.

    The portable package has always been executed by CI, but the installer -
    which is the package the README recommends - was only ever compiled and
    uploaded. That leaves the copy step, the target folder, the shortcuts and
    the registry entry unproven: an installer that installs to the wrong place,
    drops the runtime DLLs, or produces an exe that cannot start would still
    have shipped green. This job catches exactly that.

    Two things make the check non-trivial and both are handled here:

    1. A setup.exe that has to elevate can return 0 without having installed
       anything (the original process only hands the work to the elevated
       child). So success is decided by finding the installed files, never by
       the exit code alone.
    2. Whether {autopf} resolves to Program Files or to %LOCALAPPDATA%\Programs
       depends on the elevation mode. Both prefixes are probed, and if the
       machine-wide install is refused the installer is retried per-user.

    Any functional failure exits non-zero so the workflow goes red.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SetupPath,

    [string]$ScreenshotPath = 'windows-smoke-installed.png',

    [int]$InstallTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

$setup = (Resolve-Path -LiteralPath $SetupPath).Path
Write-Host "Installer under test: $setup ($((Get-Item -LiteralPath $setup).Length) bytes)"

$smoke = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\windows-smoke.ps1'
if (-not (Test-Path -LiteralPath $smoke)) {
    Write-Host "::error::windows-smoke.ps1 was not found next to this script"
    exit 1
}

# The installer writes its own log; on failure it is the only explanation CI has.
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$installLog = Join-Path $tempRoot 'ccloud-install.log'
if (Test-Path -LiteralPath $installLog) {
    Remove-Item -LiteralPath $installLog -Force
}

# Where Inno's {autopf} lands: machine-wide for an elevated run, per-user for
# a /CURRENTUSER run.
$prefixes = @(
    (Join-Path $env:ProgramFiles 'CCloud'),
    (Join-Path $env:LOCALAPPDATA 'Programs\CCloud')
)

function Get-InstallDir {
    # unins000.exe is written in Inno's post-install step, so its presence means
    # the install actually completed rather than being half-copied.
    foreach ($prefix in $prefixes) {
        if ((Test-Path -LiteralPath (Join-Path $prefix 'ccloud.exe')) -and
            (Test-Path -LiteralPath (Join-Path $prefix 'unins000.exe'))) {
            return (Resolve-Path -LiteralPath $prefix).Path
        }
    }
    return $null
}

function Show-InstallLog {
    if (Test-Path -LiteralPath $installLog) {
        Write-Host '--- last 40 lines of the Inno Setup log ---'
        Get-Content -LiteralPath $installLog -Tail 40 | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host '::warning::the installer wrote no log file'
    }
}

function Invoke-Installer {
    param([string[]]$Arguments)

    Write-Host ("Running setup.exe: {0}" -f ($Arguments -join ' '))
    # Start-Process rather than a direct call: the argument list stays literal
    # and an elevation hand-off cannot deadlock this shell.
    $proc = Start-Process -FilePath $setup -ArgumentList $Arguments -PassThru
    if (-not $proc.WaitForExit($InstallTimeoutSeconds * 1000)) {
        Write-Host ("::warning::setup.exe is still running after {0}s" -f $InstallTimeoutSeconds)
    }
    else {
        Write-Host ("setup.exe exited with code {0}" -f $proc.ExitCode)
    }
}

$quiet = @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    '/CLOSEAPPLICATIONS',
    "/LOG=$installLog"
)

$installed = Get-InstallDir
if (-not $installed) {
    Invoke-Installer -Arguments $quiet
    $installed = Get-InstallDir
}

if (-not $installed) {
    Write-Host '::warning::machine-wide install produced no CCloud folder; retrying per-user'
    Show-InstallLog
    Invoke-Installer -Arguments (@('/CURRENTUSER') + $quiet)
    $installed = Get-InstallDir
}

if (-not $installed) {
    Write-Host ("::error::CCloud was not installed into any of: {0}" -f ($prefixes -join ', '))
    Show-InstallLog
    exit 1
}

Write-Host "Installed to: $installed"
Get-ChildItem -LiteralPath $installed -Recurse -File | Sort-Object FullName | ForEach-Object {
    Write-Host ("  {0,12}  {1}" -f $_.Length, $_.FullName.Substring($installed.Length).TrimStart('\'))
}

# BUILD.md promises an Add/Remove Programs entry; assert it instead of trusting it.
$arpRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
$entries = foreach ($root in $arpRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -eq 'CCloud' }
}
if (-not $entries) {
    Write-Host "::error::CCloud is not registered in Add/Remove Programs"
    exit 1
}
foreach ($entry in $entries) {
    Write-Host ("Add/Remove Programs entry: '{0}' version '{1}' (uninstall: {2})" -f
        $entry.DisplayName, $entry.DisplayVersion, $entry.UninstallString)
}

# The same assertions and the same launch test the portable package passes -
# against the files that are now actually on disk in the install location.
# It runs in a child pwsh on purpose: windows-smoke.ps1 ends with `exit`, and
# `exit` inside a script called with & would abort this script before the
# installer log could be printed. A separate process turns that into a plain
# exit code.
$pwsh = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    (Get-Command pwsh).Source
}
else {
    Join-Path $PSHOME 'pwsh.exe'
}

& $pwsh -NoProfile -ExecutionPolicy Bypass -File $smoke `
    -ReleaseDir $installed `
    -ScreenshotPath $ScreenshotPath
$smokeExit = $LASTEXITCODE
if ($smokeExit -ne 0) {
    Write-Host "::error::the installed ccloud.exe failed the launch smoke test (exit $smokeExit)"
    Show-InstallLog
    exit $smokeExit
}

Write-Host "OK: setup.exe installed CCloud and the installed binary passed the launch smoke test."
exit 0
