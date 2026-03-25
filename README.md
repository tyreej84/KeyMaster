# KeyMaster

A lightweight WoW addon for Mythic+ groups.

## What it does

- If someone, including you, types `!key` or `!keys` in party, raid, or guild chat, it replies with your clickable keystone link.
- If you do not have a key, it does nothing.
- If a clickable keystone link cannot be resolved, it does nothing (no plain-text fallback).
- When opening a Font of Power, it attempts to auto-slot your key.
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

- The addon listens in party, raid, and guild chat channels.
- Trigger matching is strict exact-match only (`!key` and `!keys` are both supported aliases).
- Font auto-slot uses Blizzard Mythic+ APIs with fallbacks for better compatibility.
