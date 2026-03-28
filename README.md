# KeyMaster

A Mythic+ utility addon for World of Warcraft with chat replies and a live dungeon overlay.

## What it does

- Type `!key` or `!keys` in party, raid, instance, or guild chat to share your clickable Mythic+ keystone link.
- Announces your new keystone to party chat when your key changes after a run.
- Type `!score` to share your current Mythic+ score.
- Type `!best` to share your best Mythic+ run for the current week and season.
- Shows a live Mythic+ overlay with dungeon header, affixes, timer, chest breakpoints, objectives, deaths, and Enemy Forces.
- Uses a transparent black panel with white text and a blue Enemy Forces progress bar.

## Commands

| Command | Response |
|---|---|
| `!key` or `!keys` | Your clickable Mythic+ keystone link |
| `!score` | Your current Mythic+ score |
| `!best` | Your best key this week and this season |
| `/km` or `/keymaster` | Show addon status and UI command help |
| `/km settings` | Open the KeyMaster settings panel |
| `/km status` | Show current KeyMaster UI state (enabled, hidden, locked, scale, anchor) |
| `/km ui on` | Enable the KeyMaster Mythic+ overlay |
| `/km ui off` | Disable the KeyMaster Mythic+ overlay and use Blizzard's default UI |
| `/km ui restore` | Re-enable and reset the KeyMaster UI to the default top-right position |
| `/km unlock` | Unlock the Mythic+ overlay so it can be dragged into position |
| `/km lock` | Lock the Mythic+ overlay in place |
| `/km hide` | Hide the Mythic+ overlay |
| `/km show` | Show the Mythic+ overlay |
| `/km reset` | Reset overlay position and scale |
| `/km scale 1.00` | Set overlay scale between `0.70` and `1.50` |
| `/km deaths` | Print per-player death summary for current/recent run |
| `/km criteria` | Print scenario criteria debug details |
| `/km forces` | Print Enemy Forces debug details |

## Install

1. Download the latest release zip.
2. Extract the `KeyMaster` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Launch WoW and enable **KeyMaster** in the addon list.
4. Type `/reload` in-game.

## Notes

- Responds in party, party leader, raid, raid leader, instance, instance leader, and guild chat.
- Commands are case-insensitive and tolerate trailing punctuation (for example, `!score?`).
- If key/score APIs are temporarily unavailable, KeyMaster sends explicit fallback responses instead of failing silently.
- Automatic keystone slotting is currently disabled to avoid Blizzard protected-action (taint) popup errors.
- The overlay appears automatically during active Mythic+ runs when the KeyMaster Mythic+ UI setting is enabled.
- If the KeyMaster Mythic+ UI setting is disabled, Blizzard's default Mythic+ UI remains available while KeyMaster chat features still work.
- By default, KeyMaster fades Blizzard's objective/quest tracker while inside active Mythic+ runs.
- Blizzard's objective/quest tracker returns when the KeyMaster overlay is hidden, disabled, or no longer active.
- The settings panel includes a `Hide Blizzard objectives during Mythic+` toggle if you want to change that behavior.
- The KeyMaster settings panel includes a short positioning note plus `Unlock UI` and `Lock UI` buttons.
- By default, the overlay is positioned on the right side of the screen just below the minimap.
- When the overlay is unlocked, drag it to the position you want and then lock it again.
- The Enemy Forces bar uses a fixed blue fill with centered white percentage text.
- Death hover attribution uses both group-unit death state and combat-log events, with an unattributed fallback line if names are unavailable.
