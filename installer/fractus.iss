; Installateur Windows de Fractus (Inno Setup 6).
; Compilé par GitHub Actions : ISCC.exe /DAppVersion=x.y.z /DSourceDir=... installer\fractus.iss
; Installation par utilisateur (pas de droits administrateur), ce qui permet la
; mise à jour silencieuse lancée par Fractus lui-même.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "Fractus"
#define AppExe "fractus.exe"
#define AppPublisher "Fractus"
#define AppURL "https://github.com/leoblanchart92-hub/Fractus"

[Setup]
AppId={{7E3C2B6A-5B1F-4C2E-9D0B-3F1A2C4D5E6F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=Fractus-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Ferme Fractus s'il tourne (mise à jour), le relance ensuite.
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\hook\*"; DestDir: "{app}\hook"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Installation interactive : case « Lancer Fractus » à la fin.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Mise à jour silencieuse (lancée par Fractus) : on le relance tout de suite.
Filename: "{app}\{#AppExe}"; Flags: nowait skipifnotsilent

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "KillFractus"

[Registry]
; Désinstallation : retire aussi le lancement automatique.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#AppName}"; Flags: uninsdeletevalue dontcreatekey

[Code]
// Juste avant l'installation, on coupe Fractus proprement si CloseApplications
// n'a pas suffi (fenêtre sans bordure, pas de message WM_CLOSE classique).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
