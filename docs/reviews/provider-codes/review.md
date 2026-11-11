# Customizable provider codes, account labels and "Other accounts"

Completed 2026-11-10. Specification: [provider-codes.md](../../proposals/provider-codes.md) with Revisions 2 and 3. Operator approvals: P41 "agreed on your rec for Default"; P42 "sounds good on the mechanics but it should also show in the toolbar on the mac (the bars we display)"; Go "proceed with the rest as you proposed"; accept "accepted your recs on the above" (including the line-budget overrun).

Result:
- **P42.** The user overrides the menu-bar code of Claude, Codex, Cursor or the shared budget by clicking its badge in Settings → Providers, or "Menu bar code" in General → Shared budget.
  - A code is one or two ASCII letters or digits, uppercased, and stored under `providerCodes`.
  - A code another of the four already shows is refused; a look-alike is saved with a warning; clearing restores the default.
  - Overrides apply at once to the menu-bar bars, including the unhealthy marker, the dropdown badges and Settings. They beat a bundle image, and a code too wide for its area shrinks to fit.
  - Stored values load through a validation that is a fixed point, so two codes never coincide.
- **P41.** The dropdown header omits "· <label>" for a provider's only card.
- **P44.** "Other accounts" toggles from its label and by AXPress.

Tests:
- Independent frozen suites in `Tests/LimitaurCoreTests/ProviderCodes` and `Tests/LimitaurUITests/ProviderCodes` ([test-freeze.json](test-freeze.json)): frozen 22:32:02 PST, Revision 2 tests 22:34:35, revealed 22:34:43, fix-round delivery 23:04:40. Plus 10 implementer tests.
- Every adopted defect has a test that fails on the first candidate and passes on the final one.
- Final run in the operator tree: 242 UI and 640 core tests in parallel and serial, release build, Adversarial (19), AdversarialBars (18), AdversarialClaude (12), release tooling (11).
- The release gate's UI pass passed 42 checks on the fixed candidate, live:
  - P44 press, duplicate refusal with its footnote, Escape cancelling without closing.
  - Saved code stored uppercased; Settings badge and menu-bar glyph changed.
  - Closing Settings commits the draft; a reopened window shows badges; clearing restores the default everywhere.

Findings:
- **Test-writer, first delivery.** Two duplicate paths in the specification (one-pass validation; reset before the duplicate check) became Revision 2. The implementer had resolved both independently.
- **Change review.** Opinions from Opus and Sol and the test-writer's verdict became Revision 3, all adopted:
  - R3.1 case-insensitive ids (Opus, Sol, test-writer);
  - R3.2 editing lifecycle on close, disappear and Escape (Opus, Sol);
  - R3.3 focus (Opus);
  - R3.4 fit, confirmed by measurement: WW 16.6 pt in a 13 pt area (Opus);
  - R3.5 budget code row always shown, adapted (Opus);
  - a bundle-image override test (Sol, Opus).
- **Declined.**
  - Sol's argument-order blocker: the specification does not fix the parameter position, and only the tests' call order changed.
  - The test-writer's docs-scope note: those files were in the implementer brief.
- **Test validity.** Four accessibility-tree header tests could not pass in the test process and were retired in favour of pixel tests; one unobservable assertion was removed.
- **Verify.** Opus resolved all, with new minor N1 (Escape with refused hidden edits) declined as R1. Sol resolved D2–D5; its mixed-case drawing-key point was declined as R2 (spec R3.6); its blocker was the staging copy, which lacked the call-order amendment.
- Residuals: [provider-codes-residuals](../../backlog/provider-codes-residuals.md).

Budget: about 150 product lines estimated; actual +222/−34 (fix round about +32). Reported to the operator and accepted.

[four-eyes 0.7.0] outcome: completed; mode: light
Designer: claude-code claude-opus-5-5; implementer: claude claude-opus-5-5 c643b89d; fix: claude claude-opus-5-5 a62b814d.
Test-writer: claude claude-sonnet-5-5 4d2933c2, continued; frozen 22:32:02 PST, revealed 22:34:43 PST.
Panel: opinion on the candidate by claude claude-opus-5-5 cfdd5ec4 (checkout) and cursor-agent gpt-5.6-sol-high (checkout, user instructions unconfirmed); verify Opus resumed, Sol fresh shown both opinions.
Shared: designer, implementer, fix and one panel member are claude-opus-5-5 (fresh sessions); not covered: errors Opus makes consistently, partly offset by Sol (another vendor) and Sonnet tests.
Push: none.
