# P73 v2 qualification pilot: stopped on an unguarded control

2026-10-20. The operator approved P231's amendment/bundled batch with “approved”; acknowledged at P232. This adopts the v2 read contract, including its disclosed additional system reads, for development and eventual prepare, conditional on qualification. Historical proposed-status text in the frozen normative documents remains unchanged. Original spec SHA256 `34f97eae0e87f62c7c50db8140ddf2f644419270643cd37641ac5f58d06a5f76`; amendment SHA256 `c661a050a40df9a087d0c1bf631ee54aedd4fafc2932b0cc774e7503570e663d`. No new design-review round occurred. Post-round3 corrections remain NOT RE-REVIEWED.

## Measured outcome

The independent infrastructure ran from clean HEAD `1b4a1322aa0d39709f9fc0e248e553e92fe6132d`. Renderer self-checks matched both golden profiles, seven encoder negatives and four renderer negatives. Static native inventory found72 unique names; this is not native runtime record qualification.

The62-name prebuild inventory was frozen before launch. The unguarded pass stopped at record43, `trustMetadata.2`, after42 successful controls. That child exited0, emitted its complete named JSON record, but reported `status=error`, `errno=null`. No positive aggregate was validated. No no-op child, guarded startup, guarded matrix, build, app/test payload, seeder or model worker ran. Generated profiles were not compiled/applied. v2 remains unqualified; this result neither proves nor disproves its guard efficacy or startup compatibility.

The harness incorrectly required `realpath` text for a Data-volume TRUST alias to equal the canonical `/private/tmp` spelling, despite the already checked same directory identity. A bounded trusted-parent metadata-only check afterward confirmed `/private/tmp`, `/tmp` and `/System/Volumes/Data/private/tmp` identify one directory while `realpath` preserves different strings. This explains the rejected equality; it is a controller/probe defect, not a measured sandbox denial. No payload was rerun for diagnosis.

Cleanup completed: listeners closed, owned home/Darwin-temp/peer/placeholder/scratch/export roots and the driver record canary removed, no reported residue. Normal probe children left no known process group. This does not establish a comprehensive escaped-descendant census. Original normative/data hashes, frozen16-file tests and collector remained unchanged. App/build/test/collector inputs remain byte-identical to accepted P119 source `ab8b5e6`.

## Correction prepared, execution stopped

A separate, unexecuted candidate changes only `probe.py`: perform the required `realpath` and `getcwd` operations, then compare device/inode identities for the declared, resolved and canonical directories rather than their strings. Guard bytes, permissions, inventory, operations, environment and limits are unchanged. All five candidate infrastructure files parse; no corrected child or profile was executed. Corrected probe SHA256 `6a7061866212bcfc965aa2dcc4beea873543921e23d928610091be82c1c8b31d`. Recover/pin actual clean HEAD before any newly authorized batch; do not run a driver with its historical hardcoded baseline.

The amendment's one controller-retry allowance requires validated positive and no-op records, and permits only argv/serialization changes before a guarded launch. Neither prerequisite is met, and this correction changes a probe predicate. A fresh execution batch therefore needs explicit authorization. This is an execution-budget restriction from the approved amendment, not a four-eyes requirement to seek approval for small repairs. The correction and read-only diagnosis proceeded autonomously.

Recommendation: authorize one fresh batch with this exact identity correction, unchanged v2 protections and existing conditional P73 continuation. Stop on any failed control; no additional retry, fallback policy, guessed path exception or broadened authority. The separate frozen-code/data approval before first normal-user execution of the three new release-TCB files remains closed. No implementation worker has been dispatched. P119 stays closed at133 recorded passes; API/hybrid and live release gates remain separate. No push/tag/install/release or credential copying.

## Evidence

Durable directory: `/Users/ivan/ws/limitaur-review/2026-10-20-release-tooling/implementation/v2-pilot/`.

- `authorization.json`, `source-export.json`, `infrastructure-file-map.json`, `frozen-launch.json`, `parameters.json`, `trusted-input-map.json`, `canary-file-map.json`: authority and exact prelaunch bytes/identities.
- `inventory.json`, `alias-availability.json`, `positive.json`, `result.json`: complete intended names, available synthetic aliases, partial positive results and stop/cleanup record. No raw subprocess output was retained or forwarded to a model.
- `metadata-alias-analysis.json`: subsequent metadata-only diagnosis, no probe replay.
- Exact independent `policy.py`, `probe.py`, `executor.py`, `seeder.py`, `pilot.py` are preserved unchanged after the failed attempt. The seeder was not executed.
- Sibling `v2-pilot-retry-candidate/`: separate corrected infrastructure, candidate hash map and `proposal.json`; unexecuted, not an authority to rerun.
