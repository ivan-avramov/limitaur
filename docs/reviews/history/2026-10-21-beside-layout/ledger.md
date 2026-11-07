> Historical record imported 2026-11-07 from `2026-10-21-beside-layout/ledger.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../evidence/README.md).

# Beside layout, provider codes, track, signing: review ledger (review-panel 0.4.1, opinion, one round)

Material: commit 745649b, read-only clone. Brief: brief.md; three renders beside it.

| Member | Runtime | Model (reported) | Session | Context | Status | Cost |
|---|---|---|---|---|---|---|
| codex | codex | gpt-6-astra, provider openai | 01a15fad-b477-70e1-892d-dfe06d0a14be | checkout, user instructions loaded | valid, 4 findings | unreported |
| opus | claude | claude-opus-5-5 | f40aacda-639e-4990-9058-acd83768d034 | checkout (project instructions) | valid, 8 findings + 1 scope request | $0.61, 143 s |

Opus shares the driver's vendor. Neither member saw the other's findings.

| # | Raised by | Problem | Driver disposition |
|---|---|---|---|
| 1 | codex P1 | provider images replace the letters in the default beside layout | adopted: images only in jar and logo layouts; test renders beside with an image present and expects identical pixels |
| 2 | codex P2, opus 1 | logo layout without an image falls into a 5-pt bar and clips the codes | adopted: logo shares jar geometry and draws exactly the jar without an image; test asserts equality |
| 3 | codex P3 | logo layout's centred code vanishes over a hollow mark's transparent centre | recorded as a known limitation in the addendum; layout retained for comparison only, not shipped; no halo built for an experiment |
| 4 | codex P4, opus 6 | unclassified characters count as distinguishing; 6 reads like G | adopted: unclassified is its own class, identical unclassified characters are not evidence; 6 added to C/G class, 3 and 9 to B/8; table entries must be classified |
| 5 | opus 2 | yellow and red fills have ~1.9:1 and ~1.2:1 luminance contrast against the 0.6 light track | adopted, adapted: light track 0.5 (yellow 2.6:1) and a 1-pt edge in the contrast colour at the top of every partial fill; test checks the edge is darker than fill and track in light mode. Red versus grey stays low by luminance in every option; the edge carries the level |
| 6 | opus 3 | alpha assertions over an opaque bar cannot fail | adopted: luminance sums and a uniform-colour check |
| 7 | opus 4 | jar glyphs above the fill were fixed white on the light-mode track | adopted: appearance-derived glyph colour; light-mode jar assertion |
| 8 | opus 5 | preview backdrops probably do not render through cacheDisplay | rejected with evidence: corner pixels of the highlighted and plain previews are 146 and 44 grey, alpha 255 |
| 9 | opus 7 | ß traps the class lookup; fallback can return three letters | adopted: uppercase before truncation; class lookup uses the first uppercase scalar |
| 10 | opus 8 | demo render leaves the layout static changed on error | adopted: defer |
| 11 | opus scope request | fallback codes can collide with reserved ones (clio → CL, chatgpt → CH) | adopted: a colliding fallback degrades to first letter plus `?`; documented |

Changes after the round are not re-reviewed.
