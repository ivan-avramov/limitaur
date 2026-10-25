# Unhealthy-provider marker (P408)

Status: ACCEPTED 2026-10-25 (light four-eyes), revision 2; record docs/reviews/unhealthy-marker-review.md, residuals docs/backlog/unhealthy-marker-residuals.md. Discussion P408 (2026-10-24), go P527 (2026-10-25). Amends the unhealthy-provider sentence of docs/labelled-bars.md. Budget: product ≤ 30 changed lines, tests ≤ 100, documentation ≤ 10.

## Goal

A configured provider that is not healthy is shown in the first empty bar slots as its two-letter code in the secondary colour, drawn beside the same opaque neutral track and dash that an empty slot has. The operator read such a slot ("CL" next to an empty track) as a dim usage bar. Solving this means a marker slot can no longer be mistaken for a usage reading, and it says in one glyph whether the cause is authentication or another state, without changing ranking, widths, colours of ranked slots, the dropdown, or the accessibility summary.

## Settled constraints

- Operator (P408, P527): the marker drops the track for a marker slot and shows the provider code with a status glyph; light four-eyes run.
- Operator (P526): no stale data in bars; R-G1 stays on the backlog. This increment does not carry snapshots.
- Project (AGENTS.md, docs/labelled-bars.md): native AppKit, no dependencies; normal fill uses the menu-bar foreground tint; warning >80, critical >95; distinguish unknown, unavailable, stale and zero; slot geometry and width `19n + 5(n−1) + 8` unchanged.

## Assumptions (designer's)

- Two classes are enough, by cause, not by required action: "authentication" when any projected row of the provider is `unauthenticated` (every paused binding: expired, rejected, Keychain denied or suspended, connecting, nudging, as well as a failed credential load), "other" for every other non-healthy state (`throttled`, `failed`, `unavailable`, `stale`, `partial`). Whether the user must act is the dropdown row's job; the glyph does not promise it. Existing health mappings are not changed.
- Membership of the marker list is unchanged: providers with at least one row whose projected health is not `healthy`, in row order, unique (`projectDisplay`).

## Specification

1. `PresentationState` (Sources/LimitaurCore/Monitor.swift) gains `public let signInProviders: Set<ProviderID>`: the providers in `unavailableProviders` that have at least one projected row (`rows` in `projectDisplay`, after the stale projection) with health `.unauthenticated`. Every other field, including `unavailableProviders`, `providerWarning` and `accessibilitySummary`, is computed exactly as before.
2. `RingView` (Sources/Limitaur/AppUI.swift) gains `var signInProviders: Set<ProviderID> = []` that sets `needsDisplay` on change. The presentation update that copies `unavailableProviders` into the view copies `signInProviders` the same way, and the change check that compares `unavailableProviders` also compares `signInProviders`.
3. Marker slot: the slot at index `i ≥ selected.count` with `m = i − selected.count < unavailableProviders.count` (the same slots that carry a code today). A ranked slot whose fill is unknown is not a marker slot and keeps its existing layout-specific rendering. For provider `p = unavailableProviders[m]`:
   - no track and no dash are drawn in the slot;
   - the provider code `providerGlyph(for: p)` is drawn in the secondary label colour in the provider rect with today's font rule for it (`pairGlyphFont` for two characters, `glyphFont` otherwise), and the status glyph is drawn in the secondary label colour in the code rect with `codeFont`; both rects come from `glyphRects(in:)` applied to the glyph area (beside layout: the column right of the bar position, as today) or to the whole slot (jar layout, and the logo layout, whose empty slots take the jar path). In the jar layout this moves the provider code from the area above the bottom 5 pt band to the top half of the slot;
   - status glyph: `"×"` (U+00D7) when `signInProviders.contains(p)`, otherwise `"…"` (U+2026). Neither collides with a window code (`5`, `W`, `M`, `$`, `?`, scope initials).
4. Every other slot is drawn exactly as before: ranked slots, and empty slots beyond the marker list (track and dash). A provider in `signInProviders` but not in `unavailableProviders` has no effect.
5. The demo render in Sources/Limitaur/LimitaurMain.swift that sets `unavailableProviders = ["claude", "codex"]` also sets `signInProviders = ["claude"]`, so the rendered empty state shows both glyphs; like `unavailableProviders` there, it is hand-set and not derived from the demo rows.
6. docs/labelled-bars.md: the unhealthy-provider sentence describes the marker of item 3.

Success path: Claude's Keychain session is paused and Codex is throttled with no fresh metric ranked, count 3 → `unavailableProviders = [claude, codex]` (row order), `signInProviders = {claude}`; slot 0 shows "CL" over "×" with no track, slot 1 shows "CX" over "…" with no track, slot 2 shows the track and dash.
Failure path: both providers healthy and ranked → `unavailableProviders = []`, `signInProviders = []`; the rendering is the same as before the change.

## Acceptance criteria

- AC1 `projectDisplay`: a provider with one `unauthenticated` row and one `healthy` row is in `unavailableProviders` and in `signInProviders`; a provider whose only non-healthy row is `throttled`, `failed`, `unavailable`, `stale` (by the projection) or `partial` is in `unavailableProviders` and not in `signInProviders`; all healthy → both empty.
- AC2 Beside layout, marker slot: the bar rect (x 0–5 of the slot, full height) has zero alpha; the glyph column's top-half alpha sum is equal for the authentication and other markers of one provider and differs between providers; the bottom half is non-empty and its alpha sum differs between the two markers.
- AC3 Jar layout (and logo without provider images), marker slot: a 1 pt strip along the slot's left and right edges has zero alpha (no track); the top-half alpha sum depends on the provider and not on the class, the bottom-half alpha sum on the class and not on the provider.
- AC4 Within one build, in both appearances: ranked slots and empty slots beyond the marker list render identically with and without `unavailableProviders`/`signInProviders`; with every slot ranked, the markers change nothing; `signInProviders` set while `unavailableProviders` is empty renders identically to both empty.
- AC5 Rendering is deterministic; the marker renders differently in light and dark appearances.
- AC6 The full existing suite passes; frozen suites are not edited.

## Non-goals

Tooltips or hover; changes to ranking, count, width, thresholds, the dropdown or the accessibility summary; carrying snapshots across relaunch (R-G1); a marker when every slot is ranked; distinguishing a missing credential source from a transient `unavailable`; provider images in marker slots.

## Open questions

- O1 Glyphs. Recommendation: `×` (authentication, as floated in P408: not connected) and `…` (other; `~` floated in P408 is a thin stroke at this size). `!` was rejected in design review: beside bars that already signal warning and critical it can read as a usage alarm. Check the rendered demo for that misreading at Accept.

## Residuals

- The authentication glyph also shows while recovery is under way (connecting, nudging, waiting for Claude Code to write a new token); the dropdown row says which.
- An unsupported provider/source configuration (`unavailable`, "Credential source unavailable") shows `…` though waiting does not repair it.

Revision 2 after one design-review round (codex gpt-6-astra, claude-opus-5-5); not re-reviewed.
