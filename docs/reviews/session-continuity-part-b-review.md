# Session continuity, Part B (P454–P475): four-eyes record

2026-10-24. Specification `docs/proposals/session-continuity.md`, revision 10 (Part B implemented; Part C pending). Evidence root `/Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/` (implementer-b, fixer-b2…b5, testwriter/*-b*, change-review-b…b5, `go.txt`). Skill `four-eyes` 0.6.6 strict with `review-panel` 0.4.1; design review and Go shared with Part A (standing Go of 03:59:11Z for all three parts).

## Course of the run

Problem: the Claude usage endpoint throttles polls with 429 and a Retry-After at a rate that is not published; the operator wants the tightest polling that avoids it, learned rather than fixed, that never hunts: +10 s or the Retry-After on a 429 not attributed to a superseded token, −10 s only after 24 h and five consecutive clean polls, revert and a 7-day block if a 429 follows a reduction within an hour, bounds 30–120 s, persisted.

Implementer claude-sonnet-5-5 from the specification alone (candidate B). Blind test-writer codex gpt-6.1-sol (the Part A session continued) first refused correctly when its copy had not received the new baseline, then wrote 49 tests (100 cases) frozen 17:18:37Z before candidate B was revealed; a single mechanical compile error (mutating a closure parameter, 19 sites) was amended by its author under the designer's judgement and re-frozen. Candidates B2–B5 followed four change reviews (codex gpt-6-astra and claude-opus-5-5 each) and four operator-approved fix rounds ("go for the fix round" was the standing first round; "go for second fix round", "p472: approved for the 3rd fix round", "go for 4th fix round"). Review 1 (revision 9): the ranking-age shift keeps its literal 90 (a specification defect), per-entity and per-receipt throttle settlement with a monotonic fallback, persistence against stored bytes, dropdown wiring, `package` helpers. Review 2 (revision 10): the revert formula never below the current interval (a specification defect found by codex), replacement-time receipt hold, same-token rebinds always record, last-classifier recording, test timing. Review 3: settle-on-accept, held receipts block reductions, mismatch-path classifier. Review 4: receipt identity across relocations, a discriminating mismatch test. Review 5: nothing of substance from both members; test-writer verdict merge. One tests-only follow-up session added tests the second fix round had omitted. Flakiness: three timing-sensitive implementer tests failed once each under a machine load average above 40 and pass in isolation and at normal load (residual R-B1).

Verification at Accept in the operator tree: see `accept-verify-operator-tree-b.txt` in the evidence root. Residuals: `docs/backlog/session-continuity-part-b-residuals.md`. Budgets exceeded after four fix rounds (Monitor +115/70, Polling 107/60, implementer tests 596/130); waived by the operator at Accept.

Live gates pending the operator: L2 (interval persists across relaunch; reductions at least 24 h apart; on two machines) and L4 (resource smoke with the 10 s tick).

## Report block

```
[four-eyes 0.6.6] outcome: completed (Part B); mode: strict (shared run with Part A; scheduling and persistence)
designer: claude code: claude-fable-5-1, session_01KC2WZVgaYEgpQFQB5gmgd8
design review: shared with Part A (three rounds, codex gpt-6-astra and claude-opus-5-5)
implementer: claude: claude-sonnet-5-5, d53aa5bd…; fixes: 0b4254f0… (B2), 33568f75… + 90c1f4a1… tests-only (B3), e64dda6a… (B4), 96ece5e8… (B5)
test-writer: codex: gpt-6.1-sol, 01a16c11-3b07-7e42-b5b6-d58fb0224a09; continued from Part A (six Part B deliveries); same model as designer | implementer: no | no; tests frozen 2026-10-24T17:18:37Z (re-frozen after the compile amendment before B2), candidates revealed 17:20Z (B), 17:52Z (B2), 18:25Z (B3), 19:36Z (B4), 20:18Z (B5)
change review: codex: gpt-6-astra, 01a16efe…, 01a16f19…, 01a16f37…, 01a16f85…, 01a16f99…, checkout (user instructions loaded), returned ×5; claude: claude-opus-5-5, af527fff…, b96043a5…, 9fd13e1a…, 1047c1a6…, 19998937…, checkout, returned ×5; same model as implementer: none; same vendor: opus
not covered: errors Anthropic models make consistently are checked only by the codex seats; errors the designer's own model makes are not checked by any member of its own model
go: 2026-10-24T03:59:11Z (standing, all parts); fix rounds: "go for the fix round" (Part A precedent for round 1), "go for second fix round", "p472: approved for the 3rd fix round", "go for 4th fix round"; accept: 2026-10-24, "accept: proceed" (budgets waived); commit: see git log (feat: learn the polling interval …); push: none
cost, as reported: opus change reviews $1.42, $1.03, $0.59, $0.94, $0.42; implementer $1.70; fixes $1.03, $0.42, $0.79, $0.65, $0.70; codex sessions unreported
```
