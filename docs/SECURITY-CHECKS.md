# Security verification — 0.2.0-beta.2 / build 17

The three issues from the pre-release review were addressed in source. This document records the boundary of the checks; it is not a certification of security or a claim that all display hardware works.

## Administrator-service change

The app no longer contains the legacy privileged execution bridge. It never runs a shell or a bundle-relative tool with elevated privileges. System overrides now use `SMAppService.daemon` and an XPC-only helper.

- Registration happens only on an explicit install/remove action.
- Both sides require the expected code identifier, the same Apple Developer ID signing team and a valid Apple signing chain. The service refuses to start for ad-hoc/development code; its own signature also requires hardened runtime.
- `NSXPCConnection.setCodeSigningRequirement` checks the message sender. It does not trust a PID looked up after accepting a request.
- Per-operation administrator authorization is obtained by the app, sent only over authenticated XPC, validated by the daemon without UI interaction, and destroyed by the app after completion. No authorization-database rights are installed or weakened.
- The request has bounded argument and authorization sizes. It exposes no executable path, shell command or arbitrary destination. Filesystem operations remain limited to fixed override/backup directories, validated display IDs/sizes and root-controlled non-symlink paths. Requests are serialized across clients.
- Legacy helper command-line install/remove requests are rejected. The new helper is not a general-purpose privileged command runner.
- Errors, cancellation, disconnect and timeouts do not fall back to an unsigned or shell-based elevation method. A timeout may occur after the operation began; the UI asks users to inspect the result rather than claiming nothing changed.
- Removing the service leaves installed configurations and backups intact. Remove configurations first when uninstalling the feature entirely.

The macOS SDK specifies that an app containing an SMAppService LaunchDaemon must be notarized. The current environment has no Developer ID Application certificate. The ad-hoc beta therefore rejects the installer before registration or prompting; existing native modes and virtual HiDPI are unaffected.

Before a release can advertise the system installer as supported, test a Developer ID signed, notarized app in Applications on a separate account: register/approve/revoke/reapprove, authorize and cancel, install/update/remove with original and missing overrides, handle foreign edits, remove service, update/re-register helper, restart, and recover exact original configuration. These manual lifecycle tests have not been completed. Test service re-registration after helper/plist changes before distributing an update.

Apple references:
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Regression checks

Run `./scripts/build.sh` then `./scripts/test.sh` on Apple Silicon. The suite includes:

- **Build 17:** the recorded menu-bar/global mouse/deactivation ordering, late callbacks, real outside clicks, held/multiple buttons and rapid repeated clicks. The user verified ten open/close clicks, a held click and outside dismissal on the built-in display in normal mode without tracing.
- Native-mode descriptor bounds and invalid/truncated input.
- DDC frame/checksum validation and real packet construction against a fake transport.
- **New:** real vendor display-selection code tested with zero, negative, empty, missing, overflowing and valid index/ID inputs, under AddressSanitizer and UndefinedBehaviorSanitizer.
- **New:** numeric write parsing rejects malformed/overflowing input and clamps signed relative changes before addition, under UndefinedBehaviorSanitizer.
- **New:** real anonymous XPC accepts a test process matching its actual designated code requirement and rejects the same process under the production Developer ID requirement before the exported method runs. Empty/malformed authorization data and the ad-hoc client path are rejected. This does not register or run a root daemon. It needs ordinary macOS IPC access, so an external agent sandbox may need a read/test-only exception; CI runners are not inside that agent sandbox.
- **New:** incomplete DDC commands fail before hardware access and the helper rejects the old elevated CLI interface.
- Brightness-key decoding, policy and read-only startup; dense HiDPI sizing; filesystem backup/conflict/symlink rejection in an isolated temporary root; translation consistency; main-display layout and recovery policy.

The root filesystem test uses `OVERRIDE_TESTS`, never the real system override directories. No test registers a daemon, opens administrator authorization UI or changes physical display settings.

## Diagnostics and packaging

Optional panel tracing uses OSLog instead of opening a fixed shared temporary file. Default diagnostics omit UUIDs and serials; raw UUIDs require `--diagnostics-private`. Review monitor model names and OS version before publicly sharing diagnostics.

The packaging script explicitly selects source inputs and signs the public beta ad-hoc unless a Developer ID release identity is provided. Do not upload the personally Apple Development signed app from Applications. Review both ZIPs for credentials, personal diagnostics, symlinks and unexpected files, verify their SHA256SUMS, and confirm the app build is 17. Source ZIPs omit Git history; publishing a Git repository requires reviewing and committing all intended source changes separately. CI actions are pinned to commit SHAs and checkout does not persist credentials. Private reporting must be enabled by the maintainer; no private channel has been created automatically.

## Remaining practical validation

Repeat display tests after these code changes: DDC brightness on HDMI and USB-C, disconnect/reconnect without spontaneous reactivation, sleep/wake, main-display persistence, native/virtual mode confirmation and rollback, forced quit recovery and repeated menu-bar toggles. No external monitor is required to build or run the security regression suite, but software tests do not replace these physical checks. The captured popover flicker was fixed in build 17 and the user confirmed normal-mode repeated/held clicks and outside dismissal on the built-in display. External-display placement still needs physical regression testing.
