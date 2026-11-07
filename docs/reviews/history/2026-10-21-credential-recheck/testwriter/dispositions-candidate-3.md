> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/testwriter/dispositions-candidate-3.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Test-writer verdict on candidate 3: disposition (designer)

gpt-6.1-sol session 01a161b7-f24d-7c13-9b8b-d2273d66eb7e, delivery 5 (stdout-5.txt). Verdict: fix then merge.

| # | Problem | Disposition |
|---|---|---|
| P39 (new) | the account-mismatch loop in `complete()` writes `serverRejected: false` for every removed alias, downgrading an alias already marked `http401`; a selector change then re-sends the token | adopted: write `serverRejected: candidate.pauseCause == .http401`; regression test. A third fix round needs the operator's call. |
| accepted by TW | entity health and message set on a no-subscriber 429/failure | accepted deviation, recorded |

All 42 frozen tests pass; frozen hashes unchanged; probes A–E now pass; probe F fails (P39). R10 three full green runs were done by the designer on candidate 3 (verify3); M1 remains the operator's.
