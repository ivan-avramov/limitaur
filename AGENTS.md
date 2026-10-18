# Limitaur

- Build native Swift/AppKit for macOS 26+. Keep runtime dependencies empty.
- Follow the approved scope and acceptance criteria in docs/specification.md.
- Use four-eyes for non-trivial work and every credential/data-boundary change; dispatched phase workers perform only their assigned phase.
- Never print, persist, commit or transmit credentials or raw account responses. Keep provider authentication read-only.
- Distinguish unknown, unavailable, stale, unlimited and zero. Do not infer plan-specific limits.
- Use system menu-bar foreground tint for normal fill; warning >80%, critical >95%. Do not add prediction.
- Run code and tests using the isolation specified in the phase brief.
- Commit coherent accepted work. Push only on explicit approval in the current turn.
