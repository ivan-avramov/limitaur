> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-1/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 1: opus dispositions (designer)

opus claude-opus-5-5 6fdfe088-da3b-4083-b7ab-0a534a6c2ae3, $1.19, 298 s; 7 findings + 1 scope request.

| # | Problem | Disposition |
|---|---|---|
| 1 (new) | failed Connect overwrites http401; a 401 during a Connect pause is dropped | adopted: http401 sticky until a successful bind; recorded on paused bindings too (spec r5) |
| 2 (= TW P16) | expiry loop overwrites cause | adopted: transition for unpaused bindings only |
| 3 (= TW P15 + crash, cleanup) | providerID missing; adapter force-unwrap crash; cleanup ignores providerID | adopted (spec r5) |
| 4 (= TW P17 + counters) | stale expiry on lift; credentialExpiries inflates | adopted |
| 5 (= TW P18) | capacity skips message transition | adopted |
| 6 (minor, new) | dead code: `.connecting` unreachable, unread causes, always-true source check, redundant attribute | adopted: `.connecting` removed from the spec; dead branches removed; the spec'd "stamp and skip" stays as a one-line guard |
| 7 (minor, new) | deviations: wakeRecheck origin, increment order, retryDate on creation, line budget, CHANGELOG | retryDate on creation adopted; the rest recorded as accepted deviations in the spec |
| 8 (scope request) | every Settings save re-sends a rejected token | adopted: setProfiles-driven loads honour rejected memory; Connect still clears it |
