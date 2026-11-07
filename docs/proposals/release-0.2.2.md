# Release 0.2.2

Problem: publish the approved icon update as Limitaur 0.2.2 with a downloadable macOS app ZIP and a checksum of that complete ZIP.

- User authorized “yes, build and publish” on 2026-11-07. Baseline af5bf01. Routine light release using existing packaging; budget 60 changed source/test/documentation lines, excluding release notes, artifacts and review record.
- Set AppVersion.string and tracked Info.plist to 0.2.2; move icon notes under dated 0.2.2 changelog entry and summarize documentation consolidation. Refresh current README/handoff wording without rewriting historical records.
- Test-writer alone updates the two existing icon-check expected-version literals to 0.2.2. Preserve all other tests; preregister existing-suite and artifact checks rather than add duplicate tests.
- Native 35 UI + 436 core, existing Python 62 and icon checks 4 must pass on candidate. No app-mode launch, account read, provider request, install or authentication change.
- Root commits reviewed changes, then builds from a fresh tracked-only full-history checkout of that exact clean commit with LIMITAUR_SIGN_IDENTITY=-. No ignored provider images, credentials, stale bundle files or personal data in published bundle. Existing runtime and menu-bar behavior unchanged.
- Artifact target: Apple silicon arm64, macOS 26+. Verify lipo, bundle version/build/source revision, registered icon, LSUIElement, strict signature, ZIP contents and permissions after extraction. Label ad-hoc signed and not notarized; do not claim Intel or universal support.
- Assets: Limitaur-0.2.2-macos-arm64.zip containing only Limitaur.app, and matching .zip.sha256 using standard shasum format with relative filename; digest covers entire ZIP. Dist stays ignored. Refresh standard local dist/Limitaur.app and its timestamp after successful build.
- Root creates annotated v0.2.2 at release commit and ordinary atomic push of main and that tag. Stage GitHub release as draft with exact notes and two assets; download both, compare checksums and extract/verify bundle before publishing. Re-fetch published metadata/asset checksums and verify tag points to expected commit.
- No overwriting an existing release/tag/assets, force-push, automatic update system, installed-app replacement or new packaging framework. Missing/mismatched asset, architecture, signature, version or source identity stops publication.
- Acceptance: reviewed small release diff, tests pass, clean source identity, full-ZIP integrity verified after GitHub download, published non-draft release with correct tag and two downloadable assets. Keep signing and platform limitations explicit in release notes.
