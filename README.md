# Keylord

A lightweight WoW addon for Mythic+ groups.

## What it does

- If someone types `!key` or `!keys` in group chat, it replies with your key.
- If you do not have a key, it does nothing.
- When opening a Font of Power, it auto-slots your key only if your key matches that dungeon.

## Install

1. Put this folder in your WoW addons directory:
   - `_retail_/Interface/AddOns/Keylord`
2. Make sure these files are inside that folder:
   - `Keylord.toc`
   - `Keylord.lua`
3. Start the game and enable Keylord in the addon list.
4. Run `/reload`.

## Notes

- The addon listens in party, raid, and instance group chat channels.
- Font auto-slot uses Blizzard Mythic+ APIs with fallbacks for better compatibility.
