# Fidelity Forever

Graphics and audio settings for **WoW Forever**, from the game's Options > AddOns menu: presets, your own named
settings, adaptive performance and screenshot mode. It sets the client's console variables (CVars), including many
the game's own menu does not show.

## Features
- **Presets**: Default, Performance, Balanced, Adaptive, High, Beyond Ultra and Screenshot. Presets are read-only;
  change anything and you save it as a setting of your own (New, Rename, Delete, Copy from).
- **101 settings on 12 pages**: Graphics (World, Ground clutter, Lighting & shadows, Effects & particles, Water & sky,
  Characters & threads, Loading & memory, Display & HDR) and Audio (Output, Effects, Memory, Gameplay sounds). Every
  setting explains itself in its "i" tooltip. Settings the client does not have are hidden.
- **Nothing changes until you Apply**: edits are staged; a bar on every Options screen shows how many are pending.
- **Drift**: if the game changes one of your values (its own Graphics menu, a reset), that row shows it with a
  Re-apply button.
- **Adaptive performance**: while your frame rate stays under a target, detail is lowered in five steps and restored
  once it recovers. Your saved values never change. On in the Adaptive preset; any own setting can turn it on.
- **Faster loading screens** (optional, per setting): short view distances at logout, your values back after login.
- **Safety**: values known to crash the client ask first and save to disk before applying; a value the client refuses
  is reported; changes made in combat wait until combat ends.
- **Screenshot mode**: bind "Screenshot mode on/off" and "Back to my setting" in Key Bindings (no default keys).
- **Troubleshooting**: Safe mode (Performance), Undo last apply, Restore the settings you had before installing.
- Settings are searchable from the Options search box.

Slash commands: `/ff` (or `/fidelity`) opens the panel; `/ff safe`, `/ff undo`, `/ff probe` (saves what the client
reports about every CVar into the saved variables, for bug reports).

## Install
Download the zip from Releases and extract it into `World of Warcraft/_forever_/Interface/AddOns/`.

## Development
- Target: WoW Forever only (`## Interface: 16001`). Game APIs were checked against the Forever UI source and the
  Forever CVar registry (Ketho's BlizzardInterfaceResources, `forever` branch).
- No library dependencies.
- `make bootstrap` once (Lua 5.1 + luacheck into `.lua/`, needs Python), then `make check` (lint, syntax, the headless
  core test and the data test).
- `Data.lua` holds the pages, CVars (label, range or options, tooltip) and presets, and is edited by hand.
  `tests/data_test.lua` checks it: every preset value in range, no crash value in a preset, every CVar on exactly one
  page, every setting with a tooltip.
- Releases: push a `v*` tag; the release workflow checks, builds the zip with the BigWigs packager and attaches it to a
  draft GitHub release for review (`make package-check` does the same build locally). Publishing the draft uploads that
  zip to CurseForge (project `fidelity-forever`, 1807957) through `tools/cf_upload.py`; it needs the repository secret
  `CF_API_KEY`. A tag with a `-` suffix (v0.2.0-rc.1) goes up as a beta.

## License
GPL-3.0. See [LICENSE](LICENSE).
