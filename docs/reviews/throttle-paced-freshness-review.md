# Throttle-paced freshness (P377–P386): four-eyes record

2026-10-23. Specification `docs/proposals/throttle-paced-freshness.md`, revision 5. Evidence root `/Users/ivan/ws/limitaur-review/2026-10-23-throttle-freshness/` (briefs, raw outputs, dispositions, diffs, hashes, `go.txt`). Skill `four-eyes` 0.6.4 light with `review-panel` 0.4.1. Preceded by the 45 s cadence change (92e3e68, no review: a single constant).

## Course of the run

Problem: the Claude usage endpoint answers polls with HTTP 429 and a Retry-After about 100 s after the last success; the bar dropped any snapshot older than 90 s, so Claude vanished for minutes at a time. Reference read: mac-ai-trackers polls every 180 s by default and keeps last-known values until a metric's own reset; neither rule was copied.

Design review, one round: codex gpt-6-astra (7 findings) and claude-opus-5-5 (3 blockers, 4 major, 5 minor). All adopted into revision 2; one suggestion declined (limit the rule to the Claude provider). Revisions 2–5 were not re-reviewed by the design panel (light mode). Go was pre-authorised ("implement autonomously if the review comes back good").

Implementer claude-sonnet-5-5 from the specification alone (candidate 1). Blind test-writer codex gpt-6.1-sol wrote 40 tests from the specification and the baseline, frozen before any candidate was revealed; its first delivery also found two specification defects (a short Retry-After case contradicting the latch, and the in-flight clause allowing resurrection), both resolved in revision 4 before the candidate was revealed. The designer ran the frozen tests against candidate 1 (four failures: the predicted resurrection, the short-Retry-After rule, and two assertions judged invalid and amended by their author) and ran one fix round (candidate 2) before the test-writer's second delivery. Change review 1 (codex, opus) found three timing edges in candidate 2; the operator approved a second fix round ("p382: go for second round"); revision 5 and candidate 3 followed, with the test-writer amending its boundary numbers and one test (43 tests, re-frozen before candidate 3 was revealed). Test-writer delivery 3: all 43 pass, verdict fix then merge with one test-hygiene item. Change review 2: codex NOTHING OF SUBSTANCE; opus no correctness or security defect, one spec-level residual, one scope request, test notes: `docs/backlog/throttle-paced-freshness-residuals.md`.

Verification at Accept in the operator tree: release build, 25 UI + 198 core native tests three times (141 prior, 43 frozen blind under `Tests/LimitaurCoreTests/ThrottleFreshness/`, 14 implementer), the 49 frozen independent Python tests and 12 collector tests, all passing (`accept-verify-operator-tree.txt`). Line budget: 93 monitor lines against 80, recorded.

## Report block

```
[four-eyes 0.6.4] outcome: completed; mode: light (presentation timing; no credential or data-boundary change)
designer: claude code: claude-fable-5-1, session_015vrMp1ckiEtnyexp9KvYR7
design review: codex: gpt-6-astra, 01a167a1…, checkout (user instructions loaded), returned; claude: claude-opus-5-5, 24113d63…, checkout, returned; rounds 1; same model as designer: none; same vendor: opus
implementer: claude: claude-sonnet-5-5, 6d0bab0d…; fixes: 163f6d53…, f3f17606…
test-writer: codex: gpt-6.1-sol, 01a167a7-dbf5-7233-baad-1051d00e9388; second delivery continued (five deliveries, one session); same model as designer | implementer: no | no; tests frozen 2026-10-23T07:40:16Z (re-frozen after amendments before candidates 2 and 3), candidate revealed 07:49Z (candidate 2), 16:14Z (candidate 3); candidate 1 was never revealed to the test-writer
change review: codex: gpt-6-astra, 01a167c9…, 01a16991…, checkout (user instructions loaded), returned; claude: claude-opus-5-5, a7e7ba4c…, e4d9a101…, checkout, returned; same model as implementer: none; same vendor: opus
not covered: errors Anthropic models make consistently are checked only by the codex seats; errors the designer's own model makes are not checked by any member of its own model.
go: 2026-10-23T07:20:15Z, "go for the light run" / "implement autonomously if the review comes back good"; second fix round: "p382: go for second round"; accept: pre-authorised, recorded in go.txt; commit: see git log (feat: keep throttled usage visible until the provider's Retry-After); push: none
cost, as reported: opus design $0.93; opus change review $1.35, $1.90; implementer $0.58; fixes $0.18, $0.33; codex sessions unreported (tokens only: 49k, 83k, 356k, 397k, 159k, 79k, 75k)
```
