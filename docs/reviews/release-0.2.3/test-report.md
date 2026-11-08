# Frozen CLI test report

Applied implementation.diff to the tester copy and ran `python3 -m unittest discover -s Tests/ReleaseTooling -v`. Both methods passed. They exercise 13 fixture cases in total, including three successful increments and ten preflight rejections. The build marker was absent in all cases. `git diff --check` passed.

One additional disposable fixture exposed a dated-changelog validation gap. Replace its dated entry with `## [1.2.3] - 2026-99-99` and run `package`. The invalid date passes preflight and invokes the fixture builder, as confirmed by its marker. The eventual exit 1 comes from the deliberately failing builder. The approved requirement is a dated changelog section. Capturing the date and parsing it with `date.fromisoformat` would reject this before a build.

No native tests, bundle tests, or release artifact builds ran in this phase.

## Final candidate verification

Candidate 749aeb2f7470460ae7d7bb428c1ecf470ddfea8f. SHA-256 of all three candidate test files matched the frozen manifest. Final release tooling rerun passed both methods, covering 13 fixture cases.

Native tests: 436 core in 23 suites passed using `swift test --disable-sandbox`. The restricted UI invocation stopped partway through, so the native UI bundle was rerun directly with `xcrun xctest` under normal macOS access. Its final summary recorded all 36 passing in one suite.

Offline checks: 49 adversarial passed against the extracted release executable, 13 measurement checks passed, 4 Icon packaging and 3 About packaging checks passed on the actual extracted bundle. Extracted executable reported 0.2.3 and the bundle revision matched the full candidate commit. ZIP SHA-256 matched the supplied checksum: ce019d5634210364fc8027c8aa1f1d1dc5eb93be6a3c34f07b0b6021aff1b5aa. ZIP integrity passed, its sole top-level entry was Limitaur.app, and the ignored synthetic provider image was absent in the ZIP and extraction. Extracted app was arm64-only and passed strict code-signature verification.
