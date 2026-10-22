# Limitaur handoff

Updated 2026-10-22 (America/Los_Angeles). Discussion IDs continue from P354.

## Product state

Compact-bars source is accepted at `ab8b5e6` (P119, closed). At that commit 133 automated tests passed: 72 native Swift, 49 independent Python tests under Adversarial/, AdversarialClaude/ and AdversarialBars/, and 12 collector tests. The 49 independent tests are frozen; do not edit them to fit future code. New scope needs new tests.

Native app: Swift/AppKit, macOS 26+, no runtime dependencies, menu-bar only. See README.md for behaviour, commands and what is verified versus unverified.

## P73 versioning: done (2026-10-20, commits 9f42eb5 and 6116935)

The earlier release-platform design is retired and archived under `docs/archive/p73-release-platform/`. Do not resume it. The implemented scope, reviewed cold by gpt-6-astra and claude-opus-5-5 (see `docs/reviews/p73-version-review.md`), is:

- one version constant in `Sources/Limitaur/AppVersion.swift`, hand-edited, SemVer;
- `--version` prints it and exits before AppKit starts; About Limitaur… in Settings shows it;
- `scripts/build-app.sh` stamps that version, a git commit count and the HEAD revision into Info.plist, signs ad-hoc and writes a sha256 of the executable next to the bundle;
- `CHANGELOG.md` in keep-a-changelog form, no validator;
- native tests for the version string, early exit, the real executable's dispatch and the About callback.

Tests after P73: 79 native Swift, 49 frozen independent Python, 12 collector, all passing.

Dropped by decision: Python packaging tool, artifact identity manifest, tracked-source digest, changelog validator, build-tool plugin, blind AdversarialPackaging suite, sandbox harness for this increment. The 50 external AdversarialRelease tests target the retired design and stay outside the repository.

## Labelled bars (P323–P327, 2026-10-20)

Implemented per `docs/labelled-bars.md`, revised 2026-10-21 after live inspection: active layout is a bar with two-letter provider code and window code beside it; jar and logo-gauge layouts are retained in source by operator request, not default. Provider code table and confusability test: `docs/provider-codes.md`. Signing identity support for stable Keychain trust (P339). Static renders inspected at 1x and zoomed in both appearances. The operator ran the built bundle on 2026-10-20: both Codex and Claude fetched successfully from the app bundle, Claude via Keychain, so the app-bundle provider-access gate is informally cleared; the other gates remain.

## C2 credential re-check: four-eyes strict run, PAUSED at the Accept ask (2026-10-22 ~08:05Z)

Nothing is running. Nothing of this run is committed. The operator tree holds only the uncommitted specification `docs/proposals/credential-recheck.md` (revision 7, SHA256 in evidence `spec-r7-sha256.txt`). Do not stash, reset or delete it. Skill: `four-eyes` 0.6.4 (strict) with `review-panel` 0.4.1.

Evidence root `/Users/ivan/ws/limitaur-review/2026-10-21-credential-recheck/` (paths below relative to it): `go.txt` (operator words and times, including the third-round approval at 07:30Z), `design-review-record.md`, `design-{1,2,3}/dispositions*.md`, `change-review-{1,2,3,4}/dispositions-*.md`, `testwriter/invalid-tests.md`, `testwriter/dispositions-candidate-{3,4}.md`. Raw outputs: `*/stdout*.{json,txt}`, `*/stderr*.txt`.

State:
- Baseline: operator HEAD at Go `102296e` plus the spec, committed in the helper copies as `b946800`.
- Candidate 4 (final): `fixer3/candidate-4.diff` (SHA `fixer3/candidate-4-sha256.txt`), applies to the baseline and rebuilds byte-identically (`fixer3/verify4.txt`: 25 UI + 141 core tests three times, Python suites OK). Fix 3 session sonnet a959e535…, delta `fixer3/fix-3.diff`, report `fixer3/report.md`. Designer check `fixer3/designer-check-candidate3-monitor.txt`: all 9 new implementer tests fail on candidate 3's monitor, all 20 old ones pass.
- Frozen blind tests: `testwriter/frozen-2/` (5 files, hashes `frozen-2-sha256.txt`), NOT in the candidate diff; at Accept copy them into `Tests/LimitaurCoreTests/CredentialRecheck/`. Test-writer delivery 6 (`testwriter/stdout-6.txt`, codex gpt-6.1-sol 01a161b7…): all 42 pass, probes A–J pass, verdict merge.
- Change review 4 (`change-review-4/`): codex gpt-6-astra 01a16296… NOTHING OF SUBSTANCE; opus de3c0799… 4 minor findings P350–P353, all declined as residuals for this increment (dispositions-opus.md). No blocker, no major, no required fix.
- Helper copies `/tmp/limitaur-fe/{fixer3,verify4,check4,testwriter,...}` and the read-only checkout `/private/tmp/limitaur-review-checkout` may vanish; every diff is in evidence.

Accept ask: PUT TO THE OPERATOR, not yet answered. Recommendation: accept, with P350–P353 to `docs/backlog/credential-recheck-residuals.md`. On "accept": apply `fixer3/candidate-4.diff` to the operator tree (`git apply --binary`), copy `frozen-2/*.swift` into `Tests/LimitaurCoreTests/CredentialRecheck/`, run the full suite three times and the Python suites, write the backlog file and `docs/reviews/credential-recheck-review.md` with the four-eyes report block (sessions/costs from evidence), commit implementation + tests + spec + docs together (`feat: automatic credential re-check for paused accounts`), rebuild `dist` (script auto-signs with Limitaur Dev), ask the operator to relaunch and do M1, record M1 in README. Push only on the operator's word.

Sessions: design r1 codex 01a161a3…, opus 2c15f42f…; r2 codex 01a161a8…, opus b79126a5…; r3 codex 01a161ad…, opus 4086c418…; implementer sonnet a785c4cc…; fixer 1 sonnet 94893472…; fixer 2 sonnet ec8bdfb1…; fixer 3 sonnet a959e535…; change review 1 codex 01a161d3…, opus 6fdfe088…; 2 codex 01a161e4…, opus 96d12cf0…; 3 codex 01a16279…, opus e21855fe…; 4 codex 01a16296…, opus de3c0799…; test-writer codex 01a161b7… (six deliveries). Opus/sonnet share the designer's vendor; codex seats are the cross-vendor check.

## Still pending, in order

1. P339 signing identity: done 2026-10-22 (certificate "Limitaur Dev" in the login keychain, script auto-selects it; one orphaned keyless trust entry remains for the operator to delete or ignore).
2. P343/P347 credential re-check: approved and in the four-eyes run above.
3. Release gates: app-bundle provider access cleared informally by live use; default SwiftPM backend builds on the host (the recorded failure was sandbox-only); anchoring, click and both appearances exercised by daily use; keyboard, scrolling and accessibility tree unverified; sustained performance (60 s warm-up plus 600 s, both providers healthy, max RSS under 50 MiB, mean one-core CPU under 0.1%) not yet measured. Never grant OS access automatically.
4. API-metered and hybrid accounts: backlog, `docs/backlog/api-metered-accounts.md`; to be implemented on the operator's other machine.
5. Experimental jar and logo layouts: retained by operator request; delete after a period on the beside layout.
6. Cursor: deferred.

Remote: `origin` is `git@github.com:ivan-avramov/limitaur.git`, public, MIT, created 2026-10-21 and still empty. Push only on explicit instruction in that turn.
4. Known build warnings: two deprecated classic Keychain calls in `Credentials.swift` (SecKeychainGet/SetUserInteractionAllowed). Deliberate: they are the only way to guarantee no background prompt for the file-based login-keychain item Claude Code writes. Replacing them is a credential-boundary change needing strict four-eyes and empirical prompt verification; not planned (P330).

## Rules of the road

No push without explicit approval in the current turn. No install, login item, tag, release, credential copy or auth write. Claude is used as a normal CLI with its existing login. Evidence directories live under `/Users/ivan/ws/limitaur-review/`.
