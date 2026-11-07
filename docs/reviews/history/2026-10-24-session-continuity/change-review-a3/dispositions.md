> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-a3/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 3, candidate A4: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16c80-1212-7991-98b2-7475af67598d; 6 major, 1 minor) and claude-opus-5-5 (session 62fd9a02-549e-417a-bc3f-b4307033cf48, $1.49, 284 s; 1 major, 6 minor). Test-writer fourth delivery: P65–P67, verdict fix then merge. Dispatched 06:01Z, returned by 06:06:19Z.

| # | Raised | Problem | Disposition (pending operator approval of a third fix round) |
| --- | --- | --- | --- |
| 1 | TW P65, C1, O1 | The same-pass cached re-check overwrites the explicit busy retry's epoch; a 401-paused binding with the same token sticks at "Connecting account"; two reads per source per pass. | Adopted, opus's three-line fix: a retried source is excluded from the `due` loop and its `recheckDue` entry removed; tests for same and changed token asserting one read and no re-check counters. |
| 2 | C5, O2 | A stale `busyRetry` survives a later successful explicit load and later pauses a healthy binding. | Adopted: a newer explicit load consumes the entry in `beginLoad`; test with a second Connect before the retry deadline. |
| 3 | C4, O6 | The busy early return is unconditional, so a default monitor can strand an unbound profile. | Adopted (r8): the whole busy branch is gated on `reactiveRecheck`; a default monitor treats busy as the baseline denial path. |
| 4 | TW P66, C2, O3 | Background-only contention past 8.5 s returns busy, which r7 reserved for interactive contention; the "unreachable" claim is false. | Adopted as a specification change (r8): busy is also the outcome of a non-interactive read not admitted within 8.5 s; it spawns nothing and is retried. Test-writer's "treat as failure" declined for the reasons both reviewers give. |
| 5 | C6, O7 | `expire`'s probe treats any error as "exited", losing the 5 s bound. | Adopted (r8): EINTR retried; any other probe error counts as running (the timeout proceeds; signalling stays guarded by `reaped`). Codex's fuller running/exited/failure contract declined as larger than the hazard. |
| 6 | TW P67, C3, O4 | The environment assertion can print captured output on failure. | Adopted: Boolean-only assertion. |
| 7 | C7 | The wait-failure test's liveness check (`kill(pid, 0)`) passes on a zombie. | Adopted: use a non-reaping `waitid(WNOHANG|WNOWAIT)` check and unconditional cleanup. |
| 8 | O5 | The bound busy test uses a path the real reader cannot produce. | Adopted: drive it through the real reader with sleep during Connect from a 401-paused binding. |
| 9 | O "several interactive reads" | Any found/absent completion clears a deferred suspension. | Accepted as consistent with r7; recorded. |
