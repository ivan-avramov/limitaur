# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). The dated entry describes the build whose `--version` prints that number; nothing is tagged or published.

## [Unreleased]

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
