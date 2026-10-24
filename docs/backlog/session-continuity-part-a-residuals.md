# Backlog: session continuity Part A residuals

Status: backlog, recorded at the Accept ask of Part A (2026-10-24, strict four-eyes; specification `docs/proposals/session-continuity.md` revision 8). None becomes a requirement without an operator decision. Evidence: `/Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/`.

- **R-A1** Two enabled profiles on one credential source that both met a busy reader are both retried in one scheduling pass (change review 4, P82). Needs two profiles on one source, which the supported configuration (one Claude profile) does not have; the reader serialises the reads and the second sees any suspension. Candidate fix: check the `retried` set before consuming a second `busyRetry` entry.
- **R-A2** `SessionContinuityImplementerTests.swift`, the injected wait-failure case: after the group kill and the leader's reap, cleanup also signals the saved grandchild PID, which could by then be reused (P83). Test-only; fix is deleting that one line.
- **R-A3** The `expire` probe's EINTR and error branches in `ProcessRunner.swift` have no test (the probe is not behind the injection seam).
- **R-A4** After a 401 pauses a binding and a later Connect succeeds with the same token, the stale `recheckDue` entry still issues one cached re-check 30 s later (no visible effect; one spare `security` read).
- **R-A5** With several interactive reads admitted at once, any found or not-found completion clears a deferred suspension; the specification describes a single interactive read.
- **R-A6** The diagnostic `--read-keychain-service` reject path is covered by the probe's step 0 and inspection only, not by a unit test.
- **Budgets** Part A final counts exceed the stated budgets after three fix rounds adopted reviewer findings: see the Accept record for the table. Recorded; the operator decides the waiver at Accept.
