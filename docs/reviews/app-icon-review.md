# App icon review — 2026-11-07

Baseline: `7849371`. Specification: [app icon](../proposals/app-icon.md). Scope: approved artwork, bundle packaging, focused checks, current status and manual release documentation. No runtime code changed.

Approval: “I like the icon - go for it. But i want the outer-most outline to be the black (drop the white)”; revised artwork accepted: “the icon looks good”. Implementation applied under that authorization; no installation, tag, release or push.

Light independent workflow: host designer `/root`; isolated implementer `/root/icon_implementer` using the inherited host model; continued test-writer `/root/icon_testwriter` with requested `gpt-6-astra`; cold reviewer `/root/icon_cold_review` with requested `gpt-6-astra`. Exact model identities were not independently exposed by the helpers. Claude members were omitted to honor the host-only preference. All roles share OpenAI; vendor-correlated errors remain uncovered. Host follow-up continued the same test-writer, superseding the skill's obsolete non-continuation assumption.

Tests frozen 2026-11-07T18:38:47.626Z, candidate revealed 18:39:42.226Z. Frozen test SHA-256: `58cf6b307605ba2606eef63d316168d854dd6abb2653eab882af2c32092be8aa`; unchanged through verification. Candidate SHA-256: `fa4215002cfc83bb2a465ea7f494843e6d5ed1e11147ca5156813b3605e8463a`.

Baseline packaging checks: two pass, two fail as expected because the icon was absent. Candidate: four pass; all ten 16–1024 pixel representations decode, icon registration resolves, version remains 0.2.1, menu-bar mode remains enabled, strict signature verification passes. Missing ICNS: immediate exit 1, empty stdout, no output bundle; source restored afterwards.

Existing checks: `swift test` passed 35 UI and 436 core tests. The three Adversarial suites and MeasurementTests passed 62 tests (49 + 13), with both binary-path variables set to the candidate executable. All ran once against the candidate; only diagnostic modes executed. Builds explicitly used ad-hoc signing. No live account access or app-mode launch occurred.

Visual checks: approved full-size artwork and 16/32/64/128 images inspected. Source PNG preserved byte-for-byte; packaged 1024 image has alpha-zero corners and dark silhouette edges (maximum sampled sRGB channel 60.48/255). NSWorkspace resolves a valid icon without launching the app. No physical Finder/About UI inspection or installed-app replacement was performed.

Cold review: one read-only candidate pass, including specification, frozen tests, implementation/testing reports, images and source evidence. Verbatim result: **NOTHING OF SUBSTANCE**. No findings, repairs or follow-up review. Outcome: completed, light mode.

Budget: 3 added packaging/plist lines + 59 test lines (100 allowed); 44 documentation lines + 19 proposal lines (80 allowed). Binary assets and this review record excluded. Durable results are recorded here; temporary copies, build logs and process reports are disposable.
