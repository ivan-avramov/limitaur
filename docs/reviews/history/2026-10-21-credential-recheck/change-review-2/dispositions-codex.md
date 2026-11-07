> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-2/dispositions-codex.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 2: codex dispositions (designer)

codex gpt-6-astra 01a161e4-a178-7140-9b48-cc4322a2a7ec, 3 findings.

| # | Problem | Disposition |
|---|---|---|
| P1 (= TW P31 + 429 variant) | complete() drops 401/429 effects when no unpaused subscriber matches | adopted (spec r6): apply auth and throttle effects to matching bindings before the early return |
| P2 (new) | local mismatch during Connect detaches the binding carrying http401 | adopted (spec r6): server rejection kept in rejectedFingerprint, fingerprint-only |
| P3 (new) | alternate dispatch after 401 ignores the alternate's expiry | adopted (spec r6): skip and pause expired alternates |
