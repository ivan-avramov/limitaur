> Historical record imported 2026-11-07 from `2026-10-23-throttle-freshness/change-review-1/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 1 (candidate 2): opus dispositions (designer)

opus claude-opus-5-5 a7e7ba4c-ebcd-4829-b5ab-b9afcbbcc673, read-only checkout, $1.35, 259 s. 3 findings, all new, all verified in code. Confirms: nothing ranked past 300 s; no retention leak across rotation, detach, alias change, sleep, wake, clock jump or merge; untrottled behaviour unchanged; R11 edits sound.

| # | Problem | Disposition |
|---|---|---|
| 1 (major) | retention slack `pollInterval(jitter: 1.5)` = 46.5 s is shorter than the real tick gap: timer tolerance 1 s, re-arm after `refresh()` returns, App Nap; the first tick after the Retry-After deadline can land after `held`, giving a blink of about a second or two per throttle in rare phasing (roughly a (1.5+1)/46.5 chance per throttle) | adopted (spec r5): slack becomes `pollInterval(jitter: 1.5) + cadenceTolerance + 1` = 48.5 s with `cadenceTolerance` (1 s) defined once in `Models.swift` and used by `AppUI.scheduleCadence`; App Nap recorded as a residual. Changes the boundary numbers (146.5→148.5, 121.5→123.5, 116.5→118.5, 286.5→288.5) in about ten frozen assertions: their author amends them. Operator's call (P381). |
| 2 (major) = codex P1 | repeat 429 after `held` during the in-flight hold does not re-latch | adopted, variant (a): latch against the pre-completion deadline. |
| 3 (minor) = codex P2 | in-flight hold covers the 401 alternate request | adopted, opus's second variant: `alternateUsed == false` guard, no scheduling edit. |

Together with the test-writer's P33–P35 (`stop()` clearing, README wording, test helper), these form one coherent second fix round. None shows a snapshot ranked past the cap or a resurrection; each is a bounded blank the goal is meant to remove.
