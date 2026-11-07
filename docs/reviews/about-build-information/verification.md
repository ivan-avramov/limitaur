# About candidate test verification

Applied the candidate patch in the tester copy. Both frozen test SHA-256 hashes matched the freeze manifest after application.

- Baseline Swift fixture test compiled and ran. All four cases exposed missing credits and copyright (eight expected issues). The ad-hoc baseline package passed the full revision, signature and 0.2.2 version assertions and exposed the missing timestamp and packaged LICENSE.
- Candidate focused Swift Testing run passed the one About test with all four parameter cases.
- Full candidate `swift test` returned zero. XCTest reported zero cases in each of its two passes. Swift Testing explicitly completed all 436 core tests in 23 suites. Under restricted execution, the UI output stopped after ten pass records without a completion summary. The direct `xcrun xctest .build/out/Products/Debug/LimitaurUITests.xctest` run with ordinary macOS permissions completed and confirmed all 36 UI tests in one suite. Together the completed runs confirm 472 Swift Testing functions, including the four-case About function.
- The actual ad-hoc candidate package built with the native SwiftPM build system and passed all four IconPackaging and all three AboutPackaging tests. These verified the tester's full HEAD plus `-dirty`, recent UTC build time, byte-identical LICENSE, strict signing verification and unchanged 0.2.2 version.
- All 49 frozen adversarial tests passed against the packaged executable (19 Adversarial, 18 AdversarialBars, 12 AdversarialClaude). All 13 measurement tests passed. The first Adversarial discovery lacked a binary path and ran zero tests. The completed rerun supplied the packaged binary explicitly.
- Inspected the three-file implementation against the spec. The metadata comes from the app bundle, version behavior is preserved, and the package captures UTC build time and copies LICENSE before signing. LICENSE is included in the dirty input path list. The bundled license link and repository fallback passed the focused test. Root separately reported observing the copyright and credits in the standard panel from the candidate source.

Verdict: the feature-specific checks and all native and offline suites pass. No feature defect found. No live app-mode or provider launch was used.

Raw candidate logs are under `.build/about-*.log` in this tester copy.
