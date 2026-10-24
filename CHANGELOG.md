# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). The dated entry describes the build whose `--version` prints that number; nothing is tagged or published.

## [Unreleased]

### Changed
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
