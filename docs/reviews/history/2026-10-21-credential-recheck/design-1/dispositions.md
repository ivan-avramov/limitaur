> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/design-1/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 1: dispositions (designer)

Members: codex gpt-6-astra session 01a161a3-2217-7650-bef3-8abdc8956a32 (8 findings); opus claude-opus-5-5 session 2c15f42f-1958-4139-8902-73a50ce23a66, $1.06, 242 s (16 findings, 2 sensitive areas, 3 simplifications). Neither saw the other's output.

| Item | Raised by | Disposition |
|---|---|---|
| lastRecheck cleared on detach loops; first re-check immediate | opus 1, 3; codex P4 | adopted: `lastLoad` stamped at every load, never cleared by detach, removed only on profile removal/reconfiguration |
| server-verified mismatch re-sends every interval | opus 2; codex P3 | adopted: rejected fingerprint remembered; same fingerprint never binds or sends; answers open question 2 |
| non-rebind re-check forces co-subscriber fetch | opus 4 | adopted: re-check loads are silent unless they rebind |
| credentialResumes miscounted | opus 5 | adopted: load origin flag |
| Connect dropped while re-check in flight | opus 6; codex P5 | adopted: Connect cancels a pending re-check load |
| Keychain ACL after Claude Code rewrite unverified | opus 7 | adopted as manual criterion M1 with documented fallback |
| existing tests order-dependent via capacity failure | opus 8, 9 | adopted: credential-less excludes capacity and source-unavailable; suites run three times |
| sleep clause wrong; locked keychain at wake | opus 10; codex P7 | adopted: restated; silent re-checks make a denied read at wake harmless |
| rebind fetches immediately, not next cycle | opus 11; codex P6 | adopted: text and R2 corrected |
| trigger from nested refresh calls | opus 12 | adopted: top-level only |
| message flicker and duplicated literal; interval-specific wording | opus 13; codex P8 | adopted: one constant, interval-neutral; re-checks change no message |
| expired-but-throttled binding not eligible | opus 14; codex P2 | adopted: case (b) checked before throttle guards |
| R6 wording | opus 15 | adopted |
| interval validation | opus 16 | adopted |
| throttle carry-over on attach | codex P1 | adopted: loader change named in scope |
| process-wide policy flips; TCC file paths | opus sensitive areas | named and accepted in the specification |
| drop R5 manual-refresh force | opus simplification | adopted: dropped |
| drop counters | opus simplification | declined: they are the cadence oracles for R1–R4 at negligible cost |
