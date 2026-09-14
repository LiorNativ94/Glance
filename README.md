# Glance

A lightweight native macOS menu bar utility for checking your Mac’s resources and keeping it awake when needed.
Built with Swift, AppKit, and SwiftUI, with no third-party package dependencies, accounts, telemetry, or network requests.

## Features

- CPU and memory usage with recent history graphs.
- Battery level and charging status.
- Used and available space for the startup disk and connected local drives.
- Customizable menu bar metrics with persistent selections.
- A compact geometric app icon and matching fallback menu bar glyph.
- Timed keep-awake sessions, with an optional display sleep override.
- Optional launch at login.
- A separately authorized, temporary closed-lid mode.

## Screenshots

The native interface shown with sample readings and generic drive names.

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
- A Swift 6.0 or newer toolchain, available through compatible Xcode or Command Line Tools installations.

Check your installed toolchain with `swift --version`.

## Build and run

From the repository directory:

```sh
./build.sh
open dist/Glance.app
```

The build script compiles the app and its sleep helper, generates the icon, and creates an ad hoc signed application bundle.
No Apple developer certificate is required for the local build.
The generated app is not notarized.

To keep using Glance independently of the source checkout, quit the app and copy `dist/Glance.app` into your Applications folder.
Open the installed copy before enabling launch at login.

You can also open `Package.swift` in Xcode to work on the project.
Use `build.sh` to assemble the complete app bundle, including the helper and icon resources.

## Download and release

Download the DMG from [GitHub Releases](https://github.com/LiorNativ94/Glance/releases), open it, and drag Glance into Applications.
Release builds support both Apple Silicon and Intel Macs running macOS 14 or later.
They use ad hoc signing and are not notarized, so macOS may block the first launch.
If you trust the download, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it.

After committing and pushing the release workflow and your changes, publish a new version by pushing a tag:

```sh
git tag v1.2.3
git push origin v1.2.3
```

Use a new `vMAJOR.MINOR` or `vMAJOR.MINOR.PATCH` tag for each version, such as `v1.0` or `v1.2.3`.
Prerelease suffixes such as `-beta.1` are not supported.
The **Release DMG** GitHub Actions workflow tests the tagged code, builds both architectures, stamps the app version from the tag, verifies the signatures and DMG, and publishes a GitHub Release with the DMG and its SHA-256 checksum.
The version at the bottom of Settings reads that same bundled version automatically.
The rendered Settings version and popover alignment tests require an interactive desktop and run locally rather than in release CI.
No repository secrets are required; the workflow uses GitHub's built-in token with `contents: write` permission.
Repository or organization policy must allow GitHub Actions and that permission.
To build an existing tag manually, open **Actions → Release DMG → Run workflow** on `main` and enter the tag, such as `v1.0`.

To build the same DMG locally with Xcode installed:

```sh
./package-dmg.sh v1.2.3
```

The output is `dist/Glance-1.2.3-universal.dmg` and its `.sha256` checksum file.

## Usage

Click Glance’s menu bar item to open the overview.
Choose **Menu bar…** to select which metrics appear in the menu bar.
Selections persist across launches, including disconnected drives, which reappear when remounted.
If no selected metrics are available, the Glance glyph remains visible.

Enable **Keep awake** for a 30-minute, one-hour, two-hour, or untimed session.
The optional **Keep display on** setting applies only while a session is active.
The menu bar cup indicator is optional and disabled by default.

Open **Settings…** to configure launch at login or quit the app.

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
The AppKit tests open a temporary menu bar item and popover, so run them in a logged-in macOS desktop session.
Power-controller tests briefly exercise normal keep-awake assertions; they do not authorize closed-lid mode.

For a local diagnostic snapshot:

```sh
dist/Glance.app/Contents/MacOS/Glance --diagnostics
```

Diagnostics include drive names, capacities, and volume identifiers.
Review and redact that output, screenshots, and crash reports before attaching them to a public issue.

Before submitting a change, run the tests and build, then exercise the affected controls in the bundled app.
For menu bar changes, verify adding and removing metrics, selecting none, rapid toggling, and reopening the panel.
For sleep changes, verify stopping a session releases assertions with `pmset -g assertions` and test any closed-lid behavior on the target Mac.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Glance` | AppKit menu bar hosting, SwiftUI interface, preferences, and session controls. |
| `Sources/GlanceCore` | System sampling, volume identity, formatting, and sleep-lease policy. |
| `Sources/GlancePowerHelper` | Session-scoped privileged sleep helper. |
| `Resources` | App metadata, icon generation, and third-party notices. |
| `Tests` | Core, session, and popover regression tests. |
| `build.sh` | Release compilation, app assembly, and local code signing. |
| `package-dmg.sh` | Universal app build, version stamping, and DMG packaging. |
| `.github/workflows/release.yml` | Version tag builds and GitHub Release publication. |

## Privacy and repository hygiene

Glance processes system readings locally.
Metric selections and the optional cup indicator are stored in macOS user defaults, outside the repository.
Closed-lid sessions use temporary local heartbeat and status files.
Administrator authorization is handled by macOS; the app does not store an administrator password.

The repository excludes build products, application bundles, local editor state, environment files, signing material, and diagnostic output through `.gitignore`.
Ignoring a file does not remove it from existing Git history.
Review staged changes and commit author metadata before publishing, and use a GitHub no-reply email if you want to keep your personal email private.

## Third-party notices

CPU and memory glyphs are adapted from Lucide icons.
Their ISC license and attribution are included in [Resources/Lucide-LICENSE.txt](Resources/Lucide-LICENSE.txt).
That notice covers the attributed icons; it is not a license for the entire project.
