# KeyMaster

A lightweight World of Warcraft addon for Mythic+ groups.

## What it does

- Type `!key` or `!keys` in party, raid, or guild chat to share your clickable Mythic+ keystone link.
- Type `!score` to share your current Mythic+ score.
- Type `!best` to share your best Mythic+ run for the current week and season.
- If you do not have a key, `!key` and `!keys` do nothing.
- When you open a Font of Power, your key is automatically inserted if it matches the dungeon.
- If your key does not match the dungeon, a local on-screen warning appears (no chat spam).

## Commands

| Command | Response |
|---|---|
| `!key` or `!keys` | Your clickable Mythic+ keystone link |
| `!score` | Your current Mythic+ score |
| `!best` | Your best key this week and this season |

## Install

1. Download the latest release zip.
2. Extract the `KeyMaster` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Launch WoW and enable **KeyMaster** in the addon list.
4. Type `/reload` in-game.

## Notes

- Responds in party, raid, and guild chat only.
- Commands are strict exact-match - no partial matches.
- If a keystone link cannot be resolved, the addon stays silent (no fallback text).
- Auto-slot supports all current keystone item variants.
- Type `/km` or `/keymaster` in-game to confirm the addon is loaded.
