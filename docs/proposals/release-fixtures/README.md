# Invented release schema fixture

All observations and identities here are invented. These files are design material, not release evidence. The executable digest describes text, not a built app. Tool and inventory digests are placeholders. No release can qualify from this fixture.

manifest.json and the five evidence documents exercise the normative data shapes. Copy only the five evidence JSON documents into a synthetic evidence directory. validate_manifest accepts the manifest structurally; validate_evidence with the clock in golden.json returns an empty reason list. Full prepare/verify must reject this fixture as a real candidate because no app, matching source, tools or inventory exists. golden.json pins UTF-8 canonicalization, root-mode inclusion and the fixture digests.

The frozenTestsSHA256 value is the actual hash of the preserved baseline test-file map, not a new test outcome. No tests ran to create these fixtures.

The build/diagnostics guard hashes and probe booleans are invented, separate recipe records. reason-vectors.json assigns reasons to evidence validation versus verify policy. For manifest-changing vectors recompute manifestSHA256 and rebind all evidence before applying evidence-only changes; the identity-mismatch vector intentionally changes only one evidence identity. These vectors are data, not runnable tests or current qualification.

Proposed read-exclusion-v2 vectors are isolated under read-exclusions-v2/. They require the unapproved release-guard amendment; this parent v1 pack remains unchanged and active historical design context. No profile has been compiled/applied by creating either pack.
