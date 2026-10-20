# P73 corrected v2 batch: synthetic controls pass, builds fail

2026-10-20. Operator authorization: “approved, proceed with the corrected batch”, acknowledged at P239. Clean source baseline `eaeb40450792a7932ce2d2f13008dd5ea679b2e3`. This approved one fresh batch with the prepared inode-identity correction and no additional retry. The existing P73 Go and v2 read-policy adoption persist; the first normal-user release-TCB execution gate remains closed.

## Results

The corrected metadata control succeeded. All62 unguarded operations succeeded and the complete positive aggregate validated. Each recipe's no-op inventory completed normally with62 successes; the validator rejected each specifically for missing required denials. Both echo and selected isolated-Python startup markers passed under both actual profiles.

| Synthetic guarded inventory | Operations | Required denials | Required successes | Denial errno |
| --- | ---: | ---: | ---: | --- |
| Build | 62 | 43 | 19 | EPERM for all43 |
| Diagnostics | 62 | 46 | 16 | EPERM for all46 |

Every expected name/outcome matched the frozen inventory. Build profile SHA256 `13979add269424078ed7d1d0ef33251a2837ec4f559e7f1de609b5906586dcae`; diagnostics SHA256 `538ab91db4f9d37df7192329abe2bc23189221068e44d438791b0e54dd80125d`. The synthetic stage placeholder was removed, with the entire staging root absent before either real build.

Native and default (`swiftbuild`) release builds then ran independently under the same qualified build recipe, with immutable TRUST/source, separate WORK scratch/cache/config/security and synthetic environments. Both exited1; neither timed out or exceeded the output cap. Native took10.268seconds, with0 stdout/411 stderr bytes and no recognized diagnostic category. Default took31.188seconds, with53 stdout/783 stderr bytes and the fixed category `operation_not_permitted`. Raw output was held in bounded memory and discarded, not persisted or forwarded. The exact error text and rejected operation/resource are therefore unavailable. The generic category does not identify a path, syscall or cause; no source-write, hard-link, cache, service or backend attribution is established.

The batch stopped with `both_release_builds_failed`, total50.908seconds. No real bundle/executable was staged. Actual-artifact write/link protection, native discovery/terminal-record qualification and diagnostic Python/app/test payloads did not run. No test-writer/implementer/reviewer worker was dispatched, no fixture seeder ran, and no new release-TCB file was imported/executed. The synthetic diagnostics placeholder is not actual-artifact evidence. Neither backend is qualified; no native/direct-link substitution or release-ready claim.

## Integrity and cleanup

The driver reported complete cleanup, no residue, and no known child group remaining. A separate trusted-parent check confirmed all eight recorded owned directories and the external synthetic record canary were absent. No comprehensive escaped-descendant census is claimed. The five infrastructure hashes, all14 normative/data hashes, frozen16-file test map and collector map matched. App/build/test/collector inputs remain byte-identical to P119 `ab8b5e6`. P119 stays closed with133 recorded passes; these are synthetic infrastructure results, not replacement P119 tests.

No credential copying, live provider/UI/performance qualification, OS grant, installation, tag, release or push. Normal Codex/Claude CLI help was inspected for future role preparation; no model role was dispatched or auth setup performed.

## Recommended next step

Use one separately authorized diagnostic batch with identical v2 permissions, required controls, flags, environments, time/output limits and immutable SOURCE layout. Improve only trusted-parent in-memory build-output classification before freezing the driver. Pre-register fixed categories for permission/errno mentions, unsupported arguments, manifest/compiler/link/cache/temp/config failures, resource exhaustion and mentions of the known SOURCE/WORK/excluded-root classes. Match case-insensitively where appropriate. Emit category identifiers and counts only; never raw output, arbitrary filenames, assertion values or unknown paths. Treat categories as diagnostic hints, not proof of a rejected syscall or resource. Exercise the classifier on invented strings before launch.

Recover clean actual HEAD, freeze the corrected infrastructure/diff and fresh profiles, repeat mandatory synthetic controls, then run each release backend at most once. Stop after those two build attempts, even if one succeeds; this diagnostic does not launch actual-artifact controls, app/tests or model roles. Keep all mandatory cleanup and frozen-input checks. No retry, policy/path exception, environment workaround, source-write permission, network/Mach allowance or direct-link fallback. This additional build execution is outside the consumed batch and requires a new authorization; the classifier design and routine controller preparation need no separate small-redesign approval.

Prepared independently in external `implementation/build-diagnostic-proposal/classify.py`, SHA256 `0fee32ea8f1f92225b70507d849f7a806bab17bdeaa2ceae40b1c4539f2225d5`. Nine pure synthetic classification checks passed; the helper has no file/process/service access and returns fixed category/count fields only. This did not replay a probe/profile/compiler or recover discarded output. Driver integration and actual-baseline/profile freeze precede any newly authorized execution. `preparation.json` records the scope and checks; no additional build execution is authorized yet.

## Evidence and workflow

Durable directory: `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/v2-corrected-batch/`.

- `approved-corrected-batch.json`, `authorization.json`, `infrastructure-file-map.json`, `frozen-launch.json`, `parameters.json`, `source-export.json`, `trusted-input-map.json`: authority and exact source/infrastructure/profile inputs.
- `positive*.json`, `noop-*-validation.json`, `startup-*.json`, `guarded-*.json`, `inventory.json`, `alias-availability.json`: exact named synthetic controls, startup and no-op validation.
- `native-release.json`, `swiftbuild-release.json`, `placeholder-removal.json`, `result.json`: bounded build attempts and stop/cleanup record.
- `independent-result-checks.json`: subsequent trusted-parent inventory/outcome/hash/cleanup checks. No payload replay.

Four-eyes strict remains in progress for architecture/data boundaries. Existing design-review records/cast are unchanged; post-final-round corrections remain NOT RE-REVIEWED. Implementer/test-writer/change-review roles have not begun because the native-record prerequisite is unmet. Documentation-only checkpoint commits do not constitute release-source acceptance or first-TCB execution approval.
