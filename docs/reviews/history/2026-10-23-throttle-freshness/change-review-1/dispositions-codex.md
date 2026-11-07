> Historical record imported 2026-11-07 from `2026-10-23-throttle-freshness/change-review-1/dispositions-codex.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 1 (candidate 2): codex dispositions (designer)

codex gpt-6-astra 01a167c9-b157-7bd1-accb-1b3bb4a40f6e, read-only checkout, user instructions loaded, 79,506 tokens, cost unreported. 2 findings, both new, both verified in code.

| # | Problem | Disposition |
|---|---|---|
| P1 (major) = opus 2 | `complete()` clears `task` before the 429 branch latches, so a repeat 429 whose response arrives after `held` but during the in-flight hold cannot re-latch; the snapshot that was on the bar until that instant drops. Frozen `secondThrottleAtRetentionEqualityCannotRevive` pins the wrong behaviour (dispatch at T+135, 429 at T+146.5, expects empty). | adopted (spec r5): evaluate "still shown" against the pre-completion deadline (capture before clearing `task`) and latch on that; the frozen test is judged invalid and goes to its author. Requires a second fix round: operator's call (P381). |
| P2 (major) = opus 3 | the 401 alternate-credential dispatch sets a new `task` without updating `lastAttempt`, so the in-flight hold covers a request dispatched after retention ended | adopted, adapted (spec r5): the in-flight clause applies only while `alternateUsed == false`; `lastAttempt` semantics (scheduling) stay unchanged. Same round. |
