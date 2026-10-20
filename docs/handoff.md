# Limitaur session handoff

Updated 2026-10-19 (America/Los_Angeles). Safe checkpoint for clearing the chat. All role CLI calls have finished; the smoke app is stopped, task authentication seeds removed, and disposable SDK volume detached. Ordinary Claude CLI user runtime/history remains in place and was not exported or deleted. Cleanup evidence: [cleanup.json](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/cleanup.json).

## Start here

1. Read [AGENTS.md](/Users/ivan/ws/limitaur/AGENTS.md) and [approved original specification](/Users/ivan/ws/limitaur/docs/specification.md).
2. Read the [latest report](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/report.md), [pending next-stage gate](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/next-step-gate.md), and [exact proposed UI/safety contract](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/next-ui-design.md).
3. Verify the current checkout and frozen evidence before resuming. The operator repository contains documentation only. Implementation remains outside it as an **unaccepted prototype**. This handoff is a documentation-only change, not source acceptance or scope approval.

Operator checkout: `/Users/ivan/ws/limitaur`, branch `main`. Original documentation baseline: `4d97e1b7b4b007ad12da7df120972e2c5932d003`. This handoff receives its own local documentation commit. Future orchestration must baseline the actual current HEAD rather than assume that original commit is still HEAD.

Discussion IDs were through P115 before this handoff; the closing reply uses P116. Continue at **P117**. Use plain prose for questions; no structured question UI. Never push without explicit approval in that turn.

## Approval state and next action

- P20 approved the original specification. P72 approved two bounded repair rounds R3/R4 plus a development/release sequencing exception. Those repair rounds are exhausted; do not resume the frozen worker to make further edits.
- The user approved Claude as the second provider for review, then explicitly directed: **“Use claude as a cli tool.”** Use the normal installed Claude CLI with its existing login. No further authentication-setup approval is needed.
- **P113, the concrete compact-bars/remaining-safety build plan, has not been approved.** The user instead requested this handoff. Proposed count range 1–8/default 3 is a recommendation, not a settled user maximum.
- **P73, the final API-metered/hybrid/SemVer/release-tooling contract, remains independently unapproved.** The user requested those capabilities; the detailed final contract is still pending. The bars gate does not include it. Cursor is deferred.
- This handoff request authorizes documentation only. Do not infer approval to dispatch a write-capable implementation worker or integrate the prototype.

Next session: recover state, briefly explain the pending gate, and obtain explicit approval of its exact scope. After approval, perform its focused read-only verification of the two late design clauses. A materially different resolution returns to the user. Then commit the approved specification/addendum and terse AGENTS link before establishing the new isolated implementation baseline. Use a fresh worker, a new candidate-blind reviewer Phase A followed by same-session Phase B, and a fresh full frozen-candidate panel. Preserve both old frozen suites and freeze new independent tests before candidate disclosure. Renew the pre-freeze same-worker guarded feedback and development/release sequencing exceptions only as the gate explicitly allows. Commit accepted work locally; no automatic push.

## Product direction

- Native Swift/AppKit, macOS 26+, no third-party runtime dependencies. Menu-bar only, no Dock icon. The prototype already sets `LSUIElement=true` and accessory activation policy; actual interaction remains unqualified.
- Codex and Claude now; extensible provider adapters and multiple accounts. Provider authentication is read-only. Never print, persist, commit or transmit credentials or raw account responses. No inferred plan-specific limits.
- Show highest used percentages across fresh valid limits/accounts; no prediction. System menu-bar foreground tint for normal fill, dark neutral tracks; strictly >80% yellow and >95% red. Distinguish unknown, unavailable, stale, unlimited and zero.
- User requested replacing three wide dials with upward-filling vertical bars and configurable count (for example five). Pending proposal: 1–8 bars, default 3; same provider/account dropdown and exact percentage/reset/credit metadata.
- Requested API-metered monthly budgets, hybrid subscriptions drawing credits, and a possible credit-use pulse belong to the separate additions contract. SemVer and release gate setup are also requested but not implemented.

## Prototype and verification

Durable evidence root: `/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/`.

- [frozen-candidate](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/frozen-candidate): immutable 33-file R4 implementation input, not accepted source.
- [R4-final-manifest.json](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/R4-final-manifest.json): file hashes and combined digest. [R4-candidate.patch](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/R4-candidate.patch) reconstructs it from the original baseline.
- [checks-R4b](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/checks-R4b): final commands/results. Native release build passed; **52 Swift + 19 original independent + 12 collector + 12 Claude independent = 95 passing tests**. Static renders and bundle/plist/signature checks passed. This is not release acceptance.
- [unaccepted-preview/Limitaur.app](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/unaccepted-preview/Limitaur.app): signed development bundle, unaccepted and uninstalled. Do not exercise demo account actions against live preferences.
- [runtime-evidence](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/runtime-evidence), execution-ledger.json and events.json retain exact briefs, model identities, findings and timings. Reports preserve predecessor evidence and cost limitations.

Claude's full R4 review allowed development acceptance under P72, but the final Luna panel found a required data-integrity defect, independently reproduced by the driver. Therefore **no final acceptance, implementation commit, tag, push, installation or publication occurred**. Passing tests do not overrule the defect. A separate UI design review then exposed a demo data-boundary defect.

### Required remaining fixes

1. Enabled Claude `spend`/legacy `extra_usage` with malformed percentage silently disappears as healthy empty data. Synthetic examples `{"limits":[],"spend":{"enabled":true,"percent":"bad"}}` and `{"limits":[],"extra_usage":{"is_enabled":true,"utilization":"bad"}}` both returned exit 0, `partial:false`, no metrics/warnings. Require explicit unknown/incomplete state while preserving valid quotas/amounts; never infer zero or currency.
2. Demo currently retains production Settings/Save actions. Source tracing shows Save can write real account preferences and configure the live monitor. No live reproduction was attempted. Isolate the entire reachable demo action graph: in-memory presentation preferences, synthetic/inert refresh, disabled account/connect actions, production-route tests proving zero real preference/credential/HTTP access.
3. Guard huge Retry-After display dates without capping the actual monotonic throttle. A synthetic Foundation probe at 1e308 returned an empty string, not a demonstrated crash. Add direct coverage of the real HTTP redirect callback supplying nil. Improve expiry wording. Exact scope is in the pending contract.

### Pending UI contract details

The linked design is authoritative. Important constraints: separate indicator count action from account Save/Cancel; no credential/network/source reconfiguration from count changes; one accessible status button; top-N ranking with at most eight ordered candidates; all-profile presentation-time freshness checks; ordered display revisions; local-only coalesced revalidation; one-shot scheduling that handles a deadline crossed while arming without a busy loop. Quota reset equality excludes that metric and displays “reset due,” without falsely marking all other account limits stale or zeroing usage.

Three fresh read-only Astra design rounds found issues that were incorporated. **The last two clauses were applied after the last review and are not re-reviewed; no convergence claim:**

- Snapshot-scoped reset/expiry latches prevent a backwards wall-clock change from resurrecting expired cached usage. Opaque snapshot identity and bounded cleanup keep late observations from affecting replacement snapshots/bindings.
- Balance/reset-credit expiry states join rendered signatures and coalesced deadlines. Preserve last-reported amounts/counts with explicit cached/expired labels; do not invent zero or decrement authoritative capped aggregates from partial details.

The gate explicitly proposes one focused read-only check of these exact clauses before implementation.

## Performance and release limits

Live built-app metadata: Codex succeeded with one metric, one balance and reset metadata; Claude was unavailable through noninteractive app-bundle Keychain access. Normal Claude CLI login working does not prove widget bundle access. No OS grant was made.

Latest smoke was **8.002 seconds with zero warmup**, startup/error state, zero successful interval refreshes: max RSS **52.484375 MiB**, mean/median 52.4296875 MiB; mean one-core CPU **0.000590687776%**; no observed descendants; process ID matched statistics. Default eligibility and qualification were false. Startup RSS exceeds the numeric 50 MiB budget; no sustained healthy resource target pass is established.

Still required for release: 60-second warmup plus 600-second eligible healthy default Codex/Claude measurement, at least 18 successes per provider, no pauses/throttles/helpers; max sampled aggregate RSS <50 MiB and mean one-core CPU <0.1%. Record fixed indicator count and keep dropdown closed; do not extrapolate between unmeasured counts. Actual click/anchor/keyboard/scroll/light-dark/increased-contrast/accessibility checks and Claude app-bundle access remain unverified.

Default SwiftBuild compiles but its service-context link fails with permissionDenied under the guard. The emitted exact swiftc link succeeds directly under that same guard; a global scratch-path cause is not established. Native backend passes but is deprecated. Default-backend qualification remains a release gate. Do not broaden permissions based on an assumed cause.

## Integrity anchors

Verify SHA256 before using evidence; do not rewrite frozen inputs:

| Artifact | SHA256 |
| --- | --- |
| Original specification | `b4616fb36fbe722f28de3a12fa33fc1e1be07773479fb3d90396c625a707564d` |
| R4 combined 33-file manifest | `58013e4bcc6b738b09901852ae12312fa12b0106492d0e1e3a970a701006203d` |
| Pending next-ui-design.md | `cdc804741657d1608266b9e08059dfb713bbeecb5e2d414d9867c0b63c0a9b44` |
| Separate additions-design.md | `1008f15e1d1fd63534500a998b329668790eefa8c06fc6a140aed5c750253ae3` |

The combined candidate digest is SHA256 of the compact, sorted-key JSON per-file hash map, not the hash of the manifest document. Individual hashes are in R4-final-manifest.json. Original 19 tests and Claude 12 tests/plans must remain byte-identical to [reviewer-tests-freeze.json](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/reviewer-tests-freeze.json) and [claude-tests-freeze.json](/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/claude-tests-freeze.json). “Frozen” means independently written before seeing candidate code, hash-recorded, and protected from implementation edits; add new tests separately rather than changing the accepted target to fit the code.

## Roles and execution cautions

For the next nontrivial/security phase read `/Users/ivan/.agents/skills/four-eyes/SKILL.md`, its phase briefs, and `/Users/ivan/.agents/skills/review-panel/SKILL.md`. Strict mode applies. Planned roster in the gate: designer gpt-6.1-sol, verifier gpt-6-astra, fresh worker gpt-6-sol, fresh normal-CLI Claude Sonnet 5.5 reviewer, fresh full gpt-6-luna panel. Verify actual model IDs; stop for a user decision if a required role cannot be filled rather than substituting silently. Cross-vendor reviewer/worker and panel/reviewer are L3; same-vendor different-model roles are L2, including the disclosed degradation below preferred L3. The report records limitations and all actual roles; do not claim every historical model reviewed the final candidate.

Normal reviewer CLI: `/Users/ivan/.local/bin/claude`, actual prior model `claude-sonnet-5-5`. Use its existing normal login/runtime with safe mode, automatic memory/MCP disabled, restricted file tools and fresh candidate-blind session. Do not repeat the failed copied `~/.claude/.credentials.json` procedure. CLI may maintain its own login normally under the user's directive; the app's authentication remains read-only. Model tools must not read credentials or unrelated user history. Run code/tests separately under the phase's network/real-credential/runtime-state-denying isolation; never execute candidate code with CLI credentials available.

Prior reviewer session `922923f9-bc54-4392-a25b-f115b4cc8b0b` belongs to the old frozen tests/R4 review. Use a new reviewer A/B session for the new specification. Prior R4 worker `01a1570c-1875-7b90-b6cd-523c14e7a302` must not edit the frozen candidate. Exact launch guards/briefs/model evidence are in runtime-evidence. Read the recorded mechanisms and probes before making any sandbox claim.

Optional surviving scratch: `/private/tmp/limitaur-four-eyes-01a15018`. It is not durable evidence. It contains `normal_claude.py`, role/check/smoke helpers and a detached SDK sparseimage; no authentication seeds should remain. Revalidate scripts/guards before reuse. `check_round.py` does not run the Claude suite automatically; `check_claude_suite.py` did that separately. Use fresh statistics paths for any future smoke.

**Do not run `integrate_accepted.py` now.** It was never run, requires a truthful acceptance record that does not exist, and hardcodes the original HEAD. A future accepted integration must account for this handoff and approved specification commits, preserve operator changes, and verify the authorized delta. No accepted-development record may be fabricated to bypass the gate.

No computer-use work is needed to recover this checkpoint. Prior UI attachment was unsuccessful and access to Codex UI was denied; do not circumvent that. No OS grants, provider-auth writes, installation, login item, tag, push or publication are authorized by this handoff.
