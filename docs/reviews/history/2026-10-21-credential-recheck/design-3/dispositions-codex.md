> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/design-3/dispositions-codex.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 3: codex dispositions (designer)

codex gpt-6-astra 01a161ad-f80d-77b1-a874-f5403ca4e175, 8 findings.

| # | Problem | Disposition |
|---|---|---|
| P1 | stale completion clears a newer load's entry | adopted: clear only when the entry belongs to the completing load |
| P2 | throttle provenance lost through backoff/merge/creation | adopted by rollback: provenance flag removed; attachment carries the maximum active deadline like creation; cost stated as accepted |
| P3 | expiry gate restricted to re-check drivers; expired result can bind | adopted: expiry pausing on every path; expired-at-completion never binds |
| P4 | merge keeps old lastAttempt, immediate refetch | adopted: merge keeps maximum lastAttempt |
| P5 | label-edit fix incomplete (setProfiles, sleep) | adopted: credential-equivalence used in all three places |
| P6 | re-check can be first access of discovery fallback file | adopted: premise narrowed; fixed home path noted; found-to-absent case in R7 |
| P7 | denied-message exception misses failure rows | adopted |
| P8 | M1 timing | adopted: wording |
