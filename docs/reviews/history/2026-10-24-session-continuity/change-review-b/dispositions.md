> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-b/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 1, candidate B: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16efe-f64b-7370-97c8-58a5ed3481fb; 10 major, 3 minor, 1 scope) and claude-opus-5-5 (session af527fff-c210-4722-b2c0-fab84b1f4885, $1.42, 259 s; agrees with all nine required fixes, grades six minor). Test-writer second delivery: P115–P125, verdict fix then merge. Dispatched 17:39:25Z, returned 17:43:44Z.

| # | Raised | Problem | Disposition |
| --- | --- | --- | --- |
| 1 | TW P115, C1, O | Ranking-age shift uses the horizon, so bars empty at age 90 under an active policy. | Adopted; specification corrected (r9): the shift keeps the literal 90 (`deadline − (success + 90)`), the horizon applies to deadlines and proofs. |
| 2 | TW P116, C2, O | Settlement keyed by fingerprint across entities and providers; 60 s fallback not per receipt. | Adopted, opus's smaller form: settle per entity (the completing subscriber's entity) and per receipt. |
| 3 | TW P117, C3, O | Selector-only rebind discards a pending 429 as if a rotation. | Adopted: discard only when the fingerprint changed; same-token rebind records. Connect-driven rotation treated as rotation, stated (r9). |
| 4 | TW P118, C4, O | Merge drops one of two pending receipts. | Adopted: record the older at merge, keep the newer. |
| 5 | TW P119, C5, O | Deferred attribution not published. | Adopted: publish when settlement recorded. |
| 6 | TW P120, C6, O | Persistence cache holds re-encoded bytes, not stored bytes; future dates never rewritten. | Adopted: cache the loaded bytes. |
| 7 | TW P121, C7, O | Rows without a snapshot lack the interval line. | Adopted. |
| 8 | TW P122, C8, O | Demo overwrites the in-memory policies. | Adopted: carry them in the synthetic display. |
| 9 | TW P123, C9, O | Dropdown not invalidated on interval change. | Adopted: compare displayed intervals. |
| 10 | C10, O | Account-mismatch removal bypasses detach; pending signal pruned. | Adopted: record the pending receipt where that path empties the entity. |
| 11 | C14 (scope), O | 60 s fallback on wall time. | Adopted as r9: monotonic receipt time for the fallback, wall receipt time for `recordThrottle`. |
| 12 | C11, O | App helpers public in the core library; budget overruns. | Adapted: `package` visibility, formatter validates inputs; relocation declined; budgets for the operator at Accept. |
| 13 | C13, O | README freshness and retention wording wrong under an active policy. | Adopted. |
| 14 | C12, O | B7 app paths untested; a UserDefaults assertion proves nothing. | Adopted: app-level tests for the no-snapshot line, demo carry and invalidation via seams; the empty assertion replaced. |
Declined blockers or majors: none.
