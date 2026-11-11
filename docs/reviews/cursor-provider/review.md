# Cursor provider

Completed 2026-11-10; commit c088dee (rebased from 8ab597e). Specification: [cursor-provider.md](../../proposals/cursor-provider.md). Operator approvals: scope P1–P7 "p1-p7 sound good"; Go "approved"; implementer cast changed "let's switch to b)"; accept "accepted".

Result: provider `cursor` reads the cursor-agent token from Keychain item `cursor-access-token`/`cursor-user` through `/usr/bin/security`, sends `GetCurrentBillingCycle` then `GetDailySpendByCategory` with no team or user ID (caller's own spend only), and shows one `CU`/`$` bar of spend against the effective per-user limit. The design moved from `GetTeamSpend` (which returned the 15,334-member roster, 1.6 MB, unless filtered by email) to the self-scoped endpoint after the design review; the endpoint was found in the Cursor app bundle and verified live. Live C7: `--check-live` cursor success, metricCount 1; operator compared the dropdown with Cursor's dashboard ($97.61 both).

Tests: 72 independent tests (frozen 10:23:32 PST, three compile-only and two test-input amendments, one assertion moved to revision 3) plus 8 implementer tests; 512 serial suite passed; parallel failures matched baseline (pre-existing, since fixed by 8d787e2). The new unknown-spend test failed on the pre-fix candidate and passed after.

Findings: design opinion 13 distinct (F1 roster exposure, F2 identity binding, F3 unknown versus zero, F4 USD, F5 stats path, F6 rejection contract, F7 eligibility, F8 baseline amendment, F9 Add Cursor mapping, F10 real values in docs, F11 fractional cents, F12 paused wording, F13 approval references): adopted F1, F2, F5, F8, F9, F10, F13; adapted F3, F6; F4 to operator (approved USD); declined F7, F11, F12 with residuals. Change verify: V1 `--check-live` 35 s and V2 unknown spend not shown as zero adopted and fixed; V3 real limit removed from spec; V4 day-before-cycle and V5 invalid-cycle wording declined (R7, R8). Residuals: [cursor-provider-residuals](../backlog/cursor-provider-residuals.md).

Budget: about 250 product lines estimated; 180 actual. Tests 1,330 lines against about 250 (boundary tables).

[four-eyes 0.7.0] outcome: completed; mode: strict (credential source, data boundary)
Designer: claude-code claude-opus-5-5; implementer: claude claude-opus-5-5 13fcf770; fixes: claude claude-opus-5-5 b9a45553.
Test-writer: claude claude-sonnet-5-5 0b8a88bf, continued; frozen 2026-11-10 10:23:32 PST, revealed 10:26:13 PST.
Panel: design opinion cursor-agent gpt-5.6-sol-high (user instructions unconfirmed) and claude claude-opus-5-5 23d4beb0, both checkout; verify Opus resumed, Sol fresh shown both opinions.
Shared: designer, implementers and one panel member Opus 5.5; test-writer Anthropic; Anthropic-correlated errors covered only by Sol.
Push: none.
