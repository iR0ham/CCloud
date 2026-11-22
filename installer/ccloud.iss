; Inno Setup script for the Flutter Windows build.
;
; ISCC is invoked by scripts/windows-installer.ps1 with:
;   /DSourceDir=<staged release folder> /DOutputDir=<installer folder>
;   /DAppVersion=<version from pubspec>
;
; The staged folder already contains ccloud.exe, flutter_windows.dll,
; libmpv-2.dll, the data/ folder and the three MSVC runtime DLLs, so the
; installed copy runs without a separate Visual C++ redistributable install.

; The version is a required input: a missing /DAppVersion must fail the compile
; instead of silently producing an installer labelled with a stale number.
#ifndef AppVersion
  #error AppVersion must be provided with /DAppVersion=<version>
#endif
#ifndef SourceDir
  #define SourceDir "..\flutter_app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\flutter_app\build\ci-release\installer"
#endif
#define MyAppName "CCloud"
#define MyAppPublisher "CCloud"
#define MyAppURL "https://github.com/iR0ham/CCloud"
#define MyAppExeName "ccloud.exe"

[Setup]
AppId={{5A1C0F5E-7E42-4C61-9B7D-2F0C9E4B8A31}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=CCloud-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\flutter_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
MinVersion=10.0.14393
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
