# Evidence retained in the repository

Consolidated 2026-11-07 from the historical sibling review archive at baseline `be7d727`. This repository is the durable record; no external archive is required. [Manifest](manifest.json) records original and retained SHA-256 hashes, source snapshot identity and the full count/byte partition. Source identifiers are relative to the former archive root; they are provenance labels, not live paths.

**Historical CPU correction:** pre-2026-10-25 measurements interpreted mach ticks as nanoseconds and understated CPU by about 41.7× on that host (timebase 125/3). Original numeric values are preserved in imported records. Read the [performance correction](../performance.md) before using them; corrected build 41 and 51 CPU values are about 0.026% and 0.034%. No historical measurement is promoted to a newly qualifying run.

## Scope and omissions

Only the manifest's retained files and derived CSV are preserved. Raw agent transcripts, logs, screenshots, scratch checkouts, binaries, frozen test copies, drivers, profiles and intermediate metadata are intentionally omitted. An old reference to one of these is historical/omitted, even where its short filename remains in prose or JSON. Retained findings and outcome summaries are not a substitute for omitted raw evidence and cannot reproduce every historical claim. Generic platform/example paths remain; machine-specific paths are normalized. Numeric metrics, findings, dispositions and recorded residuals remain unchanged.

Imported commands, approvals, running-process claims and next steps are historical content, not instructions or renewed authority. [Reviews](../reviews/README.md) preserve rejected and retired alternatives. [API/hybrid draft](../proposals/api-metered-accounts-draft.md) is UNAPPROVED; the [backlog](../backlog/api-metered-accounts.md) controls current scope and its SemVer section is superseded.

## Renewal event derivation

[renewal-events.csv](renewal-events.csv) retains preceding, first nudge-observation and first matching resume timestamps plus allowlisted aggregate counters only. The manifest identifies the source log by hash. Compare adjacent samples within each process; for each `nudges` increment, find the first `credentialResumes` increase over the preceding sample, at or after the nudge observation and within 120 seconds. Matching resets on process changes or non-JSON records. Process segments are anonymous sequence numbers, never PIDs. The full timeline is omitted.

The nominal sample interval is 15 seconds: event times and delay are observed sample times, not exact execution times. Gaps above 16 seconds and incomplete windows are flagged. Missing counters stay blank in CSV. Delta detection assumes absent cumulative counters mean zero because `Monitor` starts `eligibilityCounts` empty and inserts counters on increment; the historical binary's encoding is assumed consistent, not independently proven. This assumption is recorded per row. Missing failure/suspension counters mean **not recorded**, not measured zero. A counter decrease without a process change would be a discontinuity, not a new event.

The source has 4 non-JSON build-change annotations before the observed nudge events; matching resets there. The CSV contains 19 observed nudge increments; 19 have a matching resume within 120 seconds. This is one-machine observational association, not exclusive causality, second-machine validation or proof of no gaps elsewhere in the full timeline.

## Retained acceptance and measurement records

| Original source identifier | Retained record |
| --- | --- |
| `2026-10-18-01a15018/compact-bars/accepted-development.json` | [accepted-development.json](history/2026-10-18-01a15018/compact-bars/accepted-development.json) |
| `2026-10-18-01a15018/compact-bars/runtime-evidence/bars-panel2/BP2-result.txt` | [BP2-result.txt](history/2026-10-18-01a15018/compact-bars/runtime-evidence/bars-panel2/BP2-result.txt) |
| `2026-10-21-credential-recheck/accept-verify-operator-tree.txt` | [accept-verify-operator-tree.txt](history/2026-10-21-credential-recheck/accept-verify-operator-tree.txt) |
| `2026-10-23-release-gates/measure-1.json` | [measure-1.json](history/2026-10-23-release-gates/measure-1.json) |
| `2026-10-23-throttle-freshness/accept-verify-operator-tree.txt` | [accept-verify-operator-tree.txt](history/2026-10-23-throttle-freshness/accept-verify-operator-tree.txt) |
| `2026-10-24-session-continuity/accept-verify-operator-tree-a.txt` | [accept-verify-operator-tree-a.txt](history/2026-10-24-session-continuity/accept-verify-operator-tree-a.txt) |
| `2026-10-24-session-continuity/accept-verify-operator-tree-b.txt` | [accept-verify-operator-tree-b.txt](history/2026-10-24-session-continuity/accept-verify-operator-tree-b.txt) |
| `2026-10-24-session-continuity/accept-verify-operator-tree-c.txt` | [accept-verify-operator-tree-c.txt](history/2026-10-24-session-continuity/accept-verify-operator-tree-c.txt) |
| `2026-10-24-session-continuity/live/measure-l4-1.json` | [measure-l4-1.json](history/2026-10-24-session-continuity/live/measure-l4-1.json) |
| `2026-10-25-hygiene-h1/accept-handcheck.md` | [accept-handcheck.md](history/2026-10-25-hygiene-h1/accept-handcheck.md) |

Three earlier proposals are intentionally omitted: `2026-10-18-01a15018/claude-continuation/next-ui-design.md` and `next-step-gate.md` are pre-P119 compact-bars proposals superseded by the accepted compact-bars specification and records; `2026-10-18-01a15018/evidence/next-scope-proposal.md` is an early SemVer/readiness proposal superseded by P73 and the retained API draft.

## Omitted source inventory

| Category | Files | Bytes |
| --- | ---: | ---: |
| binary_media_or_build_artifacts | 141 | 2716139 |
| intermediate_plans_metadata_and_other_unselected_files | 2550 | 61579421 |
| raw_logs_and_model_outputs | 112 | 8522594 |
| retired_test_copies_and_execution_helpers | 688 | 8036097 |
