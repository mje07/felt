; Felt — Windows installer (Inno Setup 6).
; Build with installer\build_installer.ps1, which passes AppVersion and CrtDir.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef CrtDir
  #error CrtDir (Visual C++ runtime folder) must be defined
#endif

#define AppName "Felt"
#define AppExe "felt.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
; Keep this AppId fixed so upgrades replace the previous install.
AppId={{6F3E2B1A-9C4D-4E7A-B8F1-2D5C7A9E0B34}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} installer
; Per-user install by default (no admin prompt); can choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
WizardSmallImageFile=..\build\icon\icon_64.png
OutputDir=..\build\installer
OutputBaseFilename=Felt-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime, deployed next to the app so it runs on a clean PC.
Source: "{#CrtDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
