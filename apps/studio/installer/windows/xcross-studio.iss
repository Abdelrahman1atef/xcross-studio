; XCross Studio installer for Windows (Inno Setup 6). Packs the portable folder
; built by `dart run tool/package.dart` (dist\xcross-studio-windows-x64).
;
;   iscc /DAppVersion=0.1.0 [/DAppName="Product Name"] apps\studio\installer\windows\xcross-studio.iss
;
; AppName is the user-visible product name: pass the same value given to
; tool/package.dart --product-name (runbook S13). AppPublisher and AppId stay.
;
; Per-user install by default (no admin rights); the GUI finds the bundled
; xcross\bin\xcross.exe next to itself.

#ifndef AppVersion
  #define AppVersion "0.1.0-dev"
#endif
#ifndef AppName
  #define AppName "XCross Studio"
#endif
#define Root "..\..\..\.."

[Setup]
AppId={{6E1A0F5C-3B7D-4E59-9C1A-58D0B7C4E2A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=XCross Studio contributors
AppPublisherURL=https://github.com/Abdelrahman1atef/xcross-studio
AppSupportURL=https://github.com/Abdelrahman1atef/xcross-studio/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile={#Root}\LICENSE
OutputDir={#Root}\dist
OutputBaseFilename=xcross-studio-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\xcross_studio.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#Root}\dist\xcross-studio-windows-x64\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\xcross_studio.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\xcross_studio.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\xcross_studio.exe"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent
