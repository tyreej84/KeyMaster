# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [1.1.3] - 2026-03-26

### Fixed
- Added debug logging around reply generation and `SendChatMessage` to diagnose any remaining chat-command failures.

### Packaging
- Built release archive at `Releases/1.1.3/KeyMaster.zip`.

## [1.1.2] - 2026-03-26

### Fixed
- Added a bag-scan fallback for Mythic+ keystone links so `!key` and `!keys` can still reply when `C_MythicPlus.GetOwnedKeystoneLink()` does not return a link.

### Packaging
- Built release archive at `Releases/1.1.2/KeyMaster.zip`.

## [1.1.1] - 2026-03-26

### Fixed
- Removed unused `NormalizeName` helper function (dead code).

### Packaging
- Built release archive at `Releases/1.1.1/KeyMaster.zip`.

## [1.1.0] - 2026-03-25

### Fixed
- Simplified chat event listening to focus on party/raid/guild channels (removed instance chat, whisper, and say).
- Added explicit debug logging at event entry point to diagnose chat-event dispatch issues.

### Testing
- Use `/km debug` to enable debugging and monitor which events are being received.

### Packaging
- Built release archive at `Releases/1.1.0/KeyMaster.zip`.

## [1.0.10] - 2026-03-25

### Fixed
- Simplified keystone link generation to eliminate the syntax error that was preventing the addon from loading.

### Packaging
- Built release archive at `Releases/1.0.10/KeyMaster.zip`.

## [1.0.9] - 2026-03-25

### Fixed
- Moved slash command registration to the earliest safe load point so addon startup can be verified even if later functionality fails.

### Packaging
- Built release archive at `Releases/1.0.9/KeyMaster.zip`.

## [1.0.8] - 2026-03-25

### Fixed
- Fixed current Retail Lua compatibility by explicitly binding helper functions used by command and debug paths.

### Packaging
- Built release archive at `Releases/1.0.8/KeyMaster.zip`.

## [1.0.7] - 2026-03-25

### Changed
- Expanded chat event coverage to include instance chat, whisper, and say for compatibility testing.
- Added `/keymaster` and `/km` slash commands with optional debug logging to diagnose command handling in game.

### Packaging
- Built release archive at `Releases/1.0.7/KeyMaster.zip`.

## [1.0.6] - 2026-03-25

### Changed
- Updated addon interface compatibility to WoW Retail `12.0.1` (`## Interface: 120001`).
- Reworked keystone link generation for current Retail APIs: resolve owned keystone map/level from `C_MythicPlus` and build the chat link directly.

### Packaging
- Built release archive at `Releases/1.0.6/KeyMaster.zip`.

## [1.0.4] - 2026-03-25

### Added
- Added `!best` command to report your best key for the current week and season.
- Added `!weekly` command alias for `!vault`.

### Changed
- Expanded strict exact-match command set to: `!key`, `!keys`, `!score`, `!vault`, `!weekly`, and `!best`.

## [1.0.3] - 2026-03-25

### Added
- Added `!score` command to report your current Mythic+ score.
- Added `!vault` command to report Mythic+ weekly vault progress.

### Changed
- Expanded strict exact-match command set to: `!key`, `!keys`, `!score`, and `!vault`.

## [1.0.2] - 2026-03-25

### Changed
- Updated chat command handling:
  - Supports strict exact-match aliases: `!key` and `!keys`
  - Command replies are handled in party, raid, and guild chat
- Removed reply cooldown so each valid `!keys` request can respond.

### Improved
- Auto-slot reliability when opening a keystone receptacle:
  - Added support for both receptacle event name variants.
  - Auto-slot now attempts insertion when receptacle context is available, while still blocking known map mismatches.

## [1.0.1] - 2026-03-24

### Added
- Added `.gitignore` rule for `Releases/`.
- Added this `CHANGELOG.md` for release tracking.

### Changed
- Key request handling now responds when you type `!key` or `!keys` yourself.
- Updated README wording to document self-trigger behavior.

### Packaging
- Standardized local release artifact layout to `Releases/<version>/KeyMaster.zip`.
- Release zip contains only runtime addon files:
  - `KeyMaster/KeyMaster.lua`
  - `KeyMaster/KeyMaster.toc`

## [1.0.0] - 2026-03-24

### Added
- Initial KeyMaster release.
- Chat trigger support for `!key` and `!keys` in party, raid, instance, and guild chat.
- Keystone reply uses clickable keystone link only (no plain-text fallback).
- 15-second anti-spam cooldown for automated replies.
- Font of Power auto-slot support when your key matches the dungeon.
