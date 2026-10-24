# Backlog: session continuity Part B residuals

Status: backlog, recorded at the Accept ask of Part B (2026-10-24, strict four-eyes; specification `docs/proposals/session-continuity.md` revision 10). None becomes a requirement without an operator decision. Evidence: `/Users/ivan/ws/limitaur-review/2026-10-24-session-continuity/`.

- **R-B1** Timing-sensitive implementer tests (Parts A and B) use bounded state waits that can time out when the machine is heavily loaded (observed once each for three tests at a load average above 40; all pass in isolation and in three consecutive full runs at normal load). Candidate: longer bounds or a load-aware wait helper.
- **R-B2** The merge relocation test fixture (`aliasReplacementDiscardsReceiptAfterItsEntityMerges`) uses a short flush before checking merge completion (test-writer, sixth delivery); a state wait would be stricter.
- **R-B3** Policy dates are wall-clock and persisted; a forward wall jump can bring one probe or one block expiry early (specification B1, accepted).
- **R-B4** Fleet effect (O14): several machines learning independently on one account can provoke up to one 429 per machine per day; L2 runs on two machines to observe it.
- **R-B5** Daily oscillation (O11): a reduction, a 429 at 61–90 min (+10, no block) and another reduction 24 h later can repeat at one level; accepted.
- **R-B6** Under an active policy above about 70 s, `defaultWorkloadEligible` (fixed 90 s) drops eligibility every cycle, so the `violations` counter rises in normal operation and a resource measurement is a smoke unless the interval is 30 s (L4).
- **R-B7** `swift build -c release` fails at `dsymutil` inside the codex sandbox ("Operation not permitted"); the native-backend fallback passes; not reproducible outside the sandbox.
- **Budgets** Final counts exceed the stated budgets after four fix rounds adopting reviewer findings: Monitor +115 net (budget 70), Polling.swift 107 lines (60), AppUI +6 (35), implementer tests 596 lines (130); frozen blind suite 916 lines. Recorded; the operator decides the waiver at Accept.
