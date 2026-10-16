# Mac Monitor

A native macOS menu-bar app for software display disconnect/reconnect, brightness and resolution/HiDPI controls. The interface supports English and Vietnamese.

[Tiếng Việt](README.md) · [Downloads](https://github.com/kidside/mac-monitor/releases) · [Installation](docs/INSTALL.md)

## Install

**0.3.0-beta.1** supports **Apple Silicon** builds targeting **macOS 14+**. Physical testing has only covered M4 Pro on macOS 27.0.1; older versions are not yet verified.

Download `MacMonitor-0.3.0-beta.1-arm64.dmg`, open the disk image, move **Mac Monitor.app** into Applications and open it. Use its menu-bar icon. To enable native sun-symbol brightness keys, allow Mac Monitor in **System Settings → Privacy & Security → Accessibility**. Sliders do not need that permission.

This beta is **ad-hoc signed and not Apple notarized**. If macOS blocks it, only proceed if you trust the download, using [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445). Keep the app at a stable path. A new ad-hoc build may require renewed Accessibility permission.

For launch at login, add the installed app to **System Settings → General → Login Items & Extensions → Open at Login**.

## Features

- Per-display software disconnect/reconnect; at least one display stays active.
- Available resolutions, including advertised HiDPI modes.
- Optional mirrored 2× virtual HiDPI display. Choose aspect-correct sizes and supported refresh rates; the app must stay open.
- Validated DDC/CI backlight control with write readback; software dimming when DDC cannot be established.
- Optional additional software dimming for monitors whose minimum backlight is still bright. Software dimming has a visible 5% floor; 100% removes it. Pure hardware control can reach the monitor's minimum at 0%.
- Native brightness keys target the display under the pointer, a selected display, or all displays. Ordinary F1/F2 function keys pass through.
- Startup reads the current DDC backlight without changing it. Software dimming starts off and is enabled explicitly for the current session. Saved configuration recovery. The off switch stays off until you reconnect; only resolution/HiDPI changes have a 20-second confirmation timer.

Software brightness at 100% does not increase physical backlight; use the monitor's buttons if DDC is unavailable. Hardware 0% does not mean disconnect.

The app enumerates displays dynamically, with no fixed two-display limit. Actual display count and usable modes depend on the Mac and connected hardware.

## Tested and limitations

Physical tests: M4 Pro, macOS 27.0.1, **Mi Monitor 27″ over built-in HDMI** and **VU241Q 24″ over USB-C**. Both support DDC in this setup. Advertised HiDPI 1920 × 1080 worked at 100 Hz and 75 Hz respectively.

Other monitors, adapters and macOS releases remain unverified. Full HD, 4K, portrait and ultrawide virtual-display configurations have not been tested. HiDPI is not inherently limited to 2K, but output quality depends on the physical display.

Display disconnect and virtual displays use private macOS APIs, which can change across OS updates. Recovery is attempted on quit or an unexpected stop, but cannot be guaranteed for every setup. This project targets direct distribution rather than the Mac App Store.

## Build

Requires an Apple Silicon Mac and Xcode Command Line Tools (`xcode-select --install` if needed).

```sh
./scripts/build.sh
./scripts/test.sh
open 'build/Mac Monitor.app'
```

The DDC helper is vendored, so there are no additional package downloads. Normal builds prefer an available Apple Development certificate; use `MAC_MONITOR_SIGNING_IDENTITY=-` for ad-hoc signing. Set `MAC_MONITOR_BUILD_DIR=build-preview` for an isolated build while the existing app runs.

```sh
./scripts/package-release.sh
```

This creates separate ad-hoc release artifacts in `dist/`, leaving `build/` unchanged. See [release instructions](docs/RELEASING.md), [contributing](CONTRIBUTING.md) and [changelog](CHANGELOG.md).

## Privacy and license

No accounts, telemetry or network requests. Preferences and recovery records stay local. Brightness-key handling does not record ordinary typing. Default `--diagnostics` omits UUIDs and serial numbers. Review monitor names and OS details before sharing. `--diagnostics-private` includes UUIDs and must stay local.

Source and icon assets are [MIT licensed](LICENSE). The modified m1ddc helper retains its upstream MIT license; see [third-party notices](THIRD_PARTY_NOTICES.md).

## Extended HiDPI

Choose desktop size, refresh rate and native/virtual rendering in each display card. The size slider previews; Apply commits with a 20-second rollback. Custom widths preserve the panel aspect ratio. Native scaling overrides use an SMAppService daemon with mutually authenticated XPC and per-operation administrator authorization, preserve existing overrides and retain exact backups. This requires a Developer ID signed, notarized release and service approval in Login Items & Extensions. Ad-hoc builds reject system configuration installation/removal; existing HiDPI modes and virtual displays remain available. The new service still needs installation/removal testing with a notarized build before this feature can be advertised as ready. They affect all displays with the same vendor/product IDs and can require a reconnect/reboot. Removal refuses to overwrite foreign changes. SIP remains enabled.

Virtual resizing retains the previous surface until confirmation and validates 2x backing dimensions. Mirroring is supported; streaming is not implemented. Custom 1808×1017 and 2048×1152 modes at 75 Hz were physically tested on VU241Q. Newly installed native override modes still need verification after macOS loads them; support is not guaranteed for every monitor or OS. Brightness remains read-only on launch.

## Language

Open the settings button at the top right and choose **Language**: **Automatic (macOS)**, **Tiếng Việt**, or **English**. Automatic follows the first macOS preferred language: Vietnamese for Vietnamese, English otherwise. Your choice is saved and updates the interface immediately without changing display settings.

## Main display

Use **Make main display** on a connected monitor card or **Choose main display** in settings, including an active built-in display. All desktop origins are translated together to preserve relative positions. The app verifies the main display, saves it as the new recovery baseline, and rolls back if verification fails. Startup does not overwrite active desktops with obsolete recovery positions; a normal quit preserves the current native layout.


## Security and uninstall

See [SECURITY.md](SECURITY.md) and [release security checks](docs/SECURITY-CHECKS.md). Optional `--trace-popover` logs panel events through OSLog; it does not write a shared `/tmp` file. It does not record ordinary typing.

In a notarized build, remove installed HiDPI configurations from each display before selecting **Remove administrator service…** in settings, then quit and remove the app. Unregistering the service retains configurations and backups. If an old override exists, keep its backup until a verified restoration is complete. Sliders, available HiDPI, virtual displays and main-display controls do not register or require the daemon.

## iPad connection (Sidecar)

Select the visible **iPad** tab at the top for a separate iPad page; the main page remains focused on external monitors. The **Connect iPad** section lists nearby compatible iPads and existing Sidecar sessions. Select **Connect** or **Disconnect**; use the refresh button to discover devices again. Unlock the iPad and use the same Apple Account on both devices. Wireless Sidecar requires Wi-Fi, Bluetooth and Handoff; USB requires trusting the Mac on the iPad. Apple’s [Sidecar requirements](https://support.apple.com/en-us/102597) still apply.

After connection, the iPad card in External displays reads the live modes provided by macOS and lets you select a resolution with 20-second confirmation/rollback. It does not create extra virtual HiDPI displays or add iPad brightness controls. It does not connect automatically on launch, replace another iPad session, or disconnect Sidecar on quit. Discovery and connections use a separate, unprivileged helper with timeouts; no Accessibility or administrator permission is needed for this feature. Sidecar uses Apple's device communication; the app does not implement its own screen streaming or require an iPad app.

Connecting attempts to preserve existing main-display positions and virtual HiDPI mirrors while placing a newly connected iPad to the right. Screen arrangements remain adjustable in macOS. This uses the private SidecarCore framework and may stop working after OS changes. Physical iPad connection and multi-display coexistence still require testing before this feature is released.

After connecting, the iPad tab shows the device name and a Connected checkmark. The iPad appears alongside other displays in External displays, with disconnect and main-display controls. Resolution selection uses macOS-advertised modes; no extra virtual HiDPI or iPad brightness controls are added.

If no iPad is found, click **Fix iPad discovery** in the iPad tab. This explicitly restarts the current user’s `sharingd` service without sudo, then retries discovery up to three times. AirDrop/Handoff may pause briefly. It never runs automatically on launch or while a Sidecar session is connected.

## Support the developer

Mac Monitor is free with all features included. Optional support is welcome through [Ko-fi](https://ko-fi.com/U8I328WDGQ) or a Vietnamese MB Bank transfer:

- Account holder: **LE CHU AN**
- Account number: **0590190828888**

![MB Bank QR](Assets/Support/MB-Bank-QR.png)

Click **Support** at the bottom of the app panel to open Ko-fi or view the bank QR and copy the account number.
