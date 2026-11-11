# Claude spend limit, monthly reset day and shared budget (addendum)

Status: approved addendum, built through four-eyes, light mode.

Operator decisions, all on 2026-11-10:
- P30 and P31 ("approved").
- P33: a monthly calendar reset, defaulting to the 1st, configurable to day 1–28 or the last day of the month ("fundamentally it is monthly").
- P34 ("build it and let's see how that looks").
- Individual provider bars stay ("keep the individual bars").

This addendum supersedes, for the Claude spend fields only, the 2026-10-18 rule that non-null `limit`, `balance` and `cap` raise "Spend limit or balance metadata unavailable". It also adds one operator-approved exception to `docs/specification.md`'s "do not infer … expiration dates": a configured monthly reset day.

Line budget: about 450 product lines and about 450 test lines.

## Goal

The operator's employer gives them a single monthly dollar budget ($5,000) shared between Claude and Cursor. Each provider reports and enforces only its own spend against that figure, so neither shows the combined total. Today Limitaur also shows Claude's spend as "Partial data", with no limit and no reset, although the endpoint now reports the limit as typed money. Solving it means three things:
- the Claude card shows spent, limit, a precise percentage and a monthly reset, like the Cursor card;
- each provider's reset is a monthly calendar day: Cursor's comes from Cursor, and Claude's is a configurable day that defaults to the 1st;
- an optional, user-configured shared budget adds the members' reported spend and shows it as its own ranked bar and dropdown card. It never shows a partial or mismatched total as complete, and the individual provider bars stay.

## Supported conditions and data formats

Observed 2026-11-10 against `https://api.anthropic.com/api/oauth/usage`. The values below are synthetic.

```json
"spend": {"enabled": true, "percent": 15, "severity": "normal",
          "used":  {"amount_minor": 41000, "currency": "USD", "exponent": 2},
          "limit": {"amount_minor": 500000, "currency": "USD", "exponent": 2},
          "cap": {"money": null, "credits": {"amount_minor": 500000, "exponent": 2}},
          "balance": null, "auto_reload": null, "disabled_reason": null},
"extra_usage": {"is_enabled": true, "monthly_limit": 500000, "used_credits": 41000.0,
                "utilization": 8.2, "currency": "USD", "decimal_places": 2}
```

The response has no reset or period field. The Claude app shows the reset as 00:00 UTC on the 1st of the next month. Cursor's billing cycle runs from 00:00 UTC on the 1st to 00:00 UTC on the 1st of the next month, as `GetCurrentBillingCycle` reports. Claude's reported spend can lag by hours (the Claude app says so).

## Interfaces

### I1 `MonthlyResetDay` (LimitaurCore, public, `Codable`, `Sendable`, `Equatable`)

```swift
public enum MonthlyResetDay: Codable, Sendable, Equatable { case day(Int) /* 1...28 */; case lastDay }
public extension MonthlyResetDay {
    static let `default`: MonthlyResetDay = .day(1)
    init?(storage: String)            // "1"..."28" or "last"; anything else nil
    var storage: String { get }
    func nextReset(after instant: Date) -> Date   // earliest 00:00 UTC on the chosen day of a month that is strictly after `instant`
    func periodStart(containing instant: Date) -> Date   // latest such 00:00 UTC at or before `instant`
}
```

- `.lastDay` resolves per month (28, 29, 30 or 31) in the Gregorian calendar, UTC.
- `.day(n)` outside 1…28 is treated as `.day(1)`.
- At exactly a reset instant, `periodStart` returns that instant and `nextReset` returns the following month's.

### I2 `SpendSummary` (LimitaurCore, public, `Codable`, `Sendable`, `Equatable`)

```swift
public struct SpendSummary: Codable, Sendable, Equatable {
    public var spent: Decimal; public var limit: Decimal?; public var currency: String; public var periodEnd: Date?
}
```

`UsageSnapshot` gains `public var spend: SpendSummary?`, defaulting to `nil`. The existing initialiser takes it as a trailing defaulted parameter. Old encoded snapshots without the key still decode.

### I3 Decoders

**Claude** (applies only when `spend.enabled` is true):
- `used` = `money(spend.used)`. `limit` = `money(spend.limit)`, the existing typed-money rule.
- If `limit` is present but not valid money, the warning is "Spend limit unavailable". `cap`, `balance` and `auto_reload` are ignored and raise no warning.
- **Percent:** `extra_usage.utilization` is used only when all of these hold:
  - `extra_usage.is_enabled` is true;
  - `monthly_limit` equals `spend.limit.amount_minor`;
  - `used_credits` numerically equals `spend.used.amount_minor`;
  - `currency` equals `spend.used.currency`;
  - the utilization is a valid percent.

  Otherwise the percent is `spend.percent`, and the existing "Spend usage unavailable" rule still applies.
- **Metric:** `UsageMetric(id: "spend", label: "Monthly spend", usedPercent:, resetsAt:)`. `resetsAt` is `resetDay.nextReset(after: now)`, where `resetDay` is the decoder's new `spendResetDay` parameter, defaulting to `.default`.
- **Amounts:** `"Spent this cycle"` = used, and, when `limit` is valid, `"Spend limit"` = limit. Both keep their own currency.
- **`snapshot.spend`:**
  - `SpendSummary(spent: used, limit: limit, currency: used.currency, periodEnd: resetsAt)`, when `used` is valid money.
  - `limit` is nil when its currency differs from `used`'s.
- The existing `extra_usage` branch, which runs when `spend` is absent, is unchanged.

**Cursor:** `snapshot.spend = SpendSummary(spent: cents / 100, limit: limitCents / 100 or nil, currency: "USD", periodEnd: cycle end)`. This applies whenever "Spent this cycle" is listed. Metrics and amounts are unchanged.

**Interface change:** `UsageDecoder.decode(provider:data:accountID:accountLabel:now:spendResetDay: MonthlyResetDay = .default)`. Codex ignores the new parameter.

### I4 Monitor

- New public method `setSpendResetDay(_ day: MonthlyResetDay, for provider: ProviderID)`, which stores the day per provider.
- The `complete` decode passes `spendResetDays[provider] ?? .default`.
- A change takes effect from the next successful fetch. There is no other monitor change.

### I5 Shared budget (LimitaurCore, pure)

```swift
public struct SharedBudgetConfig: Codable, Sendable, Equatable {
    public var enabled: Bool; public var amount: Decimal?; public var currency: String   // "USD"
    public var members: [ProviderID]; public var resetDay: MonthlyResetDay
}
public struct SharedBudgetMember: Sendable, Equatable { public let provider: ProviderID; public let spent: Decimal?; public let problem: String? }
public struct SharedBudgetState: Sendable, Equatable {
    public let config: SharedBudgetConfig; public let members: [SharedBudgetMember]
    public let total: Decimal?; public let usedPercent: Double?; public let resetsAt: Date
    public let freshnessDeadline: TimeInterval?; public let warning: String?
}
public func sharedBudget(_ config: SharedBudgetConfig, rows: [ProfileDisplay], mainProfileIDs: [ProviderID: String],
                         wallNow: Date, monotonicNow: TimeInterval) -> SharedBudgetState?
```

**Inputs.** `rows` are the projected rows, after stale marking. `mainProfileIDs` maps each member provider to its Settings main account (settings-and-dropdown I1). It returns nil when `enabled` is false or `members` is empty.

**Members.** For each member, in the config's order:
- The row is the main account's row. A missing row gives the problem "Off" when the profile is disabled or absent, and "Connecting…" otherwise.
- `spent` comes only from that row's `snapshot.spend`. The row is usable only when all of these hold:
  - health is `.healthy` or `.partial` (not stale);
  - `monotonicNow < freshnessDeadline`;
  - `spend` is present;
  - `spend.currency == config.currency`;
  - `spend.periodEnd == config.resetDay.nextReset(after: wallNow)` (exact instant).
- Otherwise `spent` is nil and `problem` is one of the following, checked in this order:
  1. the `AccountStatus` label for health,
  2. "No spend reported",
  3. "Different currency",
  4. "Different billing period".

**Totals.** `total` is the sum only when every member has `spent`. Otherwise it is nil and `warning` is "Total unavailable: <provider name> <problem>" for the first failing member.

**Percent.** `usedPercent` = total ÷ amount × 100 when `total` is known and `amount` > 0. With a nil or non-positive `amount`, it is nil and `warning` is "Set the budget amount in Settings".

**Reset and freshness.** `resetsAt` is `config.resetDay.nextReset(after: wallNow)`. `freshnessDeadline` is the minimum of the member rows' deadlines when the total is known, and nil otherwise.

### I6 Ranking and presentation

`projectDisplay` gains a trailing `budget: SharedBudgetState? = nil`. When its `usedPercent` and `freshnessDeadline` are known and `monotonicNow < freshnessDeadline` and `wallNow < resetsAt`, a candidate joins the ranking:
- It is the `RankedMetric` for provider `"budget"`, account `"shared"`, accountLabel "Shared budget", metric `UsageMetric(id: "spend:shared", label: "Shared budget", usedPercent:, resetsAt:)`, and `fetchedAt` = `wallNow`.
- It is merged into the already ordered candidates by the existing order (percent descending, then provider/account/metric ID).
- The selected list is then cut to `count`.
- It appears in the accessibility summary like any other candidate.

Individual provider candidates are unchanged and stay in the ranking. The status-bar code for `"budget"` is `SB`, added to `providerCodes` and `docs/provider-codes.md`, and `providerCodesAreDistinguishable` must still pass. `providerName("budget")` is "Shared budget".

### I7 Dropdown

When a `SharedBudgetState` exists, a budget card comes first, above the account cards, in the card style:
- **Title row:** `ProviderBadge("budget")`, "Shared budget", and a chip whose label and colour are "Your budget" `.gray`.
- **Metric block:** label "This month", `resetLabel`, `percentText`, then a `UsageBar` (severity colours apply).
- **Total line:** "<total> of <amount>" via `amountText`, or the warning in place of the total.
- **Member rows:** one per member, showing badge, provider name and either `amountText(spent)` or the problem in secondary type.
- **Footnote:** "Your budget across providers, not a provider limit. Reported spend can lag." in tertiary type.

`DropdownModel` gains `budget: SharedBudgetState?`. Its action titles are unchanged.

### I8 Settings

**Providers tab, Claude section**, shown when the section is on: a "Spend resets" `Picker` in `.menu` style, with the items "1st", "2nd", "3rd", "4th" … "28th" and "Last day of the month". Its footnote reads "Claude does not report this; the 1st matches the Claude app. Times are UTC."

**General tab, a "Shared budget" section:**
- `Toggle` "Track a shared monthly budget".
- When on:
  - "Amount": a `TextField` showing the amount as currency, committed on submit or focus loss. A non-positive or unparsable value is refused and the previous value is kept.
  - "Includes": a `Toggle` per provider that reports dollar spend (Claude and Cursor), with the accessibility label "Include <provider> in shared budget".
  - "Resets": the same day picker.
  - Footnote: "Limitaur adds each provider's reported spend for the month. This budget is yours; no provider enforces it."

**`SettingsModel` additions**, internal, applying whatever `editable` says (they are local display settings):

```swift
@Published private(set) var claudeResetDay: MonthlyResetDay
@Published private(set) var budget: SharedBudgetConfig
func setClaudeResetDay(_ day: MonthlyResetDay)
func setBudgetEnabled(_ enabled: Bool)        // turning on with amount nil pre-fills it (see below)
func setBudgetAmount(_ text: String) -> Bool   // parses with the current locale as a positive decimal; false and no change otherwise
func setBudgetMember(_ provider: ProviderID, _ included: Bool)   // only "claude" and "cursor"
func setBudgetResetDay(_ day: MonthlyResetDay)
func updateReportedLimits(_ rows: [ProfileDisplay])   // remembers each provider main account's snapshot.spend.limit and currency
```

**Pre-fill.** When the budget is turned on and the amount is nil, the amount is set to the members' reported limit when every member's main account reports the same limit and currency. Otherwise it stays nil.

**Defaults:**
- `claudeResetDay` is `.default`.
- `budget` starts as `SharedBudgetConfig(enabled: false, amount: nil, currency: "USD", members: ["claude", "cursor"], resetDay: .default)`.

**Callbacks.** Two init parameters are added: `onClaudeResetDay` and `onBudget`. They are called once per change.

**`AppController`:**
- **Persistence:**
  - `claudeSpendResetDay` stores `MonthlyResetDay.storage`;
  - `sharedBudget` stores `SharedBudgetConfig` as JSON;
  - an absent or invalid value means the default;
  - demo stores neither.
- **Wiring:**
  - at launch and on change, it calls `monitor.setSpendResetDay(_, for: "claude")`;
  - `refreshProjection` computes `sharedBudget(…)` from the projected rows and the Settings main accounts, passes it to `projectDisplay`, sets `dropdownModel.budget`, and calls `settings.updateReportedLimits`.

### I9 Renders

`--render-demo` adds the following, using synthetic values only:
- `dropdown-budget-{light,dark}.png`, with a budget card at $833.20 of $5,000.00 (16.66 %), a Claude card and a Cursor card;
- a "Spend resets" row in the Settings Providers render;
- a "Shared budget" section, on and filled, in the General render.

## Traced paths

**Success.** The Claude row is healthy, with `spend` 41000/500000 USD and `periodEnd` 2023-12-01T00:00Z. The Cursor row is healthy, with `spend` 4100 cents (41.00) USD and `periodEnd` 2023-12-01T00:00Z. The config is enabled, amount 5000, members Claude and Cursor, reset `.day(1)`, and `wallNow` is 2023-11-15. So:
- total is 451.00 and usedPercent is 9.02;
- `resetsAt` is 2023-12-01T00:00Z;
- the budget candidate ranks between the members by percent;
- the card reads "$451.00 of $5,000.00".

**Failure (period mismatch).** Cursor's cycle ends 2023-12-15, so its `periodEnd` doesn't match. The Cursor member gets the problem "Different billing period". `total` and `usedPercent` are nil, there is no bar, and the card shows the warning "Total unavailable: Cursor Different billing period".

**Failure (stale member).** The Claude row is stale, so its member gets the problem "Stale". There is no total and no bar, and the card names Claude.

## Acceptance criteria

- **C1** `swift build`, `swift test` (parallel) and `swift test --no-parallel` pass. Every existing test passes unchanged, apart from any that assert the Claude spend label or warning, each listed by name.
- **C2** `MonthlyResetDay`:
  - storage round trip and invalid storage;
  - `nextReset` and `periodStart` for day 1, day 15, day 28 and `lastDay`, across Jan 31 → Feb 28/29 (leap and non-leap years) and Dec → Jan year rollover;
  - exactly-at-reset instants;
  - out-of-range `.day` values.
- **C3** Claude decoder:
  - the observed shape gives "Monthly spend" at the utilization percent, amounts "Spent this cycle" and "Spend limit", `snapshot.spend`, and `resetsAt` from the configured day, with no warning and not partial;
  - each utilization fallback condition;
  - a malformed `limit` warns;
  - non-null `cap`/`balance` raise no warning;
  - a limit in a different currency gives a nil `spend.limit`;
  - a disabled `spend` is unchanged.
- **C4** Cursor decoder fills `snapshot.spend`, with the same metrics and amounts as before.
- **C5** `sharedBudget`:
  - the success trace;
  - each problem in order;
  - total and warning rules;
  - amount nil or zero;
  - a disabled config or no members gives nil;
  - the freshness deadline is the minimum of the members' deadlines;
  - only the main accounts count.
- **C6** `projectDisplay` with a budget:
  - ordering among members;
  - the candidate leaves the bars at its freshness deadline and at `resetsAt`;
  - the count limit applies;
  - the accessibility summary contains "Shared budget";
  - with no budget, nothing changes.
- **C7** The I8 `SettingsModel` rules:
  - pre-fill when the limits match, and none when they differ;
  - amount parsing;
  - member and reset-day changes, with one callback per change;
  - controller persistence and the `monitor.setSpendResetDay` call;
  - demo stores nothing.
- **C8** `providerCodes` includes `budget: "SB"`, and distinguishability still holds.
- **C9** Visual (designer): the I9 renders.

## Non-goals

- Limits that providers enforce combined.
- Budgets in more than one currency.
- Weekly budgets.
- Per-day spend charts.
- Notifications.
- Reading the employer's budget from anywhere.
- Other accounts in the budget.
- Re-applying a changed reset day to a cached snapshot before the next fetch.

## Residuals

- R1 Claude's reset day is configured, not reported. If Anthropic's real period differs, the bar's reset is wrong until the user changes the setting.
- R2 Reported Claude spend can lag by hours, so the combined total trails real spend.
- R3 Cursor's cycle comes from Cursor. A user whose Cursor cycle doesn't start on the configured day gets "Different billing period" and no combined bar.

## Revision 2 (after change review, 2026-11-10)

These rules override the sections above where they differ. They come from the cold opinions of the two panel members and the operator's decisions P35–P37 ("approve on p35/p36 and decline p37"). They have not been re-reviewed.

- **H1 Stable candidate time.** The budget candidate's `fetchedAt` is the earliest `fetchedAt` among the member rows' snapshots, not `wallNow`. Repeated projections over unchanged data return an equal `selected` list.
- **H2 Alias owners.**
  - `ProfileDisplay` gains `public let aliasOf: String?`, the owning profile's id, with a default of nil. The monitor sets it where it builds the "Alias of …" row.
  - In `sharedBudget`, a member whose main row has `aliasOf` set uses the owner's row: its health, snapshot, freshness and spend. The problem labels are unchanged.
- **H3 Validated configuration.**
  - A loaded `SharedBudgetConfig` keeps only members that are "claude" or "cursor", deduplicated in first-seen order.
  - A currency other than "USD" makes the whole configuration default.
  - An amount that is not positive becomes nil.
  - `sharedBudget` also ignores duplicate members.
  - `SettingsModel` mutators keep these invariants.
- **H4 Reset scheduling.** `AppController` arms a one-shot presentation refresh at the current budget's `resetsAt`, alongside the existing display deadlines. When a budget exists, it also arms one at its `freshnessDeadline`.
- **H5 Card without rows.** The dropdown shows the budget card whenever `budget` is non-nil, even with no account rows. The "No enabled accounts" empty state still appears below it when rows are empty.
- **H6 Accessibility freshness.** The budget candidate's `nominalDeadline` is the minimum `nominalDeadline` of the display's candidates whose provider and account match a usable member's snapshot. With none, it is the budget's `freshnessDeadline`.
- **H7 Rate-limited members (P36).** A member row whose health is `.throttled` counts as usable when the other I5 conditions hold, including `monotonicNow < freshnessDeadline`.
- **H8 Adversarial suite (P35).** In `Adversarial/test_acceptance.py`, `test_unverified_claude_money_does_not_become_a_known_balance` drops the final `partial or warnings` assertion, which the P30 contract supersedes. Its metric and balance assertions stay.
- **R4 (P37, declined).** Just after the configured reset, a lagging provider could still report the previous month's spend. Limitaur cannot detect this.
