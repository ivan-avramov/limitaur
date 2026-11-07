> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-a/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review, candidate A2: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16c32-d549-7f52-bd4c-a1b4e0e37072; 7 major, 2 minor) and claude-opus-5-5 (session 87e399ac-e0a3-4372-8244-baf5a9781aa4, $1.80, 347 s; 2 major, 6 minor, 2 scope requests). Test-writer second delivery (codex gpt-6.1-sol, session 01a16c11-3b07-7e42-b5b6-d58fb0224a09): findings P26–P31, verdict fix then merge. Dispatched 04:37:13Z, returned by 04:43:01Z.

| # | Raised | Problem | Disposition |
| --- | --- | --- | --- |
| 1 | C5, O F1, TW P26 | Suspended wording and counter skipped on an unpaused binding (429 path) and on wake. | Adopted (r6): wording applies whatever the current message, on wake too; restore to nil for an unpaused binding. |
| 2 | C6 | Suspension presentation unconditional for default monitors. | Adopted (r6): gated on reactiveRecheck. |
| 3 | C1 | Cancelled timeout work item retains raw output. | Adopted (r6): buffer cleared after extraction on every path. |
| 4 | C2 | Shutdown not atomic with spawn and registration. | Adopted (r6). |
| 5 | C3 | Unregistered timeout can leave a TERM-ignoring descendant alive. | Adopted (r6): timeout escalation completes against the group regardless of registry. |
| 6 | C4, O F4, TW P27 | waitid error falls through to killpg. | Adopted (r6): no signal on error, registry removal, exitCode nil; only-reaper prerequisite documented. |
| 7 | C7, O F2, TW P28 | Probe: statuses ignored, cleanup unverified, answer unvalidated, dialog timing. | Adopted: create/update statuses checked, deletion verified by attribute lookup (exit 44), services deduplicated, answer validated with EOF failing, "do not answer until the result appears" printed. |
| 8 | C9, O F5, TW P30 | README: no-prompt guarantee, denial visibility, memory-path sentence. | Adopted: three sentences reworded. |
| 9 | O F3 | `.busy` reported as denial changes messages for minutes. | Adopted (r6): busy is a no-op. |
| 10 | C8, O F6, TW P29 | Implementer tests use yes/head/ls contrary to their own comment. | Adapted: the two cases are deleted (frozen suite covers them), which also reduces the test overrun; specification A6 is not violated. |
| 11 | O F7 | Gaps: diagnostic reject path untested; rotation test starts from a 429; usleep timing. | Adopted: reject-path test, a 200-then-429 rotation test, semaphores instead of usleep where the test controls the fake. |
| 12 | O F8 | terminateAll from stop() is irreversible; hazard for Part C's quit deferral. | Recorded for Part C's brief: termination cannot be cancelled after stop(). |
| 13 | O SR1 | Suspended wording only at the next refused read. | Adopted (r6): the causing read reports suspended. |
| 14 | O SR2 | Connect answered Deny clears suspension. | Adopted (r6): interactive clears only on found or notFound. |
| 15 | TW P31 | Budgets: tests 318/190, CLI 17/15. | For the operator at Accept; designer recommends waiving both (tests shrink by two cases in this fix). |
Declined blockers or majors: none.
