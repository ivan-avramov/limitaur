# Local build layout cleanup

Completed under operator approval P15: “sounds good - make the changes” (2026-11-07). Default output is ignored build/ containing latest app, versioned ZIP and full-ZIP checksum. Successful default packaging replaces recognized generated outputs only, after validation; custom output keeps ZIP-only/no-overwrite behavior. Removed redundant executable checksum. Current README and diagnostic default paths match. Runtime, credential logic, signing and published release unchanged.

Moved13 text release0.2.3 evidence files from dist/release-review-0.2.3 to docs/reviews/release-0.2.3. Current-location references in readiness updated; frozen historical records retain historical paths. Copied exact published ZIP/checksum into build/ and extracted its app. Verified SHA256 ce019d5634210364fc8027c8aa1f1d1dc5eb93be6a3c34f07b0b6021aff1b5aa, strict signature, version0.2.3/build100/revision749aeb2. Removed redundant dist tree, including old0.2.2 files, verification downloads and source clone. Swift .build cache untouched. Previous releases remain on GitHub.

Tests: five frozen layout tests reproduced four expected baseline failures and one preservation pass. Candidate passed all five plus the two existing release CLI methods covering13 cases. Checks cover default replacement including same-version repackaging, old version cleanup, archive/checksum agreement, build failure preserving prior output, rejection of unrelated contents/symlink/file root, custom existing ZIP preservation. Root additionally injected final-directory rename failure and verified prior build restored. Python/shell syntax and diff checks pass. Native app code unchanged; no new native-suite run or live-provider launch. Cold review: NOTHING OF SUBSTANCE. No fixes or follow-up review needed.

Budget: initial estimate about100 changed lines excluding moved evidence; actual78 implementation/documentation added/deleted lines plus126 independent test lines. Overrun is test-fixture coverage, no added feature scope.

[four-eyes 0.7.0] outcome: completed; mode: light (packaging/path cleanup)
Designer: root host; implementer: host gpt-6.1-terra /root/layout_implementation; fixes:none.
Test-writer: host gpt-6.1-sol /root/layout_tests, continued; frozen2026-11-08T00:56:35Z; candidate revealed after freeze.
Panel: host gpt-6-astra /root/layout_review, briefed cold candidate, returned; verify:none. All OpenAI; shared-vendor mistakes uncovered.
Go/application authorization:2026-11-07 “sounds good - make the changes”, approving concrete P15 cleanup. Commit:this change; push:none. User's explicit instruction authorizes applying this cleanup; no additional approval requested for reversible local cleanup.
