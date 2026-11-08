# Release 0.2.3 readiness

Status: accepted and published on 2026-11-07. Operator main fast-forwarded to tested commit 749aeb2f7470460ae7d7bb428c1ecf470ddfea8f. Main and annotated v0.2.3 pushed atomically. GitHub release is public with the verified ZIP and checksum. No installation or live provider launch performed.

## Result
`prepare patch` produced0.2.3 in the two version fields and dated the release notes2026-11-07. Root committed release source749aeb2f7470460ae7d7bb428c1ecf470ddfea8f before packaging. The actual `package` command created the arm64/macOS26+ ZIP and full-ZIP checksum, using a fresh full-history tracked-only clone and ad-hoc signing. Build100, UTC2026-11-07T22:23:15Z, source revision clean. ZIP SHA256 ce019d5634210364fc8027c8aa1f1d1dc5eb93be6a3c34f07b0b6021aff1b5aa. Published artifacts: https://github.com/ivan-avramov/limitaur/releases/tag/v0.2.3; complete metadata in artifact-report.json.

Validation: 436 core and36 UI Swift Testing functions passed; 49 adversarial +13measurement +4icon +3About checks passed; release CLI 2 unittest methods/13fixture cases passed. Frozen tests exposed the absent command on baseline. Restricted AppKit run incomplete; normal-access direct xcrun xctest completed36 UI tests. Independent extracted-archive checks verified executable version, signature, architecture, clean full revision, build count, UTC build time, LSUIElement, minimum26.0, registered icon, license, sole top-level app and full-ZIP checksum. Ignored synthetic provider image present in source checkout was excluded from ZIP. See test-report.md for evidence and logs.

Budget: estimate250 added/changed lines; actual 262 added/changed and 8 removed lines excluding proposal/review records. Small overrun disclosed to retain readable independent tests; no extra feature scope.

## Findings and dispositions
R1 (test writer and cold reviewer, original, minor, confirmed): package permits impossible manually authored changelog dates. Proposed calendar parse. Disposition: optional backlog, no implementation change. Prepare generates valid dates and current0.2.3 date is correct; executable and release identity unaffected. No requirement added without operator decision. No repair/follow-up review used.

## Run record
[four-eyes 0.7.0] outcome: completed; mode: light (routine release tooling)
Designer: root active host; implementer: host gpt-6.1-terra /root/release_implementation; fixes: none.
Test-writer: host gpt-6.1-sol /root/release_tests; continued; tests frozen2026-11-07T22:21:46Z, candidate disclosed after freeze.
Panel: cold candidate, briefed, host gpt-6-astra /root/release_review; returned one minor. Verify: none.
Shared: all roles OpenAI; model/vendor-correlated errors remain uncovered. User preference retained host agents; host follow-up continued tester despite older skill CLI-only note.
Go:2026-11-07 “accepted both. proceed”; tooling accept and push/publication authorization: 2026-11-07, “Approved. Apply the tested candidate, push, and publish 0.2.3.”; commits: c351d4a/749aeb2 integrated; push: main and v0.2.3, explicit same-turn authorization.

## Publication result

Published https://github.com/ivan-avramov/limitaur/releases/tag/v0.2.3 at 2026-11-07T22:39:51Z (2026-11-07 14:39:51 America/Los_Angeles). Annotated tag object d053cb0be0d6f568dd572cef914eb2f40a1dc578 resolves to source commit 749aeb2f7470460ae7d7bb428c1ecf470ddfea8f; remote main matches. Uploaded both assets to a draft, downloaded them, compared byte-for-byte with tested local assets, checked full-ZIP SHA256 and extracted metadata/architecture/license/icon/signature, then published and verified published metadata and both GitHub asset digests. Published non-draft, non-prerelease, latest release. Operator working tree clean.

Evidence: published-metadata.json, download-verification.json (checks of GitHub-hosted bytes), release-notes.md, artifact-report.json, test-report.md and cold-review.txt. Source code is retained by Git tag v0.2.3; exact published artifacts are retained on GitHub Releases. Redundant local source/download copies were removed during the approved build-folder cleanup. The latest local app, ZIP and checksum are in ignored build/. No rebuild or version/source identity change occurred between testing and publication.

Layout note (2026-11-07): spec.md, candidate.diff, package-host.log and other frozen records retain historical dist/ paths. Those paths describe the release run, not the current layout.
