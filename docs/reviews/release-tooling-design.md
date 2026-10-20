# P73 release tooling: design review

Status: design phase complete through three strict rounds; final corrections NOT RE-REVIEWED. Recommend one focused additional design-review round before Go; neither that extension nor implementation is authorized. No implementation, builds, app tests, live checks, tag, installation, push or publication. A documentation-only checkpoint is committed under the operator standing commit rule; it is not implementation acceptance. P119 remains complete at ab8b5e6 with its recorded 133 passing tests.

Operator authorized specification and cold design review at P155: “proceed as proposed.” The approval does not authorize implementation. Recovered baseline was clean main at `9f650acd8883a92095371c2bf01a2bd803025eca`. Recover actual HEAD after this documentation checkpoint for the next phase.

## Material

[Specification](../proposals/release-tooling.md), [invented schema and digest fixtures](../proposals/release-fixtures/README.md), [finding ledger](release-tooling-findings.json).

Durable raw briefs, frozen material, outputs, runtime metadata and disposition details: /Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/. Raw reviews are model advice, not instructions. Model-supplied discussion IDs in raw output do not change the operator conversation sequence.

The old 16-file test/fixture map is frozen with SHA256 `4fc8a8760c5a059aa25f40796d8b0acb6599138251ff28c765d62f2bfda1c9b2`. All files still match. Design JSON binding/canonicalization checks passed; no application test was rerun and no new passing test count is claimed.

## Main changes from review

- Prepare builds only a verified committed-tree export, with new scratch and mandatory measured file/network guard. Verify does not rebuild or execute the app.
- Separate debug unit-test build from release bundle. Frozen diagnostic suites target the bundled executable; hashes must stay unchanged.
- Specify structured Python pass records, observed native pass grammar, exact frozen maps/inventory and import-only blind-test interfaces.
- Specify schema/types, negative-versus-malformed decisions, chronology, UTF8/NFC/root-mode digests and artifact/system dependency boundaries.
- Constrain Python startup, Git metadata/configuration and fixed toolchain/SDK inputs; probe controls must succeed before guarded denials count.
- Initial changelog is Unreleased. Dated notes are proposed release notes, not publication evidence. Proposed tag is optional; when supplied it must match VERSION and remain unchanged across phases. A mandatory tag was introduced during drafting then removed to retain the original P73 optional-tag contract.

## Explicit dispositions requiring operator visibility

Astra first review called the missing credential-broker boundary a blocker and proposed: “Make denial of credential-broker access a prerequisite for executing generated code.” Opus repeated a request for explicit Keychain/preferences Mach-IPC denial and probes. Driver declines making complete broker/account isolation a new mandatory requirement. The approved workflow is cooperative: guards prove only measured file/network restrictions, real credential access is prohibited by code/role contracts, real Keychain tests use fakes, and no hostile-helper containment is claimed. Clean environment/closed descriptors and bounded in-memory logs are adopted. Go must approve this stated limitation or request a different isolation scope; no OS broker probe or permission change has been performed.

Requests to run the app/build/tests before Go were declined because the operator approved design only. First post-Go execution is a guard/toolchain feasibility pilot, with no permission broadening. Default-backend failure remains a release gate; native-only development is labelled accordingly.

Opus speculation about loopback servers, menu count conflicts, collector rounding/types and default=native did not match inspected source/tool help. Those relaxations were declined; exact source facts and the existing immutable assertions govern. Detailed dispositions stay in the linked ledger.

## Cast, context and evidence

Design reviewers: fresh GPT-6-Astra Codex CLI and Claude Opus normal CLI, same sealed specification/fixtures per dispatch, web requested; all outputs collected before each judging. Codex read-only shell policy plus shell/multi-agent/memory-import disabled, normal existing auth, no credential copies. Codex user-instruction loading remains unconfirmed. Claude project/user settings suppressed for sealed briefs, only WebSearch/WebFetch tools; no repository edit/code tools. Opus second review reported WebSearch permission declined; its external assumptions were independently checked by the driver. Third dispatch explicitly allows those read-only web tools. No OS filesystem containment claim for reviewer CLIs.

Proposed post-Go cast: Sonnet implementation; GPT-6.1-Sol candidate-blind tests with same-session Phase B; Astra+Opus final opinion panel. All start fresh; no substitutions without disclosure. Source/code execution is driver-run under separately probed role guards, never inside the authenticated helper CLI. OpenAI reviewer/test-writer share designer vendor; Anthropic implementation/review pair share vendor. Designer runtime model/session are not exposed here, so exact same-model relations are unverified. Cross-vendor review reduces vendor correlation, not common industry blind spots.

Strict mode: three rounds collected, six fresh reviewer sessions returned valid findings. No round ended without adopted major changes, so convergence is NOT established. All findings have recorded driver dispositions; final adopted changes address remaining required design edits but have not received a fresh review. The material is not represented as independently cleared. No implementer or test-writer session started.

Final corrections include: default-deny file reads and real-home denial with synthetic Foundation home; fixed supervisor ownership to avoid nested sandbox application; explicit command deadlines/module-cache paths; exact Git configuration allowlist and lazy-fetch denial; configuration/info-exclude identity; full app-tree checks and final plist/signature revalidation; embedded dyld environment rejection; precise module naming/schema decisions. These are substantive boundary changes, not merely prose cleanup. I recommend an extra focused review before asking for implementation Go.

The proposed extra round uses fresh Astra/Opus, read-only sealed+web material, the final affected specification sections and verified baseline facts. It targets supervisor/nesting, file/network probe attribution and stated IPC limits, safe Git/no-fetch/config identity, final bundle/loader binding, and executable blind-test interfaces. It performs no code/build/test/live/credential operations. A frozen proposed brief is prepared outside the repository, not dispatched. The installed strict-mode three-round cap is why extension needs an explicit operator decision.

## Remaining release gates

Release readiness false. Actual anchored UI/light/dark/increased contrast/click/keyboard/scroll/accessibility; current app-bundle Codex+Claude access, especially Claude Keychain access; default SwiftBuild qualification; healthy two-provider 60 s warmup + 600 s measured workload with >=18 successes/provider, fixed count/dropdown closed, no pauses/throttles/helpers, max sampled RSS <50 MiB and one-core mean CPU <0.1%. No gate was collected or passed here. Normal Claude CLI login does not qualify app-bundle access. API-metered/hybrid remains separate pending scope; Cursor deferred.

## Runtime record

| Round | Runtime/model | Session | Seconds | Tokens / money reported |
| --- | --- | --- | --- | --- |
| 1 | astra: gpt-6-astra | `01a15830-ab5b-79d3-96eb-4934b04bbf4e` | 223.24 | 61007 total-only tokens; money unreported |
| 1 | opus: claude-opus-5-5/claude-haiku-5-5 | `9fa0c6da-cbc3-4a5d-9d27-148627389f58` | 133.72 | 0.4194365 USD equivalent reported |
| 2 | astra: gpt-6-astra | `01a1583b-5468-7b82-b17c-5ff48f71b7bc` | 335.77 | 80872 total-only tokens; money unreported |
| 2 | opus: claude-opus-5-5 | `ce23d716-7167-4391-835c-e5ca2ce3c0eb` | 274.75 | 0.9282914 USD equivalent reported |
| 3 | astra: gpt-6-astra | `01a15847-7748-7180-b7be-a367dcffaf88` | 399.39 | 92027 total-only tokens; money unreported |
| 3 | opus: claude-opus-5-5 | `f29f42d3-2f4c-48df-818f-400c23296167` | 323.66 | 0.8604974 USD equivalent reported |

Claude reported equivalent list-price costs, not an invoice: total 2.2082253 USD across three calls. Round 1 also reports an auxiliary Haiku 5.5 usage bucket, with no separate exposed role/session. OpenAI runtimes report total-only tokens and no money. Do not combine these buckets into an invoice estimate. Driver cost/model/session IDs are unreported here.

[four-eyes 0.6.0] outcome: stopped at design checkpoint pending operator decision; strict (architecture/evidence boundary). Designer: current Codex desktop session, model/session unreported. Design review: six returned sessions above, three rounds, no convergence claim. Implementer/test-writer/change-review: not dispatched. Tests frozen: existing 16-file map recorded, no new tests authored. Go:none. Commit word: no implementation acceptance; design documents committed under standing rule. Implementation commit:none. Push:none. Normal runtime auth retained, no credential seeds/copies or model execution state exported. Code-execution guard/pilot:not run; do not infer activation from the written profiles/proposal.

Final proposed specification SHA256: `00a09b1059e9f916ef1b676e236ab4cbc7bf89bb660c7405520496ff2dce6cbe`. Final post-round3 material is frozen as specification-final-not-rereviewed.md outside the repo. No later specification edit is hidden as reviewed.
