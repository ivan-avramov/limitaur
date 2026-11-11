# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). The dated entry describes the build whose `--version` prints that number; releases 0.2.0 and 0.2.1 have annotated tags pushed to the public repository.

## [Unreleased]

### Added
- Cursor provider: the Cursor switch under Settings → Providers reads the existing cursor-agent sign-in from the Keychain (read-only, through `/usr/bin/security`) and shows one `CU` / `$` bar of the caller's own billing-cycle spend against the effective per-user spend limit, with spent and limit amounts (labelled USD) in the dropdown; `--check-live` includes `cursor`.
- Claude spend shows as "Monthly spend" with "Spent this cycle", "Spend limit" and a monthly reset at 00:00 UTC on a configurable day (Settings → Providers → Claude → Spend resets; default the 1st).
- Optional shared budget (Settings → General): adds Claude's and Cursor's reported spend against your own monthly amount, shown as an `SB` bar and a "Shared budget" dropdown card; a partial or mismatched total is never shown as complete.
- Custom provider codes: click a provider's badge in Settings → Providers, or Menu bar code under the shared budget, to choose a one- or two-character code for the menu bar, the dropdown and Settings; duplicates are refused, look-alikes warned, and clearing restores the default.

### Fixed
- Claude spend with a reported limit no longer shows as "Partial data".
- The dropdown no longer shows "· Default" when a provider has only one account.
- "Other accounts" in Settings expands from its label and from the accessibility press action, not only from its chevron.

### Changed
- A native Settings window with General and Providers tabs replaces the Accounts dialog and the Settings pop-up menu. Each provider section has an on/off switch, its source, its live status and its options; extra Codex and Claude accounts live under "Other accounts". Changes apply immediately.
- The dropdown shows one card per account with a usage bar per metric in the threshold colours; percentages show as whole numbers with the exact value in the tooltip.
- Default-workload eligibility counts only enabled profiles.

## [0.2.3] - 2026-11-07

### Added
- About shows the repository, full source revision, UTC build time, MIT license and copyright.
- Local release helper prepares version bumps and verifies signed arm64 ZIP packages and checksums.

## [0.2.2] - 2026-11-07

### Added
- Monochrome minotaur app icon with a charcoal outer tile and transparent corners, registered in the app bundle; menu-bar indicators and Dock behavior are unchanged.

### Changed
- Consolidated historical review evidence and documentation in the repository, clarified retained records and omissions, and updated recovery observations.

## [0.2.1] - 2026-10-25

### Added
- Single-instance guard: a menu-bar launch (with or without `--stats`) takes an advisory lock on `~/Library/Application Support/Limitaur/instance.lock`; a second launch prints `Limitaur is already running` and exits with status 3 before any credential read or request. A lock that cannot be taken for another reason is reported on stderr and the app runs unguarded. Demo and diagnostic modes take no lock.

### Changed
- An unhealthy provider's empty slot no longer draws a track or dash: it shows the provider code over `×` (authentication) or `…` (any other state), so it cannot be read as a usage bar.
- After an authentication failure (every profile on the account paused by a 401/403, an expired token or a failed load) the last usage leaves the bars at its normal freshness horizon instead of staying up to 300 s under a provider `Retry-After`.
- `--stats` eligibility uses each snapshot's freshness horizon (`max(90, interval + 20)` s under a learned interval) instead of a fixed 90 s, so a 120 s interval no longer counts a violation every cycle.
- The expiry-nudge setting stored as an integer or string (`defaults write … NO`) is read as `bool(forKey:)` reads it; an absent key still means on.
- `scripts/measure-resources.py` converts process CPU times from mach ticks (timebase 125/3 on Apple Silicon); earlier CPU figures were about 41.7 times too low (corrected in docs/performance.md, all still under budget).
- Documentation: the learned cadence and exact freshness horizon in the specification, README and performance notes; quit the running instance before a `--stats` measurement.

## [0.2.0] - 2026-10-24

### Added
- On by default, can be turned off (Settings → "Run claude when the Claude session has expired"): when a re-check shows the default Keychain Claude token has expired, run `claude -p hi --model haiku --safe-mode --no-session-persistence --strict-mcp-config --tools ""` (at most hourly, never on a Keychain denial, 60 s limit, fixed environment, a directory group-writable by `admin` accepted, a lock so two Limitaur processes never run it together) so Claude Code renews the session; counters `nudges` and `nudgeFailures`, attempts persisted in `nudge.lastAttempts`, quit waits up to 5 s for a running nudge.

### Changed
- Dropdown metric rows no longer carry the severity tag `(normal)`, `(warning)`, `(critical)` or `(unknown)`; the colour of the row still marks warning and critical.
- Reset and expiry countdowns of a day or more read `in 7d 7h` instead of `in 175h`; under a day they are unchanged.
- The poll interval is learned per provider (start 50 s, bounds 30–120 s): +10 s or the `Retry-After` on a 429 not attributed to a superseded token, −10 s after 24 h and five clean polls, a reduction followed by a 429 within an hour is reverted and blocked for seven days; persisted in `UserDefaults`, shown as `polls every Ns` in the menu, with a 10 s cycle tick and a per-snapshot freshness horizon of `max(90, interval + 20)` s.
- The Claude Keychain item is read through a child `/usr/bin/security find-generic-password -a <user> -w` (five-second bound, hexadecimal output handled) instead of the in-process Keychain API, so a Claude Code token rewrite no longer revokes Limitaur's access; the deprecated `SecKeychain*UserInteractionAllowed` calls and `LocalAuthentication` are removed. A slow or denied background read suspends that source until Connect / Authorize or relaunch.
- After a 401, 403 or 429 the credential is re-read at the next tick at least 30 s after the last load, instead of after five minutes; a rotated token is counted as `credentialRotations`, a suspended source as `keychainSuspensions`.
- New diagnostic `--read-keychain-service NAME` and `scripts/keychain-acl-probe.sh` (operator-run).
- Last usage stays in the bars during a provider-declared Retry-After (until the deadline plus one poll interval, at most 300 s after the fetch) instead of vanishing after 90 s; scheduling and Retry-After handling are unchanged.
- Nominal refresh cadence raised from 30 s to 45 s after the Claude usage endpoint answered 30 s polling with HTTP 429 and multi-minute Retry-After; the scheduler keeps its 30 s per-entity minimum.
- Paused accounts are re-read non-interactively every five minutes (and on manual refresh) and resume automatically when the provider app writes a new unexpired token.
- Status bars carry two stacked codes beside each bar: a two-letter provider code (`CL`, `CX`; table in docs/provider-codes.md) above a window code (`5`, `W`, `M`, `$`, `?`, plus a model initial such as `WF`). The track follows the appearance.
- Build script accepts `LIMITAUR_SIGN_IDENTITY` for a stable signing identity across rebuilds.
- Experimental jar and logo-gauge layouts retained in source, not used by default.
- The orange provider-health dot is removed; an empty slot names the unavailable provider instead.
- MIT licence; public repository.

## [0.1.0] - 2026-10-20

### Added
- Menu-bar monitor for Codex and Claude subscription usage with 1–8 configurable bars.
- `--version` flag and About Limitaur… menu item.
- Build script stamps the version, git commit count and revision into the app bundle and writes a checksum file.
