> Historical record imported 2026-11-07 from `2026-10-20-release-tooling/implementation/churn-audit.md`. Commands, approvals and next steps describe the original run and grant no current authority. Only files listed in the [manifest](../../../../evidence/manifest.json) are retained; other artifact names denote omitted historical material. See [evidence limitations](../../../../evidence/README.md).

# P73 review-churn audit

Assessment requested by the operator after the first implementation/change review. Read-only audit of the existing evidence; no additional model review commissioned. The prepared25-group remediation was not dispatched. No implementation was applied to the operator checkout.

## Evidence

- Original design:4 rounds; disposition entries19,18,14,19 (70 total entries, not a count of independent unique bugs). Specification snapshots grew24455,40623,51784,59630,71750 bytes. The initial24.5KB proposal was already broad before reviewers expanded it.
- Guard amendment:3 rounds,25/21/22 findings (68 entries). This did not show a steady tail of minor findings.
- Current review:19 same-writer entries,25 Astra entries,20 Opus entries. These64 entries consolidate into24 reviewer issue groups. The prepared25-group batch also includes one designer About observation. The final panel was supplied the writer's report; repeated agreement is not independent rediscovery.
- Candidate production Python TCB:4266 physical lines across3 files; runner155 more. App Sources/:3128 Swift lines across10 files. These counts indicate scope, not a proof that every line is unnecessary.
- Current tests:322 names,242 passing and80 failing. Original133 all passed. Many failures stop at the same valid-root traversal failure;80 failures are not80 separately established bugs.
- No implementation apply/commit/push. Native development works; default backend, actual UI, current app-bundle integration and sustained performance remain release gates.

## Attribution

Original-design findings included real missing boundaries: source/artifact identities, exact tests, read-only verification, malformed evidence, and honest qualification labels. Designer scope already bundled these with a reusable execution/security/evidence framework.

Fix-induced surface is clearest in the guard amendment. Strict link denial required externally seeded hardlink cases, which then required a catalogue, inert Git object/index construction, per-suite slots and validation. Read-policy changes required alias/exclusion resolution and repeated binding checks. Private-volume recovery added attachment ownership and failure cleanup. These are coherent consequences of those choices, but they are not intrinsically necessary to compile SemVer into an app.

Current findings are predominantly implementation-contract failures: raw4097LF acceptance, read-opening forbidden temp ancestors, nonconforming Git argv, invalid no-op records, unresolved attachment cleanup, missing tag/count revalidation and packaging/verification/publication gaps. Changing requirements again would not repair those defects.

Some findings concern wrong or ambiguous oracles rather than product defects. The frozen releaseCLI --help expectation is not specified. Source mode semantics received different severity/interpretation from reviewers. These require designer judgement, not automatic feature growth or forwarding every question to the operator.

## Causes of avoidable churn

1. Oversized initial unit of work: versioning, packaging, five evidence schemas, a source/Git audit, sandbox orchestration, process supervision, private-volume management and binary policy were coupled.
2. Feasibility measured late: the restrictive read policy and Foundation atomic-write compatibility were discovered after extensive paper review. A small explicitly authorized platform pilot should have preceded a large contract.
3. Repairs became requirements without a complexity budget. Locally valid safeguards accumulated; total architecture cost was not reassessed.
4. Development harness and production supervisor duplicate behavior. The production implementation now has to reproduce the independently qualified controls; passing one cannot qualify the other.
5. Broad repeated briefs and findings-only review encourage discovery beyond the changed part. The final panel additionally receives the earlier findings, so duplicate volume must not be mistaken for independent evidence.
6. Designer-created one-shot/retry rules caused unnecessary approvals for unchanged-permission controller repairs. Four-eyes Go/Accept and the repository's plan rule do not require a new Go for each such fix. Material rights/scope changes remain different.

## Drift and bloat judgement

There is real architectural expansion from local version/release tooling toward a general local release qualification platform. P119 product behavior has been preserved, so this is primarily workflow/architecture drift rather than quota/UI feature drift. The expanded tool can establish consistency of identities and supplied observations; it cannot make manual UI/provider/performance observations true.

Necessary fixes should remain: safe cleanup, exact binding, bounded input/process behavior and faithful test results are required for the chosen architecture. They are not pedantry. Optional new guarantees, general format-verifier capabilities and redundant orchestration should not enter by default. For example v1 need not gain universal/fat-binary support when the contract selects one native architecture; explicit rejection is simpler.

Withdraw the earlier proposed decision to add --help solely to make the frozen oracle pass. That would bend implementation around an invalid assertion. Preserve the original freeze and its observed failure. Any correction must be a documented same-writer amendment/re-freeze under the operator's frozen-test constraint, not an automatic edit or reclassification. No frozen file has been changed.

## Recommendation

Choose one coherent scope checkpoint before dispatching the large remediation. Preferred smaller v1: authored VERSION and compiled version/About; validated changelog/build number and safe signed packaging; source/artifact identity and test results; explicit existing release gates. Keep execution containment in one measured development workflow. Defer making the release tool a self-provisioning general qualification platform until that automation is separately justified. This is a proposed change to the approved architecture and independent-test contract, not permission to silently remove safeguards.

If retaining the full contract, freeze it now, repair demonstrated violations with minimal corrections, and put new requirements in a backlog. Do not start another broad design convergence loop or add public behavior to satisfy a bad oracle.

For either path: classify each finding as existing-contract defect, failed repair, new requirement, or invalid test; deduplicate before implementation; require concrete failure evidence and the smallest correction; review complete small vertical slices and changed boundaries; use early bounded feasibility pilots; retain approval only at real scope/authority/acceptance boundaries. Preserve the P119 frozen tests, normal Claude login, all live release gates and no-push rule.
