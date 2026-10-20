# Limitaur handoff

Updated 2026-10-20 (America/Los_Angeles). The compact-bars development stage is accepted and committed locally as `ab8b5e6c163fe042f2334f89c2c81343746cd288`. The completed result/handoff documentation is in `9cdcda8b1c125a53f7551eb18782861cea2be95b`; the checkout was clean at that commit before this documentation-only refresh. No push, tag, installation or release. Runtime/test/build inputs remain unchanged. Baseline future work from actual current HEAD, not earlier hardcoded orchestration hashes.

## Read first

- [AGENTS.md](/Users/ivan/ws/limitaur/AGENTS.md), [original specification](/Users/ivan/ws/limitaur/docs/specification.md), [approved compact-bars addendum](/Users/ivan/ws/limitaur/docs/compact-bars.md), [README](/Users/ivan/ws/limitaur/README.md).
- [Development result](/Users/ivan/ws/limitaur/docs/reviews/compact-bars-result.md) and [full stage report](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/report.md).
- [Acceptance](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/accepted-development.json), [final manifest](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/remediation-1/candidate-manifest.json), [final review dispositions](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/remediation-1/review-acceptance.json).

Current closing discussion point P148; continue at P149. User standing rules: plain-prose questions, no structured question tool; concrete plan/approval before nontrivial implementation; commit coherent accepted work autonomously; push only with explicit authorization in that turn.

## Next session

Recover the current checkout and read the linked result and pending additions contract. P119 is complete; do not reopen its approval or resume its finished helper sessions. Present a concrete next implementation plan for the outstanding P73 work and obtain approval before implementation. Recommend SemVer and automated release tooling first, followed by API-metered/hybrid support, so later release evidence can be collected against the final frozen artifact. This ordering is a recommendation, not approval of either remaining scope.

Keep actual UI, current Claude app-bundle access, sustained performance and default-backend qualification explicitly unverified. Use Claude as a normal CLI with its existing login; no repeated credential-copy setup. Preserve all frozen tests and do not push. This session can be cleared: source, reviews, results, bundle and cleanup evidence are durable, and no helper or implementation phase is still running.

## Current product

Source now lives in this operator repository. Native Swift/AppKit macOS 26+, no runtime dependencies, menu-bar only with no Dock icon. It shows 1–8 upward bars (default 3), top fresh percentages across Codex/Claude profiles, system normal tint, yellow above 80% and red above 95%, a provider/account dropdown, and no prediction. Count changes do no credential/network/reconfiguration work. Demo is synthetic, uses in-memory settings and a fixed default presentation clock; account/connect disabled, refresh inert. Live freshness remains 90 seconds. Reset/credit expiry is sticky per snapshot across backwards wall changes. Large dates cannot overflow the coalesced wait; authoritative deadlines stay uncapped. Pending display delivery is bounded to newest state.

All 133 automated tests passed: 72 native Swift, 19 original independent, 12 prior Claude independent, 18 new Claude independent, and 12 collector tests. Both independent full reviews cleared required fixes; native release build, renders, bundle/signature and production-path probes passed. The 49 independent tests across Adversarial/, AdversarialClaude/ and AdversarialBars/ remain frozen; do not edit them to fit future code. Their freeze records and exact hashes are in the linked evidence. New scope needs new candidate-blind tests under the installed skill.

Final candidate digest `d58f5a277a41a4bc393638ad378f01a7f45fb26ac9a41ce59e5ddb3c2b24981b` hashes compact sorted JSON of the per-file map, not the manifest document itself. All 40 tracked paths/content hashes matched at accepted source commit. Operational handoff/result documentation follows in its own commit and is separate from that source snapshot.

A signed local [development bundle](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/remediation-1/development-preview/Limitaur.app) and [synthetic renders](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/remediation-1/renders) are saved, not installed or release-qualified.

## Outstanding scope and release gates

P119 is APPROVED and COMPLETE for development. Do not ask for its approval again. P73 API-metered accounts/hybrid credit use/SemVer/release tooling remains separately PENDING; [exact last additions contract](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/additions-design.md), SHA256 `1008f15e1d1fd63534500a998b329668790eefa8c06fc6a140aed5c750253ae3`. Its heading says approved scope, but the final detailed contract was not approved. Cursor deferred. Recommend version/release tooling before collecting artifact-bound release evidence; reporting coverage/current-day semantics and organization-unverified restart binding need careful review before API implementation. Do not silently approve or implement the pending contract.

Release readiness is false: actual menu-bar anchoring/click/keyboard/scroll/light-dark/increasedcontrast/AX; current app-bundle Codex+Claude integration, especially Claude Keychain access; default SwiftBuild backend qualification; sustained eligible two-provider performance. Native backend passes but is deprecated; default service-context linking failed under the prior guard, although its emitted direct link succeeded. Cause not established. No permission broadening occurred.

Required performance: 60-second warmup plus 600 seconds measured, healthy default Codex/Claude, at least 18 successes/provider, no authentication pauses/throttles/helpers, fixed indicator count with dropdown closed, maximum sampled aggregate RSS below 50 MiB and mean one-core CPU below 0.1%. No new live measurement for current bars source. Historical 8-second R4 startup/error smoke max RSS of 52.484375 MiB was nonqualifying. Codex metadata succeeded and Claude noninteractive app access failed only on that earlier prototype; normal Claude CLI auth does not establish widget bundle access. Never grant OS access automatically.

Known minor residuals are in the result/report: conservative amount-only spend, unverified duplicate selected-ID collisions, eligible-but-still-visible retry text, deterministic async test barrier improvement, internal test seams and unverified AppKit draw-hook behavior. No required source finding remains.

## Workflow and cleanup

The user replaced AGENTS instructions during review. Installed four-eyes was 0.6.0 (`SKILL.md` and `briefs.md`) and review-panel 0.4.0 at completion. Read current files for new work; do not blindly reuse old 0.5 scripts. The last stage retained its approved stricter OS guards and separate offline test execution. Do not imply that merely loading the skill activates a sandbox or that the guards prove Keychain/IPC containment.

Claude reviewer uses `/Users/ivan/.local/bin/claude` with existing normal login/runtime. User explicitly said “Use claude as a cli tool.” Do not copy stale `.credentials.json` or ask another auth-setup question. Existing reviewer session48810cf2-3e8d-4256-9623-7d1e70dc06f5 belongs to this completed specification; use a fresh candidate-blind session for a new feature specification. Preserve frozen tests. Normal CLI runtime was retained and not exported; task auth seed files removed. All role calls and probe apps finished; disposable SDK volume detached.

Durable evidence is `/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/compact-bars/`; earlier unaccepted95-test prototype remains under claude-continuation/ for history. Scratch `/private/tmp/limitaur-four-eyes-01a15018` is optional and may disappear. Old integration helpers hardcode obsolete baselines; do not reuse them. There is no unfinished implementation role or pending repair to resume.

No computer-use work is needed to recover. Prior access to Codex UI was denied; do not circumvent it. Actual Limitaur UI and OS access are unverified release tasks. No install/login item/authwrite/OSgrant/tag/push/publication is authorized by this handoff.
