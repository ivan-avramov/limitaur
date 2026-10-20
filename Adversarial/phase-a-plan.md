# Phase-A preregistration for phase-B review

This document was written before any candidate implementation was available.  It
does not report execution or acceptance.  The Python suite covers only the
documented fixture, percentage, and ranking diagnostic surfaces.  The invariants
below cannot be established through those surfaces and therefore require both
source review and production-core Swift tests in phase B.

All tests must use invented credentials, injected stores/transports/clocks, and a
network- and credential-denying environment.  No test may print token bytes,
fingerprints, account identifiers from a real session, or raw responses.

## Scheduler and shared-state invariants

1. **Single flight and entity ownership.** Two aliases with the same effective
   provider, credential fingerprint, and selected account context produce one
   shared entity and at most one in-flight request. Two Codex profiles using the
   same token but distinct selected account IDs remain separate until verified
   provider identity permits an atomic merge. Distinct Claude credentials never
   merge merely because responses omit account identity.
2. **Subscriber generation and request epoch.** A completion or error captured
   before disable, source change, token rotation, account switch, sleep, or last
   subscriber detach cannot update a detached profile, a replacement generation,
   or another account. Detaching one alias neither cancels nor invalidates work
   needed by another current subscriber. Detaching the last subscriber cancels the
   task and increments the epoch.
3. **Merge behavior.** When verified provider identity permits an account merge,
   the merge is atomic, retains the latest applicable cache, uses the maximum of
   every throttle deadline, has one in-flight guard, and never publishes a result
   to an identity-incompatible subscriber.
4. **Throttle persistence.** A 429 deadline survives all aliases detaching and
   reattaching. Manual refresh, dropdown-open refresh, wake, source change, and
   provider enable cannot bypass it. A genuinely different account/source has
   independent state.
5. **Authentication isolation and bounded failover.** A 401/403 pauses only the
   credential binding that sent the request, rejects late results from that
   invalidated binding epoch, and permits at most one already-bound eligible
   alternate in a nominal refresh cycle. Selection is lexical by stable binding
   identity, not display label. No concurrent or unbounded failover occurs.
   Detaching the failed source leaves valid subscribers eligible; an auth failure
   never contaminates a distinct credential.
6. **Token rotation.** A changed fingerprint invalidates usage for that source
   binding until identity is re-established, does not expose or persist the
   fingerprint, and does not discard unaffected subscribers' state. A validated
   change or explicit reconnect may clear auth pause; an ordinary timer may not.
7. **Cadence and triggers.** Launch, wake, enable, and dropdown-open when the last
   successful fetch is older than ten seconds request refresh subject to
   single-flight and all deadlines. Nominal polling is 30 seconds with bounded
   jitter and timer tolerance. Sleep and quit cancel work; wake coalesces triggers
   and does not bypass throttling. Providers remain independent after failure.
8. **Backoff calculations.** Consecutive failures establish 30, 60, 120 seconds
   through a 15-minute maximum. A valid positive Retry-After delta or date is
   never shortened by the exponential cap. Invalid/missing Retry-After selects
   exponential backoff. Absolute Retry-After is converted once using the receipt
   wall/monotonic pair, retains its wall date for display, and subsequent wall
   jumps cannot shorten its monotonic minimum.
9. **Independent clocks.** Advancing wall time alone processes absolute provider
   reset/display transitions but cannot expire a monotonic request deadline or
   throttle. Advancing monotonic time alone processes freshness, deadline, and
   backoff without changing absolute reset truth. Forward/backward clock-change
   notifications and wake process all transitions due at equality and arm only a
   strictly future deadline.
10. **Freshness and retained failures.** Freshness is exactly
    `monotonicNow < successfulFetchInstant + 90 seconds`; a reset is valid exactly
    while `wallNow < resetsAt`. Fetch failure immediately degrades health while a
    previously fresh metric remains rankable only to its boundary. It then stays
    visible as stale in the dropdown and leaves ranking. Schema failure preserves
    the previous snapshot under the same rules.
11. **No busy display loop.** The coalesced display invalidator chooses the
    earliest future monotonic freshness or converted absolute-reset deadline,
    processes every due transition, and never rearms an immediate timer for an
    already expired item. Repeated reevaluation during long backoff does not spin.
    With the dropdown closed there is no per-second timer; reset text updates at
    most once per minute while open. Rings redraw only when display state changes.

Phase-B evidence: inspect entity/key/generation ownership and timer code; run
deterministic Swift tests with fake wall and monotonic clocks, controllable
continuations, and a recording transport. Tests must explicitly cover late success
and late error for every detach/switch case, both clock directions, equality, and
repeated reevaluation.

## Credential and account-boundary invariants

1. **One-descriptor file read.** The production reader opens only an explicitly
   configured/default absolute path using `O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC`,
   applies `fstat` to that descriptor, requires a regular file no larger than one
   MiB, and bounded-reads the same descriptor with a one-MiB-plus-one limit. It
   never validates and reopens by path.
2. **Adversarial filesystem objects.** Production-reader tests cover a regular
   temporary file, missing/unreadable file, malformed JSON, one-byte-over-limit
   file, leaf symlink, FIFO with no writer (prompt rejection), directory/device,
   and path replacement after open. Parent-directory symlinks remain allowed for
   the operator-selected path. Errors contain neither content nor credential-like
   substrings.
3. **Source selection and Keychain state machine.** An explicit Claude file never
   consults Keychain. Default discovery falls back to the default file only for
   item-not-found, never denial, lock, interaction-required, or malformed
   Keychain data. Keychain lookup disables authentication UI and does not repeat
   prompts. All accesses are read-only.
4. **Strict credential decoding.** Claude accepts only a nonempty
   `claudeAiOauth.accessToken`; expiry is absent/null or a nonnegative finite
   integer in Unix epoch milliseconds divided exactly once by 1000. Boolean,
   string, fraction, negative, nonfinite, and overflow expiry fail without unit
   guessing. Known expiry `<= now` prevents a request. Codex accepts nonempty
   `tokens.access_token` and `tokens.account_id` in ChatGPT-token mode and never
   treats API-key-only data as subscription authentication. Refresh tokens are
   ignored.
5. **Account binding.** A configured expected Codex account mismatch is rejected
   before transport invocation. Returned provider identity mismatch is rejected.
   A Claude response without account identity is bound only to its selected source
   plus an in-memory token fingerprint and is never described as provider-verified.
   Duplicate identities share usage while aliases remain separately visible.
6. **Secret noninterference.** Token bytes cannot enter URLs, argv, snapshots,
   descriptions, logs, thrown errors, preferences, fixture diagnostic output, or
   app-owned files. Fingerprints cannot be persisted or displayed. Tests use a
   unique invented sentinel and scan every normalized value, error description,
   captured log, and preference serialization for the sentinel without printing
   it on failure.

Phase-B evidence: source-review the POSIX flags and descriptor lifetime, Security
framework options and branching, decoder types, preference schema, and all
description/log paths. Run production-reader and injected-Keychain Swift tests;
do not substitute a fake file reader for filesystem race tests.

## HTTP data-boundary invariants

1. Requests permit only the two fixed HTTPS origins and fixed paths in the
   specification, reject all redirects before following them, and allowlist only
   Authorization, provider account, Accept, User-Agent, and anthropic-beta headers.
   Credentials never enter a URL.
2. The production ephemeral URLSession disables cookies, persistent cache, and
   credential storage and wires a 15-second request/resource deadline plus
   cancellation. No automatic retry occurs.
3. The production bounded accumulator rejects the byte that would exceed one MiB
   even when Content-Length is absent, false, or split over many chunks. It also
   rejects an oversized declared response without relying on that declaration for
   enforcement.
4. Offline production-policy tests exercise redirect-decision callbacks,
   incremental accumulation, timeout/cancellation wiring, status mapping,
   Retry-After delta/date parsing, and request construction. Any URLSession
   behavior that cannot be exercised via URLProtocol or direct delegate calls is
   named explicitly as unverified rather than inferred.

Phase-B evidence: source review plus production URLSession policy/delegate and
accumulator tests. No localhost listener or real network is necessary or allowed.

## Other evidence gates retained for phase B

- `--render-demo` must be checked as an actual AppKit render in light and dark for
  the 25/85/98 and empty/stale examples, then compared with live view code. Static
  PNG evidence does not establish real status-item anchoring, semantic tint,
  keyboard behavior, scrolling, or changing accessibility labels; those require
  the separately recorded interactive checks in A6.
- `--check-live` is not an offline phase-A test. App-bundle invocation must be run
  separately for Codex and Claude with production adapters and report only status,
  metric counts, and metadata availability. Driver probes are not substitutes.
- The full 60-second warm-up plus 600-second resource workload, refresh counts,
  outcome classes, descendant accounting, two-second RSS samples, and cumulative
  CPU accounting remain required. Short runs are labelled smoke/idle only.
- Documentation, packaging, SDK/deployment target, LSUIElement behavior, absence
  of runtime dependencies, and the complete Swift test suite require direct
  phase-B inspection and execution. None is implied by the Python diagnostics.
