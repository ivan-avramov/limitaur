# Limitaur handoff

Updated 2026-10-20 (America/Los_Angeles). Discussion IDs continue from P348.

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

## C2 credential re-check: four-eyes strict run IN PROGRESS (2026-10-22)

Operator approvals: Go on 2026-10-22 03:46Z ("go"); second fix round approved ("go for the second round"). Nothing of this run is committed; the operator tree holds only the uncommitted specification `docs/proposals/credential-recheck.md` (revision 6, SHA256 `8c52da25…`, copy at evidence `spec-r6.md`). Do not stash or delete it.

Evidence root: `/Users/ivan/ws/limitaur-review/2026-10-21-credential-recheck/`. Read `go.txt`, `design-review-record.md`, the `design-*/dispositions*.md`, `change-review-*/dispositions-*.md`, `testwriter/invalid-tests.md`.

State at handoff:
- Baseline: operator HEAD `102296e` plus the spec committed in the helper copies as `b946800` (in `/tmp/limitaur-fe/{implementer,testwriter,fixer,fixer2}`; `/tmp` copies may vanish, the evidence directory has every diff).
- Candidate 3 (`fixer2/candidate-3.diff`, SHA256 in `fixer2/candidate-3-sha256.txt`) applies to the baseline and passes 25 UI + 132 core tests three times plus all frozen Python suites (verified by the designer in `/tmp/limitaur-fe/verify3`). It includes the spec r6, Monitor.swift, README, CHANGELOG and `Tests/LimitaurCoreTests/RecheckImplementerTests.swift`.
- Frozen blind tests: `testwriter/frozen-2/` (five files, hashes in `frozen-2-sha256.txt`; two assertions amended by the test-writer after being judged invalid, see `invalid-tests.md`). They are NOT in candidate-3.diff; at Accept, copy them into `Tests/LimitaurCoreTests/CredentialRecheck/` and commit with the rest.
- Test-writer: codex gpt-6.1-sol, session `01a161b7-f24d-7c13-9b8b-d2273d66eb7e`, resumed with `codex exec --skip-git-repo-check --sandbox workspace-write -c model_reasoning_effort=high resume <id> < brief` from `/tmp/limitaur-fe/testwriter`. Its delivery on candidate 3 (brief `testwriter/brief-5.md`) was running at handoff; result goes to `testwriter/stdout-5.txt` / `exit-5.txt`. Its verdict on candidate 2 was "fix then merge" (P31), which candidate 3 addresses.
- Change review 3: checkout staged read-only at `/tmp/limitaur-review-checkout` (candidate 3 + frozen tests + prior reports under `review/`); brief not yet written; evidence dirs `change-review-3/{codex,opus}` exist. Members: codex gpt-6-astra and claude opus, as in `change-review-2/brief.md` (reuse its shape; add the test-writer's candidate-3 report).

Remaining steps: (1) read the test-writer's candidate-3 verdict; (2) write `change-review-3/brief.md` and dispatch both members; (3) judge; if any required fix remains, that is a THIRD fix round and needs the operator's explicit call; (4) Accept ask: show the final diff and all dispositions; on "accept", apply `candidate-3.diff` to the operator tree, copy `frozen-2/*.swift` into `Tests/LimitaurCoreTests/CredentialRecheck/`, run the full suite three times and the Python suites, commit implementation + tests + spec together (`feat: automatic credential re-check for paused accounts`), write `docs/reviews/credential-recheck-review.md` and the four-eyes report block (skill `four-eyes` 0.6.3; sessions and costs are in the evidence `stdout*.json`/`stderr*.txt`); (5) rebuild `dist` (signed Limitaur Dev), operator relaunches, M1 manual check, README records M1's outcome; (6) push only on the operator's word.

Sessions so far: design review r1 codex 01a161a3…, opus 2c15f42f…; r2 codex 01a161a8…, opus b79126a5…; r3 codex 01a161ad…, opus 4086c418…; implementer sonnet a785c4cc…; fixer 1 sonnet 94893472…; fixer 2 sonnet ec8bdfb1…; change review 1 codex 01a161d3…, opus 6fdfe088…; change review 2 codex 01a161e4…, opus 96d12cf0….

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
