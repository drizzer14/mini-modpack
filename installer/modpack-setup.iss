; 14th_ua's Mini Modpack - Windows installer (Inno Setup 6.x)
;
; What it does, one double-click:
;   1. Detects the World of Tanks install folder (registry + common paths), lets
;      the user confirm/override it, and validates it (version.xml present).
;   2. Resolves the client version (e.g. 2.4.0.1) and targets mods\<version>\.
;   3. Lets the user pick which of the four bundled mods to install.
;   4. For each selected mod, removes any older build of that SAME mod already
;      in mods\<version>\ (so a re-install never double-loads two versions),
;      then installs the fresh .wotmod.
;
; These four mods are dependency-free (no OpenWG/MSA/ModsList required), so
; unlike Garage Progress Bar's installer this one has no vendor-dependency
; [Files] gating and no self-update check (YAGNI for v1).
;
; Build:  see installer\build_installer.ps1  (needs Inno Setup's ISCC + the
;         four payload .wotmods already staged by build\gather_payload.py).

#define AppVer "1.1.0"
#include "..\payload\payload.iss"

[Setup]
AppId={{6C9F2E7A-4B1D-4E63-9A2C-3F8D5B7C1A02}
AppName=14th_ua's Mini Modpack
AppVersion={#AppVer}
AppPublisher=14th_ua
DefaultDirName={code:DetectWotRoot}
DisableProgramGroupPage=yes
DisableReadyPage=no
DirExistsWarning=no
AppendDefaultDirName=no
UsePreviousAppDir=no
OutputDir=..\dist
OutputBaseFilename=14th_ua-MiniModpack-Setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=14th_ua's Mini Modpack (WoT mods)

[Types]
Name: "full"; Description: "All mods (recommended)"
Name: "custom"; Description: "Choose mods"; Flags: iscustom

[Components]
Name: "hint"; Description: "14th_ua's Hint Silencer"; Types: full custom
Name: "classicons"; Description: "Class Icons Recolor"; Types: full custom
Name: "reticle"; Description: "Neutral Reticle"; Types: full custom
Name: "rename"; Description: "UA Vehicle Rename"; Types: full custom

[Files]
Source: "..\payload\{#HintSilencerWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: hint
Source: "..\payload\{#ClassIconsWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: classicons
Source: "..\payload\{#NeutralReticleWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: reticle
Source: "..\payload\{#UaRenameWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: rename

[Messages]
; Repurpose the "Select Destination Location" page for picking the WoT root.
SelectDirLabel3=Setup will install the selected mods into the [name] mods folder of the World of Tanks installation below.
SelectDirBrowseLabel=Confirm your World of Tanks installation folder (the one containing version.xml). To continue, click Next. To choose a different folder, click Browse.

[Code]
var
  GVersion: string;  { resolved game version, e.g. 2.4.0.1 }

{ ---- WoT root / version detection (same shape as Garage Progress Bar's) --- }

function IsWotRoot(Path: string): Boolean;
begin
  Path := RemoveBackslashUnlessRoot(Path);
  Result := (Path <> '') and
            (FileExists(Path + '\version.xml') or
             FileExists(Path + '\WorldOfTanks.exe'));
end;

{ Parse "<version> v.2.4.0.1 #930 </version>" -> "2.4.0.1" }
function ReadGameVersion(Root: string): string;
var
  S: AnsiString;
  ver: string;
  p, i: Integer;
begin
  Result := '';
  if not LoadStringFromFile(Root + '\version.xml', S) then
    Exit;
  p := Pos('v.', S);
  if p = 0 then
    Exit;
  i := p + 2;
  ver := '';
  while (i <= Length(S)) and (((S[i] >= '0') and (S[i] <= '9')) or (S[i] = '.')) do
  begin
    ver := ver + S[i];
    Inc(i);
  end;
  while (Length(ver) > 0) and (ver[Length(ver)] = '.') do
    ver := Copy(ver, 1, Length(ver) - 1);
  Result := ver;
end;

{ Best-effort: scan an Uninstall hive for a "World of Tanks" entry. }
function ScanUninstall(RootKey: Integer; SubPath: string): string;
var
  Names: TArrayOfString;
  i: Integer;
  dn, loc: string;
begin
  Result := '';
  if not RegGetSubkeyNames(RootKey, SubPath, Names) then
    Exit;
  for i := 0 to GetArrayLength(Names) - 1 do
  begin
    if RegQueryStringValue(RootKey, SubPath + '\' + Names[i], 'DisplayName', dn) then
    begin
      if Pos('World of Tanks', dn) > 0 then
      begin
        if RegQueryStringValue(RootKey, SubPath + '\' + Names[i], 'InstallLocation', loc) then
        begin
          if IsWotRoot(loc) then
          begin
            Result := RemoveBackslashUnlessRoot(loc);
            Exit;
          end;
        end;
      end;
    end;
  end;
end;

function DetectFromRegistry(): string;
begin
  Result := ScanUninstall(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall');
  if Result = '' then
    Result := ScanUninstall(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall');
  if Result = '' then
    Result := ScanUninstall(HKCU, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall');
end;

function DetectFromCommonPaths(): string;
var
  cands: TArrayOfString;
  i: Integer;
begin
  Result := '';
  SetArrayLength(cands, 6);
  cands[0] := 'C:\Games\World_of_Tanks_EU';
  cands[1] := 'D:\Games\World_of_Tanks_EU';
  cands[2] := 'C:\Games\World_of_Tanks';
  cands[3] := 'D:\Games\World_of_Tanks';
  cands[4] := ExpandConstant('{autopf}\World_of_Tanks_EU');
  cands[5] := ExpandConstant('{autopf}\World_of_Tanks');
  for i := 0 to GetArrayLength(cands) - 1 do
    if IsWotRoot(cands[i]) then
    begin
      Result := cands[i];
      Exit;
    end;
end;

{ DefaultDirName callback. }
function DetectWotRoot(Param: string): string;
begin
  Result := DetectFromRegistry();
  if Result = '' then
    Result := DetectFromCommonPaths();
  if Result = '' then
    Result := 'C:\Games\World_of_Tanks_EU';  { harmless default; user confirms on the dir page }
end;

{ mods\<version> under the user-confirmed WoT root (the chosen app dir). }
function GetModsVersionDir(Param: string): string;
begin
  Result := ExpandConstant('{app}') + '\mods\' + GVersion;
end;

{ ---- WoT-running guard (file locks) -------------------------------------- }

function IsWotRunning(): Boolean;
var
  rc: Integer;
  tmp: string;
  content: AnsiString;
begin
  Result := False;
  tmp := ExpandConstant('{tmp}\wot_tasklist.txt');
  if Exec(ExpandConstant('{cmd}'),
          '/C tasklist /FI "IMAGENAME eq WorldOfTanks.exe" /NH > "' + tmp + '"',
          '', SW_HIDE, ewWaitUntilTerminated, rc) then
  begin
    if LoadStringFromFile(tmp, content) then
      Result := Pos('WorldOfTanks.exe', content) > 0;
  end;
end;

{ ---- wizard flow --------------------------------------------------------- }

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if not IsWotRoot(ExpandConstant('{app}')) then
    begin
      MsgBox('That folder does not look like a World of Tanks installation ' +
             '(no version.xml found). Please choose your WoT install folder ' +
             '(for example C:\Games\World_of_Tanks_EU).', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    GVersion := ReadGameVersion(ExpandConstant('{app}'));
    if GVersion = '' then
    begin
      MsgBox('Could not read the client version from version.xml in that ' +
             'folder. Please make sure it is your World of Tanks install folder.',
             mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsWotRunning() then
    Result := 'World of Tanks is currently running. Please close the game ' +
              'completely (exit the launcher too), then run this installer again.';
end;

{ Remove any older .wotmod of the given package-id prefix from mods\<version>\,
  so a re-install (or a version bump) never leaves two copies of the same mod
  loaded side by side. Only runs for a component the user actually selected. }
procedure CleanStalePackage(IdPrefix: string);
begin
  DelTree(GetModsVersionDir('') + '\' + IdPrefix + '_*.wotmod', False, True, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if WizardIsComponentSelected('hint') then
      CleanStalePackage('{#HintSilencerIdPrefix}');
    if WizardIsComponentSelected('classicons') then
      CleanStalePackage('{#ClassIconsIdPrefix}');
    if WizardIsComponentSelected('reticle') then
      CleanStalePackage('{#NeutralReticleIdPrefix}');
    if WizardIsComponentSelected('rename') then
      CleanStalePackage('{#UaRenameIdPrefix}');
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  { Make the Ready page remind the user to fully restart the client. }
  if CurPageID = wpReady then
    WizardForm.ReadyMemo.Lines.Add(#13#10 +
      'After installing, fully restart World of Tanks to load the mods.');
end;
