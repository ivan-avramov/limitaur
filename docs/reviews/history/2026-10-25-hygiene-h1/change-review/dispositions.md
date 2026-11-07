> Historical record imported 2026-11-07 from `2026-10-25-hygiene-h1/change-review/dispositions.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# H1 change review dispositions (2026-10-25)
Members: codex gpt-6-astra 01a17455-545a-7df3-8f66-5698000593e2; claude-opus-5-5 46c894f5-2d4e-4114-ab2c-d7e62f65c58c ($1.18).
- codex P1 / opus 2 (mkdir EEXIST -> unavailable; concurrent first launches both run): ADOPTED, fix round (candidate deviated from spec; spec r3 makes it explicit).
- codex P2 / opus 1 (real app never shown to hold its lock; --demo under a held lock unchecked): ADOPTED as an Accept check after relaunching the final build as the only instance (running the candidate as a first instance now would be a second live poller, cf. the hand-check incident).
- codex P3 (60 s arithmetic): ADOPTED, fix round (spec r3).
- opus 3 (README Retry-After retention sentence now false under P385): ADOPTED, fix round (spec r3).
- opus 4 (implementer lock tests duplicate frozen ones; test budget): ADOPTED, delete the file in the fix round.
