# Fidelity Forever

Graphics and audio settings for WoW Forever, including a lot that the game's own menu doesn't show. You get a few
presets to start from, and you can save your own. It all lives in the normal Options window, under AddOns.

Under the hood it changes the game's console variables (CVars).

Also on [CurseForge](https://www.curseforge.com/wow/addons/fidelity-forever).

## What it does
- **Presets:** Default, Performance, Balanced, Adaptive, High, Beyond Ultra and Screenshot. You can't edit a preset
  directly. Change something and you save it as your own setting, which you can rename, delete or copy.
- **101 settings on 12 pages.** Graphics has World, Ground clutter, Lighting & shadows, Effects & particles, Water &
  sky, Characters & threads, Loading & memory, and Display & HDR. Audio has Output, Effects, Memory, and Gameplay
  sounds.
- **Tooltips:** hover the "i" next to a setting to see what it does. Settings your client doesn't have are hidden.
- **Apply button:** nothing changes until you hit Apply. Until then, a bar at the bottom of the Options window shows
  how many changes you have waiting.
- **Re-apply:** if the game's own Graphics menu (or a reset) changes one of your settings, that setting gets a Re-apply
  button.
- **Adaptive performance (optional):**
  - If your frame rate stays under a target you set, it turns a few things down, then puts them back once things
    calm down.
  - It never changes your saved settings.
  - The Adaptive preset has it on, and you can turn it on for your own settings.
- **Faster loading screens (optional):** it shortens view distances while you're logged out, then puts yours back
  after you log in.
- **Crash-prone values:** a few values are known to crash the game. It asks before using them and saves your current
  settings first.
- **Refused values:** if the game refuses a value, you'll see a message.
- **Combat:** anything you apply in combat waits until combat ends.
- **Screenshot mode:** bind "Screenshot mode on/off" and "Back to my setting" under Key Bindings. No keys are bound by
  default.
- **Troubleshooting page:** Safe mode, Undo last apply, and a button to restore the settings you had before installing.

## Commands
- `/ff` or `/fidelity`: open the settings
- `/ff safe`: switch to the Performance preset
- `/ff undo`: undo the last apply
- `/ff probe`: saves what your client reports about each setting. Handy for bug reports.

## Install
Grab the zip from [Releases](https://github.com/zmsl/FidelityForever/releases) or CurseForge, and unzip it into
`World of Warcraft/_forever_/Interface/AddOns/`.

## Bugs and ideas
Open an [issue](https://github.com/zmsl/FidelityForever/issues). If a setting misbehaves, run `/ff probe` and include
the result.

## Development
- It's for WoW Forever only (`## Interface: 16001`). Game APIs were checked against the Forever UI source and the
  Forever CVar list in Ketho's BlizzardInterfaceResources (`forever` branch).
- No library dependencies.
- Run `make bootstrap` once. It puts Lua 5.1 and luacheck in `.lua/` and needs Python.
- Then `make check` runs lint, a syntax check, the core and data tests, and the release tool tests.
- `Data.lua` has the pages, settings (label, range or options, tooltip) and presets. You edit it by hand, and
  `tests/data_test.lua` checks it: preset values in range, no crash values in presets, every setting on exactly one
  page and with a tooltip.
- **Releasing:**
  1. Push a `v*` tag. GitHub checks everything, builds the zip with the BigWigs packager and makes a draft release.
     (`make package-check` does the same build locally.)
  2. Publish the draft. That uploads the zip to CurseForge (`fidelity-forever`, 1807957) using the `CF_API_KEY`
     secret.
  3. A tag with a dash, like `v0.2.0-rc.1`, goes up as a beta.

## License
GPL-3.0. See [LICENSE](LICENSE).
