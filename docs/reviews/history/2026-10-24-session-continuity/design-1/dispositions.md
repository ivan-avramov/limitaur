> Historical record imported 2026-11-07 from `2026-10-24-session-continuity/design-1/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 1: dispositions (designer: claude-fable-5-1)

Members: codex gpt-6-astra (session 01a16bd3-d84c-7413-bc54-700b79857627, checkout, user instructions loaded; 22 findings, exit 0) and claude-opus-5-5 (session 767e5696-0a64-4e5b-9868-0b1cbbe1a0c5, checkout+web, $1.54, 358 s; 25 findings, exit 0). Dispatched 02:53:27Z, returned by 02:59:26Z. Raw outputs: codex-out.txt, opus-out.json.

Judged from the goal paragraph first; bias to simplification. C = codex finding, O = opus finding.

| # | Raised | Problem | Disposition |
| --- | --- | --- | --- |
| 1 | C1, O1, O2 | Frozen suites break: policy-dependent slack moves the pinned 148.5 s deadline; expiry-triggered re-read fires at t=299 where CadenceTests pins none; a 50 s default suppresses the rig's t=45 request. | Adopted. Slack stays 48.5 constant; expiry no longer inserts recheckDue; the learned gate applies only after the app activates a provider's policy (`setPolling`), so unactivated monitors (all frozen rigs) are unchanged. Not test special-casing: production activation by the app. |
| 2 | C2, O4 | A timeout does not make a background read non-interactive; a dialog can flash for 5 s; locked keychain case. | Adopted as the settled-constraint change shown at Go: timed-out non-interactive read suspends the source until Connect; at most one bounded dialog per source. A-3 marked unverified; probe step 4 observes it. |
| 3 | C3, O6 | `|| recheckDue` bypasses enabled/loading guards; breaks Connect precedence; mislabels a 429 binding as expired. | Adopted: guards unconditional; expiry marking only for isCredentialLess; recheckDue due only when loading is nil. |
| 4 | C4, O7 | Forced drivers bypass the 30 s floor; B5 contradicted B2 and the code. | Adapted: baseline force semantics kept (changing them risks the frozen CredentialRecheck suite); the learned interval gates `.cycle` only; B5 rewritten; the base-spec wording gap recorded as a residual for the operator. |
| 5 | C5, O17 | "Within one tick" overstated; L1/L2 wording wrong. | Adopted: latency stated with the 30 s load cooldown and the throttle; L1 and L2 rewritten. |
| 6 | C6, O5, O25 | Process tree, pipe EOF, PID reuse, orphaned children at quit, inherited descriptors. | Adopted: posix_spawn with setpgroup and cloexec-default, group kill, cancelled escalation, live registry with terminateAll at stop and termination; grandchild tests. Budget raised. |
| 7 | C7, O3 | `outputLimit 0` kills the nudge on its first byte; launch failure unrepresentable. | Adopted: `OutputMode.discard` to /dev/null; `.launchFailed`. |
| 8 | C8, O15, O19, O22 | `security -w` hex-encodes non-printable data; oversize marker lost by newline strip; low-byte 44 ambiguity. | Adopted: hex decode rule (A-6), `oversized` flag, exact 44 only, probe case with two-line JSON. |
| 9 | C9, O16 | Probe byte count 70 is wrong (69), elided payload, no trap cleanup, keychain not named. | Adopted. |
| 10 | C10, O "beyond the goal" | Forgiveness invents causality and confuses entities. | Adopted the simplification: defer `recordThrottle` until the reactive re-read decides (rotation → drop, else record, 60 s fallback). Codex's "no discriminator exists" point is accepted as a bounded residual (A-4): a coincident genuine 429 is ignored once. |
| 11 | C11, O9 | Clean poll undefined; forced 200s and failures counted. | Adopted: clean = decoded `.cycle` 200; every other outcome resets the streak. |
| 12 | C12 | Revert ignores Retry-After. | Adopted: revert to max(from, rounded Retry-After). |
| 13 | C13, O20 | Wall-clock jumps; unordered side effects. | Adapted: explicit evaluation order; backward jumps handled; forward jumps across relaunch recorded as a residual (monotonic cannot persist across relaunch; the harm is one early probe). Declined: monotonic within-run bookkeeping as a second clock — complexity without removing the relaunch gap. |
| 14 | C14 | Persisted decoding must validate nested state. | Adopted (and shrunk by removing forgiveness). |
| 15 | C15, O11 | Nudge keyed per profile; file sources nudged for nothing. | Adopted: `.claudeDefaultDiscovery` only, keyed by source, 600 s spacing dropped, one process at a time. |
| 16 | C16, O10, C22 | `.expired` does not identify the token; 401-paused bindings never nudged; startup-expired case excluded. | Adopted O10 and C22 (O8 at Go): the trigger is "the re-read proved the stored token expired", bound or not, any pause cause. C16's identity check declined: the CLI renews whatever the item holds, identity adds nothing. |
| 17 | C17, O12, O13 | Nudge completion races Connect; task cancel does not stop the child; message guard broken. | Adopted: `nudgeRunning` cleared only by completion; generation and state checks before applying; nudge messages join the paused family in `recheckMessage`. |
| 18 | C18, O14, O24 | HOME is real; flags beyond the literal command; symlink discovery; transcripts written. | Adapted: symlink resolution adopted; flags kept and put to the operator (O7) with L3 confirming them; transcript side effect documented; HOME must stay (the credential lives there) — declined to change. |
| 19 | C19 | A-5 unqualified; dead-refresh-token branch never tested. | Adopted into L3 wording: first case qualified live; second recorded unverified unless it occurs. |
| 20 | C20, O17 | L2 contradicts the controller. | Adopted. |
| 21 | C21, O8, O21 | 10 s tick unmeasured; phase drift with 0.5 s margin; intervals above 90 s blank the bars. | Adopted: gate margin 2 s; L4 re-measures; freshness follows `max(90, interval + 10)` for active policies, put to the operator (O5). Declined: switch to a monitor-owned one-shot timer (would move the scheduler and risk the fake-clock suites); O2 stays an operator question. |
| 22 | O18 | Rotation counter vs resume when no prior binding. | Adopted: `credentialResumes` keeps the no-prior-binding bind. |
| 23 | O23 | Interactive read holds the lock 600 s. | Adopted: non-interactive reads return denied immediately while an interactive read runs. |
| 24 | O "diagnostic" | `--read-keychain-service` reads any service. | Adopted: restricted to the Claude service and `limitaur-probe-*`. |
| 25 | O scope request | README data-boundary sentence about trusting `/usr/bin/security`. | Adopted (documentation). |
| 26 | O "dropdown line" | Changes dropdown the goal keeps. | Kept; operator approved the idea in P407; confirmed at Go (O6). |
| 27 | O24 | Nudge history not persisted. | Declined: one nudge per launch while expired is acceptable; documented. |

Declined blockers or majors shown to the operator: none declined outright; items 4, 13, 18, 21 adapted with the reasons above.
