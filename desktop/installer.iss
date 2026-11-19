; DocScan installer (Inno Setup 6). Built by the GitHub workflow after desktop\build.ps1:
;   iscc /DAppVersion=1.0.0 /DHeavyVersion=1 desktop\installer.iss      ->  build\out\DocScan-Setup-1.0.0.exe
; Per-user install (no administrator rights), so updates can run silently. The optional readers (Nuqta and
; EasyOCR, about 2 GB) are not inside the setup file: when chosen, they are downloaded from the same release.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef HeavyVersion
  #define HeavyVersion "1"
#endif
#define Repo "eyasbzour/docscan"
#define Release "https://github.com/" + Repo + "/releases/download/v" + AppVersion

[Setup]
AppId={{6F2B8C4E-1D7A-4E59-9C1B-3A5E7D2F8B90}
AppName=DocScan
AppVerName=DocScan {#AppVersion}
AppVersion={#AppVersion}
AppPublisher=DocScan
AppPublisherURL=https://github.com/{#Repo}
AppSupportURL=https://github.com/{#Repo}/issues
AppUpdatesURL=https://github.com/{#Repo}/releases
DefaultDirName={localappdata}\Programs\DocScan
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\out
OutputBaseFilename=DocScan-Setup-{#AppVersion}
SetupIconFile=..\build\DocScan\docscan.ico
UninstallDisplayIcon={app}\docscan.ico
UninstallDisplayName=DocScan
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4
WizardStyle=modern
; the program's own single-instance mutex: setup asks to close a running copy
AppMutex=Local\DocScan.single
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=auto

[Languages]
; Arabic.isl comes from Inno Setup's unofficial translations (the workflow downloads it next to this file)
Name: "ar"; MessagesFile: "Arabic.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ar.CoreDesc=البرنامج مع قارئَي Tesseract و PaddleOCR
en.CoreDesc=The program, with the Tesseract and PaddleOCR readers
ar.HeavyDesc=قارئ Nuqta (الأدق للعربية) و EasyOCR، تنزيل نحو 2 جيجابايت
en.HeavyDesc=Nuqta (most accurate for Arabic) and EasyOCR readers, about a 2 GB download
ar.Downloading=تنزيل القرّاء الإضافية…
en.Downloading=Downloading the extra readers…
ar.Unpacking=فك ضغط القرّاء الإضافية…
en.Unpacking=Unpacking the extra readers…
ar.DownloadFailed=تعذر تنزيل القرّاء الإضافية. يكتمل التثبيت من دونها، ويمكن إضافتها لاحقاً بتشغيل المثبّت من جديد.
en.DownloadFailed=The extra readers could not be downloaded. Setup finishes without them; run it again later to add them.
ar.Open=تشغيل البرنامج
en.Open=Open DocScan

[Types]
Name: "full"; Description: "{cm:CoreDesc} + Nuqta + EasyOCR"
Name: "compact"; Description: "{cm:CoreDesc}"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "core"; Description: "{cm:CoreDesc}"; Types: full compact custom; Flags: fixed
Name: "heavy"; Description: "{cm:HeavyDesc}"; Types: full; ExtraDiskSpaceRequired: 4000000000

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\DocScan\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: core

[InstallDelete]
; an update replaces the program's own code; the readers' models and the user's data stay
Type: filesandordirs; Name: "{app}\app"

[Icons]
Name: "{autoprograms}\DocScan"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\desktop\app.py"""; WorkingDir: "{app}"; IconFilename: "{app}\docscan.ico"; AppUserModelID: "Eyasbzour.DocScan"
Name: "{autodesktop}\DocScan"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\desktop\app.py"""; WorkingDir: "{app}"; IconFilename: "{app}\docscan.ico"; AppUserModelID: "Eyasbzour.DocScan"; Tasks: desktopicon

[Run]
; also after a silent update (the program closed itself for it), so it opens again
Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\desktop\app.py"""; WorkingDir: "{app}"; Description: "{cm:Open}"; Flags: nowait postinstall

[UninstallDelete]
Type: filesandordirs; Name: "{app}\parts"
Type: filesandordirs; Name: "{app}\models"

[Code]
var
  DownloadPage: TDownloadWizardPage;

function HeavyInstalled: Boolean;
var
  V: AnsiString;
begin
  Result := LoadStringFromFile(ExpandConstant('{app}\parts\heavy\VERSION'), V) and (Trim(String(V)) = '{#HeavyVersion}');
end;

function NeedHeavy: Boolean;
begin
  Result := WizardIsComponentSelected('heavy') and not HeavyInstalled;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), CustomMessage('Downloading'), nil);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpReady) and NeedHeavy then begin
    DownloadPage.Clear;
    DownloadPage.Add('{#Release}/DocScan-part-heavy.zip', 'DocScan-part-heavy.zip', '');
    DownloadPage.Add('{#Release}/DocScan-part-models.zip', 'DocScan-part-models.zip', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if not WizardSilent then
          MsgBox(CustomMessage('DownloadFailed'), mbInformation, MB_OK);
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
end;

procedure Unpack(Zip, Dir: String);
var
  Code: Integer;
begin
  if FileExists(ExpandConstant('{tmp}\' + Zip)) then begin
    ForceDirectories(Dir);
    // Windows' own tar unpacks zips, and quickly
    Exec(ExpandConstant('{sys}\tar.exe'), '-xf "' + ExpandConstant('{tmp}\' + Zip) + '" -C "' + Dir + '"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and NeedHeavy then begin
    WizardForm.StatusLabel.Caption := CustomMessage('Unpacking');
    DelTree(ExpandConstant('{app}\parts\heavy'), True, True, True);
    Unpack('DocScan-part-heavy.zip', ExpandConstant('{app}\parts\heavy'));
    Unpack('DocScan-part-models.zip', ExpandConstant('{app}\models'));
  end;
end;
