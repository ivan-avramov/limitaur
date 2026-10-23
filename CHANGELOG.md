# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). The dated entry describes the build whose `--version` prints that number; nothing is tagged or published.

## [Unreleased]

### Changed
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
