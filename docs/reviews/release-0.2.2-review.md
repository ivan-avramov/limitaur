# Release 0.2.2 review — 2026-11-07

[Specification](../proposals/release-0.2.2.md). Baseline `af5bf01`; user authorized “yes, build and publish”. This is a routine release of the already reviewed icon and documentation work. Product changes are version metadata only; the existing icon check's two expected-version literals follow the explicitly approved version.

Light workflow, host only: designer `/root`; isolated implementer `/root/release_implementer` (inherited model); original icon test-writer `/root/icon_testwriter` continued (requested `gpt-6-astra`); fresh cold reviewer `/root/release_review` (requested `gpt-6-astra`). Exact helper model identities were not independently exposed. All share OpenAI; vendor-correlated errors remain uncovered. No external CLI reviewer was dispatched.

Test amendment frozen 2026-11-07T20:53:15Z before candidate reveal at 20:53:53.145Z; SHA-256 `9ba755bd2260713a7ad397dea807ca4bb9dd32df52bef6981c348ab6a82d2139`. Baseline: three packaging tests pass and one fails as expected for 0.2.1 versus required 0.2.2. No other tests changed or duplicated.

Candidate verification in an isolated tracked-only copy: fresh ad-hoc bundle build passed; **35 UI + 436 core native, 62 Python (49 acceptance + 13 collector), and four icon-packaging checks passed**. Strict signature, version and icon checks passed. Only version/fixture diagnostic modes executed; no account access, provider calls, application-mode launch or installation.

After testing, README/handoff status wording was updated to record those results and point to the release page for publication status; runtime inputs were unchanged. Final implementation diff SHA-256 `81db5471adc51dc1c3e1ac77e6fc3a7796791b6be1d6a72a6bd3860d40373927`, plus the frozen two-literal test patch. Cold reviewer saw the final text, test amendment, reports and packaging/publication plan: **NOTHING OF SUBSTANCE**. One opinion, no findings or repair round.

Artifact gates: root builds from the exact clean release commit with full history and no ignored resources, validates arm64/macOS 26+ metadata, source revision, icon and signature, archives only the app, and hashes the entire ZIP. Downloaded draft assets must reproduce that checksum and pass extraction/signature/metadata checks before publication. Annotated tag and main are pushed without force; final release/tag/assets are verified. Public release notes identify the source commit/build and ad-hoc, non-notarized signing status.

No product or packaging framework changes. Specification and small release edits stay within the 60-line budget; this review record and external release notes/artifacts are excluded. Durable publication status and downloadable assets are on the [0.2.2 release page](https://github.com/ivan-avramov/limitaur/releases/tag/v0.2.2); temporary build/check outputs are disposable.
