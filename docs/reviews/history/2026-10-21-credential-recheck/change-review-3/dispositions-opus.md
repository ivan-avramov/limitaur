> Historical record imported 2026-11-07 from `2026-10-21-credential-recheck/change-review-3/dispositions-opus.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# Change review 3: opus dispositions (designer)

opus claude-opus-5-5 e21855fe-060f-4c1e-8e32-eef6a5334816, $1.10, 220 s; 4 findings + test gaps.

| # | Problem | Disposition |
|---|---|---|
| 1 (new, major) | the create/attach guard ignores server rejections that moved off a binding into another profile's memory | adopted (spec r7): guard also consults serverRejected entries of same-provider profiles |
| 2 (= TW P39) | mismatch loop downgrades http401 | adopted |
| 3 (new, minor, inherited) | 401 marks only the request's source; cross-source alias becomes the fallback and re-sends | adopted (spec r7): mark by fingerprint across sources; exclude from fallback |
| 4 (= codex P2) | global forced refresh after no-subscriber completion | adopted (spec r7, via codex P2) |
| 5 | test gaps; implementer tests never shown to fail on the previous monitor | adopted: regression tests in the fix brief; designer verification step added (run the implementer tests against candidate 2's monitor and record which fail) |
