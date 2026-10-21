# P73 read-policy amendment: design result

2026-10-20. Baseline81965879463dc205eb7adf9e9a55eaeeb05dbc87, clean before design. P216 “proceed” authorized completing design/review after P212–P215 clarified over-asking. Routine drafting, read-only investigation and review within Go are autonomous. It did not authorize changing protections or applying a new profile.

## Decision presented at P231

Recommend the [explicit-exclusion amendment](../proposals/release-guard-amendment.md) for this cooperative local workflow. It intentionally permits additional system reads, including unreviewed model-written payloads before final review, while excluding declared homes/config/secrets/other private scratch and retaining direct network denial. Child writes are narrowed/restructured; parent canary writes and metadata queries are explicit. This is **not** complete host-secret or hostile-code containment. Read data could reach artifact output; allowed process/IPC/model-output routes are not comprehensively contained. The proposal includes their cooperative prohibitions and sanitized feedback policy.

Approval would adopt this contract for development and the eventual accepted production prepare, plus the bounded qualification batch and conditional resumption of existing P73 Go. It would not authorize normal-user execution of new release TCB, live provider/UI/performance qualification, install/tag/release/push, or changes to frozen tests. If runtime controls fail, stop; no guessed read expansion or weaker fallback. Runtime feasibility remains unverified.

## Review status

Three strict amendment-converge rounds, six fresh Astra/Opus calls,68 returned findings dispositioned in the [ledger](release-guard-amendment-findings.json). **Final normative corrections after round3 were NOT RE-REVIEWED. No convergence, panel clearance or executable qualification is claimed.** No fourth round was dispatched. This is separate from the earlier four original release-tooling design rounds and the one startup-diagnosis opinion round. Later candidate tests/code reviews and frozen-TCB execution approval remain required.

The final corrections address complete configuration exclusions/golden ordering, dynamic aliases, no-op bytes, hard-link fixture coverage and stdlib-only Git fixture construction, trusted-parent metadata/side-effect precedence, frozen-suite cwd/binary variables, and the failure branch. New v2 vectors are separate from unchanged original v1 examples. The template/golden/catalogue are declarative proposal data, not applied profiles or executable test results.

Important adaptations/declines:

- Adopted the blocker that “reviewed code” understated pre-final-review model payloads. The proposal now names that risk and artifact/model feedback routes. Exclusions and pattern scans are not universal secret isolation.
- Declined an automatic “variant without the `/private/var/folders` data denial.” It would intentionally expose user caches without attribution; v2 startup failure stops the chosen contract rather than authorizing another guess. This optional fallback was a reviewer proposal, not an adopted permission.
- Declined “Post-publish: bulk scratch removal” as the selected lifecycle. All mandatory/bulk cleanup is precommit; exclusive rename is the final filesystem commit, preserving no-delete/output_exists behavior. Non-guard cleanup errors are internal_error, no precommit publication. Crash residue/output-without-stdout limits are stated.
- Actual-artifact controls use fresh positive/guarded results, not another no-op pass. Placeholder results cannot qualify actual protection. No diagnostics before actual staged-executable controls; if both release builds fail, test discovery remains blocked intentionally.
- Kept global child hard-link denial and added fixed parent-seeded per-case fixtures rather than weaken R8 or let guarded tests manufacture links. SOURCE remains outside WORK. Synthetic Git copies in WORK are inert data only; new parent Git write subprocess commands were declined in favor of bounded stdlib object/index bytes. Actual seeder implementation and feasibility remain unverified.
- Did not adopt read-only mode bits or EPERM-only folklore as substitutes for attributable controls. Same-resource positive results, identity/mode/byte/link audits and original EPERM/EACCES criteria remain, with no general OS-cause claim.
- Future independent driver code cannot have an approval-time hash before implementation. Its exact per-file map must be frozen before launch and after allowed corrections; this is not an invented additional micro-approval gate. New production TCB still needs the existing explicit frozen-code approval, including trusted recipe/catalogue hashes.

## Artifacts and checks

The unchanged original spec SHA256 is34f97eae0e87f62c7c50db8140ddf2f644419270643cd37641ac5f58d06a5f76. The final amendment and full proposed vector map are frozen externally in proposed-normative-file-map.json after final corrections. Approval must reference that pair plus recipe/catalogue/vector inputs; no silent original-spec rewrite.

- [Proposed v2 pack](../proposals/release-fixtures/read-exclusions-v2/README.md): manifest/evidence/golden identities, v1 negative, recipe/generation models/no-op and per-case hard-link catalogue. All invented, inactive, not evidence.
- [Frozen-suite static inventory](release-guard-static-inventory.md): no source-relative writes identified in inspected frozen tests; TMPDIR/LIMITAUR_TEST_ROOT output, both LIMITAUR_BINARY/LIMITAUR_BIN needed. No hard-link construction found; existing symlinks preserved. Framework/SwiftPM behavior still needs measurement.
- Canonical/hash consistency checks matched v2 identities/recipe/no-op/goldens, original v1 bytes and original spec,16-file frozen test map and collector. These were data checks, not release-tool tests or a new passing-test count.
- No source/app/build/test/new release-TCB code or payload profile executed. No implementer/test-writer, live request, OS grant, install, tag, release or push. P119 remains accepted atab8b5e6 with recorded133 passes; no approval reopened.

## Sessions and limits

Every member got the same frozen input within its round, sealed+web from a fresh empty directory. Shell/write/delegation tools disabled; no auth copying, normal login retained. Codex user instructions may load despite config/rules suppression. Briefs/staged inputs passed the recorded secret-pattern scans before dispatch; no hits. Outputs were all collected before judging. A round3 snapshot-directory preparation error was fixed before any third dispatch; no extra model call/round.

| Round | Runtime/model | Session | Seconds | Runtime-reported usage |
| --- | --- | --- | --- | --- |
|1|Codex gpt-6-astra|01a15afe-dc79-7f80-9b9f-c1d27b03765c|266.45|31510 total-only tokens; money unreported|
|1|Claude Opus5.5|2a813bf8-7585-422f-af6a-90599efd409e|285.46|0.9933175 USD equivalent|
|2|Codex gpt-6-astra|01a15b09-3308-7122-8b7e-72679d5b9670|289.01|33715 total-only tokens; money unreported|
|2|Claude Opus5.5|0dcaf8ba-5237-460f-870a-6f84bdd7f859|414.72|1.1073094 USD equivalent|
|3|Codex gpt-6-astra|01a15b1a-6b46-7e50-b3f7-60fdad04a373|371.90|11382 total-only tokens; money unreported|
|3|Claude Opus5.5|50902b31-d3a1-4aa8-98de-3a7de6bb070c|476.82|1.6949794 USD equivalent|

Claude total3.7956063 USD is reported list-price equivalent, not an invoice. Rounds1/3 include auxiliary Haiku5.5 buckets without separate exposed sessions. No separately dispatched Haiku role. OpenAI/driver money and driver exact model/session are unreported. Astra shares the driver's OpenAI vendor; exact model equality unknown. Opus is cross-vendor. Fresh sessions remove transcript anchoring, not shared-model/vendor errors. Tool restrictions do not establish hostile-model OS containment.

All snapshots, briefs, raw outputs, runtime metadata, per-round dispositions, historical v1 bytes, static/data checks and final proposed file map are under `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/read-policy-amendment/`. Requested CLI calls finished; no implementation/test-writer phase is active. Current closing pointP231, nextP232.

[four-eyes0.6.0 / review-panel0.4.0] outcome: amendment design proposed, execution approval pending; strict (permission/architecture boundary). Designer/driver: current Codex desktop, exact runtime model/session/cost unreported. New design review: three rounds/six returned sessions above;68 findings dispositioned, post-last changes not re-reviewed, no convergence. Implementer/test-writer/change-review:none. Existing Go:P185; design/review continuation:P216 “proceed”; amended permission/execution Go:none. Old tests/collector preserved, no new tests or app/profile runs. First normal-user release TCB execution:none. Implementation commit:none; documentation/design-data checkpoint uses standing rule. Push:none.
