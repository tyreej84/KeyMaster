# KeyMaster

A Mythic+ utility addon for World of Warcraft with chat replies, auto-slotting, and a live dungeon overlay.

## What it does

- Type `!key` or `!keys` in party, raid, or guild chat to share your clickable Mythic+ keystone link.
- Type `!score` to share your current Mythic+ score.
- Type `!best` to share your best Mythic+ run for the current week and season.
- Shows a live Mythic+ overlay with dungeon header, affixes, timer, chest breakpoints, objectives, deaths, and Enemy Forces.
- Uses a transparent black panel with white text and a blue Enemy Forces progress bar inspired by BreakTimerLite.
- When you open a Font of Power, your key is automatically inserted if it matches the dungeon.
- If your key does not match the dungeon, a local on-screen warning appears without chat spam.

## Commands

| Command | Response |
|---|---|
| `!key` or `!keys` | Your clickable Mythic+ keystone link |
| `!score` | Your current Mythic+ score |
| `!best` | Your best key this week and this season |
| `/km` or `/keymaster` | Show addon status and UI command help |
| `/km settings` | Open the KeyMaster settings panel |
| `/km ui on` | Enable the KeyMaster Mythic+ overlay |
| `/km ui off` | Disable the KeyMaster Mythic+ overlay and use Blizzard's default UI |
| `/km unlock` | Unlock the Mythic+ overlay so it can be dragged into position |
| `/km lock` | Lock the Mythic+ overlay in place |
| `/km hide` | Hide the Mythic+ overlay |
| `/km show` | Show the Mythic+ overlay |
| `/km reset` | Reset overlay position and scale |
| `/km scale 1.00` | Set overlay scale between `0.70` and `1.50` |

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
- If a keystone link cannot be resolved, the addon stays silent.
- Auto-slot supports all current keystone item variants.
- The overlay appears automatically during active Mythic+ runs when the KeyMaster Mythic+ UI setting is enabled.
- If the KeyMaster Mythic+ UI setting is disabled, Blizzard's default Mythic+ UI remains available while KeyMaster chat and auto-slot features still work.
- The KeyMaster settings panel includes a short positioning note plus `Unlock UI` and `Lock UI` buttons.
- By default, the overlay is positioned on the right side of the screen just below the minimap.
- When the overlay is unlocked, drag it to the position you want and then lock it again.
- The Enemy Forces bar uses a fixed blue fill with centered white percentage text.
