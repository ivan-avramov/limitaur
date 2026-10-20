# Phase A plan (Claude reviewer, candidate-blind)

Status: tests written, NOT executed by me. No Package.swift/binary exist in the baseline, so nothing can run yet; with no binary every test fails with "binary not available" (deliberately fail, not skip). No claim of passing.

Binary: `$LIMITAUR_BIN` or `.build/release/Limitaur`. Run: `python3 -I AdversarialClaude/test_acceptance.py`. Uses only the documented diagnostics (`--check-percent`, `--inspect-fixture`, `--rank-fixture`); empty-ish env, invented data, no network/credentials.

## Classification (12 cases)
| Test | Class | Criterion |
|---|---|---|
| 01 threshold boundaries 0/80/80.01/95/95.01/100/250, fill clamp | preserves invariant | A2 |
| 02 invalid (-1, nan, inf, text, empty) -> unknown, fill null | preserves invariant | A2 |
| 03 Codex windows by duration, reset seconds, distinct ids | exercises new behavior | A3 |
| 04 Codex invalid envelopes ({}, wrong types, unknown-only, non-JSON) rejected, no stdout | preserves invariant | A3 |
| 05 Codex negative percent not 0, partial + warning | exercises new behavior | A3 |
| 06 count-only resets (details null), opaque credits, no USD/expiry inference | exercises new behavior | A3 |
| 07 Claude inactive Fable kept, no legacy double count, fractional/offset time | exercises new behavior | A3 |
| 08 Claude empty list authoritative; null list -> legacy fallback | exercises new behavior | A3 |
| 09 Claude wrong-type limits not rescued by legacy; {} / unknown-only fail | preserves invariant | A3 |
| 10 Claude mixed rows partial; all-malformed fails | exercises new behavior | A3 |
| 11 rank top-3, lexical tie-break, unknown excluded | preserves invariant | A2 |
| 12 rank age 89 in / 90 out, reset equality and past out | preserves invariant | A2 |

None is "reproduces failure" (no known prior failure). Assertions avoid exact label/warning strings. Test 05 line on `resetsAt == NOW+9` guards against zero-coercion; ambiguity: a candidate may drop the bad window or emit null percent, both accepted.

## Not covered by these tests (preregistered review checks needing source/manual/Swift-test evidence)
- A4: URLSession delegate redirect rejection, streaming 1 MiB accumulator, deadline/cancel wiring, ephemeral config (no cookies/cache/credential storage), header allowlist. Check source; URLProtocol tests exist; note platform behavior not exercised offline.
- A5: O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC, fstat on same fd, 1 MiB+1 bounded read, FIFO prompt reject, leaf symlink reject, Keychain fallback only on item-not-found, auth UI disabled, no writes, expiresAt ms-only with Boolean/string/negative/overflow rejected, Codex API-key-only unsupported, no secrets in errors/logs.
- Scheduler: entity/epoch/generation, late result discard, alias detach, Codex same-token distinct account selectors separate, merge keeps max throttle, per-binding auth pause + one failover, single-flight, Retry-After seconds/date -> monotonic, never shortened by cap, backoff 30..900 s, wall jumps with fixed monotonic, equality-due transitions without busy timer, sleep cancels, wake no bypass, 10 s open-refresh.
- Fingerprint never persisted/displayed; Preferences hold no tokens; 128-row cap emits warning.
- A6 interactive (anchoring, tint both appearances, keyboard, scroll, a11y tree), `--render-demo` PNG inspection; A7 full 10-minute measurement; A9 app-bundle live fetch for each provider: RELEASE gates, unverified until run.
- A1 build/test, A8 docs content, Info.plist LSUIElement, no runtime dependencies in Package.swift, Cursor deferred without stub.
- Claude spend exponent/units (per-object exponent 0...9, no inherited exponent, unverified shapes unknown) and legacy extra_usage with unverified units: needs fixtures once the diagnostics' balance shape for spend is known; omitted to avoid guessing.
