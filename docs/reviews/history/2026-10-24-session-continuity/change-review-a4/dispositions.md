> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-a4/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 4, candidate A5: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16ec8-eb67-7c22-b61f-80527e99f223; 2 findings, "nothing of substance beyond P82 and P83") and claude-opus-5-5 (session 17f6c2c0-1c38-4a7e-9dc9-0db69e563d2d, $0.60, 91 s; "nothing of substance beyond P82 and P83"). Test-writer fifth delivery: P82, P83, verdict fix then merge. Dispatched 16:40Z, returned 16:41:55Z.

| # | Raised | Problem | Disposition |
| --- | --- | --- | --- |
| 1 | TW P82, C1, O1 | Two busy-retry profiles on one source are both issued in one pass. | Recorded as residual, not fixed: it needs two enabled profiles on one source, which the goal's operating conditions (one Claude profile) do not cover; the reader serialises and the second read sees any suspension; opus shows revision 8 does not require the per-source rule for retries. Specification wording clarified (r8 note). |
| 2 | TW P83, C2, O2 | Test cleanup signals a saved grandchild PID after the group kill and leader reap; microsecond PID-reuse window, test-only. | Recorded as residual for the operator: the fix is deleting one line in the implementer test file; the designer does not edit the candidate. Listed in the Part A residuals. |
| 3 | both | `expire` probe error branches untested (no seam); default monitor at baseline; beginLoad consumption ordering correct. | Confirmed; the untested branches recorded as residual. |
