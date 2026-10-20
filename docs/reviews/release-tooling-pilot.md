# P73 baseline pilot: startup qualification stopped

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

Build profile SHA256 `ef7a3c02de6523cedae11a731cf215377aa41e5d9c317968455153cfa2ac4dcb`; diagnostics `787b08b3c7528e32db0e406190b111519d8237837a689408194ee6c2ae86f3c1`. Logging-only profile `746c823af1d817ead833d9c03a44a7024823f9d9b3f5f8ddb798bfa42e0cf7c8` differs only by the debug directive. No permission statement was widened in any executed profile.

Targeted OS reports show fault frames `ignition_halt`, `boot_boot`, `ignite`, dyld `CacheFinder` and dyld startup, namespace 0x23/code 2. Apple's [published namespace definitions](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/reason.h) map 35/0x23 to LIBIGNITION. This does not establish the private meaning of code 2 or identify any rejected resource, and is not proof the OS source exactly matches this host build. Do not infer a required path exception from these frames. Targeted unified-log queries produced no resource-specific denial message. Raw crash reports were not copied; selected metadata/symbols are retained only.

The startup comparison indicates this is not limited to the system Python launcher. Exact cause remains unestablished. No guard qualifies, no backend result is new, and native record extraction remains unqualified. No claim of Keychain/IPC containment. The existing recorded 72-test summary/133 acceptance is unchanged and is not reopened.

## Next proposed diagnostic: approval required

Prepared, NOT executed: [exact profile diff](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-startup-read-comparison.diff) and [bounded command plan](/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/proposed-startup-read-comparison.json).

Run only `/bin/echo` and the selected Python 3.15 `print` marker, max 5 s each, once. The diagnostic-only variant removes the general file-read-data whitelist denial to test whether read-policy closure participates in startup failure. It retains the original write/network/source denials and explicitly blocks all user homes and named system credential directories. No credential/account query, app/build/test/model code, or new release-tooling TCB is permitted. It is not a qualified guard and must never replace an app/test profile. No automatic permission change follows a successful marker.

Variant SHA256 `f6d281efbd4c73d266c131b3bc1e02142d5efed21b2b1a35b36cb898c78d6aff`. Approval is solely for this read-policy diagnostic exception; the original strong profiles stay unchanged. The new release-tooling first-normal-user-execution gate also remains closed. If later retrying the full probe matrix, fix the driver to retain and validate positive-control JSON before any guarded launch can take an early failure return.

The approved [proposal](../proposals/release-tooling.md) requires stopping payload execution on failed guard/probes and forbids automatic permission broadening. This failed prerequisite is why no implementation workers started despite Go. Do not request Go again; seek only the specific diagnostic exception or another explicitly scoped operator decision.

## Durable evidence

`/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/` contains Go/source/profile records, the driver, initial probe result, startup logging/profile diff, interpreter comparison, selected crash metadata, proposed diagnostic plan and `pilot-result.json`. Scratch holds no copied auth/runtime state. TCP/AF_UNIX probe listeners were closed; no live service was changed. Normal CLI login remains intact. Frozen test bytes and collector hashes match the repository baseline.

Discussion closes P191; next P192. Scoped Go approved; guard startup unresolved; diagnostic read exception pending; no new TCB normal execution, implementation acceptance or push authorization.

[four-eyes 0.6.0] outcome: stopped at failed baseline guard prerequisite; mode: strict. Designer/driver: current Codex desktop, runtime model/session not exposed. Implementer/test-writer/new change-review:none. Go: P185 “go”. Native/frozen tests:not run; no new pass count. Guard qualification:false. First normal-user release TCB execution:not approved/run. Implementation commit:none; documentation checkpoint uses standing rule. Push:none. No role cost reported because no role dispatched.
