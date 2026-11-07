> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-b3/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 3, candidate B3: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16f37-575e-79f2-9070-387b2bacb9a4; 3 major) and claude-opus-5-5 (session 9fd13e1a-662a-45a4-aaba-1b22fed4674f, $0.59, 104 s; 2 major, nothing else). Test-writer fourth delivery: P145, P146, verdict fix then merge. Dispatched 18:40Z, returned 18:43:34Z.

| # | Raised | Problem | Disposition (pending operator approval of a third fix round) |
| --- | --- | --- | --- |
| 1 | TW P145, C1, O1 | An accepted same-token Connect on the same-selector early branch, and a Claude configuration rebind with a surviving alias, bypass receipt settlement; codex adds that the alias case also misses the different-token discard. | Adopted: opus's one-line settle-on-accept before `profileFailures[id] = nil` for the same-token paths; for the alias replacement case, hold the receipt association across the detach and classify on completion (record same token, discard a different bound token, never on rejection). |
| 2 | TW P146, C2, O2 | A receipt held in `replacedThrottle` does not count for the reduction hold. | Adopted: include held receipts of the same provider in `held`. |
| 3 | C3 | Account-mismatch removal settles only when the entity empties; the last-classifier rule is missed there. | Adopted: apply the same remaining-fingerprint check after mismatch removals. |
| 4 | both | Monitor without `setPolling` unchanged; revert floor, `settleReplaced`, fallback and `detach` match r10. | Confirmed. |
Declined: none.
