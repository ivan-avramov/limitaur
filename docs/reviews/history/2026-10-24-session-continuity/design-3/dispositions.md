> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/design-3/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 3 (ceiling): dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16bee-9048-7b91-a689-7bba222a7689; 13 major, 3 minor, 2 scope) and claude-opus-5-5 (session dc376f68-37c2-4f3c-bf3e-976e448eed00, $2.33, 609 s, no web this round; 11 major, 9 minor, 2 scope). Dispatched 03:22:38Z, returned by 03:32:48Z. Revision 4 applies these and is NOT re-reviewed (strict ceiling of three rounds reached).

| # | Raised | Problem | Disposition |
| --- | --- | --- | --- |
| 1 | O1, C2 | Connect clears suspension at admission; a late background timeout re-suspends; concurrent background reads of one service spawn twice. | Adopted: one active read per service under a lock, suspension re-checked after acquiring it; interactive completion (not admission) clears suspension; a background timeout while an interactive read was admitted does not suspend. |
| 2 | O2 | Deny/Cancel (exit 51/128) does not suspend, so the dialog repeats. | Adopted: background exit 51 or 128 suspends too. |
| 3 | O3, C12 | Suspended state has no wording; diagnostic cannot report reasons through `KeychainResult`. | Adopted: internal detailed outcome with a sanitized reason; `loadDetailed` carries `suspended`; own suspended wording; `keychainSuspensions` counter (scope request accepted). |
| 4 | O4 | README exposure sentence unconditional; Always Allow on a `security` dialog widens exposure. | Adopted: conditional sentence and dialog guidance (Allow or Deny, never Always Allow). |
| 5 | O5 | Post-reap group kill may hit a reused pgid. | Adopted: `waitid(WNOWAIT)` observe, group kill, then reap; `.discard` stated. |
| 6 | O6 | Process-wide registry flag and suspension table break parallel tests. | Adopted: injectable instances with a shared default; test seams. |
| 7 | O7, C5, O20 | Snapshot carry across a token change can show another account's usage; existing-entity case undefined; beyond the goal. | Adopted the simplification: carry dropped; baseline throttle-only carry restored; dark bars until the first success recorded as residual. |
| 8 | C7 | `merge()` must carry the freshness horizon. | Adopted. |
| 9 | C6 | Pending-throttle resolution across subscribers with different sources. | Adopted: the pending record carries the failed request's fingerprint; the first completing re-read of a subscriber bound to that fingerprint decides. |
| 10 | O11 | A reduction can land while a 429 is pending. | Adopted: no reduction while the provider has a pending throttle. |
| 11 | O12, O13, O21 | Clean-poll ambiguities; violations at long intervals; B4 wording. | Adopted: forced 200s neither count nor reset; 429 at receipt does not reset; alternate-credential dispatch never counts; violations statement; wording fixed. |
| 12 | O14 | Signal-killed child reads as exit 0. | Adopted: `exitCode nil` when signalled. |
| 13 | O15 | Nudge outcome ignored while asleep leaves "Running claude…" forever. | Adopted: message transitions apply while asleep. |
| 14 | O16, C8, C17 | No-op guard needs an expired-token fingerprint the loader lacks; attempt times unclamped; nudge overwrites mismatch wording. | Adopted: the three-no-op stop is dropped (O12 removed); attempt times clamped; nudge messages only replace the paused/expired family. |
| 15 | O17, C10 | Group kill after normal exit hurts `claude`'s children; auto-updater; proxies dropped; neutral failure wording; unregistered child outlives its supervisor at quit. | Adopted: no post-exit group kill for unregistered children; `DISABLE_AUTOUPDATER=1`; neutral wording; quit waits up to 5 s for a running nudge then leaves it (residual). Proxies: declined, documented as unsupported for the nudge (the settings `env` block cannot be loaded without loading hooks). |
| 16 | O18, C4 | `-a` retry may bind a stale item; exit 44 may be a search failure. | Adopted: single read with `-a $USER`, no retry; probe gains a not-found case; search-failure ambiguity recorded as residual. |
| 17 | O19 | Counters in the wrong part; "behaves exactly as today" contradicted by A4. | Adopted: counters moved; reactive re-read gated by a `Monitor.init(reactiveRecheck:)` flag the app enables, so unactivated monitors truly behave as at baseline. |
| 18 | O9, C1 | Tick quantization makes the 30 s floor 30–40 s; forced drivers bypass the floor. | Adapted: cycle gate `max(30, interval) − 1.5` with the 28.5 s worst case stated and put to the operator (O10 extended); forced-driver floor stays O10; L4 at 30 s declared a smoke unless 18 polls are reached. |
| 19 | C3 | Whole-lookup deadline; ordering of timeout/oversize before exit status. | Adopted (one child per read now; ordering stated). |
| 20 | C9 | Attempt persisted after launch; wall-only hourly check. | Adopted: publish before launch, app stores on apply; monotonic in-run check plus persisted wall time; restore only into an empty map. |
| 21 | C11 | Executable search path and working directory not secured. | Adopted: candidate directory ownership/permission check; symlinked work directory rejected; resolved file spawned. |
| 22 | C13 | Hex transport bound off by one; non-ASCII untested. | Adopted: 2 MiB + 2; probe non-ASCII case. |
| 23 | C14, O8 | L1 promises detection without a trigger; old token may stay valid until expiry. | Adopted: L1 bound from the triggering failure or the old expiry; rewrite-to-detection measured separately. |
| 24 | C15 | Logout does not test a dead refresh token. | Adopted: dropped; branch recorded unverified. |
| 25 | C16 | Attribution narrowing; "once" claim. | Adopted. |
| 26 | C18 (scope) | Memory files and imports enter the nudge's context. | Recorded for the operator (O13); declined for this run. |
| 27 | O10 (fleet) | Five machines can provoke up to five 429s a day. | Recorded for the operator (O14); L2 on two machines. |
| 28 | O20 (one-shot timer) | Would avoid tick quantization. | Declined again (scheduler ownership); O2 stands. |
