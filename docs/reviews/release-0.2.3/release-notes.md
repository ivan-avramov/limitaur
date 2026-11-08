Limitaur 0.2.3 adds build and project details to About Limitaur:

- Clickable repository link and full source commit ID.
- UTC build date and time.
- MIT license link, with the complete license included in the app.
- Copyright © 2026 Ivan Avramov.

Release tooling now prepares patch, minor or major version increments and builds verified ZIP artifacts from the committed release source.

The app ZIP targets **Apple silicon (arm64), macOS 26 or later**. It is **ad-hoc signed and not notarized**.

Download `Limitaur-0.2.3-macos-arm64.zip` and `Limitaur-0.2.3-macos-arm64.zip.sha256` into the same folder. Verify the complete ZIP before extracting:

```sh
shasum -a 256 -c Limitaur-0.2.3-macos-arm64.zip.sha256
```

The expected result is `Limitaur-0.2.3-macos-arm64.zip: OK`.

Build **100**, from source commit [749aeb2](https://github.com/ivan-avramov/limitaur/commit/749aeb2f7470460ae7d7bb428c1ecf470ddfea8f). Validation passed 472 native tests, 69 offline checks, and 13 release-command cases.
