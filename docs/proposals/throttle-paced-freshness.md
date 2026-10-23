# Throttle-paced freshness

Status: proposed, light four-eyes. Discussion P377–P380. Revision 5: revision 1 after one design-review round (codex gpt-6-astra, claude-opus-5-5); r2 changes are not re-reviewed (light mode); r3 added a latch condition found by the implementer; r4 (from the blind test-writer's first delivery) withdrew it in favour of the goal's literal rule, narrowed the in-flight clause so a request can never resurrect a dropped snapshot, and closed O1 at 300 s; r5 (from the change review of candidate 2 and the test-writer's second delivery, operator-approved second fix round) judges "still shown" before the response is applied, excludes the alternate-credential request from the in-flight hold, widens the slack to the real tick gap, and clears the new fields in `stop()`.

## Goal

When the Claude usage endpoint answers a poll with HTTP 429 and a Retry-After, Limitaur honours the deadline and sends nothing before it, but the bar drops the account's last usage after the fixed 90-second freshness window, so during every throttle longer than 90 seconds the Claude bars vanish and return a few minutes later. Observed on 2026-10-22 and 2026-10-23 at 30 s and 45 s cadences: both Retry-After deadlines fell about 100 s after the last successful fetch, so any cadence under about 100 s is throttled and any cadence over 90 s goes stale by itself. Solving the problem means: while an account holds a provider-declared Retry-After, its last snapshot stays in the bar until that deadline plus one poll interval, bounded, with the throttle and the fetch age still visible in the dropdown; every other freshness rule, the request schedule and the Retry-After handling stay exactly as they are.

## Scope

`Sources/LimitaurCore/Monitor.swift` (entity state, the 429 branch, `merge`, `stop()`, the publish path `display()`, `projectDisplay`, the accessibility summary, `ProfileDisplay` and `PresentationCandidate`), `Sources/LimitaurCore/Models.swift` (r5: two constants only, `cadenceTolerance` and `retentionSlack`; `rankMetrics` keeps its 90-second cutoff, which the frozen Python fixture suites pin), `Sources/Limitaur/AppUI.swift` (r5: `scheduleCadence` reads `timer.tolerance` from `cadenceTolerance`), `Tests/LimitaurCoreTests/MonitorTests.swift` (three named assertions only, see R11), README, CHANGELOG, this file. Line budget: 80 lines in Monitor, 100 in new tests.

## Settled constraints

- (operator) The 90-second window stays for every account that holds no provider-declared Retry-After. No snapshot is ever ranked or shown fresh later than 300 s after its fetch.
- (base specification §Scheduling) Request scheduling is unchanged: 45 s nominal cadence, 30 s per-entity minimum, Retry-After and exponential backoff, single flight, no request before `throttleUntil`.
- (AGENTS.md) The 49 frozen independent Python tests and the 42 frozen blind Swift tests under `Tests/LimitaurCoreTests/CredentialRecheck/` are not edited. Other native tests change only where R11 names them.
- (operator) No new tunables, no adaptive cadence, no prediction. `statistics()` and `defaultWorkloadEligible` are not changed.

## Assumptions (designer)

- A1 A provider-declared Retry-After means no newer usage is obtainable before it, so the last values are the best available while the dropdown names the throttle and the true fetch age.
- A2 The observed allowance (about one request per 100 s) is not stable enough to hard-code; the provider's Retry-After is the only reliable pace signal.

## Design

### Entity state

- `retryAfterUntil: TimeInterval?` (monotonic). Set in the 429 branch of `complete()` only when a Retry-After header parses (`retryDelay` returns a value): `max(retryAfterUntil ?? 0, mono + delay)`. Local exponential backoff never sets it. Cleared to nil when a 200 stores a snapshot. `merge` keeps the maximum of both entities' values (nil-aware).
- `retention: TimeInterval?` (monotonic): the latched retention deadline. Latched by `latchRetention(&entity, now:)`, which does nothing unless the entity has a snapshot, `retryAfterUntil` is set, and the snapshot is still shown at that instant (r4: the length of the Retry-After does not matter; a zero or short Retry-After extends to its deadline plus one poll interval exactly like a long one, because the request it allows cannot complete before the next tick; local backoff never counts) (`now < freshnessDeadline(entity)` with the deadline in force before latching); then `retention = min(max(retention ?? 0, retryAfterUntil + retentionSlack), successfulInstant + 300)`, where (r5) `retentionSlack = pollInterval(jitter: 1.5) + cadenceTolerance + 1` = 48.5 s (`cadenceTolerance` = 1 s is the cadence timer's tolerance, defined once in `Models.swift` and used by `AppUI.scheduleCadence`; the extra second covers the re-arm after `refresh()` returns). Called at 429 receipt after `retryAfterUntil` is updated, and after `merge` on the merged entity. (r5) "Still shown at that instant" is judged against the deadline in force before the response was applied: `complete()` captures `shownBefore = freshnessDeadline(entity).map { mono < $0 } ?? false` before it clears `task`, and the 429 branch latches when `shownBefore` is true, so a repeat 429 that completes during the in-flight hold re-latches from the new Retry-After (still capped by the same success). Cleared to nil whenever `snapshot` or `successfulInstant` is replaced or cleared (new 200, detach of the last subscriber, the account-mismatch path, and (r5) `stop()`, which also clears `retryAfterUntil`). `merge`: the entity whose snapshot survives also keeps its `retention`, then `latchRetention` runs.

### Freshness helper

`freshnessDeadline(_ entity: Entity) -> TimeInterval?`:

```
guard let success = entity.successfulInstant else { return nil }
let nominal = success + 90, cap = success + 300
guard let retention = entity.retention, retention > nominal else { return nominal }
let held = min(retention, cap)
if entity.task != nil, !entity.alternateUsed, let retry = entity.retryAfterUntil,
   entity.lastAttempt >= retry, entity.lastAttempt < held { return cap }
return held
```

The in-flight clause keeps a retained snapshot while the request made possible by the throttle deadline is outstanding (it completes within the transport deadline), so cadence phasing cannot blank the bar between the deadline and the response. (r4) It applies only to a request dispatched while the snapshot was still retained (`lastAttempt < held`); a request dispatched after the retention deadline never brings a dropped snapshot back. (r5) It applies only to the post-throttle request itself, never to the alternate-credential request a 401 dispatches in its place (`alternateUsed == false`), since that request did not inherit the throttle deadline's allowance.

### Sites that use the helper (as of commit 92e3e68)

In `display()`: the `.stale` health transition (`age >= 90`, line 1101) and the "Cached usage stale" suffix (line 1110) become `mono >= deadline`; `ProfileDisplay.freshnessDeadline` for alias rows (1117) and primary rows (1126); the ranking proof (1135); the next display deadline (1137–1138). The ranking input: `ages[key] = max(0, age - (deadline - nominal))`, so `rankMetrics` (unchanged, 90-second cutoff) admits the snapshot exactly until the helper's deadline. In `projectDisplay`: the stale test keeps using `freshnessDeadline`; the fetch age uses the new `fetchedInstant` (below). `statistics()` and `defaultWorkloadEligible` keep their own `+ 90` and gates.

### Display types

- `ProfileDisplay` gains `fetchedInstant: TimeInterval?` (monotonic, defaulting to nil). `display()` sets it from `successfulInstant`. `projectDisplay` computes `fetchedAge = monotonicNow - fetchedInstant` when present, else the previous formula. The dropdown's "Fetched Ns ago" is therefore the true age throughout a retention.
- `PresentationCandidate` gains `nominalDeadline: TimeInterval?` (defaulting to nil) set to `successfulInstant + 90`. The accessibility summary labels a selected metric "fresh" while `monotonicNow < nominalDeadline` and "cached" afterwards.
- A throttled row keeps health `.throttled`; the extension never converts health. Only the "Cached usage stale" suffix and the ranking are deferred to the helper's deadline. A transport failure sets `.failed`, other non-success statuses `.unavailable`, as today.

### Timer

The one-shot display invalidation remains the minimum strictly future deadline across all transitions; the helper's result is one of them. It is never later than the cap.

### Success path

Fetch succeeds at T. Tick at T+45 answers 429 with Retry-After 55 s: `retryAfterUntil` T+100, snapshot shown (T+45 < T+90), so `retention` = min(T+148.5, T+300) = T+148.5. Ticks at T+90 send nothing (throttle). The first tick at or after T+100, say T+135, dispatches; `lastAttempt` T+135 ≥ T+100 and `retention` set, so the deadline is the cap while in flight; success at T+136 stores a new snapshot, clears `retryAfterUntil` and `retention`, and freshness restarts from T+136. The bar never blanked; the dropdown showed throttled, "Retry after …", and the true age; the accessibility label said "cached" from T+90.

### Failure path

Same start. If the request at T+135 fails on transport, health becomes `.failed`, `retention` stays but the in-flight clause ends; the deadline is min(T+148.5, cap) = T+148.5, after which the bar drops the snapshot and "Cached usage stale" appears. If instead the T+135 request is throttled again with Retry-After 300 s, `retryAfterUntil` becomes T+435 and, the snapshot still shown, `retention` = min(T+483.5, T+300) = T+300: the bar keeps the snapshot until T+300 exactly, then drops it. A 429 that arrives after the snapshot has already left the bar (for example at T+90.4 after a 500 at T+45 ended the backoff before the T+90 tick) does not latch, so a snapshot never returns to the bar after leaving it.

## Acceptance criteria

- R1 A snapshot fetched at T with no provider Retry-After leaves the bar at exactly T+90 (equality is due) and the row then reads "Cached usage stale".
- R2 Success at T; 429 with Retry-After 55 s at T+45: `selected` is non-empty at T+100 and at T+148; the row's health is `.throttled`, its message contains "Retry after" and not "Cached usage stale" before T+148.5; `fetchedAge` and the projected row's age are the true age (120 at T+120); no request before T+100; the accessibility label for the metric reads "cached" from T+90.
- R3 Success at T; 429 with Retry-After 3600 s at T+30: the snapshot is ranked until exactly T+300 and not at T+300.
- R4 No extension from anything but a parsed Retry-After: a 429 with no Retry-After or an unparseable one (local backoff alone, even past T+90); a 401; a 5xx; a transport failure. In each the snapshot leaves at T+90. (r4) A short Retry-After extends only to its own deadline plus one poll: a 429 at T+70 with Retry-After 5 s whose local backoff reaches T+130 retains until T+123.5, not T+178.5; Retry-After 0 or a past HTTP date at T+70 retains until T+118.5; Retry-After 5 s at T+30 changes nothing (T+83.5 < T+90).
- R5 A snapshot never returns: success at T, 500 at T+45, bar empty at T+90, 429 with Retry-After 100 s at T+90.4: `selected` stays empty. (r4) After retention ends at T+148.5, a request dispatched at T+152 does not bring the snapshot back, nor does a further 429 on that request. (r5) But a request dispatched at T+148 whose 429 with Retry-After 55 s arrives at T+149 re-latches: the snapshot stays ranked until min(T+149+55+48.5, T+300) = T+252.5.
- R6 Phasing: with `retention` T+148.5, a request dispatched at T+148 and still in flight at T+152 keeps the snapshot ranked; its success at T+154 renews freshness from T+154; its transport failure drops the snapshot at T+154. (r5) If that request returns 401 at T+150 and an alternate credential is dispatched, the hold ends with the 401: the snapshot leaves at T+150, not at the alternate's completion.
- R7 A second 429 while retained is capped by the original success (T+300); a 429 after a renewed success is capped by the renewed success.
- R8 The next display deadline is at most the helper's result and equals it when no earlier metric reset or credential expiry exists; a metric whose `resetsAt` passes during a retention leaves ranking at its reset instant.
- R9 Merge: entity A retained with `retryAfterUntil` T+240 merges with entity B whose success at T+60 is newer: the merged entity keeps B's snapshot, `retryAfterUntil` T+240, and a retention latched at the merge, so B's snapshot stays ranked past T+150 and until min(T+288.5, T+360).
- R10 `statistics()` and `defaultWorkloadEligible` are unchanged (eligibility still requires `.healthy` and an elapsed throttle).
- R12 (r5) `stop()` clears `retention` and `retryAfterUntil` together with the snapshot; `cadenceTolerance` is the single source of the timer tolerance (`AppUI.scheduleCadence` uses it) and `retentionSlack` equals 48.5.
- R11 Three existing native assertions pin the old rule for throttled entities and are updated to this rule, minimally and listed in the implementer's report: `accountThrottleAndStaleDisplay` (MonitorTests.swift:210, Retry-After 3600 at +30, expects empty selection at +90), the 429 iteration of `cachedErrorHealthSurvivesFreshnessEqualityWithoutFetching` (MonitorTests.swift:689–716), and `verifiedMergeRetainsMaximumThrottle` (MonitorTests.swift:936, "Cached usage stale" at age 150 with a 600 s Retry-After). Every other native test, the 42 frozen blind tests and the frozen Python suites pass unchanged, three times in a row.

## Non-goals

Adaptive cadence (operator's variant: start at 60 s, +15 s per 429, ceiling 180 s) is declined for this increment: it needs the same freshness change plus ratchet state, a decrease rule and tests, and still wastes one request per step; the provider's Retry-After already carries the pace. Limiting the rule to the Claude provider (reviewer suggestion) is declined: the rule is about a provider-declared Retry-After, not a provider name. Keeping values until a metric's own reset (mac-ai-trackers' rule) is declined: it can show hours-old percentages while usage continues. Per-provider cadence and any request-scheduling change are out of scope.

## Decisions and residuals

- O1 closed (r4): the cap is 300 s.
- Residual (r5, from the change review): macOS App Nap can defer the cadence timer beyond `retentionSlack` for an `LSUIElement` app; a blink then remains possible. Not built against.
- Residual (r4, from the test-writer): the accessibility label changes from "fresh" to "cached" at the nominal deadline, but no display invalidation is armed for that instant; VoiceOver sees the change at the next publish, at most one poll later. Accepted; not built against.
