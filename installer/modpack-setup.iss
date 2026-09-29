; 14th_ua's Mini Modpack - Windows installer (Inno Setup 6.x)
;
; What it does, one double-click:
;   1. Detects the World of Tanks install folder (registry + common paths), lets
;      the user confirm/override it, and validates it (version.xml present).
;   2. Resolves the client version (e.g. 2.4.0.1) and targets mods\<version>\.
;   3. Lets the user pick which of the five bundled mods to install.
;   4. For each selected mod, removes any older build of that SAME mod already
;      in mods\<version>\ (so a re-install never double-loads two versions),
;      then installs the fresh .wotmod.
;   5. Spotting Calculator only: its settings-panel dependencies (OpenWG
;      GameFace, Aslain ModMenu, ModsList API) ride along as a sub-component,
;      each copied ONLY when no copy of it is already present (any version --
;      same policy as Spotting Calculator's own installer) and never removed
;      on uninstall (other mods share them). The other four mods are
;      dependency-free. No self-update check (YAGNI).
;
; Build:  see installer\build_installer.ps1  (needs Inno Setup's ISCC + the
;         payload staged by build\gather_payload.py).

#define AppVer "1.2.0"
#define SupportedClientVersion "2.4.0.1"
#include "..\payload\payload.iss"

[Setup]
UninstallFilesDir={localappdata}\14th_ua-MiniModpack\uninstall
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
Name: "spotting"; Description: "Spotting Calculator"; Types: full custom
Name: "spotting\deps"; Description: "Settings-panel dependencies: Aslain ModMenu, ModsList API, OpenWG GameFace (each skipped if already installed)"; Types: full custom

[Files]
Source: "..\payload\{#HintSilencerWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: hint
Source: "..\payload\{#ClassIconsWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: classicons
Source: "..\payload\{#NeutralReticleWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: reticle
Source: "..\payload\{#UaRenameWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: rename
Source: "..\payload\{#SpottingWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion; Components: spotting
; Spotting Calculator's vendor deps: copied only when absent, never uninstalled
; (other mods share them) -- mirrors spotting_calculator's own installer.
Source: "..\payload\vendor\{#OpenWgWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion uninsneveruninstall; Components: spotting\deps; Check: NeedOpenWg
Source: "..\payload\vendor\openwg-gameface-LICENSE.txt"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion uninsneveruninstall; Components: spotting\deps; Check: NeedOpenWg
Source: "..\payload\vendor\{#ModMenuWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion uninsneveruninstall; Components: spotting\deps; Check: NeedModMenu
Source: "..\payload\vendor\{#ModsListWotmod}"; DestDir: "{code:GetModsVersionDir}"; Flags: ignoreversion uninsneveruninstall; Components: spotting\deps; Check: NeedModsList

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

{ ---- vendor-dependency presence (Spotting Calculator) -------------------- }

{ Recursive search for a file matching Mask under Dir (as in
  spotting_calculator's own installer). }
function FindWotmodIn(Dir, Mask: string): Boolean;
var
  FR: TFindRec;
begin
  Result := False;
  if FindFirst(Dir + '\' + Mask, FR) then
  begin
    FindClose(FR);
    Result := True;
    Exit;
  end;
  if FindFirst(Dir + '\*', FR) then
  begin
    try
      repeat
        if (FR.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          if (FR.Name <> '.') and (FR.Name <> '..') then
            if FindWotmodIn(Dir + '\' + FR.Name, Mask) then
            begin
              Result := True;
              Exit;
            end;
      until not FindNext(FR);
    finally
      FindClose(FR);
    end;
  end;
end;

function NeedOpenWg(): Boolean;
begin
  Result := not FindWotmodIn(GetModsVersionDir(''), 'net.openwg.gameface*.wotmod');
end;

{ Narrow to Aslain's build on purpose: a leftover izeberg.modssettingsapi*
  must not count as present. }
function NeedModMenu(): Boolean;
begin
  Result := not FindWotmodIn(GetModsVersionDir(''), 'aslain.modmenu*.wotmod');
end;

function NeedModsList(): Boolean;
begin
  Result := not FindWotmodIn(GetModsVersionDir(''), 'me.poliroid.modslistapi*.wotmod');
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
    if GVersion <> '{#SupportedClientVersion}' then
    begin
      if MsgBox('This modpack was built and tested for World of Tanks ' +
                'client {#SupportedClientVersion}, but this installation ' +
                'reports client ' + GVersion + '. The bundled mods may ' +
                'not load, or may misbehave, on a different client.' + #13#10#13#10 +
                'Continue anyway?', mbConfirmation, MB_YESNO) = IDNO then
      begin
        Result := False;
        Exit;
      end;
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

{ Remove any older VERSIONED .wotmod of the given package-id prefix from
  mods\<version>\, so a re-install (or a version bump) never leaves two
  copies of the same mod loaded side by side. Only runs for a component the
  user actually selected. A plain wildcard on "<IdPrefix>_*.wotmod" would
  also sweep up an unrelated "<IdPrefix>_debug.wotmod" dev build, so only
  delete a match whose suffix starts with a digit (a version number). }
procedure CleanStalePackage(IdPrefix: string);
var
  Dir: string;
  FindRec: TFindRec;
  Rest: string;
begin
  Dir := GetModsVersionDir('');
  if FindFirst(Dir + '\' + IdPrefix + '_*.wotmod', FindRec) then
  begin
    try
      repeat
        Rest := Copy(FindRec.Name, Length(IdPrefix) + 2, MaxInt);
        if (Rest <> '') and (Rest[1] >= '0') and (Rest[1] <= '9') then
          DeleteFile(Dir + '\' + FindRec.Name);
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
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
    if WizardIsComponentSelected('spotting') then
      CleanStalePackage('{#SpottingIdPrefix}');
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpReady then
  begin
    { Remind the user to fully restart the client. }
    WizardForm.ReadyMemo.Lines.Add(#13#10 +
      'After installing, fully restart World of Tanks to load the mods.');

    { Per-mod notes/disclaimers, shown only for a component the user
      actually selected -- see README.md "Notes & disclaimers". }
    if WizardIsComponentSelected('classicons') or WizardIsComponentSelected('reticle') then
      WizardForm.ReadyMemo.Lines.Add(#13#10 +
        'Class Icons Recolor / Neutral Reticle are derived from Wargaming ' +
        'client assets (not endorsed by Wargaming) and replace those stock ' +
        'files wholesale, so they conflict with any other mod overriding ' +
        'the same files.');
    if WizardIsComponentSelected('rename') then
      WizardForm.ReadyMemo.Lines.Add(#13#10 +
        'UA Vehicle Rename renames vehicles to community Ukrainian names; ' +
        'some default names include mature language by design.');
    if WizardIsComponentSelected('spotting') then
      WizardForm.ReadyMemo.Lines.Add(#13#10 +
        'Spotting Calculator''s settings panel needs Aslain ModMenu, ' +
        'ModsList API and OpenWG GameFace (bundled; each installed only if ' +
        'missing); its minimap rings work without them. Fair Play: it uses ' +
        'only your own vehicle data and values you enter.');
  end;
end;
