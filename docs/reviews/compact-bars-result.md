# Compact-bars development result

Accepted source commit: `ab8b5e6c163fe042f2334f89c2c81343746cd288`. Final reviewed candidate: `d58f5a277a41a4bc393638ad378f01a7f45fb26ac9a41ce59e5ddb3c2b24981b`. Local development acceptance only; no release, installation or push.

Implemented 1–8 upward bars (default 3), system foreground tint, strict warning thresholds, no Dock icon, independent count settings, presentation-time freshness/expiry, stable synthetic demo and read-only Codex/Claude adapters. Unknown is distinct from zero; no prediction. Display delivery buffers only the newest pending state.

133 tests passed:72 native Swift,19 original frozen,12 earlier Claude frozen,18 new Claude frozen,12 collector. Native release build, synthetic renders, bundle/plist/signature and guarded production redraw/huge-expiry probes passed. Both final reviews cleared required fixes. The driver inspected rendered pixels; model reviewers inspected source and test evidence.

Release gates remain actual anchored UI/appearance/contrast/keyboard/scroll/AX, current app-bundle Codex+Claude access, default SwiftBuild qualification, and eligible60 s + 600 sperformance. No current RSS/CPU target pass is claimed. Historical52.48MiB startup RSS is an earlier nonqualifying prototype result, not a new measurement.

Known low-priority limitations: amount-only enabled Claude spend with unknown percentage remains incomplete; duplicate unverified selected Codex IDs across different tokens can collide in ranking keys; retry eligibility text may persist until the next fetch; the count-action negative test could use a deterministic local-query completion barrier. Actual AppKit draw-hook behavior remains a release check. No required source fix is deferred.

API-metered/hybrid behavior, SemVer and automated release tooling remain pending P73. Cursor deferred.

[Full report](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/report.md), [acceptance and exact tree/delta proof](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/accepted-development.json), [final review](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/runtime-evidence/bars-panel2/BP2-result.txt). Evidence, model/session IDs, findings/dispositions and reported costs are preserved outside the repository. No credential/runtime state is included.
