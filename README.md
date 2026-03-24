# KeyMaster

A lightweight WoW addon for Mythic+ groups.

## What it does

- If someone, including you, types `!key` or `!keys` in party, raid, instance, or guild chat, it replies with your clickable keystone link.
- If you do not have a key, it does nothing.
- If a clickable keystone link cannot be resolved, it does nothing (no plain-text fallback).
- When opening a Font of Power, it auto-slots your key only if your key matches that dungeon.
- Responses are anti-spam protected with a 15-second cooldown.
- Responses include an addon tag prefix, for example: `[KeyMaster] [Mythic Keystone: ...]`

## Install

1. Put this folder in your WoW addons directory:
   - `_retail_/Interface/AddOns/KeyMaster`
2. Make sure these files are inside that folder:
   - `KeyMaster.toc`
   - `KeyMaster.lua`
3. Start the game and enable KeyMaster in the addon list.
4. Run `/reload`.

## Notes

- The addon listens in party, raid, instance group, and guild chat channels.
- Font auto-slot uses Blizzard Mythic+ APIs with fallbacks for better compatibility.
