# Release procedure

Planned release tag: `v0.2.0-beta.2` (not created or published). VERSION contains `0.2.0-beta.2`; the app bundle uses version `0.2.0`, build `17`.

## Prepare

On an Apple Silicon Mac with Xcode Command Line Tools:

```sh
./scripts/package-release.sh
```

The script builds in `dist/build`, runs checks and makes:

- `dist/MacMonitor-0.2.0-beta.2-arm64.zip` — app, installation instructions and licenses.
- `dist/mac-monitor-0.2.0-beta.2-source.zip` — explicitly selected public source files.
- `dist/SHA256SUMS.txt` — checksums for both archives.

Default release signing is explicitly ad-hoc; personal Apple Development certificates are not used. The existing app in `build/` stays unchanged. The source archive excludes build output, Git history, local diagnostics and credentials. Review archive contents before uploading.

The CI workflow builds and tests on an Apple Silicon macOS runner and uploads artifacts. It does not publish releases automatically or validate physical monitors. Its first hosted run still needs confirmation after publication.

## Publish

Create or use the public repository `kidside/mac-monitor`. Commit the reviewed source on `main`, tag that commit `v0.2.0-beta.2`, and create a GitHub **pre-release** with the text from `docs/RELEASE-NOTES.md`. Attach both ZIPs and `SHA256SUMS.txt`.

Do not include `build/`, `dist/`, raw I/O Registry dumps, serial numbers, local UUID records, signing keys or development certificates. Do not overwrite existing unrelated repository history.

## Future Developer ID signing and notarization

This beta is not Apple notarized. A future notarized release requires a **Developer ID Application** certificate and Apple notarization credentials. An Apple Development certificate is not a substitute.

```sh
MAC_MONITOR_RELEASE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/package-release.sh
xcrun notarytool submit dist/MacMonitor-0.2.0-beta.2-arm64.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
```

The build script enables hardened runtime and timestamping for Developer ID signing of both helper and app. Only an **Accepted** notarization result confirms success. Extract the accepted archive, staple the ticket to the app with `xcrun stapler staple`, validate it, repack that stapled app with the same documentation, and regenerate checksums. Do not re-sign the app or rerun the packaging script afterward: that would create a new, unstapled build. Validate installation on another Mac before publishing.

Credentials belong in a local Keychain profile or appropriate CI secrets, never repository files. Follow [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [GitHub's release instructions](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).


## Administrator-service release gate

The system override installer now uses an SMAppService LaunchDaemon with mutually authenticated XPC. See `docs/SECURITY-CHECKS.md`. macOS requires notarization for apps containing LaunchDaemons. Ad-hoc and Apple Development builds fail closed before attempting registration; they support native modes already provided by macOS and virtual HiDPI.

Do not mark the installer supported until a Developer ID + notarized build passes registration, user approval, authorized install/update/remove, cancellation, service removal, app update/re-registration and backup recovery on a separate test account. No `AuthorizationExecuteWithPrivileges`, shell elevation or unsigned fallback is permitted. On helper/plist updates, unregister and re-register the service; remove existing display configurations before final service removal if uninstalling.

Do not claim the ad-hoc beta provides this administrator-only feature. Upload source and a clearly labelled limited beta if desired; otherwise hold the app release until these checks are complete. The current development environment has no Developer ID Application identity. Do not upload the personally Apple Development signed app from Applications.
