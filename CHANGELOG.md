# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-03-26

### Added
- Added a live Mythic+ overlay UI to KeyMaster with a transparent black panel and white text.
- Added active dungeon header, affix summary, elapsed timer, and +2/+3 chest breakpoint lines.
- Added scenario objective tracking, death counter display, and an Enemy Forces progress bar.
- Added `/km` UI controls for lock, unlock, hide, show, reset, and scale.
- Added a KeyMaster settings option to disable the custom Mythic+ UI and fall back to Blizzard's default Mythic+ interface.

### Changed
- Styled the Enemy Forces bar with a BreakTimerLite-inspired blue progress fill and centered white percentage text.

### Packaging
- Built release archive at `Releases/1.2.0/KeyMaster.zip`.

## [1.1.9] - 2026-03-26

### Changed
- Removed all debug logging and slash command debug modes for a clean production build.
- Fixed latent nil reference to removed `KEYSTONE_ITEM_ID` constant in synthetic keystone link builder.

### Packaging
- Built release archive at `Releases/1.1.9/KeyMaster.zip`.

## [1.1.8] - 2026-03-26

### Fixed
- Fixed `!best` reporting impossible key levels: `GetWeeklyBestForMap`/`GetSeasonBestForMap` return scores on current Retail, not key levels. Run history is now the primary source with a key-level sanity check (2-40).
- Fixed `!best` crash caused by unescaped pipe character in chat reply string (replaced `|` with `/`).

## [1.1.7] - 2026-03-26

### Removed
- Removed `!vault` and `!weekly` commands (only showed completion counts, not reward item levels).

## [1.1.6] - 2026-03-26

### Fixed
- Replaced `CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN` event registration with `ChallengesKeystoneFrame:HookScript("OnShow")` for reliable auto-slot behaviour.
- Auto-slot now uses `PickupContainerItem` + `CursorHasItem()` before calling `SlotKeystone()`.
- Added `ADDON_LOADED` handling to hook `Blizzard_ChallengesUI` when it loads, with a fallback check at `PLAYER_LOGIN`.
- Expanded keystone item ID support to cover all known variants: 180653 (Dragonflight/TWW), 158923 (BfA), 151086 (Legion).

## [1.1.2] - 2026-03-26

### Fixed
- Added bag-scan fallback for keystone link resolution when `C_MythicPlus.GetOwnedKeystoneLink()` returns nil.

## [1.1.0] - 2026-03-25

### Fixed
- Simplified chat event listening to party, raid, and guild channels only.

## [1.0.4] - 2026-03-25

### Added
- Added `!best` command to report best key for the current week and season.
- Added `!score` command to report current Mythic+ score.

## [1.0.0] - 2026-03-24

### Added
- Initial release.
- `!key` and `!keys` commands reply with your clickable keystone link in party, raid, and guild chat.
- Font of Power auto-slot when your key matches the dungeon.