# 14th_ua's Mini Modpack

A single Windows installer bundling four dependency-free 14th_ua World of Tanks mods:

- **14th_ua's Hint Silencer** (`com.14th_ua.hint_silencer`) - silences the always-on
  Scaleform button-hint panel.
- **Class Icons Recolor** (`com.14th_ua.class-icons-recolor`) - recolors vehicle class
  icons.
- **Neutral Reticle** (`com.14th_ua.neutral-reticle`) - a neutral-colored aim reticle.
- **UA Vehicle Rename** (`com.14th_ua.super_secret_mod`) - renames vehicles to their
  Ukrainian-community names.

None of the four have any vendor dependency (no OpenWG GameFace, no ModsSettingsAPI) -
each installs standalone.

## Installing

Run `14th_ua-MiniModpack-Setup-<version>.exe`. It auto-detects your World of Tanks
install folder (falling back to a manual picker) and the game's client version folder
(`mods\<version>\`), then lets you choose which of the four mods to install. Fully
restart World of Tanks afterwards to load them.

## Building

```powershell
python build\gather_payload.py       # rebuilds all four mods, stages payload\
installer\build_installer.ps1        # compiles the Inno Setup installer
```

Output: `dist\14th_ua-MiniModpack-Setup-<version>.exe`.

Requires each sibling mod repo to be checked out next to this one
(`..\hint-silencer`, `..\class-icons-recolor`, `..\neutral_reticle`, `..\ua-rename`),
Python 2.7 at `C:\Python27\python.exe` (three of the four ship compiled `.pyc`), and
Inno Setup 6 (`ISCC.exe`) for the installer compile step.
