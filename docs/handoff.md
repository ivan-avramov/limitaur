# Limitaur handoff

Updated 2026-10-20 (America/Los_Angeles). Discussion IDs continue from P350.

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

## C2 credential re-check: four-eyes strict run, PAUSED at a clean boundary (2026-10-22 ~08:30Z)

Nothing is running. Nothing of this run is committed. The operator tree holds only the uncommitted specification `docs/proposals/credential-recheck.md` (revision 7, SHA256 in evidence `spec-r7-sha256.txt`, copy `spec-r7.md`). Do not stash, reset or delete it. Skill: `four-eyes` 0.6.3 (strict) with `review-panel` 0.4.1; read both SKILL.md files and `briefs.md`/`runtimes.md` before acting.

Evidence root `/Users/ivan/ws/limitaur-review/2026-10-21-credential-recheck/` (all paths below relative to it): `go.txt` (operator words and times), `design-review-record.md`, `design-{1,2,3}/dispositions*.md`, `change-review-{1,2,3}/dispositions-*.md`, `testwriter/invalid-tests.md`, `testwriter/dispositions-candidate-3.md`. Raw outputs: `*/stdout*.{json,txt}`, `*/stderr*.txt` (model, session id, cost).

Operator approvals so far: Go ("go"); second fix round ("go for the second round"). A THIRD fix round is prepared but NOT approved: ask the operator first (recommendation below).

State:
- Baseline: operator HEAD at Go `102296e` plus the spec, committed in the helper copies as `b94680094a98bdb14e56577bae05a1575db7b94e`. Helper copies in `/tmp/limitaur-fe/{implementer,testwriter,fixer,fixer2,fixer3,verify3}` may vanish; every diff is in evidence.
- Candidate 3: `fixer2/candidate-3.diff` (SHA `fixer2/candidate-3-sha256.txt`), applies to the baseline; the designer verified 25 UI + 132 core tests three times and all frozen Python suites in `/tmp/limitaur-fe/verify3` (R10 satisfied for candidate 3). Includes spec r6, Monitor.swift, README, CHANGELOG, `Tests/LimitaurCoreTests/RecheckImplementerTests.swift` (20 tests).
- Frozen blind tests: `testwriter/frozen-2/` (5 files, hashes `frozen-2-sha256.txt`); NOT in the candidate diff; at Accept copy them into `Tests/LimitaurCoreTests/CredentialRecheck/` and commit with the rest. Test-writer: codex gpt-6.1-sol session `01a161b7-f24d-7c13-9b8b-d2273d66eb7e`, resumed from `/tmp/limitaur-fe/testwriter` with `codex exec --skip-git-repo-check --sandbox workspace-write -c model_reasoning_effort=high resume <id> < brief` (flags before `resume`). Its verdict on candidate 3 (`testwriter/stdout-5.txt`): all 42 pass, "fix then merge" for P39.
- Change review 3 (`change-review-3/`): codex 01a16279… (3 findings), opus e21855fe… (4 findings + gaps). All adopted into spec r7 and the fix-3 brief; none declined.
- Third fix round, PREPARED: copy `/tmp/limitaur-fe/fixer3` at commit `fc896a2…`+r7 (candidate 3 applied, spec r7, frozen tests read-only, reports under `review/`); brief `fixer3/brief.md` (six items: mismatch loop keeps serverRejected; monitor-wide epoch counter; completion follow-up limited to the entity with 10 s minimum success age; guard consults same-provider serverRejected memory; 401 marks by fingerprint across sources and the fallback never re-sends it; regression tests). Dispatch (fresh claude sonnet, from the copy): `claude -p --model sonnet --setting-sources "project,local" --strict-mcp-config --tools "Read,Edit,Write,Grep,Glob,Bash" --permission-mode acceptEdits --allowedTools "Bash(swift build:*),Bash(swift test:*),Bash(python3:*),Bash(for:*),Bash(LIMITAUR_BIN=*)" --output-format json < brief`.

Recommendation for the operator: run the third fix round. All six items are one-condition edits in loops the reviewers have read three times; the blind tests pass; each round's findings have been narrower and the last two rounds' items are all in the completion path and the rejection memory. Alternative: stop (outcome rejected, nothing committed). Counterpoint: round 3 still found a pre-existing epoch-reuse hazard, so a fourth review may find more; if it does, it comes back to the operator.

After the third fix round: (1) export candidate 4 (`git add` the five scoped paths in the copy, `git diff --cached --binary b946800`), verify on a clean baseline copy with `frozen-2` tests three times plus Python suites; (2) designer check: apply candidate 4's test file onto candidate 3's monitor in a scratch copy and record which of the new tests fail (they should); (3) test-writer delivery on candidate 4 (brief in the shape of `testwriter/brief-5.md`); (4) change review 4 (brief in the shape of `change-review-3/brief.md`) with codex gpt-6-astra and claude opus on a read-only checkout; (5) judge; any remaining required fix is again the operator's call; (6) Accept ask with the final diff and all dispositions; on "accept": apply the diff to the operator tree, copy `frozen-2/*.swift` into `Tests/LimitaurCoreTests/CredentialRecheck/`, run the full suite three times and the Python suites, commit implementation + tests + spec together (`feat: automatic credential re-check for paused accounts`), write `docs/reviews/credential-recheck-review.md` and the four-eyes report block (sessions/costs from evidence), rebuild `dist` (script auto-signs with Limitaur Dev), ask the operator to relaunch and do M1, record M1 in README; (7) push only on the operator's word.

Sessions: design r1 codex 01a161a3…, opus 2c15f42f…; r2 codex 01a161a8…, opus b79126a5…; r3 codex 01a161ad…, opus 4086c418…; implementer sonnet a785c4cc…; fixer 1 sonnet 94893472…; fixer 2 sonnet ec8bdfb1…; change review 1 codex 01a161d3…, opus 6fdfe088…; 2 codex 01a161e4…, opus 96d12cf0…; 3 codex 01a16279…, opus e21855fe…; test-writer codex 01a161b7… (five deliveries). Opus/sonnet share the designer's vendor; codex seats are the cross-vendor check.

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
