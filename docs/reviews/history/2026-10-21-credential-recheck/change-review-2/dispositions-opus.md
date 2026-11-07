> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-2/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 2: opus dispositions (designer)

opus claude-opus-5-5 96d12cf0-31b5-4133-941d-690f86458faa, $1.32, 300 s; 4 findings.

| # | Problem | Disposition |
|---|---|---|
| 1 (extends TW P31, codex P1) | early return drops 429/backoff too; generation bump after Connect drops a 401 | adopted (spec r6): entity-level effects applied regardless of subscriber state and generation |
| 2 (new) | a token rejected on one alias is re-sent by another alias's re-check | adopted (spec r6): never create/attach on a re-check or setProfiles load with a fingerprint any same-provider binding holds as http401 |
| 3 (new, test gap) | r5 rules unpinned by committed tests; UI runs; M1 | adopted: fixer adds regression tests for every r5/r6 rule; R10 three full runs already done by the designer on candidate 2 and will be repeated on candidate 3; M1 is the operator's, before Accept |
| 4 (minor) | redundant guard in loaded() that would strand state | adopted: guard removed; credentialEquivalent carries the rule |
