; Inno Setup 6/7 script — Windows installer of the TERA optics desktop app.
; Build with installer\build_release.ps1 (it runs `flutter build windows` first), or:
;   iscc /DAppVersion=1.0.0 /DBuildNumber=1 installer\optics.iss
; Output: installer\Output\tera-optics-setup-<version>.exe
;
; PERMANENT VALUES (RELEASE.md → "Permanent identifiers"): AppId, AppExe, the install folder and
; the installer file name. Changing any of them after the first release breaks in-app updates or
; leaves a second copy installed.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildNumber
  #define BuildNumber "1"
#endif
#define AppName "TERA optics"
#define AppPublisher "Tera"
#define AppURL "https://tera-software1.com"
#define AppExe "tera_optics.exe"
#define BuildDir "..\app\build\windows\x64\runner\Release"

[Setup]
; Never change AppId: updates find the installed copy by it.
AppId={{130E7965-BB54-4E6B-A33F-D16C1E4E15EE}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppCopyright=Copyright (C) 2026 {#AppPublisher}
DefaultDirName={autopf}\Tera\TERA optics
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=tera-optics-setup-{#AppVersion}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
; Add/Remove Programs entry: name, icon, publisher (AppPublisher) and version.
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-machine install (admin). The in-app updater runs this same installer with /SILENT.
PrivilegesRequired=admin
; Close the running app during updates; the [Run] entry below starts the new version
; (Restart Manager restarts are off so the app is never started twice).
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage

[Languages]
; Arabic.isl ships with Inno Setup 6.3+ (Languages folder). Older versions: download it from
; https://jrsoftware.org/files/istrans/ into "Inno Setup 6\Languages".
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
arabic.DesktopIconTask=إنشاء اختصار على سطح المكتب
arabic.AdditionalIcons=اختصارات إضافية:
arabic.LaunchApp=تشغيل TERA optics
; Same shortcut name in both languages (PERMANENT: Start menu / desktop shortcut file names).
arabic.ShortcutName=TERA optics
english.DesktopIconTask=Create a &desktop shortcut
english.AdditionalIcons=Additional shortcuts:
english.LaunchApp=Launch TERA optics
english.ShortcutName=TERA optics

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIconTask}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole Flutter release folder (exe, flutter_windows.dll, data\, plugin DLLs).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{cm:ShortcutName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{cm:ShortcutName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{cm:ShortcutName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Interactive installs offer a "launch" checkbox; silent updates (in-app updater) relaunch
; through the first entry.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifnotsilent runasoriginaluser
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent runasoriginaluser

; User data (activation, encrypted secrets, cache) lives in %APPDATA% and is kept on
; uninstall and on updates on purpose.
