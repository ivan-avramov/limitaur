> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-b4/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 4, candidate B4: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16f85-9144-7f82-a62e-c1a5423c8a06; 2 major) and claude-opus-5-5 (session 1047c1a6-c640-4fd5-b208-9fa4cab69d71, $0.94, 189 s; 2 major, 2 minor). Test-writer fifth delivery: P154, P155, verdict fix then merge. Dispatched 20:06Z, returned 20:09:36Z.

| # | Raised | Problem | Disposition (pending operator approval of a fourth fix round) |
| --- | --- | --- | --- |
| 1 | TW P154, C1, O1, O2 | The alias association looks the receipt up by its old entity key; after a verified-account merge or a transfer into the sole-replacement hold the lookup fails, losing a discard (or, on the hold path, a record). Unreachable with one profile per provider; consequence within the revert window is a revert plus a 7-day block, not just one step. | Adopted: find the receipt by identity wherever it sits (opus's ~3-line lookup across entities and `replacedThrottle`), consume once; add the test-writer's two relocation probes and the same-token-first order. Both reviewers recommend fixing rather than recording. |
| 2 | TW P155, C2, O3 | The mismatch regression test can pass without its fix because the manual refresh admits the queued re-read, which records first. | Adopted: use the `.internal` driver (no re-read), assert the receipt still pending before, one credential read in total, the other alias still attached, interval 60 at receipt time before the fallback, no second increment after. |
| 3 | O4 | Test comment names the wrong account. | Adopted. |
| 4 | both | Monitor without `setPolling` at baseline; settle-on-accept, held clause and mismatch guard match r10. | Confirmed. |
Declined: none.
