> Historical record imported 2026-11-07 from `2026-10-23-throttle-freshness/testwriter/dispositions-candidate-2.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Test-writer verdict on candidate 2: disposition (designer)

gpt-6.1-sol session 01a167a7-dbf5-7233-baad-1051d00e9388, delivery 2 (stdout-2.txt), candidate 2 revealed 2026-10-23T07:49Z (after re-freeze). Verdict: fix then merge. All 40 frozen tests pass (hashes unchanged), 11 implementer tests pass, three whole-suite runs green, Python suites OK.

| # | Problem (verified by the designer) | Disposition |
|---|---|---|
| P33 | `stop()` clears `snapshot` but not `retention` (nor `successfulInstant`); r4 says retention clears whenever the snapshot clears | adopted as a required one-line fix: clear `retention` and `retryAfterUntil` in `stop()`. Harmless in use (stop is quit; the helper returns nothing without a snapshot) but a stated rule. The light-mode fix round is spent, so this goes to the operator with the change-review findings. |
| P34 | README says "Retry-After longer than that window"; r4 extends for any parsed Retry-After | adopted: wording fix, same round |
| P35 | implementer test helper `waitHeld()` unbounded; one test leaves continuations outstanding | adopted as test hygiene, same round |
| P36 | budget: 89 monitor lines vs 80; 197 test lines vs 100 | recorded for the operator; not a defect |
| P38 | no frozen test judged invalid | noted |
