> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/design-2/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 2: dispositions (designer)

Members: codex gpt-6-astra 01a161a8-f381-7513-8084-52178094eb13 (7 findings); opus claude-opus-5-5 b79126a5-a285-4fd8-a963-80bd75b30240, $0.82, 204 s (9 findings, 2 scope requests, 1 sensitive area).

| Item | Raised by | Disposition |
|---|---|---|
| re-checks reachable from complete()/setProfiles via onlyKey == nil | codex P2, opus F1 | adopted: explicit `rechecks` driver flag |
| wake replay loses origin; lastLoad stamp contradiction | codex P5, opus F2 | adopted: origin stored in sleepRevalidation; replay re-stamps; named exception |
| rejected fingerprint must not change Connect | codex P6, opus F3 | adopted: re-check loads only; set-points specified |
| automatic-resume message can lie under Keychain denial; 401 message inconsistent | opus F4 | adopted: single message exception on `.keychainDenied`; one constant for expiry and 401; M1 fallback extended |
| carry-over on attach spreads network backoff to healthy co-subscriber | opus F5 | adopted: carry-over limited to provider (429) throttles; stated as a base-rule change |
| success erases inherited throttle set during request | codex P1 | adopted: completion never lowers a deadline set after dispatch |
| label edit strands a pending load | codex P3 | adopted: identity guard by id/source/expected/enabled; loading cleared on every early return |
| silent failure must include local mismatch and capacity after a successful read | codex P4 | adopted: capacity checked before detach; both outcomes change nothing |
| case (c) defined by health `.unauthenticated` | opus F6 | adopted |
| recheck failures and credentialFailures; missing lastLoad | opus F7 | adopted |
| R2 wording versus attach/dropdown | codex P7, opus F8 | adopted |
| expiry pause discards in-flight valid result | opus F9 | adopted: pause only when no request in flight; result kept |
| manual refresh should re-check (base spec clause) | opus F10 scope request | adopted: base specification already settles it; R5 restored |
| pauses with a still-valid token never clear | opus F11 scope request | recorded as open question 2 with recommendation to keep |
| privacy prompt versus "never prompts" | opus F12 | adopted: argued (re-check never first access) and goal wording narrowed to Keychain prompts |
