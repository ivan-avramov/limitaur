# Labelled bars addendum

Approved 2026-10-20 (P323–P327). Supersedes only the bar geometry paragraph of docs/compact-bars.md. Ranking, counts 1–8, thresholds, tint, dropdown, tooltip and accessibility are unchanged.

- Each slot is a jar: 14 pt wide, 18 pt high, 1 pt rounded outline, 3 pt gaps, filling bottom to top. Width is 14n + 3(n−1) + 12 with marker room on the right.
- Each jar carries two glyphs stacked: a provider glyph on top and a one-character window code below. Glyphs are knocked out of the track and fill so they read at 0% and 100%. In the unfilled region they sit on the fixed dark neutral track and are therefore a fixed light tone in both appearances (amended after render inspection, P328); the fill itself keeps the menu-bar foreground tint.
- Provider glyph is a letter by default: C for Claude, X for Codex, first letter uppercased otherwise. A monochrome template image at `Resources/providers/<providerID>.png` in the bundle replaces the letter when present. The repository never contains those images; `Resources/providers/` is ignored.
- Window code, derived by `windowCode(for:)` from the metric alone, never from plan. A known duration decides first: `5` ≤6 h, `W` exactly 7 d, `M` 28–31 d, `?` any other duration. Without a duration the decoder kind decides: `5` session/five_hour (and legacy five_hour_*), `W` weekly/seven_day (and legacy seven_day_*), first letter of the scope display name for modern model-scoped limits (F for Fable), `$` spend or metered; then whole-word label hints; `?` otherwise, never blank.
- Backlog, not in scope: a model initial can collide with `M`, `W` or the provider letter.
- Unavailable slots keep the neutral dash and carry no glyphs. Health marker unchanged.
- Budget: about 150 lines drawing, 30 code derivation, 25 image loading, 70 tests. One cold review.
