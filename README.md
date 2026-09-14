# Glance

Your Mac’s resources and AI subscription limits, in the menu bar or beside the notch.
Glance is a lightweight native macOS utility with a compact dashboard, customizable icons, and optional keep-awake sessions.
Built with Swift, AppKit, and SwiftUI, with no third-party package dependencies or telemetry.
System readings stay local; optional Claude and Codex subscription connections fetch usage directly from their providers.

**[Download Glance v1.1 for macOS](https://github.com/LiorNativ94/Glance/releases/download/v1.1/Glance-1.1-universal.dmg)** · [All releases](https://github.com/LiorNativ94/Glance/releases)

## Features

- **Menu bar or notch:** switch locations directly from the dropdown; only your chosen location is shown.
- **Compact notch:** selected icons sit beside the camera, within the menu-bar row, without covering browser tabs.
  Its width adjusts to your selection, and the Glance logo appears only when no selected metrics are available.
- **Shared icon selection:** choose CPU, memory, battery, drives, and subscription limits in **Icons…**.
  The same selection applies to both display modes and persists across launches.
- **Claude and Codex usage:** reuse existing CLI sign-ins to see reported plan names, usage windows, and reset countdowns, with Claude and ChatGPT logos.
- **System monitoring:** CPU and memory history graphs, battery status, and used/free space for local drives.
- **Keep awake:** timed or untimed sessions, an optional display sleep override, and separately authorized temporary closed-lid mode.
- **Launch at login:** optional, with no Dock icon.

## Screenshots

These screenshots show the original v1.0 interface with sample readings and generic drive names.
Version 1.1 adds the **Show in** picker, **Icons…** controls, and **AI subscriptions** described below.

<table>
  <tr>
    <th>Overview</th>
    <th>Customize menu bar</th>
    <th>Keep awake</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/overview.png" width="280" alt="Glance overview showing CPU and memory graphs, storage usage, and battery level"></td>
    <td valign="top"><img src="docs/screenshots/customize.png" width="280" alt="Menu bar customization with selectable metrics and a live preview"></td>
    <td valign="top"><img src="docs/screenshots/keep-awake.png" width="280" alt="An active one-hour keep-awake session with duration and display controls"></td>
  </tr>
</table>

## Requirements

- macOS 14 Sonoma or later.
- An Apple Silicon or Intel Mac; the same DMG supports both.

## Install

1. Download the [v1.1 DMG](https://github.com/LiorNativ94/Glance/releases/download/v1.1/Glance-1.1-universal.dmg).
2. Open the DMG and drag Glance into Applications, quitting any existing copy first.
3. Open Glance from Applications.
   New installs start in the menu bar; existing installs restore the saved Menu bar or Notch choice.

No Xcode or Swift installation is needed to use the downloaded app.
The version at the bottom of **Settings…** matches the shipped app version: `1.1` for this release.
Open the installed copy before enabling launch at login.

Release builds use ad hoc signing and are not notarized, so macOS may block the first launch.
If you trust the download, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it.
Each [GitHub Release](https://github.com/LiorNativ94/Glance/releases) includes a SHA-256 checksum alongside the DMG.

## Usage

### Quick start

1. Click Glance in the menu bar or beside the camera to open the dashboard.
2. Use **Show in → Menu bar / Notch** at the top to choose where Glance appears.
3. Open **Icons…** and select the metrics you want in that location.
4. To add subscription limits, connect a provider in **AI subscriptions**, then select **Claude remaining** or **Codex remaining** in **Icons…**.

Connecting a provider and displaying its icon are separate choices.
Connected providers remain available in the dashboard even when their icons are unchecked.
Selections persist across launches, including disconnected drives, which reappear when remounted.
If no selected metrics are available, a small Glance button keeps the dashboard accessible.

Enable **Keep awake** for a 30-minute, one-hour, two-hour, or untimed session.
The optional **Keep display on** setting applies only while a session is active.
The menu bar cup indicator is optional and disabled by default; it is configured with **Show keep-awake icon** in **Icons…**.

Open **Settings…** to configure launch at login or quit the app.

### Notch

Choose **Show in → Notch** at the top of the dropdown.
Compact wings beside the camera show only the available metrics selected in **Icons…**, in the same order as the menu bar.
Connecting a subscription makes it available to select; it does not automatically add its icon.
The wings shrink to fit the selected metrics, with no extra Glance logo unless no selected metrics are available.
Percentage cells keep a stable width as readings change, so the notch resizes when you change icons rather than on every update.
The collapsed view stays entirely within the menu-bar row, leaving browser tabs and application content clear.
Click it to open the dashboard; click its header, press Escape, or click outside to collapse it.
Notch mode hides Glance’s menu bar item; choosing **Show in → Menu bar** restores it and hides the notch view.
The same picker appears in both dropdowns, and switching moves the open dashboard to the selected location.
Glance uses a notched display when connected, otherwise the center of the main display’s menu-bar row.
The panel follows display changes and is available across Spaces.

### Claude and Codex subscriptions

Open **AI subscriptions** from the dashboard, or **Settings… → Claude & Codex subscriptions…**.
Enable either provider to reuse its existing local sign-in.
The cards show reported plan names, session and weekly usage, and reset countdowns when those values are available.
The meters show **percent used**; the selected menu bar and notch icons show **percent remaining** for the most constrained reported limit.
Claude also shows Sonnet and Opus weekly windows when returned by the provider.
In **Icons…**, select **Claude remaining** or **Codex remaining** to add that provider to the menu bar or notch.
For example, a provider with 70% session usage and 40% weekly usage displays **30% remaining**.

- **Codex:** sign in with `codex login` using your ChatGPT subscription.
  Glance reads `~/.codex/auth.json`, or `$CODEX_HOME/auth.json` when that environment variable is set for Glance.
  API-key-only and Keychain-only Codex sign-ins are not supported by this connection.
- **Claude:** sign in with Claude Code.
  Glance reads `~/.claude/.credentials.json` or the `Claude Code-credentials` Keychain item.
  A custom `$CLAUDE_CONFIG_DIR` uses only that directory’s credentials file.
  The sign-in needs the `user:profile` scope; MCP-only credentials cannot supply subscription usage.
  macOS may request Keychain access when connecting or clicking **Refresh**.

Usage refreshes every five minutes and after wake; **Refresh** requests an update immediately unless the provider has imposed a cooldown.
Unavailable data displays a message instead of a zero-percent reading.
Expired reset times are marked as due until a fresh reading arrives.
If a sign-in expires, renew it in its owning CLI and click **Refresh**.
Glance never modifies or refreshes the source credentials and never runs a coding session to collect usage.
These provider endpoints are undocumented and can change.
This integration follows [CodexBar’s Codex](https://github.com/steipete/CodexBar/blob/main/docs/codex.md) and [Claude](https://github.com/steipete/CodexBar/blob/main/docs/claude.md) OAuth approach; it does not require CodexBar, import browser cookies, or provide billing history.

### Troubleshooting

| What you see | What to do |
| --- | --- |
| A connected provider is missing from the notch or menu bar | Select **Claude remaining** or **Codex remaining** in **Icons…**. |
| An unwanted provider icon is visible | Uncheck it in **Icons…**; you can keep the provider connected for its dashboard card. |
| The menu bar item disappeared | Notch mode hides it; open the notch dropdown and choose **Show in → Menu bar** to restore it. |
| A subscription shows `—` or asks you to sign in | Check its card in **AI subscriptions**, renew the CLI sign-in if requested, then click **Refresh**. |
| Refresh is waiting after too many requests | Allow the provider’s cooldown to expire; repeated clicks do not bypass it. |

## How readings work

CPU usage is calculated from the difference between successive host CPU counters across all cores.
Memory usage includes non-purgeable internal pages, wired pages, and compressed physical pages, excluding reclaimable file caches.
Memory is displayed in binary gigabytes; storage uses decimal units.

Storage covers the startup disk and visible local volumes mounted under `/Volumes`.
Read-only mounts, such as installer disk images left mounted, are excluded because their usage cannot change.
Used space is calculated as total capacity minus available capacity.
APFS shares free space between volumes, so readings may differ from Finder’s estimates of reclaimable space.

CPU, memory, and battery refresh every two seconds.
Storage refreshes every fifteen seconds and when volumes mount or unmount.
Graphs retain up to sixty seconds of readings in memory.

## Keep-awake behavior

Normal keep-awake uses IOKit power assertions and does not change persistent system settings.
Sessions end when their timer expires, the app quits, or the battery reaches ten percent while unplugged.
Sessions do not resume automatically after relaunching the app.

### Closed-lid mode

Closed-lid mode requires macOS administrator authorization for each session.
The bundled helper temporarily runs `pmset -a disablesleep 1`.
This is a system-wide override that also prevents manual Sleep from the Apple menu while active.
Actual lid-close behavior depends on the Mac and its power/display configuration and should be verified on the target hardware.

The helper refuses to take over if another tool has already disabled sleep.
It checks a one-second heartbeat and restores sleep when the session ends, the app exits, the heartbeat expires, or an unplugged battery reaches ten percent.
It installs no daemon or passwordless sudo rule.
After a frozen app, restoration can take up to fifteen seconds plus the next helper check.

Force-killing the privileged helper with `SIGKILL` bypasses its cleanup.
If sleep remains disabled after a failed session, restore it with:

```sh
sudo pmset -a disablesleep 0
```

## Development and verification

```sh
swift test
./build.sh
codesign --verify --deep --strict dist/Glance.app
```

Tests cover reading calculations, metric selections, sleep-session policy, the rendered Settings version, and visible popover positioning during menu bar customization.
Subscription tests cover provider response formats, account-scoped requests, missing and expired credentials, cooldowns, and disconnecting during a refresh.
Native notch tests verify camera clearance, selection-based sizing, exclusive display modes, expansion, dismissal, and synthetic subscription readings.
The AppKit tests open a temporary menu bar item and popover, so run them in a logged-in macOS desktop session.
Power-controller tests briefly exercise normal keep-awake assertions; they do not authorize closed-lid mode.

For a local diagnostic snapshot:

```sh
dist/Glance.app/Contents/MacOS/Glance --diagnostics
```

Diagnostics include drive names, capacities, and volume identifiers.
Review and redact that output, screenshots, and crash reports before attaching them to a public issue.

Before submitting a change, run the tests and build, then exercise the affected controls in the bundled app.
For display changes, verify adding and removing metrics, selecting none, rapid toggling, switching between Menu bar and Notch, and reopening the panel.
Check that a connected but unselected subscription stays out of both icon views.
For sleep changes, verify stopping a session releases assertions with `pmset -g assertions` and test any closed-lid behavior on the target Mac.

## Build and run

Building from source requires a Swift 6.0 or newer toolchain, available through compatible Xcode or Command Line Tools installations.
Check your installed toolchain with `swift --version`.

From the repository directory:

```sh
./build.sh
open dist/Glance.app
```

The build script compiles the app and its sleep helper, bundles the provider logos, generates the app icon, and creates an ad hoc signed application bundle.
No Apple developer certificate is required for the local build.
The generated app is not notarized.

To keep using Glance independently of the source checkout, quit the app and copy `dist/Glance.app` into your Applications folder.
Open the installed copy before enabling launch at login.

You can also open `Package.swift` in Xcode to work on the project.
Use `build.sh` to assemble the complete app bundle, including the helper and icon resources.

## Publishing releases

After committing and pushing your changes, publish a new version by pushing a new tag:

```sh
git tag v1.1.1
git push origin v1.1.1
```

Use a new `vMAJOR.MINOR` or `vMAJOR.MINOR.PATCH` tag for each version, such as `v1.1.1` or `v1.2`.
Prerelease suffixes such as `-beta.1` are not supported.
The **Release DMG** GitHub Actions workflow tests the tagged code, builds both architectures, stamps the app version from the tag, verifies the signatures and DMG, and publishes a GitHub Release with the DMG and its SHA-256 checksum.
The version at the bottom of Settings reads that same bundled version automatically.
The rendered Settings version and popover alignment tests require an interactive desktop and run locally rather than in release CI.
No repository secrets are required; the workflow uses GitHub's built-in token with `contents: write` permission.
Repository or organization policy must allow GitHub Actions and that permission.
To build an existing tag manually, open **Actions → Release DMG → Run workflow** on `main` and enter the tag, such as `v1.1`.

To build the same DMG locally with Xcode installed:

```sh
./package-dmg.sh v1.1
```

The output is `dist/Glance-1.1-universal.dmg` and its `.sha256` checksum file.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Glance` | Menu bar and notch hosting, SwiftUI interface, preferences, subscription connections, and session controls. |
| `Sources/Glance/Resources` | Claude and ChatGPT vector logos and their attribution. |
| `Sources/GlanceCore` | System sampling, volume identity, usage parsing, formatting, and sleep-lease policy. |
| `Sources/GlancePowerHelper` | Session-scoped privileged sleep helper. |
| `Resources` | App metadata, icon generation, and third-party notices. |
| `Tests` | Core, subscription, power, display-mode, and native layout regression tests. |
| `build.sh` | Release compilation, app assembly, and local code signing. |
| `package-dmg.sh` | Universal app build, version stamping, and DMG packaging. |
| `.github/workflows/release.yml` | Version tag builds and GitHub Release publication. |

## Privacy and repository hygiene

Glance processes system readings locally.
Metric selections and the optional cup indicator are stored in macOS user defaults, outside the repository.
Notch visibility and enabled subscription providers are also stored in user defaults.
Subscription connections are off by default and read local credentials only for enabled providers.
Access tokens are sent only to the corresponding provider’s fixed HTTPS usage endpoint; redirects are refused.
Glance stores no copies of credentials or usage readings on disk, and background Keychain reads never prompt.
Closed-lid sessions use temporary local heartbeat and status files.
Administrator authorization is handled by macOS; the app does not store an administrator password.

The repository excludes build products, application bundles, local editor state, environment files, signing material, and diagnostic output through `.gitignore`.
Ignoring a file does not remove it from existing Git history.
Review staged changes and commit author metadata before publishing, and use a GitHub no-reply email if you want to keep your personal email private.

## Third-party notices

CPU and memory glyphs are adapted from Lucide icons.
Their ISC license and attribution are included in [Resources/Lucide-LICENSE.txt](Resources/Lucide-LICENSE.txt).
Claude and ChatGPT logo assets are sourced from CodexBar and retain their [MIT notice](Sources/Glance/Resources/CodexBar-LICENSE.txt).
The logos identify their respective providers and remain their owners’ trademarks.
These notices cover the attributed assets; they do not license the entire project.
