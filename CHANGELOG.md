# Changelog

All notable changes to this project will be documented in this file.

## [1.7.0] - 2026-04-14

### Changed
- Renamed addon branding from **KeyStone Master** to **KeyStoneMastery**.
- Updated chat reply prefix to `KeyStoneMastery:`.
- Prepared Retail `12.0.5` readiness notes and validation checklist.
- Updated project docs to call out Retail `12.0.5` forward compatibility.
- Expanded `/ksm` dashboard as a full multi-tab Mythic+ panel (`Main`, `Party`, `Guild`).
- Added Guild tab controls for pagination and `Hide Offline` filtering.
- Guild request button now triggers active guild key pulls across enabled sources.
- Kept `KeyMaster.lua` as the main runtime file and split shared constants/data into dedicated modules:
  - `KeyMaster.Constants.lua`
  - `KeyMaster.Data.lua`
- Split reusable parsing/formatting/request helpers into `KeyMaster.Utils.lua`.
- Split guild safety/recent-activity helpers into `KeyMaster.GuildUtils.lua`.
- Split addon sync/external key-ingestion pipeline into `KeyMaster.Sync.lua`.
- Extracted `/ksm` tab refresh logic into `KeyMaster.UI.KSM.lua` to keep `KeyMaster.lua` focused on orchestration.
- Updated TOC load order so shared modules load before `KeyMaster.lua`.

### Fixed
- Reduced risk of Lua chunk-local overflow in the main file by moving large static tables out of `KeyMaster.lua`.
- Added passive guild key cache ingestion from observed keystone chat links and external key-sharing payloads.
- Restricted `!keys` handling to KeyMaster sync behavior while leaving active external pulls to the Guild request path.
- Strengthened guild sync payload parsing and sanitization for malformed addon messages.
- Added AstralKeys `sync*` batch payload parsing (in addition to `updateV*`) so guild key snapshots populate reliably.
- Expanded external key-ingestion channels for AstralKeys/OpenRaid messages beyond guild-only flows to improve party/guild coverage.
- Ensured guild chat key replies are merged into `/ksm guild` rows even when roster-derived entries already exist, with Blizzard roster/API enrichment for class, online state, and score when available.
- Improved Blizzard rating enrichment lookups for Party/Guild tabs by trying multiple member identifiers (GUID, full name, normalized name) when score data is missing.
- Restored guild/officer `!keys` auto-replies when chat payload coercion is required by using safer command normalization flow.
- Added AstralKeys plaintext chat parsing for messages like `Astral Keys: [Dungeon (12)]` so guild tab rows are created from those links.
- Expanded generic guild chat keystone parsing to capture additional addon/user-facing formats (including `(+12)` and `+12` variants) so addon responders reliably populate `/ksm guild`.
- Added fail-safe guild command replies so `!keys`/`!score`/`!best` still respond with fallback text when runtime command parsing or reply generation returns nil.
- Updated `!keys` reply building to fall back to owned snapshot text (`+level dungeon`) when hyperlink creation is unavailable, preventing false "Keystone unavailable" replies.
- Fixed portal click-casting reliability in `/ksm` Main/Party/Guild views by using a shared known-spell check (`IsSpellKnownOrOverridesKnown`/`IsPlayerSpell`) and robust cast fallback path.
- Replaced direct portal cast calls with secure spell action-button bindings in Main/Party/Guild portal buttons to resolve BugGrabber `ADDON_ACTION_FORBIDDEN` protected-call errors.
- Removed legacy direct-cast behavior from the old portal helper so stale call paths cannot invoke protected cast APIs.
- Fixed portal button click execution by registering secure portal buttons for hardware clicks and binding spell cast tokens compatible with secure action attributes.
- Hardened portal spell API compatibility checks to avoid indexing non-table globals on clients where `C_Spell`/`C_SpellBook` differ, preventing addon load/runtime breaks.
- Hardened `/km` and `/ksm` slash registration with unique command IDs and early command binding to avoid addon command collisions and preserve command availability during partial initialization.
- Added dual slash alias registration (`KEYMASTER`/`KEYSTONEMASTER` plus `KEYSTONEMASTERY*`) and login-time rebind to keep `/km` and `/ksm` available even if another addon overwrites slash tables.
- Improved `/ksm guild` population reliability by including recent roster members even when key cache is empty, guarding against invalid roster names, and always showing the current player row.
- Hotfixed `/ksm` tab rendering break by removing non-WoW Lua `goto`/label syntax from guild-tab roster parsing.

### Packaging
- Built release archive at `Releases/1.7.0/KeyMaster.zip`.

## [1.6.8] - 2026-04-13

### Changed
- Renamed addon from **KeyMaster** to **KeyStone Master**
- Updated chat reply prefix to `KeyStoneMaster:`

### Fixed
- Fixed protected function call error with frame event registration

### Packaging
- Built release archive at `Releases/1.6.8/KeyMaster.zip`.

## [1.6.7] - 2026-04-11

### Fixed
- Stopped registering the full event list in the main chunk, which was still triggering protected `Frame:RegisterEvent()` forbidden errors in fresh BugGrabber captures.
- Kept only `ADDON_LOADED` registration at file load and moved runtime event registration into addon `ADDON_LOADED` handling with one-time guarding.

### Notes
- Addon name changed to **KeyStone Master**

### Packaging
- Built release archive at `Releases/1.6.7/KeyMaster.zip`.

## [1.6.6] - 2026-04-11

### Fixed
- Moved frame event registration to early startup immediately after frame creation, before taint-prone runtime paths.
- Removed the `securecallfunction` registration wrapper and late registration path tied to fresh `UNKNOWN()` forbidden BugGrabber stacks.

### Packaging
- Built release archive at `Releases/1.6.6/KeyMaster.zip`.

## [1.6.5] - 2026-04-09

### Fixed
- Routed frame event registration through `securecallfunction` to avoid the protected `Frame:RegisterEvent()` forbidden path seen in fresh BugGrabber dumps.
- Kept one-time startup event wiring behavior while hardening against taint-sensitive registration contexts.

### Packaging
- Built release archive at `Releases/1.6.5/KeyMaster.zip`.

## [1.6.4] - 2026-04-08

### Fixed
- Removed runtime/deferred `Frame:RegisterEvent()` calls and restored one-time static event registration at file load.
- Eliminated the KeyMaster forbidden call path seen in BugGrabber stacks (`Frame:RegisterEvent()` at runtime).

### Packaging
- Built release archive at `Releases/1.6.4/KeyMaster.zip`.

## [1.6.3] - 2026-04-03

### Fixed
- Deferred runtime event registration when combat lockdown is active, then retries registration after combat ends.
- Added idempotent login initialization so startup setup still runs if `PLAYER_LOGIN` was missed while runtime events were deferred.

### Packaging
- Built release archive at `Releases/1.6.3/KeyMaster.zip`.

## [1.6.2] - 2026-04-02

### Fixed
- Replaced the `pcall`-based deferred event bootstrap with a safer `ADDON_LOADED`-first registration flow.
- Eliminated the protected `UNKNOWN()`/`Frame:RegisterEvent()` forbidden path seen in BugGrabber stacks.

### Packaging
- Built release archive at `Releases/1.6.2/KeyMaster.zip`.

## [1.6.1] - 2026-04-02

### Fixed
- Moved frame event registration out of main chunk and into a deferred bootstrap path to prevent `[ADDON_ACTION_FORBIDDEN]` errors on `Frame:RegisterEvent()`.
- Added guarded retry registration logic so event wiring completes safely after load/combat constraints clear.

### Packaging
- Built release archive at `Releases/1.6.1/KeyMaster.zip`.

## [1.6.0] - 2026-04-02

### Fixed
- Deferred outgoing chat replies during combat and flushes them once combat ends instead of dropping them outright.
- Deferred new-keystone party announcements during combat so post-run key updates still announce safely after `PLAYER_REGEN_ENABLED`.

### Packaging
- Built release archive at `Releases/1.6.0/KeyMaster.zip`.

## [1.5.9] - 2026-04-01

### Fixed
- Restored automatic keystone slotting when the Font of Power receptacle opens — scans bags for a Mythic Keystone and slots it via `C_ChallengeMode.SlotKeystone()` without triggering protected-action errors.
- Updated settings panel description to accurately reflect that automatic keystone slotting is active when the KeyMaster Mythic+ UI is enabled.

### Packaging
- Built release archive at `Releases/1.5.9/KeyMaster.zip`.

## [1.5.8] - 2026-03-31

### Fixed
- Removed runtime/retry event registration and restored static frame event registration to avoid protected `Frame:RegisterEvent()` forbidden errors.
- Hardened chat command extraction to avoid direct restricted-string equality checks that can trigger secret-string taint comparisons.
- Added a `canaccessvalue` guard before chat parsing so unreadable secret-string payloads are dropped safely.
- Wrapped command reply construction in protected execution to fail closed on unexpected runtime payload edge cases.

### Packaging
- Built release archive at `Releases/1.5.8/KeyMaster.zip`.

## [1.5.7] - 2026-03-30

### Fixed
- Hardened chat command parsing against secret-string taint by converting incoming chat message values to plain strings before comparisons/parsing.
- Reworked deferred event registration to use direct `frame:RegisterEvent(...)` calls in safe initialization context, removing pcall-wrapped registration that could trigger protected-action reports.
- Added one-time frame-event registration guard to prevent duplicate event wiring.

### Packaging
- Built release archive at `Releases/1.5.7/KeyMaster.zip`.

## [1.5.6] - 2026-03-29

### Fixed
- Added `!scores` as an alias for `!score` so both commands return Mythic+ score replies.
- Improved `!best` run-history parsing to accept numeric-string level/map values and partial run records.
- Added safe fallback so weekly best uses season best when week-specific API flags are missing but valid season data exists.

### Packaging
- Built release archive at `Releases/1.5.6/KeyMaster.zip`.

## [1.5.5] - 2026-03-29

### Fixed
- Restored startup initialization by registering `ADDON_LOADED` at file load so the addon can receive its first event and initialize correctly.
- Kept deferred registration for remaining frame events after initialization to preserve protected-call safety.

### Packaging
- Built release archive at `Releases/1.5.5/KeyMaster.zip`.

## [1.5.4] - 2026-03-29

### Fixed
- Deferred frame event registration to ADDON_LOADED handler to prevent protected-function errors during addon load.
- RegisterEvent calls now use deferred execution via pcall guards in a safe event context.

### Packaging
- Built release archive at `Releases/1.5.4/KeyMaster.zip`.

## [1.5.3] - 2026-03-29

### Fixed
- Hardened chat command handling to avoid comparing directly against tainted secret-string message values.
- Command replies now route through normalized command tokens (`!key`, `!keys`, `!score`, `!best`) for safer comparisons in chat-event handlers.

### Packaging
- Built release archive at `Releases/1.5.3/KeyMaster.zip`.

## [1.5.2] - 2026-03-28

### Fixed
- Enemy Forces label now renders on a dedicated top overlay layer above the progress fill so the text stays over the bar as it fills.
- Reduced label backdrop tint so bar fill remains visible while preserving text contrast.

### Packaging
- Built release archive at `Releases/1.5.2/KeyMaster.zip`.

## [1.5.1] - 2026-03-28

### Fixed
- Increased Enemy Forces bar label readability by darkening the label backdrop and using outlined text styling.

### Packaging
- Built release archive at `Releases/1.5.1/KeyMaster.zip`.

## [1.5.0] - 2026-03-28

### Fixed
- Completed-run summary now preserves and displays actual completion time instead of occasionally showing `00:00`.
- Remaining-time display on completion now supports signed values; overtime is shown as a negative value and highlighted in red.
- Added delayed completion-time refresh to pick up final run time when completion info arrives slightly after the completion event.

### Packaging
- Built release archive at `Releases/1.5.0/KeyMaster.zip`.

## [1.4.9] - 2026-03-28

### Added
- Added automatic new-key announcements to party chat when your owned keystone changes after Mythic+ completion/reset.
- Key-change detection uses a stored keystone snapshot and delayed post-completion checks so rerolled keys are picked up reliably.

### Packaging
- Built release archive at `Releases/1.4.9/KeyMaster.zip`.

## [1.4.8] - 2026-03-28

### Fixed
- Blizzard objective tracker now returns correctly when the KeyMaster overlay is hidden or disabled, while still fading during active Mythic+ overlay use.
- Improved Enemy Forces label readability by adding stronger text contrast over the blue progress bar.
- Reworked death attribution to track party member death state directly from group units in addition to combat-log events, making hover details more reliable.

### Packaging
- Built release archive at `Releases/1.4.8/KeyMaster.zip`.

## [1.4.7] - 2026-03-28

### Changed
- Updated README to reflect current behavior for chat command coverage, command matching tolerance, and fallback responses.
- Documented current protected-action safety state: automatic keystone slotting remains disabled.
- Added slash-command documentation for `/km deaths`, `/km criteria`, and `/km forces`.

### Packaging
- Built release archive at `Releases/1.4.7/KeyMaster.zip`.

## [1.4.6] - 2026-03-27

### Fixed
- Corrected run-active detection so completed Mythic+ runs do not remain in an active-timer state after completion.
- Completion view now zeroes the remaining timer at run end, restoring expected timer reset behavior.

### Packaging
- Built release archive at `Releases/1.4.6/KeyMaster.zip`.

## [1.4.5] - 2026-03-27

### Fixed
- Restored suppression of the default Blizzard objective tracker during Mythic+ using alpha changes instead of frame reparenting.
- This keeps the custom KeyMaster overlay visible without bringing back the earlier protected-action risk from tracker parent swaps.

### Packaging
- Built release archive at `Releases/1.4.5/KeyMaster.zip`.

## [1.4.4] - 2026-03-27

### Fixed
- Improved `!key` and `!keys` reliability by detecting Mythic Keystones from actual bag hyperlinks, not only the owned-keystone API path.
- Added direct bag-link fallback so players with a keystone in their bags are more likely to respond even when Blizzard keystone ownership APIs are late or inconsistent.

### Packaging
- Built release archive at `Releases/1.4.4/KeyMaster.zip`.

## [1.4.3] - 2026-03-27

### Fixed
- Disabled automatic keystone slotting to eliminate the remaining protected-action path most likely causing Blizzard UI blocked popups.
- Manual keystone slotting remains available through the default Blizzard UI.

### Packaging
- Built release archive at `Releases/1.4.3/KeyMaster.zip`.

## [1.4.2] - 2026-03-27

### Fixed
- Removed direct Objective Tracker frame parent manipulation from runtime updates to avoid Blizzard protected-action taint errors.
- This hotfix targets the "action only available to Blizzard UI" block message.

### Packaging
- Built release archive at `Releases/1.4.2/KeyMaster.zip`.

## [1.4.1] - 2026-03-27

### Fixed
- Broadened death attribution capture gating to track group deaths whenever Mythic dungeon context is active, even if challenge-state APIs briefly lag.
- Reduces cases where total deaths are shown but hover details fall back to `Unattributed` for the whole run.

### Packaging
- Built release archive at `Releases/1.4.1/KeyMaster.zip`.

## [1.4.0] - 2026-03-27

### Fixed
- Auto-reply command parsing now tolerates color formatting and inline punctuation more robustly.
- `!key`, `!keys`, `!score`, and `!best` now always return a response instead of failing silently when game API data is temporarily unavailable.
- Added explicit fallback replies (`Keystone unavailable`, `M+ Score unavailable`) to make temporary data gaps clear.

### Packaging
- Built release archive at `Releases/1.4.0/KeyMaster.zip`.

## [1.3.9] - 2026-03-27

### Fixed
- Expanded chat trigger coverage for auto-replies to include party/raid leader channels and instance chat channels.
- Relaxed command parsing so requests like `!score?` and `!best.` still trigger replies.

### Packaging
- Built release archive at `Releases/1.3.9/KeyMaster.zip`.

## [1.3.8] - 2026-03-27

### Fixed
- Improved death-name capture timing so per-player attribution is recorded more reliably during active Mythic dungeon runs.
- Death tooltip now shows an `Unattributed` fallback count when Blizzard death totals exist but per-player names were unavailable.

### Packaging
- Built release archive at `Releases/1.3.8/KeyMaster.zip`.

## [1.3.7] - 2026-03-27

### Fixed
- Enemy Forces bar text now truncates fractional percentages to match Blizzard-style integer display (for example, 85.5% now shows as 85% instead of 86%).

### Packaging
- Built release archive at `Releases/1.3.7/KeyMaster.zip`.

## [1.3.6] - 2026-03-27

### Fixed
- Death attribution capture now prefers player GUID detection, making per-player death names more reliable in combat-log edge cases.
- Death hover hitbox is now more robust and keeps an interactive area even when text width/height reports transient zero values.

### Packaging
- Built release archive at `Releases/1.3.6/KeyMaster.zip`.

## [1.3.5] - 2026-03-27

### Fixed
- Reworked Enemy Forces percent calculation to follow the in-game criteria logic path first.
- Weighted criteria now prioritize direct handling of `quantity`, `quantityString`, and `totalQuantity` before custom fallbacks.
- Retained dungeon total-unit conversion only as fallback when criteria data is incomplete.

### Packaging
- Built release archive at `Releases/1.3.5/KeyMaster.zip`.

## [1.3.4] - 2026-03-27

### Fixed
- Enemy Forces conversion now uses dungeon-specific total-unit values across the full current Midnight season dungeon pool.
- Added mapID-based total-unit lookup for deterministic conversion, with name fallback handling for localization/name variants.
- Added `/km forces` debug command to print live Enemy Forces mapping details (mapID, known total, cached total, criterion raw values).

### Packaging
- Built release archive at `Releases/1.3.4/KeyMaster.zip`.

## [1.3.3] - 2026-03-27

### Fixed
- Completed-run panel now stays visible while you remain inside the Mythic+ dungeon and clears immediately when you leave (e.g., hearth out).
- Improved weighted Enemy Forces fallback: when weighted quantity is absolute progress with a non-100 total, percent is now computed as `quantity / total * 100`.

### Packaging
- Built release archive at `Releases/1.3.3/KeyMaster.zip`.

## [1.3.2] - 2026-03-27

### Fixed
- Fixed `/km criteria` runtime error (line 262) caused by early references to local helper functions that are declared later in file scope.
- Criteria debug now uses direct Blizzard API calls within the command handler, preventing nil-function lookup errors.

### Packaging
- Built release archive at `Releases/1.3.2/KeyMaster.zip`.

## [1.3.1] - 2026-03-27

### Fixed
- Replaced fuzzy Enemy Forces objective matching with strict normalized label matching against Blizzard's Enemy Forces criterion.
- Removed broad substring matching (e.g., generic "forces") that could bind to the wrong weighted objective and show incorrect percentages.
- Enemy Forces criterion selection is now deterministic and confidence-based among exact-name weighted candidates only.

### Packaging
- Built release archive at `Releases/1.3.1/KeyMaster.zip`.

## [1.3.0] - 2026-03-27

### Changed
- Adopted rollover versioning policy: when patch reaches 9, the next release increments minor and resets patch to 0.
- Promoted latest fixes into 1.3.0 under the new versioning scheme.

### Packaging
- Built release archive at `Releases/1.3.0/KeyMaster.zip`.

## [1.2.14] - 2026-03-27

### Fixed
- Enemy Forces percent resolution now mirrors the game criteria weighted handling more closely after mid-run reloads.
- For weighted Enemy Forces criteria, fallback now uses the weighted quantity directly (percent-like) instead of quantity/total conversion.
- Percent parser now tolerates WoW color formatting and spacing variants like `88 %`, reducing false fallback to bad values.

### Packaging
- Built release archive at `Releases/1.2.14/KeyMaster.zip`.

## [1.2.13] - 2026-03-27

### Fixed
- Enemy Forces bar mapping is now strict: it only binds to weighted-progress criteria whose name matches the Blizzard Enemy Forces label.
- This removes ambiguous criterion fallback that could select a completed objective and incorrectly show 100% early.
- Per-player death attribution now records while Mythic+ is actively detected (not only when the start-event flag is set), preventing missed capture from event ordering edge cases.

### Packaging
- Built release archive at `Releases/1.2.13/KeyMaster.zip`.

## [1.2.12] - 2026-03-27

### Fixed
- `/km criteria` now always prints a status header and wraps debug collection in `pcall`, so failures are shown as chat errors instead of appearing to do nothing.

### Packaging
- Built release archive at `Releases/1.2.12/KeyMaster.zip`.

## [1.2.11] - 2026-03-27

### Fixed
- Further tightened Enemy Forces criterion selection by preferring weighted-progress objectives with expected totals and computing percent from quantity/total when needed.
- Fixed death-hover interaction while UI is locked by keeping frame mouse enabled (dragging is still blocked by lock checks).

### Added
- Added `/km criteria` debug command to print raw scenario criteria values (name, weighted flag, quantity, total, quantityString) for fast in-run diagnosis.

### Packaging
- Built release archive at `Releases/1.2.11/KeyMaster.zip`.

## [1.2.10] - 2026-03-27

### Fixed
- Tightened Enemy Forces mapping again by prioritizing the localized Blizzard label (`CHALLENGE_MODE_ENEMY_FORCES`) on weighted-progress criteria.
- Improved death-hover reliability by expanding the hover hit area to the full deaths row width.

### Added
- Added `/km deaths` to print per-player death attribution captured during the current/recent run.

### Packaging
- Built release archive at `Releases/1.2.10/KeyMaster.zip`.

## [1.2.9] - 2026-03-26

### Fixed
- Tightened Enemy Forces detection to only use weighted-progress scenario criteria, matching in-game criteria behavior more closely.
- This avoids treating unrelated percentage-based objectives as Enemy Forces, which could cause the bar to jump to 100% on an early pull.
- Improved the deaths hover area and tooltip behavior so hovering the deaths line always gives visible feedback.

### Changed
- Group death attribution now uses explicit combat-log player and affiliation flags for more reliable party-member tracking.

### Packaging
- Built release archive at `Releases/1.2.9/KeyMaster.zip`.

## [1.2.8] - 2026-03-26

### Added
- Added a hover tooltip on the deaths line that shows which party members died and how many times.

### Changed
- Death tooltip data is tracked from `COMBAT_LOG_EVENT_UNFILTERED`, matching a combat-log-first attribution approach.
- Death breakdown is preserved briefly on the completed-run summary as well.

### Packaging
- Built release archive at `Releases/1.2.8/KeyMaster.zip`.

## [1.2.7] - 2026-03-26

### Fixed
- End-of-key summary now uses Blizzard's `C_ChallengeMode.GetCompletionInfo()` for final completion time and upgrade levels.
- This prevents the completion display from falling back to `00:00` when the live world timer resets after dungeon completion.

### Packaging
- Built release archive at `Releases/1.2.7/KeyMaster.zip`.

## [1.2.6] - 2026-03-26

### Fixed
- Enemy Forces now uses Blizzard-provided percentage text directly from scenario criteria (the `%` value), instead of inferred quantity/total math.
- This prevents incorrect early 100% spikes caused by selecting non-forces criteria with ratio-style values.

### Packaging
- Built release archive at `Releases/1.2.6/KeyMaster.zip`.

## [1.2.5] - 2026-03-26

### Fixed
- Fixed end-of-key timer resetting to `00:00` by capturing a completion snapshot and rendering that summary after `CHALLENGE_MODE_COMPLETED`.
- Added explicit key result line showing `Result: +1`, `Result: +2`, `Result: +3`, or `Result: Depleted`.
- Improved Enemy Forces objective detection to avoid false positives (such as immediate 100% from non-forces criteria).

### Changed
- Added a short post-completion display window showing final elapsed time, remaining time, and key result.

### Packaging
- Built release archive at `Releases/1.2.5/KeyMaster.zip`.

## [1.2.4] - 2026-03-26

### Fixed
- Fixed inaccurate Enemy Forces progress by improving how the addon identifies the Enemy Forces scenario criterion.
- Replaced first-match weighted detection with scored candidate selection using name, percent text, weighted flag, and quantity metadata.

### Packaging
- Built release archive at `Releases/1.2.4/KeyMaster.zip`.

## [1.2.3] - 2026-03-26

### Fixed
- Fixed a render deadlock where the Mythic+ panel could remain hidden forever because visibility logic only ran in `OnUpdate` while the frame was hidden.
- `RefreshMythicUI()` now performs an immediate render pass so event-driven updates can show the frame instantly.
- Removed `PLAYER_ENTERING_WORLD` flag reset that could clear M+ state during key-start transitions.

### Changed
- Refactored UI drawing into a shared `RenderMythicUI()` routine used by both event refreshes and periodic timer refreshes.

### Packaging
- Built release archive at `Releases/1.2.3/KeyMaster.zip`.

## [1.2.2] - 2026-03-26

### Fixed
- Fixed M+ overlay not appearing during actual Mythic+ runs by using event-driven detection from challenge events.
- Added `ui.inChallengeMode` flag that is set immediately when `CHALLENGE_MODE_START` event fires, bypassing API initialization delays.
- Challenge mode detection now has higher priority for event-based signal over API queries.
- Added "M+ detected: yes/no" output to `/km status` for better diagnostic visibility.

### Changed
- Improved event handling for `CHALLENGE_MODE_START`, `CHALLENGE_MODE_COMPLETED`, and `CHALLENGE_MODE_RESET` with dedicated handlers.
- Challenge mode flag is now cleared on world transitions to prevent stale state.

### Packaging
- Built release archive at `Releases/1.2.2/KeyMaster.zip`.

## [1.2.1] - 2026-03-26

### Added
- Added `/km status` to show current KeyMaster UI state (enabled, hidden, tracker-hide mode, lock state, scale, and anchor).
- Added `/km ui restore` to re-enable and reset the KeyMaster UI to a known-good default position.
- Added `Unlock UI` and `Lock UI` buttons to the KeyMaster settings panel.
- Added a `Hide Blizzard objectives during Mythic+` setting (enabled by default).

### Changed
- Improved Mythic+ activity detection and added a fallback overlay state while challenge data initializes.
- Changed default overlay anchor to top-right under the minimap.
- Improved slash/help messaging for positioning and UI recovery.

### Packaging
- Built release archive at `Releases/1.2.1/KeyMaster.zip`.

## [1.2.0] - 2026-03-26

### Added
- Added a live Mythic+ overlay UI to KeyMaster with a transparent black panel and white text.
- Added active dungeon header, affix summary, elapsed timer, and +2/+3 chest breakpoint lines.
- Added scenario objective tracking, death counter display, and an Enemy Forces progress bar.
- Added `/km` UI controls for lock, unlock, hide, show, reset, and scale.
- Added a KeyMaster settings option to disable the custom Mythic+ UI and fall back to Blizzard's default Mythic+ interface.

### Changed
- Styled the Enemy Forces bar with a blue progress fill and centered white percentage text.

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