# AdversarialBars Phase A plan (reviewer 1, candidate-blind)

STATUS: authored text only; NOT YET WRITTEN OR RUN by the author. The driver materializes these bytes, runs them on the documentation-only baseline (expected: truthful binary-unavailable failures), then freezes and hashes before any candidate disclosure.

Run: LIMITAUR_BIN=<production executable> python3 -I -m unittest AdversarialBars/test_acceptance.py
Absent or unusable LIMITAUR_BIN fails every test, never skips. Offline, fabricated values, temp files under TMPDIR.

## Confirmed contract used
- Rank fixture: JSON array of {providerID, accountID, fetchedAt, metrics:[{id, label, usedPercent, resetsAt optional}]}, times in Unix seconds. Invocation: --rank-fixture PATH --now EPOCH [--count N], with --count appended after --now. No flag-order test.
- Default count 3; valid count integer 1..8; invalid count exits 2 with a fixed diagnostic and no JSON on stdout.
- Output: JSON array of {providerID, accountID, id, usedPercent}.
- --inspect-fixture claude|codex PATH returns {providerID, metrics, balances, informationalAmounts, resetCredits, partial, warnings}. Claude input is the raw direct-response shape from the specification.
- --check-percent VALUE returns JSON with severity and fill. Only equality/inequality of severity values is asserted, never level names.
- Incomplete means partial == true or nonempty warnings. Warning text is never asserted.

## Black-box tests (18 methods)
Class: REQ-FIX = reproduces a required-fix failure; INV = preserves invariant; NEW = new behavior.

| Test | Class |
|---|---|
| default_is_three | INV |
| counts 1,3,5,8 sizes and prefix consistency with N=8 | NEW |
| fewer than N returns all, no padding | NEW |
| zero eligible returns empty array | NEW |
| invalid counts (0,9,-1,abc,1.5,empty,huge,3x): exit 2, no stdout JSON, identical non-echoing stderr | NEW |
| lexical tie-break providerID/accountID/metricID across accounts | INV |
| stale boundary 89 in, 90 and 500 out; stale high values do not block fresh fill | INV |
| reset equality: resetsAt <= now excluded, now+1 and absent kept, siblings kept | INV |
| over 100 keeps raw value and outranks 100 | INV |
| unknown (null/missing/negative/string) excluded; known 0 kept as 0 | INV |
| exact duplicate identity once; same id on distinct accounts kept; output fields | INV |
| modern enabled spend with invalid percent is incomplete, quota kept | REQ-FIX |
| legacy enabled extra_usage with invalid utilization is incomplete, quota kept | REQ-FIX |
| enabled missing percent: no synthesized 0, incomplete | REQ-FIX |
| empty modern limits does not hide malformed enabled spend | REQ-FIX |
| disabled spend with zero used stays healthy, no metric | INV |
| valid extra_usage percent with null units invents no currency; amount-only spend adds no fake percent or foreign currency | NEW |
| check-percent edges 80/80.01/95/95.01 and fill clamp 150 == 100 | INV |

Deliberately not asserted: whether valid amount-only enabled spend is partial (specification ambiguous); disabled spend with a malformed percent; exact warning text; label/ID formats; internal source structure.

## Phase B source-review checklist (not provable with the approved diagnostics)
Static inspection is not behavior proof. Require native test seams with spies and fake clocks, and confirm tests exercise production code paths.

1. Count action routing: the production Indicators action with an eligible account, an in-flight shared request and an active throttle causes zero credential reads, zero HTTP calls, no manualRefresh, no saveProfiles()/setProfiles(), and no change to epochs, generations, auth pause, throttle or cache. Only the presentation integer is persisted.
2. Demo isolation: every reachable action (Settings, Accounts, Save, Add, Refresh, Connect, count) uses in-memory preferences and the synthetic backend. Spies fail on any real preference, credential or transport access. The production demo wiring is tested, not a detached helper. Accounts and Connect are disabled.
3. Rapid and deliberately reordered async count changes end at the latest N on the main actor; display revisions reject older results.
4. Delayed publication: advance a fake clock through freshness 90s and reset equality, then raise N. No expired candidate appears or is labelled fresh; unavailable slots show while the local query refills.
5. Delayed stream and local-query delivery for an expired account outside both N and the eight candidates, while another provider fills N: bars, dropdown, health marker, tooltip and accessibility text all come from one projection and one clock sample.
6. Deadline crossed between display construction and arming, with no other event: corrected publication, no fetch, one coalesced local revalidation, only strictly future arming, no immediate recursive or repeating timer.
7. Sticky reset-due latch: forward past reset, then wall clock backwards, with delayed publication and no successful fetch. The metric stays reset-due and unranked in bars, dropdown and accessibility. A late observation carrying an old snapshot generation cannot affect a replacement snapshot or another binding. Latches are bounded and cleaned on replacement, detach and quit. Successful replacement clearing is tested separately.
8. Dropdown signature covers per-metric reset-due, balance expiry and reset-credit detail expiry. The equality transition re-renders with unchanged snapshot bytes and fetched-age minute bucket. No zeroed balance, no decremented authoritative or capped count; unknown expiry stays unknown; a backwards clock does not revive expired items; no new per-second timer or network work.
9. Snapshot freshness equality marks a previously healthy cached profile stale even when other providers fill all N slots, preserves existing auth/error status, and covers aliases and empty-metric snapshots.
10. Huge Retry-After (for example 1e308): monotonic deadline is uncapped, the display date is guarded with a fixed unavailable label, no crash.
11. Production willPerformHTTPRedirection callback with nil request, plus the 3xx rejection and policy function; wire/TLS/cookie/cache behavior stays reported as unverified offline.
12. Canonical display constructor guarantees selected == candidates.prefix(3) metrics; the compatibility initializer yields unavailable validity for live presentation; maximumCount outside 1..8 falls back to 3 with no unchecked negative prefix; persisted invalid or missing counts fall back to 3.
13. Single status button owns clicking and the only accessibility summary; the drawing view is not an accessibility element; the health marker has reserved room and cannot overlap the last bar at counts 1, 3, 5 and 8; LSUIElement and accessory activation policy intact.
14. Enabled spend/extra_usage warning fix in the decoder matches the black-box cases above across modern and legacy forms.
15. Frozen old suites unchanged; no added polling, animation, timers beyond the one-shot scheduler, or helper processes; provider/auth/HTTP policy unchanged.
16. Manual release gates (actual-app anchoring, appearance and increased contrast, keyboard, scrolling, accessibility tree, Claude app-bundle access, sustained performance) are reported as unverified unless actually run.
