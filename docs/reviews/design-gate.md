# Initial design gate

Product scope: native macOS menu-bar app, Codex and Claude, system menu-bar tint, three highest percentage limits, no prediction. macOS 26 is the earliest released version meeting the requested 20+ minimum.

Strict four-eyes design verification: GPT-6 Astra via Codex in three fresh sessions, against GPT-6.1 Sol designer; L2. Sixteen findings were adopted/adapted. The last three corrections to account identity, credential-specific auth state and monotonic clocks were applied after the final dispatch and were not re-reviewed. No claim of convergence.

The operator approved the final specification and concrete Codex-only L2 assignment at the implementation gate:

> p20: proceed

Planned roles: GPT-6 Sol implementation; GPT-5.6 Sol adversarial tests and review; GPT-6 Luna frozen-candidate review. Different-model/same-provider fresh contexts reduce transcript anchoring and model-specific errors; they do not reduce vendor-wide training habits, shared tuning, shared data blind spots. Model tiers use the host catalog dated 2026-10-18; billing basis is unknown.

Specification SHA256: `b4616fb36fbe722f28de3a12fa33fc1e1be07773479fb3d90396c625a707564d`. Full orchestration evidence is maintained outside the repository; the final review report will record executed roles, checks and limitations.
