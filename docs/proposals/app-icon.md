# App icon and status refresh

Problem: Give Limitaur the approved simplified monochrome minotaur icon, remove the white outside the charcoal tile, and reconcile stale project status and the existing SemVer procedure.

- Approval: user, 2026-11-07: “I like the icon - go for it. But i want the outer-most outline to be the black (drop the white)”. P5 documentation scope approved with it.
- Baseline: 7849371; implementation and verification use isolated copies. Light review; no runtime/authentication changes.
- Budget: 100 added packaging/test lines, 80 added documentation lines; binary assets and review records excluded.
- Preserve the approved artwork tracked in Resources/AppIcon.png: transparent outside, charcoal outer edge, off-white interior mark.
- Track Resources/AppIcon.png (source) and Resources/AppIcon.icns (all standard 16–1024 pixel representations). Generate with macOS sips/iconutil, no new runtime dependency or build-time image dependency. Record a short regeneration command in README.
- Resources/Info.plist names AppIcon.icns using CFBundleIconFile; scripts/build-app.sh copies it into Contents/Resources before signing. Missing icon fails packaging. Keep LSUIElement true, signing behavior and version behavior intact.
- Success: packaging in a fresh output path carries the registered icon, validates/signs, reports 0.2.1, and leaves app behavior unchanged. Failure: missing source ICNS exits nonzero, never reports successful packaging.
- Check corners are alpha-transparent and outer visible pixels dark, interior artwork retained; inspect at 16/32/64/128 pixels and full size. Do not change menu-bar indicators.
- README: correct unhealthy-slot wording, stale nudge/M1 observations and superseded release-gate claims; state app icon vs no persistent Dock presence; clarify manual SemVer release procedure without new machinery.
- CHANGELOG: add icon under Unreleased; correct obsolete claim that nothing has been tagged. Keep version 0.2.1 and dated releases intact.
- Handoff: add current summary; replace stale pending list, preserving historical sections. Current outstanding: keyboard/scroll/accessibility, L2 reduction observation and second machine, API/hybrid and Cursor deferred; file-source recovery unverified. Orphan signing entry and old Keychain-API warnings are resolved.
- Evidence supplied by parent: release 0.2.1 build 92, release tests 35 UI + 436 core + 49 Python + 13 collector. L1 passed in C9, relaunch persistence in C10. Timeline through 2026-11-07: 19 nudge increments, each followed by credentialResumes increment within 120 seconds; no recorded nudgeFailures/keychainSuspensions at those samples. This is aggregate observational evidence, not proof of exclusive causality; do not claim second-machine validation.
- Preserve limitaur-review in place; no deletion/archive in this increment. No install, live app launch, provider requests, version bump, tag, push or release.
- Tests: focused offline packaging checks and current native suite; existing tests unmodified. Build/test process access may be requested if needed, with ad-hoc signing forced (LIMITAUR_SIGN_IDENTITY=-). Do not launch app mode.
- Acceptance: approved visual direction preserved, icon registration/copy verified in built bundle, missing-asset failure verified, checks truthful, no runtime code changes, documented evidence qualified, budget met.
