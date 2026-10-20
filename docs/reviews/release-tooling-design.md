# P73 release tooling: design review

Status: scoped implementation Go approved at P185 (“go”). The baseline guard pilot subsequently failed before payload/test/worker execution; see [pilot checkpoint](release-tooling-pilot.md). Go remains valid but qualification is incomplete. A specific startup-only diagnostic read exception is pending at P191. First normal-user execution of new TCB code remains separately unapproved. Historical four-round design record follows; no convergence/clearance claimed.

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

Historical checkpoint before the approved extension: three rounds collected, six fresh reviewer sessions returned valid findings. No round ended without adopted major changes, so convergence is NOT established. All findings have recorded driver dispositions; final adopted changes address remaining required design edits but have not received a fresh review. The material is not represented as independently cleared. No implementer or test-writer session started.

Final corrections include: default-deny file reads and real-home denial with synthetic Foundation home; fixed supervisor ownership to avoid nested sandbox application; explicit command deadlines/module-cache paths; exact Git configuration allowlist and lazy-fetch denial; configuration/info-exclude identity; full app-tree checks and final plist/signature revalidation; embedded dyld environment rejection; precise module naming/schema decisions. These are substantive boundary changes, not merely prose cleanup. That recommendation was authorized and the additional round is recorded below.

The operator approved the extra focused round at P174 with “proceed”. Fresh Astra/Opus received the same frozen specification and invented fixtures; presentation status/history was removed without altering normative clauses. Both returned complete findings. Its raw brief/snapshot/outputs are preserved outside the repo. The one-round extension is complete; no further design round or implementation dispatch is authorized.

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

Prior post-round3 specification SHA256 `00a09b1059e9f916ef1b676e236ab4cbc7bf89bb660c7405520496ff2dce6cbe` was the fourth dispatch input. New post-round 4 material is explicitly not re-reviewed.

## Fourth round and proposed scoped Go

Astra returned five major findings; Opus returned two blockers, five majors and six minors. These are reviewer severities; the ledger records driver adaptations/dispositions. The supervisor/test seam blockers were valid. The revised contract identifies the parent TCB and stops claiming it is guarded; it narrows independent tests and introduces an approval of frozen TCB bytes before their first normal-user smoke. Full source acceptance/commit remains conditional on that smoke passing. This is a proposed workflow variation requiring Go, not permission inferred from the design-review approval.

Build/diagnostic recipes now have separate hashes/probes and fixed launch bindings. Probes describe direct file opens, TCP/AF_UNIX connects and protected-executable opens, not all brokered network/filesystem actions. No Keychain/IPC isolation or real broker/preference probe is claimed. The prior declined broader isolation request remains visible above; it is not panel agreement.

The rpath rule is exact and relocation-safe. LC_LAZY_LOAD_DYLIB_INFO rejection is supported by the installed SDK/Apple primary sources. Integration requires credentialPath only under each provider, not an extra root value. Canonical Git config listing closes the parser-differential ambiguity. Reason ownership, R2 driver-build ownership, absolute interpreter and path-based codesign limits are explicit. Updated invented guard/schema/reason vectors are not executable test results.

Driver correction: the saved accepted native summary is 72, but the proposed anchored extractor finds 71 individual records. Earlier material overstated the individual-row count. This is an instrumentation qualification gap for the new tooling, not evidence of an unrun/failed test and not a reopening of P119. A fresh guarded baseline record pilot must qualify all named tests before independent Phase A dispatch. Existing 133 accepted tests are preserved; none reran here.

Proposed Go sequence:

1. Recover actual clean HEAD. Driver runs a disposable baseline guard/backend/native-record pilot using independently prepared guard infrastructure, without importing new release-tooling TCB code. Stop on failed guard/record qualification; no permission broadening, count relaxation or frozen-test edits. A default backend failure stays a release gate; native development remains explicitly limited.
2. Freeze the qualified test interface, then GPT-6.1-Sol writes candidate-blind tests from baseline/spec. Sonnet implements in a separate copy; frozen test maps/collector remain immutable. Model CLIs use normal login and no repository-code execution tools. Driver runs payloads under the qualified recipe profiles.
3. Continue the same independent test-writer for Phase B; Astra+Opus review the frozen candidate and sensitive TCB hunks. One standard fresh-worker remediation if required; further fixes require the skill's decision point. Record every outcome truthfully.
4. Present exact TCB diff/hash map plus reviews and guarded-test results. Operator approval is required before its first normal-user end-to-end smoke in a private synthetic repository. No wrapper nested sandbox, app/test payloads remain recipe-guarded. Approval may also authorize conditional application/commit only if that smoke and all acceptance criteria pass. Failure means no application/commit. No push/tag/install/release.

The proposal now names the supervisor trust decision; no fifth design round is automatically proposed. Post-fourth-round changes are not independently cleared. Their executable verification and the separate first-execution permission are explicit gates. Implementation Go has not been granted.

### Fourth-round runtimes

| Runtime/model | Session | Seconds | Reported usage |
| --- | --- | --- | --- |
| astra: gpt-6-astra | `01a159cd-ab3a-7220-bd16-4d70ba055c4b` | 277.84 | 64703 total-only tokens; money unreported |
| opus: claude-opus-5-5/claude-haiku-5-5 | `889f9dad-cda5-4c29-94d0-7e8be29d5621` | 268.91 | 0.960428 USD equivalent reported |

Claude fourth call includes an auxiliary Haiku 5.5 usage bucket and two reported web-search requests, no separately exposed session/role. Four-call Claude equivalent list-price total is 3.1686533 USD, not an invoice. OpenAI money and driver costs remain unreported. All eight reviewer sessions are complete; no helper/implementer/test-writer is running. Existing CLI auth/runtime state retained, no copies/export.

[four-eyes 0.6.0] outcome: stopped at scoped implementation Go; strict; design rounds 4 (round 4 explicitly approved at P174); eight returned results, no convergence claim; post-round 4 edits not re-reviewed. Implementation/test-writer/change-review:none. New tests authored:none. App build/test/pilot:none. Go:none; first TCB execution approval:none; implementation commit:none; push:none. Documentation checkpoint uses standing commit authorization only.

Current proposed specification SHA256: `34f97eae0e87f62c7c50db8140ddf2f644419270643cd37641ac5f58d06a5f76`; immutable copy: specification-after-round4-not-rereviewed.md in the external review directory.

Closing discussion P184, next P185. Proposed scoped implementation Go remains unanswered. No fifth round was dispatched; all fourth-round findings have dispositions, and the code-level proof/execution gates are explicitly pending. This documentation checkpoint does not authorize implementation or first normal-user TCB execution.

## Scoped Go and pilot outcome

Operator “go” at P185 approved scoped implementation on `46e34e4`. The required guard startup pilot failed; no implementer or independent test-writer was dispatched. Operator “proceed” at P192 then approved only two fixed startup markers with the frozen diagnostic read-policy exception. Both passed; that authorization is consumed. Operator “approved: proceed” at P197 approved one dyld-cache read root in fresh run-specific strong profiles; the first echo still aborted. Execution stopped before Python/full probes/builds/tests/workers. [Measured pilot results](release-tooling-pilot.md). Operator “proceed” at P201 approved one read-only Astra/Opus diagnosis opinion round; both returned and all16 findings have dispositions in the [diagnosis result](startup-guard-diagnosis.md). Its bounded existing-report/log checks found no reason/resource evidence. No guard qualifies; exact rejected resource remains unknown. P208 proposes a canary-checked reporting diagnostic, NOT approved or executed; no additional round authorized. No app/build/test code or new release TCB executed. Source acceptance remains P119, unchanged. Go persists behind guard/record qualification. No push. No further permission change or future frozen-TCB execution is approved. Discussion P208; next P209.
