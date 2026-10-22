# Backlog: API-metered and hybrid accounts

Status: backlog, not approved for implementation in this checkout. The operator has an API-billed account on another machine and will pick this up there. The detailed contract drafted on 2026-10-18 is external (`/Users/ivan/ws/limitaur-review/2026-10-18-01a15018/claude-continuation/additions-design.md`); this page is its summary and the list of decisions still open. Its SemVer section is superseded by the minimal P73 versioning already shipped.

## What it adds

- A second account type: a reporting-credential source (an admin or reporting key in a pre-existing JSON file, selected by path in Settings, read with the same bounded reader as today) that fetches organisation or project cost totals for the current UTC month.
- A typed spend budget: spent and cap as Decimal in one currency over a period and exact scope. With a known complete total and a positive cap in matching units, spent/cap gives a percentage that ranks beside quota percentages with the same thresholds and the `$` window code. Unknown or mismatched cap or currency means no gauge. Values above the cap keep the raw percentage; only drawing clamps.
- Fixed endpoints: OpenAI `GET https://api.openai.com/v1/organization/costs` (Bearer reporting credential, daily buckets, `has_more`/`next_page`, `project_ids` filter) and Claude `GET https://api.anthropic.com/v1/organizations/cost_report` (`x-api-key` plus `anthropic-version`, USD cents as decimal strings, daily buckets). Same transport rules as today: redirects rejected, streamed 1 MiB bound, no custom URLs or headers.
- Hybrid state for subscription accounts: an explicit billing state (included, exhausted, credits unconfirmed, confirmed paid fallback, paid exhausted, unknown) from validated source fields only. A bypassed quota leaves the top-N only with fresh provider confirmation naming the metric and a verified link to an active paid budget; otherwise the highest percentage still ranks.

## Settled design decisions worth keeping

- Billing credentials never go to subscription endpoints or redirects; subscription tokens never go to billing endpoints. Reporting access is not inferred from an inference key.
- Organisation identity is unverified unless the provider proves it. A budget binds to the exact credential fingerprint and scope; a replaced credential or a process restart requires explicit re-establishment before ranking. No automatic rebinding of a persisted budget to a newly loaded key.
- Pagination completeness is separate from coverage: at most 4 pages and 4096 rows per cycle; repeated or missing cursors, out-of-month buckets, malformed amounts or scope mismatch invalidate the total and prevent the gauge. Claude priority-tier costs are omitted by the provider, so a total is informational unless coverage is explicitly limited and labelled.
- Current-day semantics are not established: daily buckets can enclose the query cutoff. Until verified, current-day totals are informational, no gauge; never prorate or clip.
- Poll billing at most every 60 s including manual actions; subscriptions stay at 30 s. Reported totals show source lag or unknown source time separately from fetch time. Remove prior-month totals at the exact UTC rollover even under backoff.
- Paid-fallback indicator may pulse only on fresh confirmed state via a slow Core Animation opacity change, static under Reduce Motion, stopped on stale, sleep or disconnect.

## Open before implementation

- Reporting coverage and current-day semantics per provider need verification against live responses; the drafted contract flags them as unresolved.
- The organisation-unverified restart binding rule is strict; decide whether the friction is acceptable for a single-user tool.
- Where the reporting key file lives on the other machine, and whether Settings should accept a Keychain item instead of a file.
- Line budget before design, per AGENTS.md, and a cold design opinion before writing code, since this touches a credential boundary.

## Preregistered acceptance from the draft

B1 existing suites preserved; B2 budget arithmetic fixtures including 4100/5000 = 82%, exact thresholds, overflow and currency mismatch; B3 request routing, header and query allowlists, pagination completeness, per-page errors and rollover; B4 hybrid matrix with no pulse on unconfirmed credits and linkage invalidation; B6 Settings, demo and README coverage. B5 (release tooling) is superseded.
