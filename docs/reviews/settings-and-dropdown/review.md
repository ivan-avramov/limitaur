# Settings window and dropdown redesign

Completed 2026-11-10; commit 12f12d6. Specification: [settings-and-dropdown.md](../../proposals/settings-and-dropdown.md) with revisions 2 and 3. Operator approvals: P21–P26 "go with your recs on all four - i trust your choice"; second fix round "go for the second fix round"; accept "accepted. Proceed". Operator feedback during the run: "menus are MUCH better - excellent work!".

Result: a native Settings window (General and Providers toolbar tabs, SwiftUI grouped forms) replaces the NSAlert Accounts dialog and the Settings pop-up menu; one section per provider with switch, source and file chooser, live status and Connect, provider options, and "Other accounts". The dropdown shows one card per account with badge, status chip, usage bars in threshold colours and secondary rows. Keyboard shortcuts, a minimal main menu, read-only demo Settings, and default-workload eligibility counting only enabled profiles (P25).

Tests: independent suites and 13 ports (frozen 11:21:33 PST; amended for revision 2 at 11:55:52 and revision 3 at 12:09:37) plus implementer tests; final 146 UI and 518 core tests passed in parallel and serial. Renders (light/dark dropdown, empty states, both Settings tabs) reviewed by the designer.

Findings: change opinions from both members and the designer's render review became revision 2 (F1 percentText trap, F2 hidden enabled accounts, F3 popover keyboard, F4 Settings keyboard and main menu, F5 demo Settings, F6 accessibility labels and label commit, F7 connecting state, F8 stale styling, F9 warning colour, F10 metric density, F11 popover sizing, F12 renders, F13 docs), all adopted. Verify: Sol nothing of substance; Opus raised six minor items; the operator chose a second fix round for four (G1 window position only, G2 demo Settings content, G3 shared status mapping, G4 label-commit scope); two stay manual checks. Residuals: [settings-and-dropdown-residuals](../backlog/settings-and-dropdown-residuals.md).

Budget: about +750/−300 estimated; actual +1066/−324 product lines, reported to the operator before acceptance.

[four-eyes 0.7.0] outcome: completed; mode: light
Designer: claude-code claude-opus-5-5; implementer: claude claude-opus-5-5 26ffc129; fixes: claude claude-opus-5-5 8b828992, b188049a.
Test-writer: claude claude-sonnet-5-5 d4a1bc81, continued; frozen 11:21:33 PST, revealed 11:29:33 PST.
Panel: cold candidate claude claude-opus-5-5 8c6bc54f and cursor-agent gpt-5.6-sol-high, checkout; verify Opus resumed, Sol fresh shown both opinions; second fix round no panel pass (budget used).
Shared: as for the Cursor run.
Push: none.
