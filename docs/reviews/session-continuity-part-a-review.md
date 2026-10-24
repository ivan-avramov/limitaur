# Session continuity, Part A (P399–P450): four-eyes record

2026-10-24. Specification `docs/proposals/session-continuity.md`, revision 8 (Part A implemented; Parts B and C pending their own runs under the same specification). Evidence root `/Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/` (briefs, raw outputs, dispositions per round, candidate diffs with hashes, frozen-suite hashes and reveal times, `go.txt`). Skill `four-eyes` 0.6.6 strict with `review-panel` 0.4.1.

## Course of the run

Problem: the 2026-10-23 live M1 gate failed because Claude Code's token refresh rewrites the Keychain item through `/usr/bin/security add-generic-password -U`, which removed the app's standing access; the in-process `SecItemCopyMatching` read was denied from then on. Reference reads: openusage and mac-ai-trackers both read the item through a child `/usr/bin/security` process. Part A adopts that read path with a bounded, non-prompting background policy, an app-gated reactive re-read after 401/403/429, provenance for Part C, and an operator-run probe.

Design review, strict, three rounds (the ceiling): codex gpt-6-astra and claude-opus-5-5 each round; 112 findings in total; revisions 2, 3 and 4 applied them; revision 4 not re-reviewed; the operator's question on transcripts led to the verified `--safe-mode` and `--no-session-persistence` nudge flags (Part C). Go 2026-10-24T03:59:11Z ("p423: accepted" / "p424: go"), all open questions as recommended.

Implementer claude-sonnet-5-5 from the specification alone (candidate A). Blind test-writer codex gpt-6.1-sol wrote 48 tests from the specification and the baseline, frozen 04:13:24Z before any candidate was revealed; its first delivery predicted a real specification defect (timeout classified after a nil exit code), fixed in revision 5. Candidate A failed to compile with the frozen suite present only because both authors chose the `SC` helper prefix; fix round 1 renamed the implementer's helpers and applied revision 5. Candidates A2–A5 followed the test-writer's second to fifth deliveries and four change reviews (codex gpt-6-astra, claude-opus-5-5 each): review 1 adopted suspension-on-deny, reader-level suspension clearing on Connect completion, busy as a no-op, runner lifecycle hardening (revision 6); review 2 adopted the busy retry, deferred suspension while Connect is queued, the timeout probe, and probe-script checks (revision 7; second fix round operator-approved, "go for the fix round"); review 3 adopted the same-pass re-check collision fix, stale-retry consumption, the gated busy branch and the probe-error contract (revision 8; third fix round operator-approved, "go for third round"); review 4 found nothing of substance beyond two residuals. Frozen tests judged invalid and amended by their author: one case for revision 5, three for revision 6, one authorised addition; every amendment re-frozen with hashes before the next candidate was revealed.

Verification at Accept in the operator tree: see `accept-verify-operator-tree-a.txt` in the evidence root (three native runs, release build, the 49 frozen Python tests against the release binary, 12 collector tests). Residuals: `docs/backlog/session-continuity-part-a-residuals.md`. Budgets exceeded after the fix rounds (ProcessRunner 173/140, Monitor +59/50, LimitaurMain +17/15, probe 106/80, implementer tests 680/190); waived by the operator at Accept.

Live gates pending the operator: probe script A10 once, relaunch of the rebuilt signed bundle, L1 over the next token refresh.

## Report block

```
[four-eyes 0.6.6] outcome: completed (Part A); mode: strict (credential boundary, child processes)
designer: claude code: claude-fable-5-1, session_01KC2WZVgaYEgpQFQB5gmgd8
design review: codex: gpt-6-astra, 01a16bd3…, 01a16be1…, 01a16bee…, checkout (user instructions loaded), returned ×3; claude: claude-opus-5-5, 767e5696…, a3026304…, dc376f68…, checkout (+web rounds 1–2), returned ×3; rounds 3; same model as designer: none; same vendor: opus
implementer: claude: claude-sonnet-5-5, 8820d5f5…; fixes: 36f424a4… (A2), b9179d17… (A3), a11947f4… (A4), 663eeaf1… (A5)
test-writer: codex: gpt-6.1-sol, 01a16c11-3b07-7e42-b5b6-d58fb0224a09; second delivery continued (five deliveries, one session); same model as designer | implementer: no | no; tests frozen 2026-10-24T04:13:24Z (re-frozen 04:36:31Z, 05:05Z, 05:39Z after authorised amendments), candidates revealed 04:25Z (A2), 04:55Z (A3), 05:39Z (A4), 16:04Z (A5); candidate A was never revealed to the test-writer
change review: codex: gpt-6-astra, 01a16c32…, 01a16c4d…, 01a16c80…, 01a16ec8…, checkout (user instructions loaded), returned ×4; claude: claude-opus-5-5, 87e399ac…, f696ec94…, 62fd9a02…, 17f6c2c0…, checkout, returned ×4; same model as implementer: none; same vendor: opus
not covered: errors Anthropic models make consistently are checked only by the codex seats; errors the designer's own model makes are not checked by any member of its own model
go: 2026-10-24T03:59:11Z, "p423: accepted" / "p424: go"; second fix round: "go for the fix round"; third fix round: "go for third round"; accept: 2026-10-24, "accept"; commit: see git log (feat: read the Claude Keychain item through security …); push: none
cost, as reported: opus design $0.93, $2.26, $2.33; opus change reviews $1.80, $1.77, $1.49, $0.60; implementer $1.33; fixes $0.18, $1.15, $0.92, $0.59; codex sessions unreported
```
