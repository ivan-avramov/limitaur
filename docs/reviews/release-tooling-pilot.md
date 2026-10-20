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

## Proposed narrow OS-cache exception: approval required

Read-only filesystem inspection found `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld` outside the original allowlist; `/System/Library/dyld` is absent. The candidate directory is not a symlink and contains OS shared caches. `statvfs` does not report a read-only filesystem. This is a plausible loader-cache read root, not a denial trace or proven cause. [Selected metadata](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/os-dyld-cache-metadata.json).

Prepared, NOT authorized or executed: add only `(allow file-read* (subpath "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"))` to each original profile. Keep default data-read denial and every original write/network/home/source rule. Proposed build SHA256 `044bd889edfc3d7a31e31648cfd24875868b0e7b9bc44458c97fa4d0ceedda8d`; diagnostics `76459c9d9f6db2994762c90da46d062fb4daa4df2fa8532ef1b657932cf02272`. Exact [build diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-build-os-dyld-cache.diff), [diagnostic diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-diagnostics-os-dyld-cache.diff), and [qualification sequence](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-os-cache-qualification-plan.json).

If approved: recover clean current HEAD and freeze a fresh tracked copy; freeze actual run-specific profiles with only this new read root (source immutability may be tightened). Run fixed startup markers first, then the complete positive-control and direct read/write/TCP/AF_UNIX denial matrix for both recipes, including diagnostic protected-executable write denial. Stop on failure without further permission changes. Only successful full guard qualification permits resuming the existing Go's baseline native/default builds and named-record pilot; only record qualification permits blind test-writer/implementer dispatch. Default-backend failure remains a release gate. No count relaxation, frozen-test edits or future first-normal-user TCB execution is authorized by this proposal.

The approved [proposal](../proposals/release-tooling.md) requires stopping payload execution on failed guard/probes and forbids automatic permission broadening. This failed prerequisite is why no implementation workers started despite Go. Do not request Go again; seek only the specific diagnostic exception or another explicitly scoped operator decision.

## Durable evidence

`/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/` contains Go/source/profile records, the driver, initial probe result, startup logging/profile diff, interpreter comparison, selected crash metadata, historical diagnostic plan, approved diagnostic result, narrow-cache proposal and `pilot-result.json`. Scratch holds no copied auth/runtime state. TCP/AF_UNIX probe listeners were closed; no live service was changed. Normal CLI login remains intact. Frozen test bytes and collector hashes match the repository baseline.

Discussion closes P196; next P197. Scoped Go approved; broad startup-only comparison completed; narrow OS-cache read exception pending. No guard qualifies. No new TCB normal execution, implementation acceptance or push authorization.

[four-eyes 0.6.0] outcome: stopped at unqualified baseline guard prerequisite after approved startup comparison; mode: strict. Designer/driver: current Codex desktop, runtime model/session not exposed. Implementer/test-writer/new change-review:none. Go: P185 “go”. Diagnostic authorization: P192 “proceed”, two fixed markers completed. Native/frozen tests:not run; no new pass count. Guard qualification:false. First normal-user release TCB execution:not approved/run. Implementation commit:none; documentation checkpoint uses standing rule. Push:none. No role cost reported because no role dispatched.
