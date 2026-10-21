# Reduced P73 versioning/packaging design checkpoint

Recorded 2026-10-20 (America/Los_Angeles), closing discussion P308. Documentation checkpoint only; no reduced implementation or test writer has started. Pre-checkpoint HEAD is eebcdf191ae1ede6f9f61948a1b14f913ab0fe4b; recover actual HEAD after this commit.

## Authority and contract

The operator approved the reduced scope after the churn audit and then instructed continuation. Existing Go covers routine preparation, implementation and repairs within the approved execution boundaries. Do not ask for another implementation Go or turn minor design choices into permission prompts. The operator subsequently requested this handoff before further work.

Normative contract: [release-tooling-v1.md](../proposals/release-tooling-v1.md), SHA256 `1468c65287d84346b3fc3eb43c706562cf0e3ea5eb4399b153925a8f9982111d`. It replaces the unimplemented full release-platform product design, preserving its historical evidence. Deliver VERSION, local SwiftPM generation, early --version/About, build/changelog validation, ad-hoc packaging and a bounded artifact identity manifest. Keep the development harness external. No production supervisor, provisioner, generic Git auditor, Mach-O parser, evidence engine or automatic readiness claim.

P119 remains closed at ab8b5e6 with 133 recorded passing tests. Preserve its 16-file frozen map and collector byte-for-byte. API/hybrid is later, unapproved work. No push, tag, installation, release, credential copying, auth writes or new host permissions. Normal Claude CLI login remains the method; CLI success does not qualify the app bundle's access.

## One focused design round

Astra and Opus reviewed the same frozen packet independently; both results were collected before judgment. Astra returned 2 findings; Opus returned 18. All 20 have explicit dispositions in the external ledger. Final contract corrections were NOT re-reviewed; this is not a convergence or implementation clearance claim. Continue to blind tests, implementation and executable validation, then fresh final change review. Do not start a second paper-design loop for optional hardening.

Adopted or clarified: wrapper-owned release configuration; tracked-only status/digest semantics; private snapshot directory and exclusive file creation; explicit build-number recomputation; helper never executes the app; physical root/known alias handling; inert SOURCE Git metadata and bounded WORK data fixtures; protected real artifact fixtures; parent-controlled incremental VERSION tests; changelog/CLI grammar; and partial-publication diagnostics.

Retained existing canonical LF hash preimages and normalized N.0.0 build numbers rather than adopting conflicting representations. Preserve existing Settings indices and indicator submenu; append About directly at index 3. Declined an unnecessary native test target, hypothetical frozen parent-menu/help assertions, another plugin feasibility pilot, and a generic hidden-index-flag auditor. Prior candidate evidence already establishes guarded plugin/native-build feasibility; actual tracked-byte hashing binds the trusted checkout inputs without expanding into hostile-Git auditing. See the ledger for each disposition and its reason.

Runtime: Astra gpt-6-astra, session 01a15c8c-239e-75a0-99e8-3babfad07f0e,134.463s, cost unreported. Opus claude-opus-5-5, session ee0dfa72-0520-43c0-acb0-a18eba1ff3d2,318.935s, reported $0.8761978. These are review calls, not app/test runs.

## Preserved history and next work

Old candidate 1 was never applied to this checkout. Its recorded 322 tests yielded 242 passes / 80 failures, including all original 133 passes. The former 25-group full-platform remediation was never dispatched and is superseded. Its frozen 50 AdversarialRelease tests remain unchanged outside the checkout, with their original results. They target the retired API; do not amend them, claim them passing, or silently transfer them into the new acceptance suite.

Next, adapt fresh per-phase drivers from the qualified external v2/private-volume infrastructure; do not blindly rerun consumed drivers with old baselines. Use a fresh GPT-6.1-Sol blind writer for AdversarialPackaging, freeze it before candidate disclosure, then fresh Sonnet in a separate tracked-only source copy. Use the same writer for B review and fresh Astra/Opus for final change review. One coherent semantic remediation round is budgeted. Original 133 tests remain mandatory. Tests and app/helper code run only under the unchanged qualified guards, including real artifact protection controls. No reduced worker is active.

The trusted stdlib inert Git metadata fixture control passed on five synthetic files, fixed read-only Git queries and unchanged metadata; cleanup completed. This is fixture-infrastructure evidence only. It does not qualify the reduced product, replace phase controls or add app test passes. The generic reduced driver has not yet been adapted. Old normal-user release-TCB execution remains separately gated and is unnecessary here; new helpers also execute only guarded during this task.

Actual anchored UI/AX, current app-bundle Codex/Claude integration, default-backend qualification and sustained 60-second warmup plus 600-second two-provider performance remain release gates. No new live measurement or release readiness is claimed.

## Evidence locations

Reduced evidence: `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/reduced-v1/`. Read `design/input-freeze.json`, `design/dispositions.json`, `design/runtime-metadata.json`, both `design/{astra,opus}/result.txt` and `infrastructure/git-fixture-control.json` as needed. `checkpoint.json` records the latest local checkpoint commit after it is created.

Historical evidence: `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/`, especially `churn-audit.md`, `candidate-1/`, `change-review-1/dispositions.json`, `phase-a/freeze.json`, `phase-a/frozen/AdversarialRelease/`, `descriptor-canary/result.json` and `phase-infrastructure/`. Historical state entries are superseded by the reduced checkpoint; preserve raw evidence.

Skill-improvement proposal: `/tmp/four-eyes-review-panel-churn-proposal.md`. No installed skill was changed by this session. Its size changed after the original write; inspect current contents before relying on it. This temporary proposal is not needed to reconstruct the approved Limitaur contract.
