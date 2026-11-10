# Cursor provider (addendum)

Status: approved addendum to `docs/specification.md`, built through four-eyes (strict: credential source and data boundary). Operator approved scope P1–P7 on 2026-11-10 ("p1-p7 sound good"), dispatch at Go ("approved") and the result ("accepted"). It supersedes the baseline clauses listed under "Baseline amendments"; the designer, not the implementer, edits `docs/specification.md` and `AGENTS.md` to record it.

Revision 3 (after change review) adds the I5.6 unknown-spend rule, the 35-second `--check-live` wait and R7–R8. Revision 2 applies the design-review findings (cold opinion, 2026-11-10), not re-reviewed. Its main change, the self-scoped endpoint replacing `GetTeamSpend`, follows a reviewer's proposal to use a self-only endpoint.

## Goal

Limitaur monitors Claude and Codex subscription usage only. The operator also uses Cursor on an Enterprise team plan billed by token spend against a per-user monthly spend limit, and wants that spend shown in Limitaur beside the other providers. Solving it means: Limitaur reads the existing cursor-agent session on this machine read-only, fetches only the operator's own spend from Cursor, and shows one ranked `CU` / `$` bar (spend ÷ effective per-user limit, resetting at the end of the billing cycle), with the same unknown, stale, authentication-pause and re-check semantics as the existing providers, without requesting other team members' data.

## Scope

- Provider ID `cursor` with one credential source, `CredentialSource.cursorDefaultDiscovery`.
- Credential loading, a Cursor adapter making two fixed requests, decoding, Settings ("Add Cursor"), polling persistence and `--check-live`.
- Implementer docs: README, `docs/providers.md`, CHANGELOG Unreleased entry. Designer docs after acceptance: `docs/specification.md` amendments, `AGENTS.md` addendum list, "Cursor deferred" statements in `docs/handoff.md`, `docs/compact-bars.md`.

Line budget: about 250 product lines (Swift under `Sources/`), about 250 test lines, docs extra.

## Settled constraints

- S1 (operator, P1): token from the Keychain item service `cursor-access-token`, account `cursor-user`, through the existing `/usr/bin/security` helper reader, never an in-process Keychain API. (P1's identity file is no longer needed.)
- S2 (operator, P2, narrowed by review): only fixed Cursor endpoints; none that returns other members' data.
- S3 (operator, P3): one metric, spend ÷ effective per-user limit; window code `$`; reset at the cycle end; the dropdown shows spent and limit amounts.
- S4 (operator, P4): an "Add Cursor" button in Accounts; existing saved profiles are not migrated.
- S5 (designer default, stated to operator as P10): the existing learned polling policy applies unchanged.
- S6 (designer default, P12): no expiry nudge for Cursor. Expired or rejected sessions pause and recover through the existing five-minute re-check after `cursor-agent login` writes a new token.
- S7 (designer default, P13): on-demand usage beyond the limit is not shown.
- S8 (repository): AGENTS.md: no credentials or raw responses printed, persisted, committed or transmitted; read-only authentication; zero runtime dependencies; unknown versus zero distinct.
- S9 (operator, Go 2026-11-10 "approved", on the designer's recommendation P17): amounts are labelled `USD` although the response carries no currency (see A1); a deliberate exception to the baseline currency rule.

## Assumptions (designer)

- A1 Amounts are US cents. The schema field is `spend_cents`, Cursor's dashboard shows `$`, and the limit matched the dashboard's spend limit. No currency field exists.
- A2 Responses use proto3 JSON mapping: int64 fields as decimal-digit strings, int32 as numbers, unset or empty fields omitted. The schema in the Cursor app bundle types `DailySpendPoint.spend_cents` as int32, `day` as int64, `effective_limit_cents` as optional int32.
- A3 The daily sum over the billing cycle is what the dashboard's "Personal Usage → Cumulative Spend" chart plots against "Spend limit".

## Supported conditions and data formats

Observed on this machine on 2026-11-10 (macOS 26, cursor-agent session, Enterprise team, caller role member). The values below are synthetic.

Keychain: `security find-generic-password -s cursor-access-token -a cursor-user -w` prints an ASCII JWT of about 400 bytes on one line. Its base64url payload is JSON with a numeric `exp` (Unix seconds). It is read without a dialog.

Requests: both are `POST`, with the headers `Authorization: Bearer <token>`, `Content-Type: application/json`, `Accept: application/json` and `User-Agent: Limitaur/1`.

1. `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentBillingCycle`, body `{}`. Response: `{"startDateEpochMillis":"1700000000000","endDateEpochMillis":"1702592000000"}`.
2. `https://api2.cursor.sh/aiserver.v1.DashboardService/GetDailySpendByCategory`, body `{"periodStartMs":"<start>","periodEndMs":"<end>"}` (no team or user ID, so the caller's own spend). Response:

```json
{"dailySpend":[{"day":"1700000000000","category":"model-a","spendCents":1200,"totalTokens":"34000"},
               {"day":"1700086400000","category":"model-b","spendCents":2900,"totalTokens":"81000"}],
 "categories":["model-a","model-b"],
 "effectiveLimitCents":500000}
```

Observed behaviour:
- A period with no spend returns only `{"effectiveLimitCents":…}`.
- An inverted period is accepted with HTTP 200, so Limitaur validates the period itself.
- An invalid or absent token returns HTTP 401.
- Both responses are about 1 KiB.

## Interfaces

I1 `CredentialSource.cursorDefaultDiscovery`; `stableID` `"cursor:default"`. Exhaustive switches treat it as having no configured path.

I2 `CredentialStore` gains `cursorKeychain: any KeychainReading`, defaulting to `SecurityToolKeychainReader(service: "cursor-access-token", account: "cursor-user")`, and injectable like `keychain`. `loadDetailed(.cursorDefaultDiscovery, now:, interactive:)` works as follows:
1. Read with the given `interactive` flag. `.found` sets `viaKeychain`. `.notFound` throws `.missing`, with no file fallback. `.denied` follows the existing suspended, busy and `keychainDenied` path.
2. The token is the found bytes as UTF-8 (`classify` already strips one trailing newline). It must be 1…8192 bytes long with every byte in 0x21…0x7E; otherwise throw `.malformed`.
3. Expiry. When the token has exactly three `.`-separated parts, the middle part base64url-decodes (padding optional) to a JSON object, and its `exp` is a non-boolean number with an integral value in 0…8_640_000_000_000, then `expiresAt` is that instant. Otherwise `expiresAt` is `nil`. If `expiresAt <= now`, throw `.expired`.
4. Return `Credential(accessToken: token, selectedAccountID: nil, expiresAt:)`. Binding, entity grouping and alias rules are those of a Claude Keychain credential (source plus token fingerprint).

I3 `CursorOperation: Sendable, Equatable` is either `.currentBillingCycle` or `.dailySpend(startMs: String, endMs: String)`. `HTTPRequest` gains `cursorOperation: CursorOperation?`, defaulting to `nil`; existing initialisers and call sites are unchanged. `RequestPolicy.makeRequest` behaves as follows:
- For `cursor` it sends `POST` to the operation's fixed URL above, with the four headers and the body above built with `JSONSerialization`.
- It throws `TransportFailure.unsupportedProvider`, sending nothing, when `cursor` has no operation or when `startMs` or `endMs` is not 1…16 ASCII digits.
- Codex and Claude requests are unchanged (GET, no body).
- Redirect rejection, timeouts, the ephemeral session and the 1 MiB streaming bound per response apply to each request unchanged.

I4 `CursorUsageAdapter: ProviderAdapter` (`id` `"cursor"`) replaces `DirectUsageAdapter(id: "cursor")` in the default registry. `request(credential:transport:)` works as follows:
1. Send `.currentBillingCycle`. A non-200 response is returned as is, with its status, headers and body.
2. Parse that body as a JSON object whose `startDateEpochMillis` and `endDateEpochMillis` are 1…16-digit strings or integral non-negative numbers. Start must be less than end, and end minus start at most 62 days. Otherwise throw `CursorAdapterFailure.invalidCycle`; the monitor's existing error path treats it as a failure.
3. Send `.dailySpend(startMs:, endMs:)` with those values as digit strings. A non-200 response is returned as is.
4. Otherwise return `HTTPResponse(status: 200, headers:` of the second response`, body:)`. The body is the JSON object `{"billingCycle": <first body object>, "dailySpendByCategory": <second body object>}`. A second body that is not a JSON object throws `invalidCycle`.

`fetch` maps outcomes as `DirectUsageAdapter` does. No retries; at most two requests per call.

I5 `UsageDecoder.decode(provider: "cursor", …)` takes the I4 envelope:
1. `billingCycle` start and end are validated as in I4.2. `dailySpendByCategory` must be an object. Either failing throws `invalidEnvelope`.
2. `dailySpend`: absent means no rows. Present, it must be an array of at most 4096 objects; otherwise throw `invalidEnvelope`.
3. Each row needs a `spendCents` that is a non-boolean integral number in 0…2^31−1, or absent (meaning 0). Its `day`, as a digit string or integral number, must satisfy start ≤ day < end. Any violation throws `invalidEnvelope`; there are no partial sums. `category` and `totalTokens` are ignored.
4. `spent` = the sum of `spendCents` as `Decimal`. With validated rows and the limit present, an empty or absent list is a known 0.
5. `effectiveLimitCents` present and a positive integral number gives:
   - one `UsageMetric(id: "spend", label: "Monthly spend", usedPercent: spent ÷ limit × 100, resetsAt: end)`, with no `windowDuration` (so `windowCode` is `$`); values above 100 are kept raw;
   - `informationalAmounts` `"Spent this cycle"` = spent ÷ 100 and `"Spend limit"` = limit ÷ 100, both in `USD` (S9).
6. `effectiveLimitCents` absent gives no metric, `partial`, and the warning `"Spend limit unavailable"`. Present and 0 gives no metric, `partial`, and the warning `"Spend limit is zero"`. Present in any other form throws `invalidEnvelope`. "Spent this cycle" is listed in both cases only when `dailySpend` is present; with neither `dailySpend` nor a limit, spend is unknown and no amount is listed.
7. `providerID` is `"cursor"`. Category names, token counts and day buckets do not enter the snapshot; warnings are fixed strings.

I6 Monitor: `sourceMatches` accepts `("cursor", .cursorDefaultDiscovery)`. `reconnect` reads `.cursorDefaultDiscovery` interactively, as it does `.claudeDefaultDiscovery`. Nothing else changes; the nudge stays limited to `.claudeDefaultDiscovery`.

I7 App:
- Accounts buttons, in order: Save, Cancel, Add Codex, Add Claude, Add Cursor. Each `NSAlert` result maps explicitly: `.alertThirdButtonReturn` → codex, `.alertThirdButtonReturn + 1` → claude, `+ 2` → cursor. Any other result changes nothing. "Add Cursor" appends `AccountProfile(id: UUID, providerID: "cursor", label: "New account", source: .cursorDefaultDiscovery, enabled: false)`.
- A Cursor row shows the source popup with the single item "cursor-agent sign-in" and an empty, disabled path field. Save keeps that source and skips path validation.
- The informative text adds: "Cursor reads the cursor-agent sign-in; run cursor-agent login when it expires."
- Fresh-install defaults stay Codex and Claude. Polling persistence loads `["claude", "codex", "cursor"]`.

I8 `--check-live` adds `cursor`, sending through `registry.adapter(for:)?.request` for every provider (or an equivalent that sends both Cursor requests), and decodes with `accountID: credential.selectedAccountID ?? "local"`. The overall wait is 35 seconds (two sequential 15-second requests plus margin). The output fields are unchanged.

## Signatures (exact)

```swift
// LimitaurCore
public enum CredentialSource { …existing…; case cursorDefaultDiscovery }
public enum CursorOperation: Sendable, Equatable { case currentBillingCycle; case dailySpend(startMs: String, endMs: String) }
public enum CursorAdapterFailure: Error, Sendable, Equatable { case invalidCycle }
public struct HTTPRequest { public let cursorOperation: CursorOperation?
    public init(providerID: ProviderID, bearer: String, accountID: AccountID?, cursorOperation: CursorOperation? = nil) }
public struct CredentialStore { public let cursorKeychain: any KeychainReading
    public init(files: any CredentialFileReading = SecureFileReader(), keychain: any KeychainReading = SecurityToolKeychainReader(),
                cursorKeychain: any KeychainReading = SecurityToolKeychainReader(service: "cursor-access-token", account: "cursor-user")) }
public struct CursorUsageAdapter: ProviderAdapter { public init() }   // id == "cursor"
// ProviderRegistry() default list: DirectUsageAdapter("codex"), DirectUsageAdapter("claude"), CursorUsageAdapter()
// Cursor reads use KeychainReading.claudeCredentialDetailed(interactive:) on cursorKeychain (the protocol is not renamed).

// Limitaur (executable target, internal, testable)
func addedAccountProfile(for response: NSApplication.ModalResponse, id: String) -> AccountProfile?
// .alertThirdButtonReturn → codex default-path profile; rawValue + 1 → claude .claudeDefaultDiscovery; rawValue + 2 → cursor
// .cursorDefaultDiscovery; label "New account", enabled false, the given id; any other response → nil. showSettings uses it.
```

## Baseline amendments (designer records after acceptance)

`docs/specification.md`, "HTTP and credential boundary":
- Add the two fixed Cursor URLs.
- Allow `POST` with the I3 JSON bodies for Cursor only.
- Add `Content-Type` to the header allowlist for Cursor only.
- Add the `cursorDefaultDiscovery` source with its Keychain item and no file fallback.

Currency (S9): amounts are labelled USD by operator decision, without a provider-supplied currency. `AGENTS.md`: list this addendum.

## Traced paths

Success:
1. A load reads a token whose `exp` is in the future.
2. The binding gets entity key `cursor|<fingerprint>|source:cursor:default`.
3. The first POST returns cycle 1700000000000…1702592000000.
4. The second POST returns two rows summing to 4100 cents, with limit 500000.
5. The envelope decodes to metric `spend` 0.82 %, reset 2023-12-14T22:13:20Z, and amounts 41 and 5000 USD.
6. The bar shows `CU` over `$`.

Failure (rejected token):
1. The first POST returns 401.
2. The adapter returns it.
3. The existing 401 path pauses the profile.
4. The re-check every five minutes re-reads the Keychain.
5. A new token (`cursor-agent login`) resumes the profile. No `claude` nudge starts.

Failure (invalid period from server): `endDateEpochMillis` ≤ start throws `invalidCycle` before the second request. The entity fails and backs off, and the last good snapshot is kept until it goes stale.

## Acceptance criteria

C1 The existing suites pass unchanged (`swift test`). Codex and Claude request construction is unchanged.

C2 Credential:
- A found JWT with a future `exp` yields the I2 credential.
- A non-JWT token yields `expiresAt == nil` and succeeds.
- Each of the following yields its stated error: past `exp`, not-found, denied, empty, a byte outside 0x21…0x7E, and more than 8192 bytes.
- An injected Claude keychain is never called for a Cursor load, and the reverse.
- `String(describing:)` and `Mirror` of the credential and of `HTTPRequest` never contain the token.

C3 Requests:
- Each operation has the exact method, URL, the four headers and the exact body.
- A cursor request with no operation, or with a non-digit or over-long period string, throws and sends nothing.
- Codex and Claude have no body and no `Content-Type`.
- Redirects are still rejected.

C4 Adapter, with a scripted transport:
- The order is cycle request, then spend request, with the parsed period.
- A non-200 first response (401, 429 with `Retry-After`, 500) is returned unchanged, and no second request is made.
- A non-200 second response is returned unchanged.
- An invalid cycle (missing, inverted, over 62 days, non-digit) throws after one request.
- A transport error propagates.

C5 Decoder:
- The traced example gives 0.82 % (to 1e-9), window code `$`, the reset at end, and amounts 41 and 5000 USD.
- No rows with limit present gives a known 0 %.
- Limit absent and limit 0 each give their distinct warning, `partial`, and no metric.
- 410000 of 500000 gives 82 %; 600000 of 500000 gives 120 % (kept raw).
- Rejected: a row outside the period, a negative, fractional, boolean or over-int32 `spendCents`, more than 4096 rows, a non-array `dailySpend`, and a non-object section.
- The snapshot's JSON encoding contains no category name or token count.

C6 Monitor, with injected keychain and transport:
- A Cursor profile becomes healthy and ranks.
- A 401 pauses it.
- An expired token pauses it, and a re-check after a new token resumes it.
- No nudge runs for Cursor, and the Claude nudge still runs for an expired default Claude session.
- Two Cursor profiles with the same token alias to one entity.

C7 Live, on the operator's machine after acceptance: `--check-live` reports `cursor` `success` with `metricCount` 1. After "Add Cursor" the app shows the bar, and the dropdown amounts match the dashboard's cumulative spend.

## Non-goals

On-demand spend, per-model breakdown, team or admin views, the IDE's own session store, Cursor token refresh, a Cursor nudge, Cursor demo rows, migrating saved profiles, a Cursor-specific polling floor or paused message, and API-metered accounts.

## Residuals and declined findings

- R1 A profile list saved with a Cursor profile cannot be decoded by Limitaur 0.2.3 or earlier, which then falls back to its defaults (downgrade unsupported).
- R2 The endpoints are undocumented and private; a change surfaces as failed or unavailable.
- R3 Token renewal is not automatic on this machine (operator report).
- R4 A Cursor 403 or a 200 error envelope is unobserved. A 403 pauses the profile like a 401, which `cursor-agent login` may not cure. Any other unexpected response fails and backs off.
- R5 Any additional profile, enabled or not, makes aggregate default-workload eligibility false, as today for extra Codex or Claude profiles.
- R7 A row whose `day` precedes the cycle start rejects the whole response. Observed: the cycle starts at 00:00 UTC and day buckets are 00:00 UTC; a cycle not aligned to a bucket boundary would fail every poll.
- R8 An invalid cycle from the server is shown as "Connection unavailable", like a network failure.
- R6 The paused message for Cursor is the generic one ("resumes automatically after the provider app signs in again"); the Accounts text names `cursor-agent login`.
