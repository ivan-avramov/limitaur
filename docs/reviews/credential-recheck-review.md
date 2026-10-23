# Credential re-check (P343/P347): four-eyes record

2026-10-21 to 2026-10-22. Specification `docs/proposals/credential-recheck.md`, revision 7. Evidence root `/Users/ivan/ws/limitaur-review/2026-10-21-credential-recheck/` (briefs, raw outputs, dispositions, diffs, hashes, `go.txt` with the operator's words and times). Skill `four-eyes` 0.6.4 strict (credential boundary) with `review-panel` 0.4.1.

## Course of the run

Design review, converge, three rounds (strict ceiling): codex gpt-6-astra and claude-opus-5-5, fresh sessions each round, read-only checkout. Round 3 still changed acceptance criteria, so convergence by the unchanged-criteria rule is not claimed; revision 4 went to Go marked not re-reviewed. Round 3 rolled back two round-2 additions (throttle-provenance flag, wake replay of in-flight re-checks). Declined: a next-due display field (scope, not needed by the goal); dropping the cadence counters (they are the oracles for R1–R4). Record: `design-review-record.md`.

Go: 2026-10-22T03:46Z, "go". Baseline `102296e` plus the spec, `b946800` in the helper copies.

Implementation: claude-sonnet-5-5, fresh session, from the specification alone. Blind tests: codex gpt-6.1-sol wrote 42 tests in five files from the specification and the baseline, frozen 04:06Z before the candidate was revealed; two assertions judged invalid against the specification (`testwriter/invalid-tests.md`) were amended by the test-writer only and re-frozen 04:24Z. The five frozen files are committed unchanged under `Tests/LimitaurCoreTests/CredentialRecheck/`.

Four candidates. Each went to the test-writer's continued session and to a change review (codex gpt-6-astra, claude-opus-5-5, read-only checkout, sensitive hunks named). Every finding of rounds 1–3 was adopted or adapted into specification revisions 5, 6 and 7 and fixed by a fresh sonnet session; no finding of those rounds was declined. Fix rounds 2 and 3 were approved by the operator in words ("go for the second round"; "Go for the 3rd round of fixes"). Each fix round's new implementer tests were run by the designer against the previous candidate's monitor; in round 3, 9 of 9 failed there and all 20 earlier ones passed.

Candidate 4: test-writer verdict merge, 42 frozen and 29 implementer tests pass, probes A–J pass. Change review 4: codex NOTHING OF SUBSTANCE after reading the full material; opus four minor findings, verified in code, declined for this increment as residuals and recorded in `docs/backlog/credential-recheck-residuals.md` (P350–P353). Accepted 2026-10-23T03:03Z, "p354: accept".

Verification at Accept in the operator tree: release build, 25 UI + 141 core native tests three times, the 49 frozen independent Python tests and 12 collector tests, all passing (`accept-verify-operator-tree.txt`). Line budget: the fix-3 delta was 39 lines in the monitor; the whole change is 368 lines in `Monitor.swift` against the baseline.

Not verified here: M1 (live automatic resume on the operator's machine with the signed build) is the operator's manual gate and is recorded in README when done.

## Report block

```
[four-eyes 0.6.4] outcome: completed; mode: strict (credential boundary, Keychain interaction policy)
designer: claude code: claude-fable-5-1, session_015vrMp1ckiEtnyexp9KvYR7 (and the preceding session that ran design review through fix round 2)
design review: codex: gpt-6-astra, 01a161a3…, 01a161a8…, 01a161ad…, checkout (user instructions loaded), returned; claude: claude-opus-5-5, 2c15f42f…, b79126a5…, 4086c418…, checkout, returned; rounds 3; same model as designer: none; same vendor: opus
implementer: claude: claude-sonnet-5-5, a785c4cc…; fixes: 94893472…, ec8bdfb1…, a959e535…
test-writer: codex: gpt-6.1-sol, 01a161b7…; second delivery continued (six deliveries, one session); same model as designer | implementer: no | no; tests frozen 2026-10-22T04:06:11Z (re-frozen 04:24:33Z after the two amendments), candidate revealed 04:06:20Z (candidates 2–4: 04:27:28Z, 07:08:58Z, 07:41:24Z)
change review: codex: gpt-6-astra, 01a161d3…, 01a161e4…, 01a16279…, 01a16296…, checkout (user instructions loaded), returned; claude: claude-opus-5-5, 6fdfe088…, 96d12cf0…, e21855fe…, de3c0799…, checkout, returned; same model as implementer: none; same vendor: opus
not covered: errors Anthropic models make consistently are checked only by the codex seats (design review, test-writer, change review); errors the designer's own model makes are not checked by any member of its own model.
go: 2026-10-22T03:46:35Z, "go"; accept: 2026-10-23T03:03:10Z, "p354: accept"; commit: see git log (feat: automatic credential re-check for paused accounts); push: none
cost, as reported: opus design $1.06, $0.82, $1.32; opus change review $1.19, $1.32, $1.10, $1.18; implementer $0.94; fixes $0.48, $1.00, $0.87; codex sessions unreported (tokens only)
```
