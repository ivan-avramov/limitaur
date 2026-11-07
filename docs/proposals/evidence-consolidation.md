# Evidence consolidation — approved P6

Problem: keep durable review records, verification evidence and unfinished designs in this repository, publish the curated result, then remove the obsolete sibling review folder after verified publication.

- Approval: 2026-11-07, “go with your p6 plan as outlined”; baseline `be7d727`.
- Scope: selected historical text, compact aggregate renewal observations, provenance manifest, indexes and documentation links. No product, build, authentication or runtime changes; no release or tag.
- Budget: 300 new/changed documentation lines excluding imported historical records, generated tables/manifest/CSV and review record; imports below 1 MiB.
- [Manifest](../evidence/manifest.json) defines exact retained selection, source/destination hashes, source snapshot and omitted categories. [Evidence index](../evidence/README.md) defines transformations, sampling assumptions and limits.
- Preserve substantive findings, outcomes and original numeric measurements. Normalize machine-specific paths, retain generic examples, and identify omitted intermediates honestly. Historical commands and approvals are inactive.
- Keep API/hybrid draft UNAPPROVED under the current backlog; preserve the mach-timebase correction warning beside historical CPU evidence.
- Import plain text only; exclude raw transcripts, full timeline, old binaries, duplicate checkouts and private runtime data. Flag suspected secrets by location/category only.
- Validate exact coverage/hash and inventory partitions, JSON/prose preservation, source-derived CSV, links, documentation-only scope and publication scans. Missing counters remain distinct from measured zero.
- Success: the curated records are navigable and self-contained; independent checks and bounded review find no unresolved material defect. Any failed publication or source-stability gate stops deletion.
- Root publication gate: ordinary fast-forward push of the accepted commit; remote main equals local; fresh remote checkout has the same manifest and retained/derived file hashes.
- Root deletion gate: original source hashes and file inventory unchanged; no active users of the folder, symlinks or nested mounts; remove only the old sibling review folder after remote verification.
- No force-push, history rewrite, publication of local secrets, generic evidence framework or deletion elsewhere. No open design decisions remain in this increment.
