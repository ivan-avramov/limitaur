# Guard amendment: frozen-suite write inventory

2026-10-20. Read-only source inspection, not a test run or guard qualification. Existing frozen16-file map and collector digest were checked unchanged. No test was edited.

| Input | Observed write/root behavior | Proposed runner contract |
| --- | --- | --- |
| Adversarial/test_acceptance.py:27–57,74 onward | Source root from `__file__`; uses LIMITAUR_BINARY or source-relative .build fallback; fixtures in tempfile directories; each app child receives synthetic HOME/TMPDIR. | Set LIMITAUR_BINARY to actual protected bundle. Parent TMPDIR under WORK; no fallback. |
| AdversarialClaude/test_acceptance.py:16–32 | Source root from `__file__`; LIMITAUR_BIN or .build fallback; mkdtemp fixtures. App child replaces env with fixed PATH and HOME=tempfile.gettempdir(), dropping inherited TMPDIR. | Set LIMITAUR_BIN; test process temp root under WORK. Fixed diagnostic routes must not need unrelated child temp/source writes; failure stays tests_failed. Do not alter frozen env code. |
| AdversarialBars/test_acceptance.py:21–43 | Requires LIMITAUR_BIN; TemporaryDirectory explicitly uses TMPDIR; fixtures written there; app child inherits test env. | Set staged LIMITAUR_BIN, synthetic HOME/CFFIXED_USER_HOME/TMPDIR under WORK. |
| Tests/LimitaurCoreTests/CoreTests.swift:207–234,241–274,389–404 | Three file-writing tests choose LIMITAUR_TEST_ROOT, falling back to TMPDIR. UUID child folders, synthetic files/statistics and two symlinks; no source-relative writes found. | Set existing WORK test-files root; keep symlink construction possible inside WORK. No real auth file/keychain write is required by these source paths. |
| Other Swift test files in frozen map | Search for file/directory writes/current-directory/process construction found no additional output roots. Runtime Foundation/SwiftPM behavior is not inferred from that absence. | Compiler cwd immutable TRUST/source; all build/cache/security/config/scratch flags under WORK. |
| Tests/MeasurementTests/test_measure_resources.py:13–16,179–185,217–231 | Imports frozen collector by `__file__`-relative path; synthetic IO/clock/sample/open functions are mocked. No source write or hard-link construction found. | Load exact source module from TRUST, cwd WORK; no collector edit. Process-statistics behavior is not a grant to read other process arguments/environment. |

Across the three old Python independent suites, collector tests and frozen native files, no hard-link construction was found. Two existing Swift symbolic-link constructions were found. No write beside `__file__` or relative-to-source output was identified in these inspected tests. This does not prove absence of effects in their dependencies, framework startup or SwiftPM.

For Python, invoke the fixed runner by absolute TRUST/source path with cwd=WORK; it imports the mapped frozen modules from absolute source paths using their existing suite IDs. Set both binary variables to the same checked staged executable. All test scratch and record output stay within WORK. Do not copy/modify frozen test code to change its roots. New tests use the separately declared fixture interface.

SwiftPM source-root writes (such as a required `.swiftpm`/Package.resolved write) and an unexpected frozen-suite external write remain measured build_failed/tests_failed, not authorization for an exception. R2 VERSION edits are parent operations on an R2-only synthetic copy between guarded builds; never on prepare's audited SOURCE or the operator checkout.
