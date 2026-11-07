# About build information

## Goal
Make the About page show the repository URL, the code commit used to build it, when it was built, the license, and a copyright notice benefiting Ivan Avramov.

## Scope and constraints
Operator approved P1/P2 on 2026-11-07. Light mode. Budget 180 added/changed lines for product, packaging, tests and README; review records excluded. Preserve the native standard About panel and existing version/build behavior. No dependencies, credential access, provider changes, version bump or publishing in this increment.

## Contract
- AppVersion.aboutPanelOptions(bundle:) supplies attributed credits with clickable https://github.com/ivan-avramov/limitaur and a clickable MIT license link, and copyright © 2026 Ivan Avramov via the native copyright option.
- Credits display full LimitaurSourceRevision from the Limitaur bundle, including its existing -dirty suffix, and LimitaurBuildDate in an explicit UTC ISO-8601 form. No runtime Git lookup or current-date fallback. Missing or empty metadata, and non-Limitaur bundles, show Unavailable for revision and build time.
- scripts/build-app.sh stamps LimitaurBuildDate as UTC time during packaging, preserves full HEAD revision and dirty marking, copies LICENSE verbatim into Contents/Resources/LICENSE before signing, and includes LICENSE among dirty build inputs.
- MIT link uses the bundled license file when available; source checkout license URL is fallback when unbundled. Repository URL is constant, not arbitrary remote text.
- README explains these fields and the bare-executable fallback.

## Traces
Packaged app: build script stamps revision/time and copies LICENSE; About reads its own bundle and renders credits with links, version/build and copyright.
Bare executable or missing metadata: About retains version and renders Unavailable values without inventing build facts; MIT fallback URL remains usable.

## Acceptance
A1 About options contain the repository link, license link and exact copyright.
A2 Synthetic app bundle displays supplied full revision including dirty marker and supplied build time. Empty/missing and nonapp metadata show Unavailable.
A3 Actual packaged app has full current HEAD revision (dirty when inputs changed), parseable current UTC build timestamp, byte-identical LICENSE and a valid signature; --version remains unchanged.
A4 Native suite and existing offline suites pass, or baseline failures are identified. Standard panel layout is visually checked without live provider access.

## Non-goals
Release command, version bump, tags, upload, installing or relaunching the live app, changing signing policy, new custom window.

## Roles
Host agents in isolated tracked-source copies: Terra implementation, Sol tests, Astra cold review. All OpenAI; vendor-correlated mistakes remain possible. Test agent is continued using host follow-up support. One cold review, at most one focused follow-up. Operator acceptance precedes applying and committing.
