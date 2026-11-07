> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/design-3/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 3: opus dispositions (designer)

opus claude-opus-5-5 4086c418-250c-4c04-b3e4-a1407a4fa0f6, $1.32, 297 s; 14 findings, 1 scope request.

| # | Problem | Disposition |
|---|---|---|
| 1 | driver flag unbuildable: all drivers via public refresh(); nominal cycle is the default | adopted: RefreshDriver enum, `.cycle` default, `.internal` for completion/setProfiles/post-load |
| 2 | expiry pause gated by driver sends expired tokens | adopted (already in r4 via codex P3): expiry pausing on every path |
| 3 | denied-message exception one-way; wake with locked keychain sticks; failure rows | adopted: two-way between the two constants; never on `.wake`; failure rows included |
| 4 | same-token pauses never clear (declined Connect, malformed mid-rewrite, clock jump) | adopted: pause cause; lift on same unexpired credential unless http401; open question 2 resolved |
| 5 | "no reading of refresh tokens" is false | adopted: constraint restated; sensitive area named |
| 6 | capacity check before detach blocks resume at exactly the cap | adopted: count the freed slot |
| 7 | providerThrottle flag inconsistent | adopted (already in r4): flag removed, max deadline carried |
| 8 | retryDate and 401 alternate dispatch site | adopted |
| 9 | equality must include selectedAccountID | adopted |
| 10 | rejectedFingerprint clearing | adopted: cleared on any explicit bind |
| 11 | drop wake replay of re-checks | adopted: cancelled at sleep, not replayed |
| 12 | one read per source per pass | adopted |
| 13 | network/removable/iCloud paths can hang reads and fill capacity | adopted: named and accepted; README |
| 14 | README missing from scope | adopted |
| scope | next-due display field | declined: not needed by the goal |
