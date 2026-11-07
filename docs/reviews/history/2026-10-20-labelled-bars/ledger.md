> Historical record imported 2026-11-07 from `2026-10-20-labelled-bars/ledger.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../evidence/README.md).

# Labelled bars: review ledger (review-panel 0.4.1, opinion mode, one round)

Material: commit b1aa0a3, read-only clone. Brief: brief.md. Four demo renders beside it.

| Member | Runtime | Model (reported) | Session | Context | Status | Cost |
|---|---|---|---|---|---|---|
| codex | codex | gpt-6-astra, provider openai | 01a15d14-cf76-7df2-a8f9-75eb0cf9171d | checkout, user instructions loaded (~/.codex/AGENTS.md) | valid, 7 findings | unreported |
| opus | claude | claude-opus-5-5 | bdb2b668-1ba2-4c29-9e4d-08506c6937dc | checkout (project instructions) | valid, 6 findings + 1 scope request | $0.67, 138 s |

Opus shares the driver's vendor. Neither member saw the other's findings; where both raised an item the agreement is independent.

| # | Raised by | Problem | Member proposals | Driver disposition |
|---|---|---|---|---|
| 1 | codex P1, opus 1 | sourceAtop tint in the shared (opaque grey) context fills the whole provider box; logos render as squares | tint in an isolated layer, or clip to the image alpha | adopted, adapted: build a CGImage mask per provider from the PNG alpha and paint through it in both passes (the isolated-layer variant trapped under the test runner, so it was replaced) |
| 2 | opus 1 | loader cache ignores the bundle argument; nil-only test | inject bundle, test a synthetic PNG | adopted: injectable `bundle` clears the cache; synthetic disc logo test checks hole at centre, fill at corners |
| 3 | codex P2 | Codex by-limit-id buckets named like Claude kinds (weekly, spend) misclassified | classify by duration first | adopted: known duration decides first |
| 4 | codex P3, opus 3 | label substrings override a known duration (15h→5, 17d→W, 130d→M); tolerances not in contract | token matching, no fallback with known duration, remove tolerances | adopted: `?` for unmatched known durations; W exactly 7 d; M 28–31 d (contract amended to say so); whole-word label hints |
| 5 | codex P4, opus 2 | legacy five_hour_*/seven_day_* keys get `?` | keep known window; opus also suggested suffix initial | adopted codex's version: 5 / W, no initial guessed from a key |
| 6 | codex P5, opus 6 | stale logos survive rebuilds | clear directory first | adopted |
| 7 | codex P6, opus 5 | render tests never check the knockout at 100% or glyph positions | full-fill comparisons, pixel sampling, multiple jars | adopted: alpha sums over top/bottom halves at 100%, three-jar comparison |
| 8 | codex P7, opus 4 | addendum says foreground tint for unfilled glyphs, code uses fixed light tone | operator amendment or follow as written | adopted as amendment to docs/labelled-bars.md; flagged to operator as P328 |
| 9 | opus 7 (scope request) | model initial can collide with M, W or provider letter | contract decision | backlog, recorded in the addendum |
| — | opus 6 | ignored logo dir never marks the revision dirty | plist note | rejected: local dev bundles only; recorded here |

Changes after the round are not re-reviewed.
