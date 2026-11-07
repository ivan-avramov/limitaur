> Historical record imported 2026-11-07 from `2026-10-25-hygiene-h1/design-review/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# H1 design review round 1 dispositions (2026-10-25)
Members: codex gpt-6-astra 01a17440-25e0-7032-a2ba-ed3af803400f; claude-opus-5-5 3054528e-0af8-4727-8722-cab18ce70eb9 ($1.90). Checkout at c454fac + spec r1.
- codex P1/P2/P3, opus 6/7/8 (P385: in-flight cap, later latches, detach, wrong site list, bind-clearing claim): ADAPTED by rewrite: one state-based read-time rule (every subscriber auth-paused with a pauseCause -> nominal deadline) at freshnessDeadline and its three callers; auth transitions explicitly unchanged; Connect pause excluded; bind-clearing sentence corrected.
- codex P4 (AC1 fixture impossible with codex at 90 s): ADOPTED: both policies 120 s; validUntil asserted.
- codex P5, opus 1 (plist key blocks other user sessions; not needed): ADOPTED: key and build assertion dropped.
- codex P6, opus 2 (exclusiveLock collapses busy/failed; default -1): ADOPTED: dedicated takeInstanceLock with acquired/held/unavailable.
- codex P7, opus 3 (existing directory unvalidated; fail mode): ADOPTED nudge's directory rules; DECIDED fail-open on unavailable (guard is not a security boundary), residual named.
- opus 4 (README measurement procedure): ADOPTED one README clause.
- opus 5 (lock after argument checks; quit window): ADOPTED; residual named.
- codex P8 (docs: exact formula, 18->10, threshold unreachable at 120 s): ADOPTED, threshold unchanged.
- codex P9, opus 9 (R-C11/P353 partial; AC6 re-read; racy toggle read): ADOPTED: labelled partial, rest stays in backlog; AC6 includes re-read; bounded poll; menu rebuilt per toggle.
- Sensitive area (both): P385 near auth branches: kept light because the rule is read-time and transitions are unchanged; change review to diff the auth branches for control-flow changes.
