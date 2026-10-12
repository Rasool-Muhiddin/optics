; Inno Setup 6 script — Windows installer of the Optics Lab desktop app.
; Build with installer\build_release.ps1 (it runs `flutter build windows` first), or:
;   iscc /DAppVersion=1.0.0 /DBuildNumber=1 installer\optics.iss
; Output: installer\Output\optics-setup-<version>.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildNumber
  #define BuildNumber "1"
#endif
#define AppName "Optics Lab"
#define AppNameAr "مختبر العوينات"
#define AppPublisher "Tera (تيرا)"
#define AppURL "https://tera-software1.com"
#define AppExe "optics_app.exe"
#define BuildDir "..\app\build\windows\x64\runner\Release"

[Setup]
; Never change AppId: updates find the installed copy by it.
AppId={{6C2E5B1A-8F4D-4E7B-9A3C-0D5F7E1B2A44}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\Tera\Optics Lab
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=optics-setup-{#AppVersion}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
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
arabic.LaunchApp=تشغيل برنامج مختبر العوينات
arabic.ShortcutName=مختبر العوينات
english.DesktopIconTask=Create a &desktop shortcut
english.AdditionalIcons=Additional shortcuts:
english.LaunchApp=Launch Optics Lab
english.ShortcutName=Optics Lab

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
