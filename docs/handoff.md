# Limitaur handoff

Updated 2026-10-23 (America/Los_Angeles). Discussion IDs continue from P382.

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

## C2 credential re-check: ACCEPTED and committed (2026-10-23, commit 5d977a3)

Four-eyes strict run complete; record `docs/reviews/credential-recheck-review.md`, residuals `docs/backlog/credential-recheck-residuals.md` (P350–P353, operator's call whether any becomes a requirement). Evidence root `/Users/ivan/ws/limitaur-review/2026-10-21-credential-recheck/`. Tests after the change: 25 UI + 141 core native (42 frozen blind under `Tests/LimitaurCoreTests/CredentialRecheck/`, never edit them; 29 implementer), 49 frozen independent Python, 12 collector, all passing three times in the operator tree at Accept.

Open: M1 (spec R-list) is the operator's manual gate: relaunch the rebuilt signed bundle, let the Claude token expire, run Claude Code, observe resume within about one interval plus one cycle with no dialog; then record the outcome in README (replace the "not yet observed live" clause). `dist/Limitaur.app` was rebuilt after the commit and is signed with "Limitaur Dev" (0.1.0, build 36, revision 5d977a3, sha256 beside it); codesign waited several minutes on a Keychain prompt before completing, so expect that prompt once per new signing process. Helper copies under `/tmp/limitaur-fe/` and `/private/tmp/limitaur-review-checkout` are disposable.

## C3 throttle-paced freshness: four-eyes light run, PAUSED at the second-fix-round ask (2026-10-23 ~08:10Z)

Nothing is running. Nothing of this run is committed except the 45 s cadence (92e3e68). The operator tree holds the uncommitted specification `docs/proposals/throttle-paced-freshness.md` (revision 4, SHA256 in evidence `spec-r4-sha256.txt`). Do not stash, reset or delete it. Operator words: "go for the light run" (P378), "implement autonomously if the review comes back good".

Evidence root `/Users/ivan/ws/limitaur-review/2026-10-23-throttle-freshness/`: `go.txt`, `design-1/` (codex 01a167a1…, opus 24113d63…, `dispositions.md`), `implementer/` (sonnet 6d0bab0d…, `candidate-1.diff`, `report.md`, `verify-candidate-1.txt`, `frozen-on-candidate-1.txt`), `testwriter/` (codex gpt-6.1-sol 01a167a7-dbf5-7233-baad-1051d00e9388, three deliveries; `frozen-2/` is the current frozen set of 40 tests, hashes `frozen-2-sha256.txt`; `invalid-tests.md`; `dispositions-candidate-2.md`), `fixer/` (sonnet 163f6d53…, `candidate-2.diff` = current candidate, `verify-candidate-2.txt`: 25 UI + 192 core three times, Python OK), `change-review-1/` (codex 01a167c9…, opus a7e7ba4c…, `dispositions-*.md`). Helper copies `/tmp/limitaur-fe2/{implementer,testwriter,fixer,verify}` and `/private/tmp/limitaur-review-checkout` are disposable.

State: candidate 2 passes everything; test-writer verdict "fix then merge" (P33 `stop()` does not clear `retention`; P34 README wording; P35 test helper unbounded wait); change review found three timing edges (repeat 429 completing after `held` during the in-flight hold does not re-latch; alternate-credential request inherits the hold; 46.5 s slack shorter than the real tick gap). All adopted into a proposed revision 5 (not yet written). The light-mode fix round is spent, so a second round is the operator's call (P381): recommended. On "go": write r5 (pre-completion "shown"; `alternateUsed == false` guard; slack 48.5 s via `cadenceTolerance` in Models.swift used by AppUI; `stop()` clears `retention`/`retryAfterUntil`; README), brief a fresh sonnet fixer from a copy at candidate 2 + r5, have the test-writer amend the boundary numbers and `secondThrottleAtRetentionEqualityCannotRevive` (resume its session; re-freeze), verify candidate 3 on a clean copy, test-writer delivery 4, change review 2, then apply, commit (`feat: keep throttled usage visible until the provider's Retry-After`), rebuild dist. On "accept as is": apply candidate 2, commit with the six items in `docs/backlog/`. Push only on the operator's word.

## Still pending, in order

1. P339 signing identity: done 2026-10-22 (certificate "Limitaur Dev" in the login keychain, script auto-selects it; one orphaned keyless trust entry remains for the operator to delete or ignore).
2. P343/P347 credential re-check: done (5d977a3); M1 live gate and dist rebuild pending, see above.
3. Release gates: app-bundle provider access cleared informally by live use; default SwiftPM backend builds on the host (the recorded failure was sandbox-only); anchoring, click and both appearances exercised by daily use; keyboard, scrolling and accessibility tree unverified; sustained performance (60 s warm-up plus 600 s, both providers healthy, max RSS under 50 MiB, mean one-core CPU under 0.1%) not yet measured. Never grant OS access automatically.
4. API-metered and hybrid accounts: backlog, `docs/backlog/api-metered-accounts.md`; to be implemented on the operator's other machine.
5. Experimental jar and logo layouts: retained by operator request; delete after a period on the beside layout.
6. Cursor: deferred.

Remote: `origin` is `git@github.com:ivan-avramov/limitaur.git`, public, MIT, created 2026-10-21 and still empty. Push only on explicit instruction in that turn.
4. Known build warnings: two deprecated classic Keychain calls in `Credentials.swift` (SecKeychainGet/SetUserInteractionAllowed). Deliberate: they are the only way to guarantee no background prompt for the file-based login-keychain item Claude Code writes. Replacing them is a credential-boundary change needing strict four-eyes and empirical prompt verification; not planned (P330).

## Rules of the road

No push without explicit approval in the current turn. No install, login item, tag, release, credential copy or auth write. Claude is used as a normal CLI with its existing login. Evidence directories live under `/Users/ivan/ws/limitaur-review/`.
