# Changelog

## 0.3.1-beta.3 — 2026-10-17

- Show a bilingual closed-lid explanation directly below the built-in display switch when a blocked action is attempted. Keep the switch state unchanged and send no display-enable request.

## 0.3.1-beta.2 — 2026-10-17

- Read AppleClamshellState before built-in display actions. Closed or unknown lid state blocks manual actions, automatic recovery and delayed retries. Shared recovery skips built-in mode, mirror and placement changes, including startup/quit/watchdog paths.
- Preserve built-in identity in recovery records and show closed/unknown lid status in the panel. Defer requested restoration until the lid is open.

## 0.3.1-beta.1 — 2026-10-17

- Add a separate built-in display section on Apple Silicon, with explicit permission for software disconnect/reconnect and optional automatic disconnection when an eligible physical external display is active.
- Attempt recovery if the last eligible external screen disappears; manual reconnect and Restore all suspend the automatic rule. Exclude virtual, AirPlay, Sidecar and unclassified outputs from replacement-screen eligibility.
- Preserve built-in identity while disconnected, bound retry attempts, and offer Shift-at-startup suppression. This applies after login while the app runs.
- User confirmed manual built-in disconnection and reconnection on the development Mac. Automatic hotplug recovery, screenless MacBooks and other models still require hardware validation. Intel binaries are not provided.
- Include bilingual first-launch instructions at the top level of the DMG and in the application ZIP.

## 0.3.0-beta.1 — 2026-10-16

- Add optional developer support through Ko-fi and the provided MB Bank QR, with an account-copy button and English/Vietnamese text.

- Add a visible Fix iPad discovery action when no iPad is found: restart only the current user’s sharingd without sudo, with bounded rediscovery and busy/connected-session guards.

- Show connected iPads with controls in External displays; the visible iPad tab handles discovery and connection status. Add live macOS-provided resolution selection, read-back validation and 20-second confirmation/rollback.

- Add iPad discovery and explicit Sidecar connect/disconnect controls in English and Vietnamese. Keep iPad resolution/scaling under macOS control.
- Isolate private Sidecar calls in a timed, unprivileged helper. Keep existing physical/virtual HiDPI mirror relationships when arranging the new iPad.
- Physical iPad connection and resolution testing is pending.

## 0.2.0-beta.2 — 2026-10-13

- Fix the captured status-item flicker: defer global mouse/focus dismissal until button release, cancel it when the forwarded icon action arrives, and ignore late callbacks. Remove unreliable status-item coordinate hit testing. Cover rapid clicks, held buttons and focus event ordering. The user confirmed repeated/held clicks and outside dismissal on the built-in display without tracing.

- Replace legacy privileged execution with an SMAppService daemon, mutually authenticated XPC and per-operation administrator authorization. Ad-hoc/development builds fail closed; a notarized Developer ID build and service lifecycle testing are required to enable this feature for distribution.
- Reject invalid/negative/overflowing DDC display indices, malformed numeric values and incomplete commands. Add sanitizer-backed boundary tests.
- Move optional panel trace to OSLog, removing the fixed shared temporary file. Omit UUIDs from default diagnostics; raw UUIDs require --diagnostics-private.
- Add app version/build and service removal controls, update bilingual installation guidance and include the security policy in release archives.
- Pin CI actions to reviewed commit SHAs and disable persisted checkout credentials.


## 0.2.0-beta.1 — 2026-10-12

First public beta, prepared from the version tested on M4 Pro with two external displays.

- Select a main display from each monitor card or settings, preserving relative positions and updating recovery baselines. Ignore obsolete recovery layouts for active displays on startup; normal quit retains the live native layout.
- Menu-bar controls for individual software disconnect/reconnect and display recovery. An explicit off request no longer automatically reconnects after a confirmation timeout. If macOS reactivates a user-disabled output, the app reapplies that request, with last-display protection and a bounded retry limit.
- Dense HiDPI size slider, custom aspect-preserving widths, refresh selection and native/virtual rendering. Generate reversible model-specific native scaling overrides with a one-shot authorized helper; keep existing settings and refuse foreign modifications. Virtual resizing preserves all display origins and the main display, retains the previous screen until confirmation, verifies 2x dimensions, and restores native mirroring/layout in separate transactions.
- Available resolution selection and optional mirrored virtual HiDPI. Include supported native HiDPI modes that disappear from the public list after switching away; preserve logical/backing dimensions and refresh rate in recovery records.
- Native sun-symbol brightness keys, with configurable display targeting. Ordinary F1/F2 pass through.
- DDC backlight control over tested HDMI and USB-C paths. Correct Get VCP checksum includes the host source address.
- Validate DDC replies and confirm writes by reading back the monitor value; invalid responses do not become 0%.
- Optional additional software dimming, enabled explicitly per session. Startup reads current DDC brightness without writing a saved value or applying a dimming overlay; preserve existing overlay strength during topology refresh.
- Add opt-in `--trace-popover` lifecycle diagnostics for intermittent menu-bar toggling. A physical click check completed six open/close cycles without an immediate reopen; intermittent reports still need observation.
- Rebuild the popover after display topology changes to avoid clipping. Handle status-item toggle and outside dismissal explicitly so a click cannot close and immediately reopen the panel; hiding also cancels a queued topology reopen.
- Reconnect disabled displays using preserved identity, mode and placement data. Resolve recovery identities by enumerating current outputs, avoiding a cold-process SkyLight assertion in the reverse UUID API.
- Vietnamese/English interface with macOS language detection and a persistent manual language picker. Translate brightness status, HiDPI guidance, errors and accessibility labels without altering display settings.
- App icon, MIT license, bilingual documentation, isolated release packaging and CI checks.

Apple Silicon only. Ad-hoc signed, not Apple notarized. Private display APIs and other hardware/macOS combinations remain beta limitations.
