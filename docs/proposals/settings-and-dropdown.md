# Settings window and dropdown redesign (addendum)

Status: approved addendum, built through four-eyes, light mode. The operator approved P21–P26 on 2026-11-10 ("go with your recs on all four - i trust your choice"), the second fix round ("go for the second fix round") and the result ("accepted. Proceed"). It supersedes the `docs/compact-bars.md` clause "Settings opens a native menu with an Indicators submenu … and a separate Accounts… action" and the dropdown's flat text layout. Ranking, thresholds, freshness, the menu-bar drawing and all provider behaviour are unchanged.

## Goal

Limitaur's Accounts dialog is an `NSAlert` with a scrolling stack of checkboxes and path fields and five buttons ("Save", "Cancel", "Add Codex", "Add Claude", "Add Cursor"). Its Settings control is a small pop-up menu, and its dropdown is a flat column of text lines. The operator finds these confusing and cheap-looking. Solving it means:
- a native macOS Settings window with one section per supported provider, each with an on/off switch, its source, its live status and its options, and no "Add" buttons for the common case;
- a polished dropdown that presents each account as a card, with usage bars in the threshold colours.

Both must keep every piece of information and every action the current UI offers. They must work in light and dark, by keyboard and with VoiceOver. They add no third-party dependency and change no monitoring behaviour.

Line budget: about 750 product lines added (with about 300 removed), about 500 test lines including ports.

## Settled constraints

- S1 (operator, P21): a Settings window replaces the Accounts dialog and the Settings pop-up menu. It has two toolbar tabs, General and Providers. Changes apply immediately (macOS convention), with no Save or Cancel buttons.
- S2 (operator, P22): the dropdown shows one card per account, with a usage bar per metric in the threshold colours (normal = menu-bar foreground tint, warning above 80 %, critical above 95 %).
- S3 (operator, P23): each provider section has one main account. An "Other accounts" disclosure lists additional accounts, each with an on/off switch, and has an add button (Codex and Claude only).
- S4 (operator, P24): percentages show as whole numbers; the exact value is in the tooltip.
- S5 (operator, P25): default-workload eligibility counts only enabled profiles.
- S6 (repository): AppKit app, SwiftUI allowed (Apple framework), no third-party dependencies, macOS 26, `LSUIElement` stays true, no login item.

## Architecture

- New file `Sources/Limitaur/Design.swift`: the shared visual pieces (`ProviderBadge`, `StatusChip`, `UsageBar`) and the pure formatting functions (I4).
- New file `Sources/Limitaur/SettingsWindow.swift`: `SettingsModel` (I2) plus the SwiftUI views and an `NSWindowController` hosting an `NSTabViewController` with `tabStyle = .toolbar`. Each tab is an `NSHostingController` containing a SwiftUI `Form` with `.formStyle(.grouped)`. There is one window instance, created lazily and reused. Opening it calls `NSApp.activate()`, then `makeKeyAndOrderFront`, and centres the window the first time.
- New file `Sources/Limitaur/DropdownPanel.swift`: `DropdownModel` (I3) and the SwiftUI views. The popover's `contentViewController` is an `NSHostingController` with `sizingOptions = .preferredContentSize`.
- `AppUI.swift` changes:
  - It loses `DropdownView`, `showSettings()` (the `NSAlert`), `settingsMenu()`, `showSettingsMenu()`, `toggleNudge` and `addedAccountProfile`.
  - `AppController` owns `settings: SettingsModel` and `dropdownModel: DropdownModel`, keeps profile persistence, and feeds both models from `refreshProjection` and `apply`.
  - `AppActionRouter.accounts` opens the Settings window, which keeps the demo guard.
  - `AppController.settingsPresenter: (SettingsModel) -> Void` is a seam like `aboutPresenter`; by default it shows the window.
- `Monitor.swift` (P25): in `defaultWorkloadEligible`, `configuredProfiles.count == 2` becomes a count of enabled configured profiles `== 2`.
- `LimitaurMain.swift`: `--render-demo` renders the new dropdown and the two Settings tabs (I6).

## Visual design language

Values are exact unless marked "about".

- **Type.**
  - Card title: `.system(size: 13, weight: .semibold)`.
  - Body and metric label: `.system(size: 12)`.
  - Percent: `.system(size: 12, weight: .semibold).monospacedDigit()`.
  - Secondary: `.system(size: 11)` in `.secondary`.
  - Tertiary (fetch age, polling): `.system(size: 10)` in `.tertiary`.
- **`ProviderBadge(provider:)`:** the provider code from `providerCodes` (CL, CX, CU; fallback per the existing rule) in `.system(size: 10, weight: .bold, design: .rounded)`, centred in a 26×17 `RoundedRectangle(cornerRadius: 5)` filled with `Color.primary.opacity(0.09)`. Decorative for accessibility.
- **`StatusChip(status:)`:** a 7 pt `Circle` in the status colour, then 4 pt, then the status text in secondary type. Accessibility label is the status text. The `AccountStatus` cases (in `Design.swift`) map from `Health`, with label and colour:

  | `Health` | Case | Label | Colour |
  |---|---|---|---|
  | healthy | `.healthy` | "Healthy" | `.green` |
  | partial | `.partial` | "Partial data" | `.yellow` |
  | throttled | `.throttled` | "Rate limited" | `.orange` |
  | stale | `.stale` | "Stale" | `.gray` |
  | unavailable | `.unavailable` | "Unavailable" | `.orange` |
  | failed | `.failed` | "Connection failed" | `.orange` |
  | unauthenticated | `.signIn` | "Needs sign-in" | `.red` |

  In Settings only there are two more cases: `.off` "Off" `.gray` (profile disabled) and `.connecting` "Connecting…" `.gray` (enabled, no display row yet).
- **`UsageBar(percent:)`:**
  - Height 5, `Capsule` track `Color.primary.opacity(0.10)`.
  - The fill is a `Capsule` whose width fraction is `ringFill(percent)` (0…1); it is absent when the percent is unknown.
  - Fill colour by `severity`: normal `Color.primary.opacity(0.65)`, warning `.yellow`, critical `.red`.
  - Decorative for accessibility.
- **Cards:**
  - `RoundedRectangle(cornerRadius: 12)` filled with `Color.primary.opacity(0.045)` and stroked with `Color.primary.opacity(0.07)` at 0.5 pt.
  - Padding 12, internal vertical spacing 8, 10 between cards.
- **Popover:**
  - Content width 360, padding 14 on all sides, on the system popover material; no custom background fill.
  - Content height follows the content up to 560. Beyond that the card list scrolls, while the header and footer stay fixed.

## Interfaces

### I1 Profile mapping

There are three provider sections, always in the order Claude, Codex, Cursor.

**Main account.** A section's main account is the profile with id `"<provider>-default"` (`claude-default`, `codex-default`, `cursor-default`). Without one, it is the first profile of that provider in saved order. Without any profile, the section has no main account.

**Provider switch.** Turning a section on:
- enables its main account;
- creates it when absent, appended to the profile list as `AccountProfile(id: "<provider>-default", providerID:, label: "Default", source:, enabled: true)`;
- uses these default sources: Claude `.claudeDefaultDiscovery`, Codex `.codexFile(CredentialStore.defaultCodexPath)`, Cursor `.cursorDefaultDiscovery`.

Turning it off sets `enabled = false` on the main account only. The profile is kept. Other accounts keep their own switches. The section's switch shows the main account's `enabled` value, and Off when there is no main account.

**Other accounts.** These are all of a provider's profiles besides the main account. Adding one (Codex and Claude only) appends `AccountProfile(id: UUID().uuidString, providerID:, label: "Account <n>", source:, enabled: false)`:
- `n` is the smallest integer ≥ 2 not already used as an "Account <n>" label for that provider;
- the source is `.codexFile(CredentialStore.defaultCodexPath)` for Codex and `.claudeFile(CredentialStore.defaultClaudePath)` for Claude.

Removing one deletes that profile. A main account cannot be removed.

**Fresh installs.** Defaults stay Codex and Claude enabled, with no Cursor profile; the Cursor section shows Off.

Every change saves the profile list exactly as `saveProfiles()` does today (`normalizedProfiles`, UserDefaults key `profiles`, `monitor.setProfiles`). Demo mode never saves.

### I2 `SettingsModel`

`SettingsModel` lives in the `Limitaur` target, is internal and `@MainActor final class SettingsModel: ObservableObject`, and is testable.

```swift
struct SettingsAccount: Identifiable, Equatable { let id: String; var label: String; var enabled: Bool
    var source: CredentialSource; var status: AccountStatus; var message: String? }
struct SettingsSection: Identifiable, Equatable { let provider: ProviderID; var main: SettingsAccount?
    var others: [SettingsAccount]; var id: String { provider.rawValue } }
@Published private(set) var sections: [SettingsSection]
@Published private(set) var indicatorCount: Int
@Published private(set) var nudgeEnabled: Bool
let editable: Bool                                   // false in demo; every mutator below is then a no-op
init(profiles: [AccountProfile], indicatorCount: Int, nudgeEnabled: Bool, editable: Bool,
     onProfiles: @escaping ([AccountProfile]) -> Void, onIndicatorCount: @escaping (Int) -> Void,
     onNudge: @escaping (Bool) -> Void, onConnect: @escaping (String) -> Void, onAbout: @escaping () -> Void)
var profiles: [AccountProfile] { get }               // current list in saved order
func setProviderEnabled(_ provider: ProviderID, _ enabled: Bool)
func setClaudeUsesKeychain(_ keychain: Bool)        // main Claude account: .claudeDefaultDiscovery, or .claudeFile(current file path or defaultClaudePath)
func setSourcePath(_ accountID: String, _ path: String) -> Bool   // trims whitespace; false and no change unless it starts with "/"; Codex → .codexFile, Claude → .claudeFile; never for Cursor
func setLabel(_ accountID: String, _ label: String) // trims; an empty result keeps the old label
func setAccountEnabled(_ accountID: String, _ enabled: Bool)
func addAccount(_ provider: ProviderID) -> String?  // nil for Cursor or unknown providers
func removeAccount(_ accountID: String)             // ignored for a main account
func setIndicatorCount(_ count: Int)                // ignored outside 1...8
func setNudge(_ enabled: Bool)
func connect(_ accountID: String)                   // calls onConnect; works in demo only if editable
func showAbout()
func updateStatuses(_ rows: [ProfileDisplay])       // maps each row's health and message by profile id; disabled accounts show .off; enabled accounts without a row show .connecting
```

Each mutator that changes the profile list calls `onProfiles` once, with the full list. `setIndicatorCount` calls `onIndicatorCount`, and `setNudge` calls `onNudge`, only when the value changes.

`AppController` wires these callbacks as follows:
- `onProfiles` stores the list and runs the existing save path;
- `onIndicatorCount` calls `selectCount`;
- `onNudge` performs what `toggleNudge` did (defaults key `claudeNudgeEnabled`, `nudgeToggled?`, `monitor.setNudgeEnabled`);
- `onConnect` calls `router.connect`;
- `onAbout` calls `aboutPresenter`.

`AppController` also pushes `updateStatuses` whenever the dropdown rows are rebuilt.

### I3 `DropdownModel` and the controller seams

`DropdownModel` is internal and `@MainActor final class DropdownModel: ObservableObject`. It publishes:
- `rows: [ProfileDisplay]`, `now: Date`, `polling: [String: PollingPolicy]` and `demo: Bool`;
- the action closures `refresh`, `settings`, `quit` and `connect(String)`.

`func actionTitles() -> [String]` returns the accessibility titles of the actions currently offered, in visual order:
- "Refresh" and "Settings" (header);
- "Connect / Authorize <label>" for each unauthenticated row when not in demo;
- "Open Settings" when `rows` is empty and not in demo;
- "Quit" (footer).

`func perform(_ title: String)` runs the action with that title. An unknown title does nothing.

`AppController` keeps its existing seams with the same meaning:
- `updateDropdown(_:)`;
- `pressDropdownButton(_:)` and `performDropdownButton(_:)`, which now call `dropdownModel.perform`;
- `hasDropdownButton(_:)`, which now uses `actionTitles().contains`;
- `routeConnect(_:)`, `configureDropdownActions()`, `prepareDemo()`, `selectCount(_:)`, `presentedCount`, `receiveDisplay(_:)` and `nudgeToggled`.

The "Settings" action calls `router.accounts()`. That replaces the pop-up menu.

### I4 Formatting functions

These live in `Design.swift` and are internal and pure.
- `percentText(_ value: Double?) -> String` returns:
  - "—" for an unknown value (`validatedPercent` nil);
  - "<1%" for a value above 0 and below 0.5;
  - "99%" for a value below 100 that rounds to 100;
  - otherwise the rounded whole number followed by "%", so 0 gives "0%", 98.4 gives "98%", 120 gives "120%" and 100 gives "100%".
- `exactPercentText(_ value: Double?) -> String` returns `String(format: "%.2f%%", value)`, or "unknown".
- `amountText(_ amount: Decimal, currency: String, locale: Locale = .current) -> String`:
  - For three uppercase ASCII letters, a `NumberFormatter` with `numberStyle = .currency`, `currencyCode = currency` and the locale, giving "$86.14" and "$5,000.00" for USD in `en_US`.
  - Otherwise "\(amount) \(currency)".
- `resetLabel(_ metric: UsageMetric, expired: Bool, now: Date) -> String`:
  - "reset due" when expired;
  - "resets " + `resetCountdownText(resetAt:now:)` when known, unless that returns "reset due" or "reset time unavailable", which pass through as they are;
  - "reset unknown" otherwise.
- `providerName(_ id: ProviderID) -> String` returns "Claude", "Codex" or "Cursor", otherwise `rawValue.capitalized`.

### I5 Views

**Dropdown, top to bottom.**

Header row:
- "Limitaur" in `.system(size: 13, weight: .bold)`, a capsule "Demo" tag when `demo`, a spacer;
- two borderless icon buttons, `arrow.clockwise` ("Refresh") and `gearshape` ("Settings"), with those exact accessibility labels and `.help` text.

Then a divider and the card list. Each card, in order:
1. **Title row:** `ProviderBadge`, then `providerName` followed by " · " and the account label, with the label in secondary colour. A spacer, then a `StatusChip` for the row's health.
2. **One block per metric:**
   - The label, followed by `" · " + scopeLabel` when a scope label is present; a spacer; then `percentText` in the severity colour (warning yellow, critical red, otherwise primary).
   - Below that, a `UsageBar`.
   - Below that, `resetLabel` in tertiary type, with `.help` giving the full absolute date as today (`DateFormatter` `.full`/`.long`).
   - The percent's `.help` is `exactPercentText`.
   - One accessibility element per metric: "<label>, <percentText>, <resetLabel>".
   - A conflicted metric shows its label with "conflicted · usage unknown" and no bar, then one secondary line per observation, "Observed <exact%> · <reset>", as today.
3. **Secondary rows**, each with a label on the left and a value on the right, in secondary type, in the existing order:
   - balances: amount, or "unlimited"/"unknown"/"unavailable"/"not applicable", with " · <expiry>" (`creditcard`);
   - informational amounts, as `amountText` (`dollarsign.circle`);
   - earned resets ("Earned resets" with "<n> available", "Applicable" with "<n>", then the details lines or "Reset detail and expiry unknown") (`arrow.counterclockwise`);
   - capabilities;
   - warnings (`exclamationmark.triangle`, in `.orange`).
4. **Footer line** in tertiary type: `fetchedLine` or `pollsLine` with leading spaces trimmed, then the row's message, if any, in secondary type.
5. When unauthenticated and not demo, a `.borderedProminent` `.controlSize(.small)` button "Connect / Authorize", whose accessibility label is "Connect / Authorize <label>".

A stale card renders its metric blocks at opacity 0.55. With no rows, the list area is replaced by a centred "No enabled accounts" in secondary type and, when not in demo, a "Open Settings" button.

Footer: a divider, then a trailing borderless "Quit" button.

**Settings, Providers tab.** A grouped `Form`, 560 wide, scrolling, with a min height of 420 and a max of 640. One `Section` per provider. The section header row is the `ProviderBadge`, then `providerName` in `.headline`, a spacer, and a `Toggle` in `.switch` style whose accessibility label is "<provider name> enabled". When the section is on, its rows are:
- **Source:**
  - Claude: a `Picker` in `.menu` style, "Keychain item" or "Credential file"; with a file, a path row (path in secondary type, middle-truncated) plus a "Choose…" button.
  - Codex: a path row plus "Choose…".
  - Cursor: "cursor-agent sign-in".
  - "Choose…" opens an `NSOpenPanel` (files only, single, `showsHiddenFiles = true`, starting in the current path's directory) and calls `setSourcePath`.
- **Status:** a `StatusChip`, with the message in secondary type below it, and a "Connect / Authorize" button when the status is `.signIn`.
- **Claude only:** a `Toggle` "Renew an expired session by running claude", with the footnote "Runs claude at most once an hour so Claude Code renews its sign-in. Turn off if Claude Code authenticates with an API key."
- **Cursor only:** the footnote "Run cursor-agent login when the session expires; Limitaur picks it up within five minutes."
- **"Other accounts (<n>)":** a `DisclosureGroup`, Codex and Claude only, collapsed by default. It lists each other account as a row containing the label `TextField` (committed on submit or focus loss), an enable `Toggle`, the path with "Choose…", the `StatusChip` and a `trash` borderless button ("Remove <label>"). Then a borderless "Add account" button.

When the section is off, it shows one secondary line: Claude "Reads the Claude Code sign-in", Codex "Reads ~/.codex/auth.json", Cursor "Reads the cursor-agent sign-in". The Cursor section never has other accounts or an add button; any existing extra Cursor profiles are listed read-only, with Remove.

**Settings, General tab.** A grouped `Form`, 560 wide.
- Section "Menu bar": a `Picker` "Indicators" in `.segmented` style over 1…8, bound through `setIndicatorCount`, with the footnote "Number of usage bars shown in the menu bar."
- Section "About": `LabeledContent` "Version" (`AppVersion.string`), then a button "About Limitaur…" that calls `showAbout`.

When `editable` is false, every control has `.disabled(true)` and the Form shows the top footnote "Demo data; settings are read-only."

### I6 Demo rendering

`--render-demo DIR` keeps its existing bar PNGs and their names. It replaces `dropdown-{light,dark}.png` and `dropdown-empty-stale-{light,dark}.png` with the new dropdown rendered in an `NSHostingView` at width 360. It adds `settings-providers-{light,dark}.png` and `settings-general-{light,dark}.png`, rendering each tab's SwiftUI content in an `NSHostingView` at width 560, using a demo `SettingsModel`:
- Claude on (Keychain), Healthy;
- Codex on, Needs sign-in, with one other account;
- Cursor off.

The demo dropdown sample adds one Cursor row: a "Monthly spend" metric at 2 %, with amounts 86.14 and 5000 USD. Rendering stays offline and reads no credentials.

## Acceptance criteria

- C1 `swift build`, then `swift test` with the default parallel run (and `--no-parallel` too), pass. Every pre-existing test that targets removed surfaces is ported to the new seams with its invariant intact; ports are listed by test name. The ported invariants are:
  - demo disables account, connect and nudge actions;
  - an indicator change makes no credential read and no HTTP call;
  - the nudge's persistence and default-on behaviour;
  - the router counts;
  - the Connect button exists only for an unauthenticated row and never in demo.
- C2 `SettingsModel`: the I1 and I2 rules. That covers:
  - the main-account resolution order;
  - switching a section on creates the main account with the specified id, label, source and position;
  - switching it off keeps the profile;
  - add, remove and labels, including the "Account <n>" numbering;
  - Cursor add refused;
  - relative paths rejected;
  - `editable` false leaves profiles, count and nudge unchanged and makes no callback;
  - `updateStatuses` mapping, including `.off` and `.connecting`;
  - exactly one `onProfiles` call per change.
- C3 `DropdownModel`: `actionTitles` in the specified order under each condition (normal, unauthenticated, demo, empty), and `perform` routing to the right closure.
- C4 Formatting: every I4 case, with `amountText` checked under `en_US`.
- C5 P25: with `codex-default` and `claude-default` enabled and healthy, a third disabled profile no longer makes eligibility false, and a third enabled one still does.
- C6 Visual (designer's review, not automated): the I6 PNGs in light and dark show the design language above with no clipping, overlap or truncated primary text at the specified widths.

## Non-goals

A right-click menu on the status item, login items, notifications, history charts, renaming main accounts in Settings (the label stays "Default"), changes to provider behaviour, and the experimental jar/logo layouts.

## Residuals

- R1 SwiftUI raises resident memory. The resource figure recorded in `docs/performance.md` (53.4 MiB, build 51) needs re-measuring.
- R2 Keyboard focus landing on the first popover button and the full VoiceOver tree remain manual checks, as before.

## Revision 2 (after change review, 2026-11-10)

These rules override the sections above where they differ. They came from the designer's render review, the test-writer's review, and the cold opinions of the two panel members. They have not been re-reviewed.

- **F1 Large percentages.** `percentText` never converts to `Int` when the rounded value is 1e15 or more; it uses `String(format: "%.0f%%", rounded)` instead, so `1e30` and `Double.greatestFiniteMagnitude` format without trapping.
- **F2 Other accounts while a section is off.** A section's "Other accounts" and the Cursor extras are always shown, whatever the main switch says. The Off line replaces only the main account's rows.
  - With no other accounts, Codex and Claude show a borderless "Add another account" button in place of the disclosure, and Cursor shows nothing.
  - With other accounts, the disclosure reads "Other accounts (<n>)".
  - Cursor extras get the enable `Toggle`. A Claude other account whose source is `.claudeDefaultDiscovery` shows "Keychain item" as its source, with "Choose…".
- **F3 Keyboard in the popover.**
  - When the popover opens, keyboard focus is on Refresh (`@FocusState`, with `.defaultFocus` or equivalent).
  - The header and footer buttons carry `.keyboardShortcut`: ⌘R Refresh, ⌘, Settings, ⌘Q Quit.
  - The card list scrolls by keyboard (arrow keys, Page Up/Down) once it has focus.
- **F4 Keyboard in Settings and the app.**
  - At launch the app installs a minimal `NSApp.mainMenu`, which is not visible for an accessory app:
    - an app menu with About Limitaur, Settings… ⌘, and Quit Limitaur ⌘Q;
    - Edit with Undo, Redo, Cut, Copy, Paste and Select All, using the standard selectors and key equivalents;
    - Window with Close ⌘W.
  - Escape (`cancelOperation`) closes the Settings window.
  - The window uses `toolbarStyle = .preference`, `collectionBehavior` including `.moveToActiveSpace`, and `setFrameAutosaveName("LimitaurSettings")`.
- **F5 Demo Settings.**
  - In demo, the dropdown's "Settings" action (and "Open Settings") presents the Settings window through `settingsPresenter`, without the router. The router's `accounts` guard is unchanged.
  - `editable` false makes the Providers controls, the nudge and Connect read-only.
  - `setIndicatorCount` and `showAbout` work whatever `editable` says. In demo the count goes to the in-memory store through `selectCount`.
  - The demo footnote reads "Demo data; provider settings are read-only."
- **F6 Labels and commit.**
  - The provider title in each section carries the accessibility header trait.
  - Repeated controls name their account: "Choose file for <provider> <label>", "Label for <provider> <label>", "<provider> <label> enabled", and "Remove <label>".
  - A label field also commits on disappear and when the window closes.
- **F7 Connecting.** `updateStatuses` maps a row with health `.unavailable` and message "Connecting account" to `.connecting`, with no message.
- **F8 Stale cards.** Opacity no longer dims a stale card. Its bars fill with `Color.secondary`, and its percent text is `.secondary`. Labels and secondary rows keep their normal colours, and the chip says "Stale".
- **F9 Warning colour.** Warning text, though not the bar, uses a dynamic colour: `systemYellow` in dark appearance, and sRGB (0.70, 0.50, 0.00) in light appearance.
- **F10 Metric density.** Each metric is laid out as:
  - first line: the label (followed by " · scope" when present), a spacer, `resetLabel` in tertiary type, 8 pt, then `percentText`;
  - second line: the `UsageBar`.

  The separate reset line is removed.
- **F11 Popover sizing.** The first open shows the final height without a visible resize. The list height is measured or estimated before the popover is shown.
- **F12 Renders.** The Settings PNGs use an editable model with inert callbacks and no demo footnote, so the controls look enabled. The rendered sample includes a Cursor card within the visible height, and the empty state gets `dropdown-empty-{light,dark}.png`.
- **F13 Docs.**
  - README: describe demo Settings as above, and say that an additional *enabled* profile makes default-workload eligibility false.
  - CHANGELOG: the Unreleased Cursor entry names the Cursor switch under Settings → Providers instead of "Add Cursor".

## Revision 3 (second fix round, operator 2026-11-10 "go for the second fix round")

- **G1 Window frame.** Only the Settings window's position is remembered across launches: its top-left point, under the UserDefaults key `settingsWindowTopLeft`. The selected tab's content always sets the size. A window frame autosave that restores height is not used. After a relaunch the window opens at the saved position, with the height of the tab shown.
- **G2 Demo Settings content.** In demo, the read-only `SettingsModel` is built from the demo's own profiles, the profiles of the rows that `installDemo` presents. It receives those rows through `updateStatuses`, so its sections match the demo dropdown. It still never saves.
- **G3 One status mapping.** A single `AccountStatus(row: ProfileDisplay)` initializer applies the I2/F7 rules, including "Connecting account" mapping to `.connecting`. It serves both `updateStatuses` and the dropdown card's `StatusChip`, so a connecting account shows "Connecting…" in both. The card's message line still shows a message other than "Connecting account".
- **G4 Label commit scope.** A label field commits on window close only for the Settings window's own `willClose`, never for other windows such as the open panel or About.
