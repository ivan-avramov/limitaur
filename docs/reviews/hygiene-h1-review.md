# Hygiene H1 review record

Specification docs/proposals/hygiene-h1.md revision 3; evidence /Users/ivan/ws/limitaur-review/2026-10-25-hygiene-h1/.

```
[four-eyes 0.6.6] outcome: completed; mode: light (P385 is read-time presentation retention; the change reviews checked that no authentication transition changed)
designer: Claude Code: claude-opus-5-5, session 01GZQTjDDNCxf46QxiXTzfmn
design review: codex: gpt-6-astra, 01a17440-25e0-7032-a2ba-ed3af803400f, checkout, returned; claude: claude-opus-5-5, 3054528e-0af8-4727-8722-cab18ce70eb9, checkout, returned; rounds 1; same model as designer: opus; same vendor: opus
implementer: claude: claude-sonnet-5-5, a6974bd5-1b46-4a9f-a04a-713946c91f57; fixes: claude-sonnet-5-5, 767757fb-a9e6-494d-a56a-ccfaa8d10f69
test-writer: codex: gpt-6-astra, 01a17447-b37e-7912-b9d7-c7ba5aaabf82; second and third deliveries continued; same model as designer | implementer: no; tests frozen 2026-10-25T18:24Z, candidate revealed 18:26Z; one test amended by its author in the fix round (bounded re-acquire) and refrozen 18:45Z
change review: round 1 codex 01a17455-545a-7df3-8f66-5698000593e2, opus 46c894f5-2d4e-4114-ab2c-d7e62f65c58c; round 2 (fix) codex 01a17463-4698-7003-830c-57d09fb0735a (NOTHING OF SUBSTANCE), opus 551c2ea9-9031-421b-8f52-13cf48eae3ff; same model as implementer: none; same vendor: opus
not covered: opus with designer: errors this model makes consistently in design judgement; sonnet/opus: Anthropic-shared implementation errors, checked only by codex
go: 2026-10-25, "Proceed"; accept: 2026-10-25, "p55: accepted" (P555); commit: see git log; push: none
```

Design review: P385 per-site clamp replaced by one state-based read-time rule (both members: in-flight cap, later latches, detach, inaccurate site list); `LSMultipleInstancesProhibited` dropped (blocks other user sessions); tri-state lock with the nudge's directory rules, fail-open on unavailable; AC1 fixture fixed; docs exactness; R-C11 and P353 scoped to halves.

Change review 1: adopted mkdir EEXIST race (both), 60 s arithmetic (codex), README retention sentence (opus), deletion of duplicate implementer tests (opus); real-app lock check moved to after Accept (both, major). Fix round: one fresh implementer; frozen lock test's re-acquire amended by its author after one unexplained failure. Change review 2: codex NOTHING OF SUBSTANCE; opus two minors: retry comment's cause unproven (backlog R-H1), test budget (operator accepted, P555.1).

Incident: the designer's first lock hand-check ran the candidate as a second live instance for about 2.5 minutes (stand-in holder failed unverified): one extra Claude 429 on the live app, persisted Claude `lastChange` reset to 18:27:40Z. Record in the evidence `accept-handcheck.md`.

Tests at Accept: 35 UI + 436 core native three times in the operator tree (frozen HygieneH1: 3 core files, 2 UI files, never edit them), release build clean, 49 frozen Python, 13 collector.
