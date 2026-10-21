# Limitaur

Native macOS 26+ menu-bar monitor for existing Codex and Claude local sessions. It reads subscription usage and displays the highest fresh quota percentages as narrow bars that fill upward. Beside each bar, two codes are stacked: the provider code on top (`CL` Claude, `CX` Codex; full table in `docs/provider-codes.md`) and the window code below: `5` session or up to six hours, `W` weekly, `M` monthly, `$` spend, `?` unknown, followed by a model initial for model-scoped limits, so Fable's weekly limit reads `WF`. The Indicators menu selects 1–8 bars (default 3) immediately; Accounts… remains a separate dialog. Yellow starts above 80%; red above 95%.

Two experimental layouts, a labelled jar and a logo-shaped gauge, remain in the source behind `RingView.layout` for comparison and are not used by default. A monochrome black-on-transparent square PNG at `Resources/providers/<providerID>.png` is picked up by those layouts; that directory is ignored by git, so logos never enter the repository. The app does not predict usage, buy credits, redeem resets, refresh credentials, or send telemetry.

## Authentication and sources

Codex defaults to `~/.codex/auth.json` and requires `tokens.access_token` plus `tokens.account_id`. An API key alone cannot supply subscription limits. Claude defaults to a noninteractive read of the `Claude Code-credentials` Keychain item, falling back to `~/.claude/.credentials.json` only when the item is absent. A configured Claude file path bypasses Keychain. Settings contain labels and absolute source paths, never tokens. Existing sessions are required; Limitaur does not register its own OAuth client. Background Keychain denial remains visible. Use the account's **Connect / Authorize** action to request macOS access to that existing item; ordinary Refresh never prompts or clears a rejected credential.

Both providers are polled through observed internal HTTPS usage endpoints. These are not guaranteed public APIs and may change. No browser cookies, transcripts, shell provider commands, or arbitrary account files are used. The two default profiles can be enabled or disabled in Settings. The same panel adds and removes explicitly sourced profiles.

## States and refresh

Unknown means no verified value; zero is a known numeric zero. Unlimited is independent of a numeric balance. Unavailable and authentication failure are account states. Last known data remains visible after a failure and becomes stale after 90 monotonic seconds; stale meters leave the bars. Reset times are absolute and a meter leaves ranking at its reset instant until another fetch confirms usage. A backwards wall-clock change does not restore expired cached usage. Reported balance and earned-reset quantities remain visible with an expired or cached qualifier. Refresh runs near 30 seconds while awake, on wake, and when the menu opens if the last success is older than 10 seconds. Failure backoff begins at 30 seconds and reaches 15 minutes. `Retry-After` and manual refresh respect provider throttles. A failed provider does not stop another provider.

## Build and run

```sh
swift build -c release
swift test
sh scripts/build-app.sh
open dist/Limitaur.app
```

The bundle script accepts an optional output path followed by SwiftPM build options. For an isolated native backend build, pass `--build-system`, `--scratch-path`, and `--cache-path` arguments after the output path. It queries SwiftPM for the binary directory. The native backend is deprecated; the default SwiftBuild backend still has an unresolved linking permission error in the recorded isolated checks.

The build script creates a local signed app bundle. It does not install a login item or publish a release. The bundle has no Dock icon.

By default the bundle is ad-hoc signed, and every rebuild gets a new identity, so macOS asks again before the app may read the Claude Keychain item. To keep that trust across rebuilds, create a self-signed code-signing certificate once and name it when building:

1. Keychain Access → Keychain Access menu → Certificate Assistant → Create a Certificate…
2. Name `Limitaur Dev`, Identity Type `Self Signed Root`, Certificate Type `Code Signing`, then Create.
3. Build with `LIMITAUR_SIGN_IDENTITY="Limitaur Dev" sh scripts/build-app.sh`, or export the variable in your shell.

The first launch of a bundle signed with the new identity asks once; later rebuilds do not. Nothing here notarizes or publishes.

## Version

The version lives in one place: the `string` constant in `Sources/Limitaur/AppVersion.swift`. `Limitaur --version` prints it and exits before any settings, credential or network code runs; About Limitaur… in the Settings menu shows it. The build script reads that constant, stamps its numeric core into `CFBundleShortVersionString` (Apple allows only three integers there, so a prerelease or build suffix appears in `--version` and About but not in the plist), sets `CFBundleVersion` to the git commit count, records the HEAD revision (with a `-dirty` suffix when any build input under `Sources`, `Resources`, `scripts` or `Package.swift` is modified or untracked) in `LimitaurSourceRevision`, checks that the built binary reports the same version, and writes `Limitaur.app.sha256` next to the bundle. `CHANGELOG.md` holds release notes in Keep a Changelog form. Nothing here notarizes, tags or publishes.

## Local diagnostics

```sh
BIN_DIR="$(swift build -c release --show-bin-path)"
"$BIN_DIR/Limitaur" --version
"$BIN_DIR/Limitaur" --check-percent 95.01
"$BIN_DIR/Limitaur" --inspect-fixture codex Tests/LimitaurCoreTests/Fixtures/codex-direct.json
"$BIN_DIR/Limitaur" --inspect-fixture codex Tests/LimitaurCoreTests/Fixtures/codex-app-server.json
"$BIN_DIR/Limitaur" --inspect-fixture claude Tests/LimitaurCoreTests/Fixtures/claude-modern.json
"$BIN_DIR/Limitaur" --rank-fixture Tests/LimitaurCoreTests/Fixtures/ranking.json --now 1800000000
"$BIN_DIR/Limitaur" --rank-fixture Tests/LimitaurCoreTests/Fixtures/ranking.json --now 1800000000 --count 5
"$BIN_DIR/Limitaur" --render-demo /tmp/limitaur-demo
"$BIN_DIR/Limitaur" --demo
"$BIN_DIR/Limitaur" --demo-open-popover
dist/Limitaur.app/Contents/MacOS/Limitaur --check-live
```

Fixture diagnostics use synthetic JSON, do not access credentials, and output normalized JSON. The optional ranking `--count` accepts integers 1–8; the default remains 3, and invalid explicit values exit with a fixed error and no snapshot. `--check-live` uses the real app bundle adapters, waits at most 20 seconds overall, and emits only provider status and counts. The demo mode is offline and labelled; it opens the popover for keyboard and accessibility inspection. Demo indicator choices remain in memory, while account and connection actions are disabled. Static PNGs show actual jar rendering at counts 1, 3, 5 and 8 in light and dark appearances; they do not verify menu-bar anchoring, keyboard interaction, or the accessibility tree in a running app.

For a qualifying resource measurement, launch the bundle executable with an explicit sanitized aggregate statistics path, enable both default providers, close the dropdown, then sample its PID:

```sh
dist/Limitaur.app/Contents/MacOS/Limitaur --stats /tmp/limitaur-aggregate.json
python3 scripts/measure-resources.py PID --stats /tmp/limitaur-aggregate.json
python3 scripts/measure-resources.py PID --warmup 5 --seconds 30
```

The default samples aggregate parent and descendant RSS every two seconds after 60 seconds of warmup for 600 seconds and computes CPU from nanosecond process counters. The short command is a smoke sample. Record the selected indicator count and keep it fixed, with the dropdown closed, during a qualifying measurement; results for one count do not qualify other counts. A qualifying performance result needs at least 18 successes for each default provider, no failed or throttled requests, both intended defaults continuously eligible, and no child helpers. The statistics file contains only aggregate outcomes and anonymous eligibility counters. RSS peaks and short-lived children between samples can be missed.

Earlier guarded build, test and short resource results are recorded in [performance evidence](docs/performance.md); they do not verify later source edits. Actual UI behavior, Claude app-bundle access and the sustained two-provider resource workload remain unverified. Cursor support is deferred.
## Local demo appearance checks

Run `Limitaur --demo-light` or `Limitaur --demo-dark` to open a synthetic dropdown in that app-local appearance. The demo includes enough provider and account rows to check scrolling, keyboard focus, and accessibility without reading credentials or making requests. `Limitaur --demo` uses the current system appearance. `Limitaur --help` lists the diagnostic options. These commands prepare manual UI checks; they do not establish that those checks passed.

`Limitaur --stats FILE` requires a fresh absolute output path. It refuses existing files, symlinks, and configured credential paths; subsequent measurements write through the descriptor it created.

