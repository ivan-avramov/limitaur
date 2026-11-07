> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/change-review-a2/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 2, candidate A3: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16c4d-9183-7251-a1b7-e6ffb2c66658; 3 major, 4 minor) and claude-opus-5-5 (session f696ec94-69c3-49c9-b97d-86f1802c6136, $1.77, 368 s; 2 major, 7 minor). Test-writer third delivery: P45–P47, verdict fix then merge. Dispatched 05:06Z, returned by 05:12:34Z.

| # | Raised | Problem | Disposition (pending operator approval of a second fix round) |
| --- | --- | --- | --- |
| 1 | TW P45, C1, O1 | A busy load is dropped; unbound or 401-paused profiles stay at "Connecting account"; likeliest trigger is sleep during Connect. | Adopted, opus's smallest fix: remember explicit busy loads (`busyRetry[id] = clearPause`), re-insert re-check busy loads into `recheckDue`, retry on the re-check pass 30 s after the last load, gated on `reactiveRecheck`; replace the test that pins the stuck state; add the sleep-during-Connect case. Codex's retained-task variant declined as larger for the same outcome. |
| 2 | TW P46, C3, O2 | Test falls back to PID 0 and can SIGKILL the test process group; the injected reap-failure case leaves a zombie. | Adopted: guard both PID uses; reap the second child with the real wait after the assertion. |
| 3 | C2 | A background timeout while Connect is queued never suspends, and a Connect that then fails leaves the source unsuspended. | Adopted (r7): deferred suspension obligation, cleared only by interactive found/notFound, otherwise applied when the interactive read finishes. |
| 4 | O3 | Timeout can be marked after a normal exit at ~5 s and suspend a successful read. | Adopted: `expire` checks `waitid(WNOHANG|WNOWAIT)` first. |
| 5 | O4 | Busy returned for non-interactive contention after a 6 s wait, shorter than a read can take. | Adopted: wait 8.5 s (r7 note). |
| 6 | O5 | README overstates: "until Connect completes"; denial wording on unpaused bindings. | Adopted. |
| 7 | C7 | Probe: second `read` after `stayed` unchecked. | Adopted. |
| 8 | TW P47, C4, O7 | Diagnostic reject path untested. | Adopted as probe step 0 (exit 2, empty stdout, `unsupported service`); no seam. |
| 9 | C5, C6, O6 | Acceptance prose A7/A8 stale against r6; A1 should state kill-at-leader-exit and "no runner signal after a wait failure". | Adopted (r7 text). |
| 10 | O8 | Frozen reader test lacks the notFound-clears case; stale comment. | Recorded for the next permitted frozen amendment; not edited now. |
| 11 | O9 | Test gaps: wake-path wording, restore-to-nil never exercised, signal history after reap failure. | Adopted: the restore-to-nil test gets its later read; wake-path case added; reap-failure signal history asserted via the seam. |
| 12 | C6 (reused group) , O "checked" | No reused-group signalling under the sole-reaper rule; buffer clearing complete; default monitor at baseline. | Confirmed, no change. |
