# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

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
