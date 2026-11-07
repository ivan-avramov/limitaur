> Historical record imported 2026-11-07 from `2026-10-23-throttle-freshness/change-review-2/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 2 (candidate 3): opus dispositions (designer)

opus claude-opus-5-5 e4d9a101-fa06-408b-9a60-a3e18cfa2e98, read-only checkout, $1.90, 400 s. "No correctness or security defect in candidate 3 against r5." Four items, all new.

| # | Problem | Disposition |
|---|---|---|
| P383 (opus 1, minor, spec-level) | retention is latched from `retryAfterUntil + retentionSlack`, but the next request cannot leave before `throttleUntil` = max(Retry-After, local backoff); on a second consecutive 429 the backoff (60 s, then 120 s) can outlast a short Retry-After, so the post-throttle request is dispatched after retention and the bar blinks 11–18 s | recorded as a residual, not fixed: both fix rounds of the light run are spent; the observed pattern alternates success and 429 (backoff resets on each 200) with Retry-After about 55 s, which does not blink; the blink needs two consecutive 429s with a Retry-After under the backoff. Opus's proposed latch `max(retryAfterUntil, throttleUntil) + retentionSlack` keyed on a parsed header is a reasonable next step; it reverses one R4 clause and two frozen tests. Backlog. |
| P384 (opus 2, test) | the implementer's `stop()` test cannot fail: `stop()` already clears the snapshot; only the frozen alias test pins the `retention` half of R12; the `retryAfterUntil` clearing is unobservable | recorded: backlog test item; spec note added that the `retryAfterUntil` clearing in `stop()` is hygiene no test can observe |
| P385 (opus 3, scope request) | retention outlives a credential rejection: a 401 before `held` with no alternate, or an expiry pause, keeps the T values ranked until `held` while the row says authentication required (before this change a paused binding was ranked until T+90, so this only lengthens an existing window) | recorded for the operator as a scope request; not applied. Proposed clamp: `retention = min(retention, max(nominal, mono))` on 401/403 and on auth pause. |
| P386 (opus 4, tests) | gaps: a 429 with Retry-After on the alternate request before `held`; the two no-eligible-subscriber re-dispatch paths under the hold; merge during the in-flight hold with a late completion of the cancelled request | recorded: backlog test items |

Codex (gpt-6-astra, same round): NOTHING OF SUBSTANCE after reading the full material. Opus shares the designer's vendor; codex is the cross-vendor check.

Designer's judgement: no finding shows the goal failing on an input it covers; no blocker; no required fix; the test-writer's remaining item is test hygiene. The run proceeds to Accept under the operator's pre-authorisation ("implement autonomously if the review comes back good"; "go for second round").
