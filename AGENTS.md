# Limitaur

- Build native Swift/AppKit for macOS 26+. Keep runtime dependencies empty.
- Follow docs/specification.md and its approved docs/compact-bars.md addendum.
- Use four-eyes for non-trivial work and every credential/data-boundary change; dispatched phase workers perform only their assigned phase.
- Never print, persist, commit or transmit credentials or raw account responses. Keep provider authentication read-only.
- Distinguish unknown, unavailable, stale, unlimited and zero. Do not infer plan-specific limits.
- Use system menu-bar foreground tint for normal fill; warning >80%, critical >95%. Do not add prediction.
- Run code and tests in the copy the brief names.
- Commit coherent accepted work. Push only on explicit approval in the current turn.
