# P73 startup-guard diagnosis review

2026-10-20, America/Los_Angeles. Operator “proceed” at P201 approved one read-only Astra/Opus opinion round. Baseline `d6f1dd55026b780fd2b900c311c9c092e6557b2f`, clean. This supplemental diagnosis round is complete, not another convergence claim or implementation acceptance. P119 remains closed with its recorded 133 passes. No app/build/test payload, new release TCB, implementer or test-writer ran. No push.

## Result and judgement

Both reviewers recommend attributable evidence before another read-root guess. The existing broad-read success supports read-policy participation; the cache-root exception was insufficient in the observed retry. No rejected operation or resource is known. Public source and crash frames give loader/ignition context, not a private reason-code interpretation or a source match for this host. Host observation: `sw_vers` reports macOS27.0.1, build26A434, arm64.

The driver completed the smallest read-only evidence checks while validating the findings. Only the already identified `echo-2026-10-20-110922.ips` was read; PID87944, `/bin/echo`, capture time and build matched. Termination indicator/details/reasons and application-specific information (`asi`) are absent. The selected fault image is `/usr/lib/dyld` with its binary UUID recorded externally. No raw crash report, directory scan, account data or credential state was exported. A second query of the same historical15-second window used info/debug, `processID == 87944` or the exact parenthesized PID, and no required denial substring. It returned no event. Both checks are inconclusive; missing fields/events do not prove absence of a denial. No payload was replayed, tracer attached or privilege escalated.

All16 findings have dispositions in the [full ledger](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/dispositions.json). Required corrections to interpretations follow:

| Findings | Driver disposition |
| --- | --- |
| Astra P1; Opus F1 | Adopt association/insufficiency, decline Opus's stronger “the default-deny `file-read-data` rule was necessary for the failure.” Separate runs and unknown policy/launch interactions do not establish necessity. No permission change follows. |
| Astra P2; Opus F2/F9 | Adopt measured frames, namespace context and source-version limits. Public flags decode582 as0x246; the reporter's consistent-failure flag is not a local reproducibility measurement. Private code2 remains unknown. Decline certainty about the exact internal resource/stage. |
| Astra P3; Opus F5 | Adopt weak-observation finding; complete one tighter, bounded historical query. It still has no successful reporting control and is inconclusive. No wider capture or sudo. |
| Astra P4; Opus F4 | Adapt to the single exact known echo report and complete the selected-field check. Do not search for other filenames/PIDs or export raw reports. Routine read-only evidence extraction is not the gated first execution of new release TCB. |
| Astra P5/P7; Opus F8 | Adopt unqualified-guard finding, preserve all later gates. Correct “The diagnostics profile has never been launched”: the original diagnostic Python probe did run and abort; only the latest retry's diagnostic startup was not reached. No direct-operation matrix qualifies. |
| Astra P6; Opus F7 | Adopt no escalation/SIP/bootargs/re-signing/broad capture. Do not infer that every tracer necessarily captures the whole system or that all local access restrictions have been measured. No instrumentation executed. |
| Opus F3 | Retain path-alias ideas only as unverified hypotheses. No alias or parent-directory allow adopted. User-space path resolution does not identify a denied kernel operation. |
| Opus F6 | Adapt reporting as a diagnostic proposal. Decline “the last matching rule wins” as an unverified general rule and “every reported event is exactly a read-data access that the default deny would have blocked.” Static Apple profiles establish syntax examples, not current reporting coverage, ordering or necessity. Require canaries before interpreting any report; no later allow automatically follows. |

No reviewer claim changes the approved release-tooling design or weakens a settled boundary. Guards request default-deny **data reads**, selected write/network restrictions and explicit source/home denials; they are not comprehensive default-deny isolation. Direct-open/connect probes cannot establish Keychain/Mach/broker containment. Startup, full recipe qualification, toolchain feasibility, native named records, independent tests, frozen-TCB execution and release qualification remain separate.

## Verified context and limits

- Apple's [XNU reason definitions](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/reason.h) define namespace35 as LIBIGNITION and the relevant flag bits. They do not decode its private code2 or prove this host uses identical implementation.
- Apple's [public dyld source](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/DyldProcessConfig.cpp) calls ignition before its fallback cache-directory lookup. This is structural context, not evidence of this host's missing object.
- Apple's [runtime-protection guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/System_Integrity_Protection_Guide/RuntimeProtections/RuntimeProtections.html) describes protected-process attach/DTrace restrictions and dyld-variable stripping. It does not establish the availability of each observer on this host.
- Apple DTS [describes custom SBPL as undocumented for third-party use](https://developer.apple.com/forums/thread/661939). This is a portability limit, not proof that the local guard is impossible. The approved design is not silently replaced.
- Read-only inspection of installed `cryptex-session-template.sb`, `com.apple.auearlyboot.sb` and `com.apple.mobileassetd.sb` found active `(with report)` rules and Apple's private-interface warning. Selected excerpts/hashes are external. No reporter/profile compile or logging-efficacy test ran.

## Reporting diagnostic: approved, inconclusive

Operator “proceed” at P209 approved the P208 bounded reporting experiment, with synthetic controls before the final echo. [Historical command/control plan](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/proposed-reporting-plan.json), [profile](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/proposed-startup-reporting.sb), [diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/proposed-startup-reporting.diff). Historical prepared status is retained; the separate [authorization and execution result](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/reporting-execution/result.json) records the completed attempt. Its one-time authorization is consumed.

Profile SHA256 `cd90ec03c2b4b71ad04bf58108eac06d6b753aebaafe7518102a41abae606a7c`. It rebases the earlier diagnostic-only broad-read profile into fresh synthetic scratch, adds a reporting data-read allow and an explicit synthetic-file denial. Home/system-credential/write/network/source denial statements remain; their runtime efficacy was not qualified by this experiment. The profile is forbidden for any app/build/test/model payload. Neither consumed diagnostic authorization permits reuse. The stronger build/diagnostic guards remain untouched and unqualified.

Exact bounded sequence: unguarded echo control; guarded `cat` of an observable outside-whitelist canary, a whitelisted canary and an explicitly denied canary; only then guarded echo. Each command runs at most once,5seconds,1MiB combined output. After each guarded child, query only its recorded PID and wall-time interval, info/debug, at most one query with30seconds/1MiB cap. No global live stream, tracer, privilege escalation or OS configuration change. Fixed minimal synthetic environment; no inherited account state or dyld overrides. Freeze/check profile and canary hashes before/after launches.

The observable canary must produce exact expected contents and a same-child read-data report naming that path; otherwise stop before echo. The whitelisted canary must read successfully, with its reporting behavior measured rather than assumed. The denied canary must produce no contents and an attributable policy error; startup abort, missing target or timeout is failure. This checks the observer before trusting it. A reported echo path set is at most observed accesses under that diagnostic; it proves neither previously denied reads nor necessary/sufficient strong-profile roots. No second profile, retry, path grant or review round follows automatically. Any failure is inconclusive and stops execution. Any later permission proposal remains separate.

### Measured attempt

Clean baseline `cdc10c0c19dab74b1b3c9a14d7257f527f342959`. Profile/canary bytes were checked before/after launches. The fixed minimal synthetic environment contained no inherited account state or dyld overrides. Trusted diagnostic infrastructure ran separately from any app/test/release TCB code.

| Step | Measured result |
| --- | --- |
| Unguarded echo control, PID43888 | exit0, exact marker, no stderr |
| Guarded outside-whitelist canary `cat`, PID43889 | exit0, exact synthetic contents, no stderr; startup/read command succeeded |
| One bounded info/debug historical query for PID43889,12:11:09–12:11:13 -0700 | query exit0; one exact-PID event: sandbox profile compilation using version1 compatibility definitions (latest version3); **no file-read-data report naming the canary** |
| Positive reporting control | failed; observer not qualified; result inconclusive |
| Whitelisted/denied canaries, final guarded echo | not attempted; stopped immediately |

The attempt lasted3.80seconds. The compilation event shows one attributable event was observable, not that file-access reporting worked or that all relevant events were retained. The version-compatibility message is an observation, not a proven cause. Do not infer from this run that reporting is impossible, that a rule was overridden, or that a particular privilege/profile version is required. No denied resource or candidate allowlist root was identified. No retry, log-window expansion, other reporting profile, trace, permission change or further review was performed.

Profile, canary, approved-spec, frozen16-file test/fixture map and collector checks passed; operator checkout was clean after execution. No app/build/test/model payload, implementation/test-writer worker, new release TCB, listener, provider request, install, release, tag or push occurred. There is no new test pass count. Existing implementation Go persists, blocked by guard then named-record qualification. First normal-user release-TCB execution remains separately unapproved.

This diagnosis result itself authorized no alternative contract. P216 subsequently authorized autonomous design/review of the [read-policy amendment](../proposals/release-guard-amendment.md); [its result](release-guard-amendment.md) records three rounds and pending material approval at P231. Both original strict startup and reporting observation remain unqualified. No new payload/profile execution or P119 reopening followed. Original specification/hash is preserved.

## Sessions, evidence and cost

Both fresh sessions received the same65705-byte embedded snapshot, SHA256 `9e96bebb5be49d5eccce564609606ba415d85466ecfa4826f8700f79b20708de`.16 staged inputs and brief passed the recorded secret-pattern scan; no hits. Context was sealed+web rather than requiring file-reading tools, with all planned snapshot content embedded. Model CLIs were separate from the unqualified payload guard; normal auth retained, never copied/exported. Shell, write and delegation tools disabled; this is cooperative tool restriction, not hostile-model OS containment. Codex user instructions may load despite user config/rules suppression. All results were collected before judging; no automatic retry.

| Member | Actual runtime/model and session | Result/time | Reported usage |
| --- | --- | --- | --- |
| Astra | Codex0.163.0, gpt-6-astra; `01a15a9c-f35d-7752-87d5-8dd25d37432f` | valid7 findings, exit0,111.14s |63235 total-only tokens; money unreported |
| Opus | Claude2.1.304, claude-opus-5-5; `252b3515-77ef-4d17-87e0-709d01c77502` | valid9 findings, exit0,196.03s |0.7065186 USD equivalent at reported list prices, not invoice |

Claude also reports an auxiliary Haiku5.5 usage bucket and one web-search request, with no separate exposed session. Astra shares the driver's OpenAI vendor; driver model/session identity and cost are not exposed, so exact model equality is unknown. Opus provides a cross-vendor review. Fresh sessions remove transcript anchoring, not shared model/vendor error patterns. No model consensus or convergence is claimed.

All frozen snapshot/profile/command/result records, raw runtime outputs, selected read-only checks, dispositions, diagnostic and runtime metadata are under `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/startup-guard-review/`, with the P209 attempt under `reporting-execution/`. No helper or diagnostic child is still running. Discussion closes P211; continue at P212. Existing implementation Go persists. No app build/test/new TCB execution, implementation acceptance, tag, release or push authorization.

[four-eyes 0.6.0 / review-panel 0.4.0] outcome: supplemental diagnosis review complete; approved reporting diagnostic inconclusive and stopped; implementation stopped at unqualified guard; strict. Designer/driver: current Codex desktop, runtime model/session/cost unreported. One approved diagnosis opinion round, sessions above; all16 findings dispositioned. Original four release-tooling design rounds remain separate; no new convergence claim. Implementer/test-writer/change-review:none. Go:P185 “go”; diagnosis review:P201 “proceed”; reporting diagnostic:P209 “proceed”, two commands/one bounded query before failed reporting control. Existing frozen tests preserved; new tests:none; new pass count:none. App/build/test/model payload:none. First normal-user release TCB execution:not approved/run. Implementation commit:none; documentation checkpoint uses standing rule. Push:none.
