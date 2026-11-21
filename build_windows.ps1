# Builds the Flutter Windows app (flutter_app) locally on Windows.
#
# Prerequisites:
#   - Flutter 3.47.8 (stable) on PATH
#   - Visual Studio 2022 with the "Desktop development with C++" workload
#
# Usage: powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location (Join-Path $root "flutter_app")
try {
  flutter pub get
  flutter build windows --release

  $out = Join-Path (Get-Location) "build\windows\x64\runner\Release"
  Write-Host ""
  Write-Host "==> Done: $out"
  Write-Host "    Run $out\ccloud.exe"
} finally {
  Pop-Location
}
