# Release layout verification

The frozen layout test SHA-256 matched b940b7f648faca3443771929cfd8aa90ec0af6360700ea73833942cf7bb85759 before candidate application.

- Baseline layout run: 5 tests, 1 pass (failed build preserves previous output), 4 expected failures (default layout and three refusal checks).
- Frozen candidate: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -v -s Tests/ReleaseTooling` passed 7 unittest methods. This comprises 5 layout tests and 13 existing CLI cases across 2 methods.
- The synthetic layout tests seeded current and previous version names and verified both were replaced by the exact app, ZIP, and digest outputs. A second publish of the same version succeeded. ZIP contents and digest agreed with the published files.
- An injected build failure preserved the seeded ZIP. Default publication refused unrelated contents, a symlink root, and a regular file root, preserving the test fixtures. The existing CLI case confirmed a preexisting ZIP in a custom output directory was preserved.
- Test scope covered packaging with a synthetic build and real ZIP operations. Actual release migration, native signing, and native app behavior were outside this run. No rename failure was injected.
