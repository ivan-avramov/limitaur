> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-b2/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 2, candidate B2: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16f19-b140-7b62-9831-97a82ddc2529; 6 major) and claude-opus-5-5 (session b96043a5-3bed-4e3c-8b2e-648ac3523de9, $1.03, 173 s; 3 major, 1 minor). Test-writer third delivery: P132–P134, verdict fix then merge. Dispatched 18:08Z, returned 18:11:56Z.

| # | Raised | Problem | Disposition (pending operator approval of a second fix round) |
| --- | --- | --- | --- |
| 1 | TW P132, C1, O1 | A same-token explicit rebind with an alias still attached never records the pending 429. | Adopted, opus's form: settle the old entity's receipt on any accepted same-token rebind, whatever the origin or subscriber count. |
| 2 | TW P133, C2, O2 | A configuration replacement records the receipt at detach, so a successful different-token load cannot discard it. | Adopted, opus's form: hold the sole subscriber's receipt aside at replacement, classify when the load completes, 60 s fallback covers loads that never finish. |
| 3 | TW P134, C3, O3 | `pendingThrottleHoldsReduction` flaky: fixed sleeps instead of state waits; a silent `answer` on a not-yet-arrived request; the rig's init wait. | Adopted: bounded waits on state transitions, no arbitrary sleeps; not a monitor race (both reviewers). |
| 4 | C3, O4 | The same test cannot fail: `lastChange` is never 24 h old. | Adopted: age the policy so the fifth clean poll would reduce without the hold. |
| 5 | C4, O1 | A capacity-rejected different-token Connect discards the receipt without binding. | Adopted (covered by the `full ||` condition in fix 1). |
| 6 | C5 | Removing the last subscriber able to classify a receipt (after a verified-account merge) leaves it pending until the fallback. | Adopted: record when no remaining subscriber or admitted replacement can decide it. |
| 7 | C6 | Revision 9's revert formula lets a stale receipt lower the interval after a later increase (100 → 50). | Adopted as a specification correction (r10): revert result is `min(ceiling, max(interval, lastReduction.from, r))`. |
| 8 | both | Monitor without `setPolling` unchanged. | Confirmed. |
Declined: none. Budget: Monitor will exceed its 70-line budget after fix 2 (about +12); for the operator at Accept.
