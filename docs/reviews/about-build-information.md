# About build information review

Status: accepted by the operator on 2026-11-07 (“accepted both. proceed”); applied to the operator tree. Baseline 2abe1aa9f0eecedec02a391ca635144292999b28. Approved P1/P2 scope, user Go: “sounds good: proceed” on 2026-11-07. Release tooling is a separate proposed increment.

Change: retain standard About panel; display repository, full build revision, UTC build time, bundled MIT license link and © 2026 Ivan Avramov. Missing metadata shows Unavailable. Packaging copies LICENSE before signing, stamps build time and includes LICENSE in dirty inputs. Product, tests and README total 118 added/removed lines, within 180 budget.

Validation: 436 core and 36 UI Swift Testing functions passed, including four new parameterized About scenarios; 49 adversarial, 13 measurement, four icon-package and three About-package checks passed. Frozen tests reproduced missing metadata/copyright/license on baseline. Plain host-restricted UI runs stopped without a summary; direct xcrun xctest under normal macOS access completed all 36 UI tests. Focused candidate bundle identity was the isolated tester HEAD with -dirty, not a release identity. Actual signed package verified revision, timestamp, license and version. Root compiled the exact candidate AppVersion.swift into a temporary preview with synthetic build metadata and inspected the native panel: all fields/links visible, full revision wraps without clipping, copyright in footer. Temporary preview closed. No live provider monitoring, install or release performed.

Cold review: GPT-6 Astra returned NOTHING OF SUBSTANCE. No findings to dispose; no repair round or follow-up review used. All roles use OpenAI; correlated model/vendor mistakes remain uncovered. Host follow-up supports continuing the same test-writer despite the older skill's CLI-only guidance.

[four-eyes 0.7.0] outcome: completed; mode: light
Designer: root active host session; implementer: host gpt-6.1-terra /root/about_implementation; fixes: none.
Test-writer: host gpt-6.1-sol /root/about_tests; continued; frozen 2026-11-07T22:10:40Z, candidate revealed immediately after freeze.
Panel: host gpt-6-astra /root/about_review, briefed cold candidate; returned. Verify: none.
Go: 2026-11-07, “sounds good: proceed”; accept: 2026-11-07, “accepted both. proceed”; commit: this change; push: none.

Temporary review material, raw logs and tests are retained in /private/tmp/limitaur-about-20261107/. Accepted patch is recorded by this commit; detailed verification is retained under docs/reviews/about-build-information/.
