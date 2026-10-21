# P73 minimal versioning: review record

2026-10-20. Commit 9f42eb5 (version constant, `--version`, About item, stamped packaging, changelog, tests) was reviewed cold by gpt-6-astra via codex and claude-opus-5-5 via the claude CLI, each in a fresh session on a read-only clone. Six findings, all minor, all adopted in the follow-up commit: `./`-prefixed shasum path; a bounded subprocess test of the real executable's `--version` dispatch; changelog entries moved under 0.1.0; numeric core only in `CFBundleShortVersionString`; dirty marker covers untracked build inputs; positive About build-number test. The follow-up changes were not re-reviewed. Ledger, brief and raw outputs: `/Users/ivan/ws/limitaur-review/2026-10-20-p73-minimal/`.

Test counts after the change: 79 native Swift, 49 frozen independent Python, 12 collector; all pass. Release gates (actual UI/AX, app-bundle provider access, sustained performance, default backend) are unchanged and still unverified.
