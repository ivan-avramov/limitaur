> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-3/dispositions-codex.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 3: codex dispositions (designer)

codex gpt-6-astra 01a16279-b663-7740-b695-b77b3e67654e, 3 findings.

| # | Problem | Disposition |
|---|---|---|
| P1 (new; pre-existing hazard widened) | entity epochs restart at 0 on recreation, so a stale completion can pass the guard | adopted (spec r7): epochs from a monitor-wide increasing counter |
| P2 (new; pre-existing policy widened) | no-subscriber completion forces a global refresh bypassing cadence | adopted (spec r7): follow-up limited to the entity with the 10 s minimum success age |
| P3 (= TW P39) | mismatch removal downgrades an alias's http401 | adopted (spec r7) |
