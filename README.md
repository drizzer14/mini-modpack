# 14th_ua's Mini Modpack

A single Windows installer bundling six 14th_ua World of Tanks mods:

- **14th_ua's Hint Silencer** (`com.14th_ua.hint_silencer`) - silences the always-on
  Scaleform button-hint panel.
- **Class Icons Recolor** (`com.14th_ua.class-icons-recolor`) - recolors vehicle class
  icons.
- **Neutral Reticle** (`com.14th_ua.neutral-reticle`) - a neutral-colored aim reticle.
- **UA Vehicle Rename** (`com.14th_ua.super_secret_mod`) - renames vehicles to their
  Ukrainian-community names.
- **Spotting Calculator** (`com.14th_ua.spotting_calculator`) - draws spotting-distance
  rings around your own tank on the battle minimap.
- **14th_ua HP** (`com.14th_ua.hp`) - an in-battle per-row team HP bar beside the
  players panels.

The first four have no vendor dependency and each installs standalone. Spotting
Calculator's settings panel needs Aslain ModMenu, ModsList API and OpenWG GameFace; the
installer bundles them as a sub-option of Spotting Calculator and copies each one only if
you don't already have the same or a newer version installed (an older copy is replaced
by the bundled one, and uninstalling never removes them, since other mods share them). The minimap rings work
without them. 14th_ua HP requires OpenWG GameFace (the overlay does not appear without
it); the installer copies the same bundled copy along with it, under the same rule.

Targets World of Tanks client **2.4.0.2**. The installer warns (but does not block) if
your client reports a different version.

## Notes & disclaimers

- **Class Icons Recolor** and **Neutral Reticle** are derived from Wargaming client
  assets (recolored icons / modified reticle SWFs) - not endorsed by Wargaming - and
  each replaces the corresponding stock file wholesale, so it conflicts with any other
  mod that also overrides the same file.
- **UA Vehicle Rename**'s package id, `com.14th_ua.super_secret_mod`, is historical: it
  is the mod's original working-title id from before its current name and scope were
  settled, kept unchanged since so existing installs upgrade in place. It only renames
  vehicles - nothing about it is hidden or secret. Some default renames include mature
  language by design.
- **Spotting Calculator** is Fair Play by design: it uses only your own vehicle's data
  and the values you enter in its settings (enemy view range, enemy Commander Vision
  System). Its settings panel needs the bundled vendor mods above; the rings work
  without them.
- **14th_ua HP** sets the game option "Show vehicle HP in players panel" to Never
  during a battle (so the HP number isn't shown twice) and restores your own setting
  when the battle ends. Its red "one-shot" band is a Fair Play gray area, disclosed:
  it uses only your own loaded shell's alpha damage and the HP the players panel
  already shows - no hidden battle data. It contains a font subset derived from
  Wargaming client assets, not endorsed by Wargaming.

## Installing

Run `14th_ua-MiniModpack-Setup-<version>.exe`. It auto-detects your World of Tanks
install folder (falling back to a manual picker) and the game's client version folder
(`mods\<version>\`), then lets you choose which of the six mods to install. Fully
restart World of Tanks afterwards to load them.

## Building

```powershell
python build\gather_payload.py       # rebuilds all six mods, stages payload\ (+ payload\vendor\)
installer\build_installer.ps1        # compiles the Inno Setup installer
```

Output: `dist\14th_ua-MiniModpack-Setup-<version>.exe`.

Requires each sibling mod repo to be checked out next to this one
(`..\hint-silencer`, `..\class-icons-recolor`, `..\neutral_reticle`, `..\ua-rename`,
`..\spotting_calculator` - whose `installer\vendor\` also supplies the three vendor
mods, sha256-checked against its `MANIFEST.json` - and `..\14th_ua_hp`, whose own
`MANIFEST.json` must pin the same OpenWG GameFace file), Python 2.7 at
`C:\Python27\python.exe` (five of the six ship compiled `.pyc`), and Inno Setup 6
(`ISCC.exe`) for the installer compile step.
