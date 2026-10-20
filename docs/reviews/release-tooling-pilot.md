# P73 baseline pilot: guard qualification pending

2026-10-20, America/Los_Angeles. Scoped implementation Go approved at P185: operator “go”. Pilot baseline `46e34e476a84f1de3a98c6176f69f522eb7789e6`, clean before execution. Go remains valid, but its guard prerequisite is not met. No implementation/test-writer worker was dispatched; no app build, native test, record-format run, live request, tag or push occurred. P119 remains accepted with its recorded 133 passes.

## Measured result

Two separate build/diagnostic profiles were generated for a tracked-file-only baseline copy and fresh scratch at `/private/tmp/limitaur-p73-ca5ca9489491/`. They requested default-deny data reads except recorded OS/SDK/tool/work roots; direct home reads denied; direct network including AF_UNIX denied; writes limited to private work; tracked source/frozen files immutable; diagnostic app writes denied. These are requested policies, not successful containment evidence.

| Check | Observed result |
| --- | --- |
| Unguarded synthetic probe process | exit 0; per-operation control JSON was not retained by the driver's early-failure path, so no control-matrix pass claimed |
| Build-profile `/usr/bin/python3` probe | SIGABRT, exit -6, no stdout/stderr/probe result |
| Diagnostic-profile `/usr/bin/python3` probe | SIGABRT, exit -6, no stdout/stderr/probe result |
| Same permissions, `(debug deny)` startup marker | SIGABRT, no marker or resource-specific denial message |
| Original profile, selected Python 3.15 startup marker | SIGABRT, no marker |
| Original profile, `/bin/echo` startup marker | SIGABRT, no marker |
| Swift/native/default builds, tests, new roles | not attempted |

Build profile SHA256 `ef7a3c02de6523cedae11a731cf215377aa41e5d9c317968455153cfa2ac4dcb`; diagnostics `787b08b3c7528e32db0e406190b111519d8237837a689408194ee6c2ae86f3c1`. Logging-only profile `746c823af1d817ead833d9c03a44a7024823f9d9b3f5f8ddb798bfa42e0cf7c8` differs only by the debug directive. These initial and logging-only profiles did not widen permissions. The later explicitly approved startup-only exception is recorded below.

Targeted OS reports show fault frames `ignition_halt`, `boot_boot`, `ignite`, dyld `CacheFinder` and dyld startup, namespace 0x23/code 2. Apple's [published namespace definitions](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/reason.h) map 35/0x23 to LIBIGNITION. This does not establish the private meaning of code 2 or identify any rejected resource, and is not proof the OS source exactly matches this host build. Do not infer a required path exception from these frames. Targeted unified-log queries produced no resource-specific denial message. Raw crash reports were not copied; selected metadata/symbols are retained only.

The startup comparison indicates this is not limited to the system Python launcher. Exact cause remains unestablished. No guard qualifies, no backend result is new, and native record extraction remains unqualified. No claim of Keychain/IPC containment. The existing recorded 72-test summary/133 acceptance is unchanged and is not reopened.

## Approved startup comparison: completed

Operator “proceed” approved the P191 diagnostic at P192. The [exact profile diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-startup-read-comparison.diff) and [historical command plan](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-startup-read-comparison.json) were frozen before execution; the plan retains its original prepared status. The separate [execution result](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/approved-startup-read-comparison-result.json) records approval and completion.

Executed only `/bin/echo` and the selected Python 3.15 `print` marker, max 5 s each, once. Both exited 0 with the expected 23-byte marker and no stderr. The diagnostic-only variant removes the general file-read-data whitelist denial to test whether read-policy closure participates in startup failure. It retains the original write/network/source denials and explicitly blocks all user homes and named system credential directories. No credential/account query, app/build/test/model code, or new release-tooling TCB ran. It is not a qualified guard and must never replace an app/test profile. Its one-time execution authorization is consumed; no automatic permission change follows the successful markers.

Variant SHA256 `f6d281efbd4c73d266c131b3bc1e02142d5efed21b2b1a35b36cb898c78d6aff`. Approval covered solely this read-policy diagnostic exception; original build/diagnostic profile hashes remain unchanged. The comparison implicates restrictive read policy but identifies no rejected resource. The new release-tooling first-normal-user-execution gate remains closed. Before retrying the full probe matrix, fix the driver to retain and validate positive-control JSON before any guarded launch can take an early failure return.

## Narrow OS-cache exception: approved retry failed

Read-only filesystem inspection found `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld` outside the original allowlist; `/System/Library/dyld` is absent. The candidate directory is not a symlink and contains OS shared caches. `statvfs` does not report a read-only filesystem. This is a plausible loader-cache read root, not a denial trace or proven cause. [Selected metadata](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/os-dyld-cache-metadata.json).

Operator “approved: proceed” at P197 approved the P196 plan: add only `(allow file-read* (subpath "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"))` to each original profile. Keep default data-read denial and every original write/network/home/source rule. Frozen template build SHA256 `044bd889edfc3d7a31e31648cfd24875868b0e7b9bc44458c97fa4d0ceedda8d`; diagnostics `76459c9d9f6db2994762c90da46d062fb4daa4df2fa8532ef1b657932cf02272`. Exact [build diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-build-os-dyld-cache.diff), [diagnostic diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-diagnostics-os-dyld-cache.diff), and [historical qualification plan](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-os-cache-qualification-plan.json). Historical prepared files remain unchanged; separate authorization/result records supersede their status.

The approved sequence required fresh current-HEAD copies/profiles, startup markers, then full recipe controls/denials before baseline builds/record qualification and workers. It required stopping on failure without more permission changes. Default-backend failure remains a release gate; no count relaxation, frozen-test edits or future first-normal-user TCB execution was authorized.

Retry baseline: clean `80ae62b34e3b15e5aa15ee8330d3cd911c35a7d9`, tracked-file-only copy at `/private/tmp/limitaur-p73-cache-782fa8474908/work/source`. Actual profiles rebase the frozen templates to this private run root and add only missing current tracked-file write denials. Build SHA256 `d38b60196519c382dd36d9f23c108bb40822a0e3a0597152f07bbbaa8e07548f`; diagnostics `60fd4f98805cf7c8fbc37adff3ec5754f6f38eee7ff55cf6fa5f8cf34b33183e`. [Authorization, profiles and result](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/cache-retry/result.json) and sibling records preserve the exact inputs.

The first build-profile `/bin/echo limitaur-startup-probe` aborted with SIGABRT/exit -6, no stdout/stderr, after 0.006 s. Execution stopped immediately. Python/diagnostic startup, full probes, builds, tests, record pilot and workers were NOT attempted. No listeners were opened. The trusted retry driver now captures bounded output during reads and persists positive-control JSON before guarded launch, but the full probe path was not reached or qualified. The app path contains only a synthetic probe file, not a built executable.

Selected crash metadata repeats ignition_halt/boot_boot/ignite/dyld CacheFinder and namespace0x23/code2. A targeted unified-log query for PID87944 returned no matching denial event. No rejected resource is known. This one read exception is insufficient; it does not prove the cache root unnecessary or identify another required root. Frozen test/collector, proposal, source-copy and profile hashes still match. No new app/test count, release qualification, TCB execution, worker dispatch or push.

Operator “proceed” at P201 approved one focused read-only Astra/Opus opinion round on startup-guard diagnosis. Both returned; all16 findings have dispositions. [Diagnosis result and proposed reporting experiment](startup-guard-diagnosis.md). Read-only inspection of omitted fields in the exact known echo report found no reason text, and a tighter query of the same historical window found no event; neither identifies a resource. No payload was replayed, no further permission adopted, and no extra round authorized. The proposed reporting experiment at P208 is NOT approved or executed. Existing scoped Go persists behind guard/record prerequisites. Do not continue guessed path exceptions or rerun failed payloads automatically.

The approved [proposal](../proposals/release-tooling.md) requires stopping payload execution on failed guard/probes and forbids automatic permission broadening. This failed prerequisite is why no implementation workers started despite Go. Do not request Go again; seek only the specific diagnostic exception or another explicitly scoped operator decision.

## Durable evidence

`/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/` contains Go/source/profile records, the driver, initial probe result, startup logging/profile diff, interpreter comparison, selected crash metadata, historical diagnostic plan, approved diagnostic result, narrow-cache proposal and `pilot-result.json`. Scratch holds no copied auth/runtime state. TCP/AF_UNIX probe listeners were closed; no live service was changed. Normal CLI login remains intact. Frozen test bytes and collector hashes match the repository baseline.

Operator “proceed” at P209 approved the reporting diagnostic. Unguarded echo and guarded observable-canary cat passed, but the bounded query found only a compilation event and no required read-data canary report. Positive reporting control failed; later canaries/final echo not attempted. [Measured diagnosis/reporting result](startup-guard-diagnosis.md). Authorization consumed, no root attribution or guard qualification. P211 recommends design-only isolation reassessment before another execution proposal; no alternative policy or new experiment adopted.

Discussion closes P211; next P212. Scoped Go approved; narrow-cache startup and reporting-observer prerequisites remain unresolved; supplemental read-only diagnosis review complete. No guard qualifies. No additional payload/permission approval, TCB normal execution, implementation acceptance or push authorization.

P216 subsequently authorized autonomous redesign/review. The [read-policy amendment result](release-guard-amendment.md) records three strict rounds and pending material approval at P231, with final corrections not re-reviewed. No new payload profile, build/test or TCB execution followed; this historical pilot remains unqualified. Current handoff continues at P232.

[four-eyes 0.6.0] outcome: stopped at failed narrow-cache startup retry; mode: strict. Designer/driver: current Codex desktop, runtime model/session not exposed. Implementer/test-writer/new change-review:none. Go: P185 “go”. Diagnostic authorization: P192 “proceed”, two fixed markers completed. Narrow-cache authorization: P197 “approved: proceed”, first echo failed and execution stopped. Native/frozen tests:not run; no new pass count. Guard qualification:false. First normal-user release TCB execution:not approved/run. Implementation commit:none; documentation checkpoint uses standing rule. Push:none. No role cost reported because no role dispatched.
