# Contributing

Report bugs in GitHub Issues with the macOS version, Mac chip, monitor model, connection path and steps to reproduce. Mention whether the slider reports DDC or software dimming. Omit serial numbers, display UUIDs, account information and raw diagnostic dumps.

Build and run checks on an Apple Silicon Mac:

```sh
MAC_MONITOR_BUILD_DIR=build-preview MAC_MONITOR_SIGNING_IDENTITY=- ./scripts/build.sh
MAC_MONITOR_BUILD_DIR=build-preview ./scripts/test.sh
```

Tests cover DDC frame construction and validation, brightness-key decoding, brightness policies and recovery data. They do not simulate WindowServer or prove physical monitor compatibility. Changes affecting display topology, DDC or virtual HiDPI need physical testing, including recovery after a failed change. Describe the hardware and result in the pull request.

Keep vendor changes documented in Vendor/README.md and preserve the upstream license. Never commit signing keys, credentials, personal diagnostics or generated build output. Contributions are under the project's MIT license.
