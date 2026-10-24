# Limitaur handoff

Updated 2026-10-24 ~20:40Z (13:40 America/Los_Angeles). Discussion IDs continue from P480.

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

## C3 throttle-paced freshness: ACCEPTED and committed (2026-10-23, commit 8c3056a)

Light four-eyes run complete (record `docs/reviews/throttle-paced-freshness-review.md`; residuals P383–P386 in `docs/backlog/throttle-paced-freshness-residuals.md`, operator's call whether any becomes a requirement). Cause: the Claude usage endpoint answers polls with 429 and a Retry-After about 100 s after the last success. Shipped: cadence 45 s (92e3e68) and, while an entity holds a parsed Retry-After, its last snapshot stays ranked until the deadline plus 48.5 s, cap 300 s after the fetch (8c3056a). Tests after the change: 25 UI + 198 core native (43 frozen blind under `Tests/LimitaurCoreTests/ThrottleFreshness/`, never edit them; 14 implementer), 49 frozen independent Python, 12 collector, all passing three times in the operator tree at Accept. Evidence root `/Users/ivan/ws/limitaur-review/2026-10-23-throttle-freshness/`. Helper copies `/tmp/limitaur-fe2/` and `/private/tmp/limitaur-review-checkout` are disposable.

`dist/Limitaur.app` (0.1.0, build 40, revision 8c3056a, signed "Limitaur Dev") is running on the operator's machine since 2026-10-23 ~16:40Z; on this launch the operator chose Always Allow on the two Keychain dialogs (the item's data entry and its wrapping key; two prompts per new signing identity, none afterwards), so Claude is bound and the non-interactive re-check can pass.

Open items after this section are superseded by the C4 section below.

## C4 release-gate measurement and M1 attempt (2026-10-23 evening, P392–P398)

What ran. `dist/Limitaur.app` build 41 (0.1.0, revision 8024a83, source-identical to 8c3056a, signed `Limitaur Dev`) was stopped and relaunched at 17:41 local with `--stats`, so provider outcome counts and the eligibility block are recorded. It is still running as PID 19894 with that flag; the stats file, a 15-second timeline of it (`stats-timeline.log`, sampler runs until about 20:41 local or until the process exits) and the measurement result live in `/Users/ivan/ws/limitaur-review/2026-10-23-release-gates/`. No preferences file exists, so indicator count was the default 3 and the two default accounts were configured.

Resource gate (P393). 60 s warmup plus 600 s: CPU 0.00063 % of one core (met), max RSS 51.42 MiB, median 50.94 MiB (budget 50 MiB, not met by about 1 MiB of flat baseline), no descendants. Nonqualifying because three Claude 429s and the token expiry fell inside the window, and because 45 s polling cannot reach A7's 18 successes in 600 s. Recorded in docs/performance.md; the A7 drift is backlog P398.

Throttle observation (P394, follow-up to P390). Eight clean Claude polls at 45 s, then three consecutive 429s at about 00:47:42Z, 00:48:32Z and 00:50:02Z; no further Claude requests after that because the account paused at the token expiry. Three consecutive 429s is the P383 scenario (backoff 60 s then 120 s against a shorter Retry-After); whether the bar blinked is unobserved. The 429s began 36 s after Claude Code rewrote the Keychain item (00:47:06Z), which may be coincidence or an old-token effect; one data point only.

M1 attempt (P395). Sequence from the counters: token bound at launch with expiry 00:52:06Z; Claude Code refreshed the Keychain item at 00:47:06Z (item `mdat`, metadata only); Limitaur paused the account at the expiry (credentialExpiries 1) and re-checked without interaction at about 00:52Z, 00:57Z and 01:03Z (credentialRechecks 3, credentialResumes 0); a `claude -p` run at 00:58:32Z answered in 3 s and did not modify the item again. `--check-live` from the same bundle reported Claude unavailable and Codex success at 01:03:46Z. So the app loaded the item at 00:41Z and cannot load it since the rewrite. The two candidate causes are an access list that no longer includes the app, or item contents the decoder rejects; the auto-mode permission classifier blocked both an ACL dump of that item and a read of Credentials.swift, so the discrimination is the operator's. README's M1 clause now records this outcome.

Open, in order, for the operator:
1. Resolved 2026-10-23 19:14 local (P399): the Claude row showed "Keychain access unavailable; choose Connect / Authorize", the denied wording, last fetch 5213 s old. So the token rewrite revoked the app's non-interactive access although Always Allow had been granted that day. Next experiment: Connect / Authorize now (expect prompts; choose Always Allow), confirm the row turns healthy, then wait for the next Claude Code token refresh (the item's `mdat` changes; the timeline log shows the pause) and see whether access is lost again. Per-refresh loss makes Keychain-source automatic resume a design round (P401); a one-off loss is a note.
2. Throttle observation continues with the running instance; the timeline log shows counts per 15 s. If a blink is seen, P383 is the candidate fix.
3. Decisions when raised: RSS budget (P393: revise to 56 MiB or investigate footprint), A7 cadence drift (P398), P339 orphan certificate (P396, one command), test-litter plists (P397), earlier backlogs P350–P353 and P383–P386.
4. Release gates otherwise unchanged: keyboard, scrolling and accessibility tree unverified.

## C5 session continuity, Part A: ACCEPTED (2026-10-24, strict four-eyes)

Record `docs/reviews/session-continuity-part-a-review.md`; specification `docs/proposals/session-continuity.md` revision 8 (three parts; A accepted, B and C pending); residuals `docs/backlog/session-continuity-part-a-residuals.md`; evidence root `/Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/`. Cause and fix: Claude Code's token refresh rewrites the Keychain item through `security add-generic-password -U`, which revoked the app's in-process access (C4); Part A reads the item through a child `/usr/bin/security` process (as openusage and mac-ai-trackers do), with a 5 s non-interactive bound, per-launch suspension of a source after a timeout or a Deny, suspension cleared only by a Connect that finds the item or finds it absent, an app-gated reactive re-read after 401/403/429, the `--read-keychain-service` diagnostic, and the operator-run probe `scripts/keychain-acl-probe.sh`. Tests after Accept: 25 UI + 277 core native (48 frozen blind under `Tests/LimitaurCoreTests/SessionContinuity/`, never edit them; the earlier 42 + 43 frozen suites unchanged), 49 frozen Python, 12 collector; see `accept-verify-operator-tree-a.txt` in the evidence root. Helper copies under `/tmp/limitaur-sc/` and `/private/tmp/limitaur-review-checkout*` are disposable.

Open, in order:
1. Operator live steps for Part A: build and sign the bundle (`scripts/build-app.sh`, one codesign prompt); run `scripts/keychain-acl-probe.sh` once (it creates and deletes scratch items in the login keychain and includes one deliberate denied case; type the dialog answer it asks for; record the output in README's authentication paragraph); relaunch `dist/Limitaur.app`; L1: over the next Claude Code token refresh (item `mdat` changes), the new token is bound within 30 s plus one tick of the first failing poll, or within one tick plus five minutes of the old expiry, with no denied wording and `keychainSuspensions` 0; record the outcome in README.
2. Part B (learned polling interval) and Part C (expiry nudge) of the same specification, each its own implementer/test-writer/change-review cycle under the standing Go (go.txt), with the frozen test-writer session continued if it can be resumed (codex session 01a16c11-3b07-7e42-b5b6-d58fb0224a09). Change-review 2 of Part A recorded for Part C's brief: termination cannot be cancelled after `stop()`.
3. P408 (unhealthy-provider bar marker), separate light run; residual backlogs P350–P353, P383–P386, P396–P398, R-A1–R-A6 on the operator's call.

## C6 session continuity, Part B: ACCEPTED (2026-10-24 20:40Z, strict four-eyes); Part A live; Part C next

Part B (learned polling interval) accepted and committed (see git log, "feat: learn the polling interval …"); record `docs/reviews/session-continuity-part-b-review.md`, residuals `docs/backlog/session-continuity-part-b-residuals.md`, specification revision 10. Tests after Accept: 25 UI + 352 core native (frozen blind suites under `Tests/LimitaurCoreTests/SessionContinuity/` (48) and `SessionContinuityB/` (49), never edit them; earlier 42 + 43 unchanged), 49 frozen Python, 12 collector, three times in the operator tree (`accept-verify-operator-tree-b.txt`).

Part A live: build 48 (revision 6619311) running since 18:01Z with `--stats /Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/live/stats.json`; first poll read the real Keychain item through `security` with no dialog, both providers healthy. Probe run recorded in README (steps 0–4 and 6 passed; step 5 exposed the exit-code normalisation fixed in 45b66e1; the step-6 dialog stayed until answered, so A-3 is false and the per-launch suspension is the bound). L1 (bind within 30 s plus one tick of the first failing poll after the next Claude Code token refresh, no denied wording, `keychainSuspensions` 0) not yet observed: read `live/stats-timeline.log` (change-driven samples) for `credentialRotations`/`credentialResumes`. The build 48 bundle does not yet contain Part B.

Open, in order, for the next session:
1. Read `live/stats-timeline.log`: has a token refresh happened (`credentialRotations` or `credentialResumes` incremented, `keychainSuspensions` 0, no denied wording)? Record L1 in README.
2. Rebuild and sign (`sh scripts/build-app.sh`), relaunch with `--stats`, and start the Part B live gates: L2 (interval and blocks persist across relaunch; reductions at least 24 h apart; ideally on two machines) and L4 (resource smoke with the 10 s tick, `scripts/measure-resources.py`).
3. Part C (expiry nudge, specification Part C, revision 10) under the standing Go (go.txt): implementer claude-sonnet-5-5 in a fresh copy at the new HEAD; blind test-writer codex session 01a16c11-3b07-7e42-b5b6-d58fb0224a09 continued (its copy `/tmp/limitaur-sc/tests` must be fetched and checked out at the new HEAD first, and the Part B directory there removed since it is now tracked); change review codex gpt-6-astra + claude-opus-5-5; fix rounds need the operator's approval after the first. Carry into the Part C brief: termination cannot be cancelled after `stop()` (change-review 2 of Part A); the nudge child is unregistered and not killed at quit; the verified flags `--safe-mode --no-session-persistence --strict-mcp-config --tools ""`.
4. Then P408 (unhealthy-provider bar marker), light run; backlogs on the operator's call.

Helper copies under `/tmp/limitaur-sc/` and `/private/tmp/limitaur-review-checkout*` are disposable. Specification file `docs/proposals/session-continuity.md` is committed at revision 10.

## Still pending, in order

1. P339 signing identity: done 2026-10-22 (certificate "Limitaur Dev" in the login keychain, script auto-selects it; one orphaned keyless trust entry remains for the operator to delete or ignore).
2. P343/P347 credential re-check: done (5d977a3); throttle-paced freshness done (8c3056a); relaunch and M1 live gate pending, see above.
3. Release gates: app-bundle provider access cleared informally by live use; default SwiftPM backend builds on the host (the recorded failure was sandbox-only); anchoring, click and both appearances exercised by daily use; keyboard, scrolling and accessibility tree unverified; sustained performance (60 s warm-up plus 600 s, both providers healthy, max RSS under 50 MiB, mean one-core CPU under 0.1%) not yet measured. Never grant OS access automatically.
4. API-metered and hybrid accounts: backlog, `docs/backlog/api-metered-accounts.md`; to be implemented on the operator's other machine.
5. Experimental jar and logo layouts: retained by operator request; delete after a period on the beside layout.
6. Cursor: deferred.

Remote: `origin` is `git@github.com:ivan-avramov/limitaur.git`, public, MIT, created 2026-10-21 and still empty. Push only on explicit instruction in that turn.
4. Known build warnings: two deprecated classic Keychain calls in `Credentials.swift` (SecKeychainGet/SetUserInteractionAllowed). Deliberate: they are the only way to guarantee no background prompt for the file-based login-keychain item Claude Code writes. Replacing them is a credential-boundary change needing strict four-eyes and empirical prompt verification; not planned (P330).

## Rules of the road

No push without explicit approval in the current turn. No install, login item, tag, release, credential copy or auth write. Claude is used as a normal CLI with its existing login. Evidence directories live under `/Users/ivan/ws/limitaur-review/`.
