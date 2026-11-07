> Historical record imported 2026-11-07 from `2026-10-23-throttle-freshness/design-1/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Design review round 1: dispositions (designer)

Members: codex gpt-6-astra 01a167a1-e67b-7962-bb28-058ce8d730d4 (7 findings, 49,231 tokens, cost unreported); opus claude-opus-5-5 24113d63-74cd-472e-a13d-2f9427359e88 ($0.93, 178 s; 3 blockers, 4 major, 5 minor, 1 scope note). Every code claim verified by the designer at 92e3e68.

| Problem | Raised by | Disposition (spec r2) |
|---|---|---|
| `rankMetrics` (Models.swift) drops age ≥ 90 independently; extended proof never consulted; bar still blanks | codex P1 (blocker), opus 1 (blocker) | adopted as both proposed: `rankMetrics` unchanged (frozen fixtures); `display()` passes the age minus the extension; R2 asserts `selected` non-empty |
| `projectDisplay` derives age from deadline − 90, falsifying "Fetched Ns ago" | codex P2, opus 3 | adopted: `ProfileDisplay.fetchedInstant`; projected age from it; R2 asserts the projected age |
| three native assertions pin the old rule (MonitorTests 210, 689–716, 936) | codex P3 (blocker), opus 2 (blocker) | adopted (a): the three assertions are updated and listed (R11); opus (b) "Claude only" declined: the rule is about a provider-declared Retry-After, not a provider name. The r1 "existing native tests unchanged" line was the designer's own mislabelled constraint, not the operator's |
| `throttleUntil` mixes backoff and Retry-After; `.throttled` set without a header | codex P4, opus 4 | adopted: `retryAfterUntil` set only from a parsed header; helper keyed on it, not on health or `throttleUntil`; R4 cases |
| merge copies health from the newer snapshot while keeping the throttle | codex P5 | adopted via provenance: no health gate; `merge` keeps max `retryAfterUntil` and re-latches; R9 |
| a 429 arriving after the snapshot left the bar would bring it back | opus 5 | adopted: retention latched only while the snapshot is shown; R5 |
| cadence timer not phase-aligned to the throttle; blank between deadline and response | opus 6 | adopted: slack `pollInterval(jitter: 1.5)`; in-flight clause holds a retained snapshot until the post-deadline request completes; R6 |
| display timer "equals" wording wrong with earlier resets | codex P6, opus 10 | adopted: minimum of all transitions; R8 |
| `statistics()` edit promises nothing; measurement gates | codex P7, opus 9 | adopted (opus form): `statistics()` and `defaultWorkloadEligible` untouched; R10 |
| site list incomplete (`age >= 90` sites) | opus 7 | adopted: sites listed by line as of 92e3e68 |
| ".stale at extended deadline" invites a health conversion | opus 8 | adopted: throttled rows keep `.throttled`; only the suffix and ranking defer |
| failure path says `.unavailable` for transport failure | opus 11 | adopted: `.failed` |
| accessibility summary says "fresh" for a retained value | opus 12 (hazard) | adopted: `PresentationCandidate.nominalDeadline`; label "cached" past 90 s |
| O1 cap could be 180 s | opus scope note | recorded under O1; 300 s kept as recommendation |

Convergence (light mode, one round): all blockers and majors adopted; the acceptance criteria changed, so r2 is marked not re-reviewed. Residuals: none named.
