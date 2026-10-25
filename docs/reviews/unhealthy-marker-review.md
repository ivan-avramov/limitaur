# Unhealthy-marker (P408) review record

Specification docs/proposals/unhealthy-marker.md revision 2; evidence /Users/ivan/ws/limitaur-review/2026-10-25-unhealthy-marker/.

```
[four-eyes 0.6.6] outcome: completed; mode: light (presentation only, no credential or data-boundary change)
designer: Claude Code: claude-opus-5-5, session 01GZQTjDDNCxf46QxiXTzfmn
design review: codex: gpt-6-astra, 01a17402-61f8-74c1-9ea5-ad582e8fa507, checkout, returned; claude: claude-opus-5-5, c863f1bd-ec43-45db-ae2b-c2fced76bc33, checkout, returned; rounds 1; same model as designer: opus; same vendor: opus
implementer: claude: claude-sonnet-5-5, d7963aa9-f12a-489a-ab70-52d69b63ec7e; fixes: none
test-writer: codex: gpt-6-astra, 01a17409-6f7a-7d60-a032-9f937cc292c0; second delivery continued; same model as designer | implementer: no; tests frozen 2026-10-25T17:13Z, candidate revealed 2026-10-25T17:16Z; one test amended by its author (windowless needsDisplay) and refrozen 17:19Z
change review: codex: gpt-6-astra, 01a17414-b777-7a00-bda0-65cfa264f9ea, checkout, returned; claude: claude-opus-5-5, b8742525-8f52-42e0-9f1a-96f8115a73cb, checkout, returned; same model as implementer: none; same vendor: opus (with implementer and designer)
not covered: opus with designer: errors this model makes consistently in design judgement; sonnet/opus: Anthropic-shared errors in AppKit drawing, checked only by codex
go: 2026-10-25T17:08Z, "p529: accepted / proceed"; accept: 2026-10-25, "accept"; commit: see git log; push: none
```

Design review (round 1): both members found that `unauthenticated` covers recovery in progress (connecting, nudging, auto-resuming pause), so an "act/wait" glyph would mislead; adapted by redefining the glyph as cause (authentication / other). Adopted: corrected residual, logo exception wording, within-build acceptance criteria, named font, jar repositioning, demo note, "!" replaced by "×". Declined: dropping the change-check comparison (opus F8: "Drop the change-check edit from item 2"), kept for symmetry and to avoid coupling to the accessibility text.

Change review: no product defect. Declined to backlog, shown to the operator: R-M1 controller-path test gap (both, major: "Removing the assignment at AppUI.swift:789 would leave these tests passing"), R-M2 provider-image test gap (codex, major). Budget overrun 31/30 accepted as is.

Tests: 32 UI + 426 core native three times (6 frozen UnhealthyMarker tests), release build clean, 49 frozen Python, 13 collector (verify-c1.txt). Render checked in both appearances for the "bar or alarm" misreading: none.
