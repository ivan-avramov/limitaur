> Historical record imported 2026-11-07 from `2026-10-20-p73-minimal/ledger.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../evidence/README.md).

# P73 minimal versioning: review ledger (review-panel 0.4.1, opinion mode, one round)

Material: commit 9f42eb5 in historical-workspace/limitaur, read-only clone at historical-scratch/limitaur-review-checkout. Brief: brief.md.

| Member | Runtime | Model (reported) | Session | Context | Status | Cost |
|---|---|---|---|---|---|---|
| codex | codex | gpt-6-astra, provider openai | 01a15ce8-c3e0-7e02-9ebd-138848333af2 | checkout, user instructions loaded (~/.codex/AGENTS.md) | valid, 2 findings | unreported |
| opus | claude | claude-opus-5-5 | b42322fd-6707-419e-bc6c-20f8b198b8fb | checkout (project instructions) | valid, 4 findings | $0.29, 71 s |

Opus shares the driver's vendor (Anthropic). Neither member saw the other's findings. Raw outputs: codex/stdout.txt, opus/stdout.json.

| # | Raised by | Problem | Member's proposal | Driver disposition |
|---|---|---|---|---|
| 1 | codex | shasum receives a dash-prefixed relative path when the output app name starts with `-` | prefix with `./` | adopted; reproduced; severity minor (contrived path) |
| 2 | codex | no test runs the real executable, so a wrong `--version extra` fallthrough into AppKit would pass | subprocess tests for `--version`, `--version extra`, `--version --demo` with a bound | adopted, adapted to one parametrised bounded test against the sibling built binary |
| 3 | opus | CHANGELOG lists the flag as Unreleased while the binary prints 0.1.0 | move entries under 0.1.0 or bump | adopted; entries moved under 0.1.0 dated 2026-10-20 |
| 4 | opus | a prerelease suffix would be stamped into CFBundleShortVersionString | regex check or stamp numeric core | adopted, adapted: stamp numeric core; README notes it |
| 5 | opus | `-dirty` ignored untracked files SwiftPM compiles | drop `--untracked-files=no` or limit paths | adopted: `git status --porcelain -- Package.swift Sources Resources scripts` |
| 6 | opus | About test never exercises the build-number branch | positive case with a temp bundle | adopted |

No findings against settled constraints; no scope requests. Changes applied after the round were not re-reviewed.
