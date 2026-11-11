# Customizable provider codes, account labels and "Other accounts"

Status: approved for implementation 2026-11-10 (operator: P41 "agreed on your rec for Default"; P42 "sounds good on the mechanics but it should also show in the toolbar on the mac (the bars we display)"; P44 and Go "proceed with the rest as you proposed"). Line budget: about 150 product lines, tests separate.

## Goal

The operator finds some two-letter provider codes hard to read in the menu bar. They want to change the code of each provider, and of the shared budget, from Settings by clicking its badge. The new code then shows everywhere the code shows: the menu-bar bars, the dropdown badges and the Settings badges. Solving it means a typed code is validated, saved, applied at once in all three places, and survives a relaunch, while an unusable or duplicate code never reaches the menu bar. Two small fixes ride along: the dropdown stops showing "· Default" when a provider has only one account (P41), and "Other accounts" expands from its label and from the accessibility press action, not only from its chevron (P44).

## Scope

1. **P42 provider codes.** Override codes for `claude`, `codex`, `cursor` and `budget`.
2. **P41 account label.** The dropdown card header leaves out the account label when it is the provider's only card.
3. **P44 disclosure.** The "Other accounts (N)" disclosure toggles from a click on its label and from AXPress.

## Settled constraints

- Codes are one or two characters, A–Z or 0–9 (ASCII), stored uppercased (operator via P42 mechanics).
- An exact duplicate of another provider's code in use is refused; a look-alike under `providerCodesAreDistinguishable` is saved with a warning (operator via P42 mechanics).
- The override applies in the menu bar, the dropdown and Settings (operator, P42).
- Demo mode neither loads nor stores overrides, and its Settings stays read-only (existing rule).
- `providerCodes`, `providerGlyph(for:)`, `providerCodesAreDistinguishable` and `docs/provider-codes.md` keep their current meaning; the reserved table is the default.
- The status item's accessibility summary is unchanged.
- No new runtime dependencies; macOS 26+.

## Assumptions

- Overrides are per provider, not per account: every account of a provider shows the same code.
- A user override beats the optional provider image from `Resources/providers/` (the bundle mask): with an override, the code is drawn as text.

## Interfaces

### Core (`Sources/LimitaurCore/WindowCode.swift`)

- `public let editableProviderCodes: [ProviderID] = ["claude", "codex", "cursor", "budget"]`
- `public func normalizedProviderCode(_ raw: String) -> String?`: trims whitespace and newlines, uppercases; returns the result when it is 1 or 2 characters, each in A–Z or 0–9; otherwise nil (including empty).
- `public func providerGlyph(for provider: ProviderID, overrides: [String: String]) -> String`: `normalizedProviderCode(overrides[provider.rawValue.lowercased()] ?? "")` when non-nil, else `providerGlyph(for: provider)`.
- `public func validatedProviderCodes(_ raw: [String: String]) -> [String: String]`: keeps keys in `editableProviderCodes` whose value normalizes, stores the normalized value, drops a value equal to that provider's default, then drops every override whose effective code equals another editable provider's effective code. Order-independent.

### Settings model (`SettingsModel`)

- `@Published private(set) var providerCodes: [String: String]` (overrides only), initialised from a new init parameter `providerCodes: [String: String] = [:]` passed through `validatedProviderCodes`.
- New init parameter `onProviderCodes: @escaping ([String: String]) -> Void = { _ in }`.
- `func code(for provider: ProviderID) -> String`: the effective code.
- `func lookalike(for provider: ProviderID) -> ProviderID?`: the first other editable provider, in `editableProviderCodes` order, whose effective code has the same length and is not distinguishable from this one's; nil when none.
- `@discardableResult func setProviderCode(_ provider: ProviderID, _ raw: String) -> ProviderCodeChange` where `enum ProviderCodeChange: Equatable { case saved(String), reset, unchanged, invalid, duplicate(ProviderID), readOnly }`:
  - not editable → `.readOnly`; a provider outside `editableProviderCodes` → `.invalid`;
  - trimmed empty, or a code equal to the default → the override is removed → `.reset` (or `.unchanged` when there was none);
  - fails normalization → `.invalid`;
  - equals another editable provider's effective code → `.duplicate(that provider)`;
  - otherwise the override is stored → `.saved(code)`, or `.unchanged` when it equals the current override.
  - `onProviderCodes` is called once with the whole override map on `.saved` and `.reset` only.

### Controller and persistence (`AppController`)

- UserDefaults key `providerCodes`, a dictionary of strings, read from the injected `defaults` at launch through `validatedProviderCodes` and written on each `onProviderCodes`. Demo neither reads nor writes it.
- `var providerCodes: [String: String] { get }` exposes the applied overrides.
- On a change, the status item redraws at once (no wait for the next poll), the dropdown model updates, and the Settings model already holds the value.

### Drawing and views

- `RingView.providerCodes: [String: String]` (default empty; setting it redraws). Each slot's provider code, including the unhealthy marker's, is `providerGlyph(for:overrides:)`; with a non-nil override for that provider the bundle image is not used.
- `DropdownModel.providerCodes: [String: String]`; account cards and the budget card show the effective code in their badge.
- `ProviderBadge` shows a given code (the effective one) instead of computing the default itself.

### Settings UI

- Providers tab: each section's badge is a button, accessibility label "Edit code for <Name>" (Name from `providerName`). Pressing it (click or AXPress) replaces the badge with a text field, accessibility label "Code for <Name>", prefilled with the effective code, focused, about 44 pt wide.
  - Return or focus loss calls `setProviderCode`. `.saved`, `.reset` and `.unchanged` end editing; `.invalid` and `.duplicate` keep it with a footnote: "Use one or two letters or digits." or "<Other name> already uses <CODE>.".
  - Escape ends editing without a change.
  - While editing, a footnote reads "Clear to restore <DEFAULT>."
  - While `lookalike(for:)` is non-nil, the section shows the footnote "Looks like <Other name>'s <CODE> in the menu bar."
- General tab, Shared budget section, when the budget is on: a row "Menu bar code" with the same control for `budget`.
- Read-only (demo) Settings: the badges are plain badges, not buttons.

### P41

A dropdown account card's header reads "<Provider> · <label>" when the dropdown holds two or more account cards of that provider, and "<Provider>" alone otherwise. Its accessibility follows the visible text. The status item's accessibility summary and "Connect / Authorize <label>" are unchanged.

### P44

The "Other accounts (N)" disclosure toggles on a click anywhere on its label row and on the AXPress action of its disclosure element. Its expanded state is kept while the Settings window stays open, across polls and model updates.

## Traced paths

- **Success.** The user clicks the CU badge, types "cr", and presses Return. `setProviderCode("cursor", "cr")` returns `.saved("CR")`, and `onProviderCodes(["cursor": "CR"])` fires once. The controller writes `providerCodes = {cursor: CR}`, sets `RingView.providerCodes` and `DropdownModel.providerCodes`, and the Cursor slot redraws as CR at once. The dropdown card and Settings badge read CR. After a relaunch, `validatedProviderCodes` keeps CR.
- **Failure.** The user types "CL" for Cursor. `setProviderCode` returns `.duplicate("claude")`, and nothing is stored or called back. The field stays open with "Claude already uses CL.", and the menu bar keeps CU. A tampered stored value `{cursor: "CL", codex: "??"}` loads as `{}`: CL duplicates Claude's code and "??" does not normalize.

## Acceptance criteria

- C1 `normalizedProviderCode`: " cr " → "CR"; "c" → "C"; "9z" → "9Z"; "", "ABC", "C?", "é", "Ⅻ" → nil.
- C2 `providerGlyph(for:overrides:)` returns a valid override, falls back to the default for a missing or invalid one, and leaves `providerGlyph(for:)` unchanged.
- C3 `validatedProviderCodes` drops unknown keys, invalid values and values equal to the default, normalizes the rest, and drops both sides of a duplicate, including one against another provider's default code.
- C4 `setProviderCode` returns each case listed under the settings model, calls back exactly once per `.saved` or `.reset`, and never on any other case; read-only models never change.
- C5 `lookalike(for:)`: setting Cursor to "GL" reports Claude (CL), while "CR" reports none.
- C6 The controller loads `providerCodes` from the injected defaults through the validation, persists each change, and applies it to the status view and the dropdown model without a new poll; demo neither reads nor writes.
- C7 `RingView` with an override draws the override and not the default: its rendered pixels differ from the default rendering, equal a rendering of the same code through the reserved table where one exists, and the unhealthy marker uses it too.
- C8 P41: one card per provider gives headers without " · Default"; two Codex cards give "Codex · <label>" for both.
- C9 P44: the disclosure expands by AXPress and by a click on its label (manual or gate check; no view-inspection seam exists).
- C10 The full suite, the frozen Python suites and the release-tooling tests pass in parallel and serial.

## Non-goals

- Per-account codes; codes longer than two characters, other scripts or emoji; editing the reserved table or the code-class rule.
- Changing the status item's accessibility summary.
- Codes for providers without a Settings section.

## Open questions

None. The designer extends `scripts/release-gate.py` with a code-change check after acceptance; that is development infrastructure and is not part of this increment.

## Revision 2 (designer, 2026-11-10, after the test-writer's first delivery)

These rules override the sections above where they differ. Both fix a path where two editable providers could end up with the same effective code; they are not re-reviewed.

- **R2.1 Stable validation.** `validatedProviderCodes` repeats its duplicate removal until no two editable providers share an effective code. Example: `{claude: AA, codex: AA, cursor: CL}` loads as `{}`. Dropping both AA overrides gives Claude back CL, which then duplicates Cursor's override. The result is therefore always a fixed point: validating it again returns it unchanged. Swapped codes `{claude: CU, cursor: CL}` have no duplicate and are kept.
- **R2.2 Reset checks for duplicates.** In `setProviderCode`, a trimmed-empty value or the provider's default is refused with `.duplicate(other)` when the default is another editable provider's effective code. Example: with `{claude: AB, cursor: CL}`, clearing Claude returns `.duplicate("cursor")`, and nothing changes or is called back.
- **R2.3** A provider id is matched case-insensitively wherever a `ProviderID` or override key is read (`providerGlyph(for:overrides:)` already lowercases).

## Revision 3 (designer, 2026-11-10, after the change review)

These rules come from adopted findings of the change review (panel: Opus and Sol; test-writer). They override the sections above where they differ and are not re-reviewed.

- **R3.1 Case.** R2.3 applies at every entry point. `validatedProviderCodes` lowercases keys before validation, and two raw keys that differ only in case drop that provider's override. `setProviderCode`, `code(for:)` and `lookalike(for:)` lowercase the provider id first. Overrides are always stored under the lowercase id, and `lookalike(for:)` never reports the provider itself.
- **R3.2 Editing lifecycle.**
  - The code field commits, as on focus loss, when the Settings window closes (⌘W, the close button) and when the field disappears (tab switch, the budget switched off).
  - Escape while the field is editing ends editing without a change and does not close the window. A second Escape closes the window as before.
  - Closing the window always ends editing and clears any footnote, so a reopened window shows badges.
- **R3.3 Focus.** The field has keyboard focus as soon as it appears; typing goes into it without another click.
- **R3.4 Fit.** In the menu bar, a provider code whose width in its font exceeds its glyph area is drawn at the largest smaller size that fits, in every layout and in the unhealthy marker. Codes that fit are drawn exactly as before.
- **R3.5 Budget code row.** The General tab's "Menu bar code" row for `budget` shows whether or not the budget is on, so the code that blocks a duplicate can always be changed.
- **R3.6 (designer, after verify).** R2.3 and R3.1 cover the validation and Settings entry points. The drawing paths (`RingView.providerCodes`, `DropdownModel.providerCodes`, `providerGlyph(for:overrides:)`) receive only maps already passed through `validatedProviderCodes`, which are lowercase. A mixed-case key passed directly to them is outside the supported use.
