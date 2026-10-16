# Security

This project is an experimental macOS display utility. Tests do not certify the absence of vulnerabilities. Use the latest reviewed beta source; older builds are not maintained as separate security branches.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option if the maintainer has enabled private vulnerability reporting. If that option is unavailable, open an issue requesting a private contact without including exploit details, device identifiers, credentials or diagnostic dumps. Do not post passwords, signing keys or authorization data in public issues. No private reporting endpoint has been provisioned by the development agent.

## Permissions and data

- Accessibility is optional and used to intercept brightness keys. Sliders do not require it. Ordinary typing is passed through and is not recorded.
- The app does not implement accounts, telemetry, analytics, remote control, or network requests. Preferences and display-recovery information stay local.
- Default `--diagnostics` omits display UUIDs and serial numbers; review model names and OS details before sharing. `--diagnostics-private` contains UUIDs and must remain local.
- Optional `--trace-popover` uses OSLog. There is no shared temporary trace file; logging is off unless explicitly requested at launch. Authorization data is never logged.

## Administrator service

Only the additional system HiDPI configuration installer needs a privileged service. Existing modes, virtual displays, brightness, software disconnect/reconnect and main-display selection do not.

The service is registered only after an explicit install/remove request. It requires a Developer ID signed, hardened, notarized app and macOS user approval. Client and daemon enforce the expected identifier and same signing team through NSXPCConnection code-signing requirements. Each filesystem request also requires administrator authorization; the daemon cannot prompt or create authorization database rules. It accepts only bounded display vendor/product IDs and sizes, writes to fixed system directories, rejects unsafe ownership/permissions and symlinks, serializes requests, preserves original backups and refuses foreign changes.

Unsigned, ad-hoc and Apple Development builds reject this feature before registering the service or asking for administrator rights. There is no legacy privileged execution, shell elevation, setuid or unsigned fallback. The new notarized service lifecycle still requires manual validation before the installer is advertised as supported.

Remove installed configurations from each monitor before unregistering the service in app settings. Unregistering does not erase configurations or backups. Do not delete a backup until restoration has been verified. Disabling the service in Login Items & Extensions revokes its eligibility to run; the app then cannot install/remove configurations until it is approved again.

See [release security checks](docs/SECURITY-CHECKS.md) for the verification boundary and outstanding release requirements.
