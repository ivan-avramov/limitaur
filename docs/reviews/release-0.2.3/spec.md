# Release 0.2.3 and local release tooling

## Problem and goal
A new release must bump SemVer and build the ZIP artifacts belonging to that release. Provide repeatable local preparation and packaging, and prepare Limitaur 0.2.3 with the accepted About information.

## Approval and bounds
Operator approved P6 on 2026-11-07: “accepted both. proceed”. Budget 250 added/changed lines across tooling, tests, CHANGELOG and README; specification/review records excluded. Baseline 08e58b5 (accepted About). Light mode for routine release tooling. No product/provider/authentication changes, runtime dependencies, CI, automatic publishing or installed-app replacement. Preserve arm64/macOS 26+, ad-hoc signing, no notarization.

## CLI and formats
Use Python standard library in scripts/release.py. Entry point `python3 scripts/release.py prepare patch|minor|major` or `python3 scripts/release.py package [--output-dir PATH]`. Repository is the script's parent directory, independent of cwd. Default output directory is repository dist/releases/VERSION. Unsupported arguments exit nonzero with a concise diagnostic. All failures exit nonzero; no success message on failure. Work only with normal trusted local Git repositories and stable X.Y.Z versions (three unsigned integers without leading zeroes). No concurrent source edits are supported.

Prepare:
- Require clean working tree (tracked and nonignored untracked); parse unique AppVersion.string and matching Info.plist CFBundleShortVersionString before writes. Reject malformed/mismatched current versions, shallow history, existing target tag, missing/empty Unreleased notes or an existing target changelog entry without changing files.
- patch: X.Y.Z -> X.Y.(Z+1); minor: X.(Y+1).0; major: (X+1).0.0.
- Update AppVersion.swift and tracked plist to new numeric version; put nonempty Unreleased notes under `## [VERSION] - YYYY-MM-DD` (local calendar date), retaining empty Unreleased header and all older entries. Print new version. No commit/tag/push/build from prepare; review/commit is explicit between stages.

Package:
- Require clean committed source, full history, matching source/plist version and dated changelog section. Version must be newer than all local stable vX.Y.Z tags, or the highest matching version tag must resolve exactly to HEAD. Reject stale versions or matching tags at another commit.
- Refuse existing versioned ZIP or checksum in output directory. Build in a temporary tracked-only full-history local clone checked out at captured HEAD, so ignored provider images and stale bundles are excluded. Set LIMITAUR_SIGN_IDENTITY=- and explicit --arch arm64; native SwiftPM build system is permitted. Do not install, launch app mode, alter source files, commit, tag, push or upload.
- Validate built AND extracted app: --version, bundle version, commit-count build number, full captured source revision without dirty, UTC ISO timestamp, arm64-only architecture, LSUIElement true, macOS minimum 26, exact LICENSE bytes, registered AppIcon.icns present, strict signature. For trusted freshly built ZIP, check sole top-level Limitaur.app and archive integrity.
- Produce `Limitaur-VERSION-macos-arm64.zip` plus `.zip.sha256` in standard lowercase SHA256, two spaces, relative ZIP filename, newline format. Digest covers whole ZIP. Preserve executable permissions. Verify extraction, signature/metadata and checksum before success; publish outputs only after verification. Print artifact paths. No overwrite or partial-success claims.

## Files
Implementer: scripts/release.py (new), README.md (release instructions), CHANGELOG.md (Unreleased About details and release helper notes).
Test-writer: Tests/ReleaseTooling/test_release.py (new), Tests/IconPackaging/test_bundle.py and Tests/AboutPackaging/test_bundle.py (replace only hardcoded version expectations with source-derived expectations).
Existing runtime/tests otherwise frozen. Test fixture repositories may be initialized and committed by tests for Git-history behavior; never commit implementation source copies or operator repo from helpers.

## Acceptance and traces
R1 Behavioral tests run CLI in temporary fixture repos: three increments, preserved notes/history, invalid/mismatched versions, missing notes, duplicate tag, dirty source and package preflight/tag failures. Baseline has no command, so successes fail as expected; report failures honestly. Avoid tests tied to source structure.
R2 A real package build from a root-created clean candidate commit passes all bundle/extracted metadata/signature checks, ZIP checksum, sole top-level directory and exclusion of ignored source material. Preparing this increment produces 0.2.3; final executable and assets agree with committed version.
R3 Run existing native suite (436 core +36 UI) and 69 offline checks, with source-derived version checks. Under constrained host AppKit needs ordinary macOS access: direct xcrun xctest on built UI bundle previously completed all 36. Verify actual summaries, not just exit 0.
R4 Review one cold candidate; at most one focused fix/verification. Keep operator tree unchanged until final tooling acceptance. Root can commit an isolated candidate to exercise packaging and preserve exact release artifact identity; helpers never commit source copies.

Success trace: clean repo with Unreleased notes -> prepare patch -> review/commit version edits -> package clones that commit -> verified 0.2.3 ZIP/checksum. Failure trace: dirty tree or version mismatch -> nonzero before edits/build; existing artifact -> refuse before build.

## Execution and publication
Terra implements, Sol writes tests before candidate disclosure, Astra cold reviews; all host agents/OpenAI. Operator accepted About separately. Root prepares an isolated reviewed release commit, assets, and release notes for final acceptance. Publishing still requires explicit current-turn push authorization. After authorization, integrate exact candidate commit, annotate v0.2.3, push commit/tag, upload draft release, download/check assets, publish and verify. No tag/asset overwrite.
