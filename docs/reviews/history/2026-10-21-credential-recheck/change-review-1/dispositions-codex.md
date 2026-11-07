> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-1/dispositions-codex.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 1: codex dispositions (designer)

codex gpt-6-astra 01a161d3-49e6-7d33-9068-3734150b6c80, 8 findings.

| # | Problem | Disposition |
|---|---|---|
| P1 (= TW P15) | credential-equivalence omits providerID; token can reach the other adapter | adopted; spec r5 |
| P2 (new) | changed selector bypasses the 401 rule; frozen StateTests:122 expects the forbidden request | adopted: http401 pauses compare by fingerprint only; test judged invalid, test-writer to amend |
| P3 (new) | 401 not recorded on already-paused aliases | adopted; spec r5 |
| P4 (= TW P16 + message) | expiry pause overwrites cause and denied message | adopted: expiry pause transitions unpaused bindings only |
| P5 (= TW P17) | same-token lift keeps stale expiry | adopted |
| P6 (new) | sorted one-read-per-source can starve | adopted: oldest-lastLoad selection per source |
| P7 (= TW P18) | capacity return skips message transition | adopted |
| P8 (minor) | README overstates "never prompts" | adopted |
