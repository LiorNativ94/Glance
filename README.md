# Glance

A native macOS menu bar monitor with CPU, memory, battery, connected storage and temporary keep-awake sessions.
Requires macOS 14 or later and Xcode command-line tools to build.
No dependencies, accounts, network requests or telemetry.

## Build and run

```sh
./build.sh
open dist/Glance.app
```

For reliable operation when the drive is disconnected, copy `dist/Glance.app` to your Mac’s Applications folder.
Open `Package.swift` in Xcode to edit the project, or run `swift test` for focused core tests.

## Menu bar

Click the menu bar item to open Overview, then choose Customize menu bar.
Only selected metric icons and percentages appear; no redundant app logo is added.
If no selected metrics are currently available, Glance shows one activity icon.
Selections persist, including disconnected drives, which reappear when remounted.
The keep-awake cup is optional and off by default.

## Readings

CPU uses the difference between successive host CPU counters across all cores.
Memory combines non-purgeable internal pages, wired pages and compressed physical pages, excluding reclaimable file caches.
The memory display uses binary gigabytes to match installed RAM; storage uses decimal units.
Storage shows mounted user volumes, including the startup disk and volumes under `/Volumes`, with used space derived from total minus available capacity.
On APFS, free space is shared with other volumes and may differ from Finder’s reclaimable-space estimate.
Samples refresh every two seconds; storage refreshes every fifteen seconds and on mount/unmount notifications.
Graphs show up to sixty seconds of history kept only in memory.

## Keep awake

Normal keep-awake uses IOKit power assertions and does not alter system settings.
The optional display assertion keeps the screen on only during an active session.
Sessions are not resumed automatically after restarting the app.
Both stop automatically at ten percent battery when unplugged.

Closed-lid mode is a separate, explicitly authorized session.
It launches the bundled helper through macOS administrator authorization and temporarily uses `pmset -a disablesleep 1`.
This system-wide override also prevents manual Sleep from the Apple menu while active.
The helper refuses to take over if another tool already disabled sleep, checks a one-second heartbeat, and restores sleep when the session ends, the client exits, the heartbeat expires, or battery reaches ten percent.
It installs no daemon or passwordless sudo rules and rechecks the flag across power-source transitions.
The temporary worker may remain for up to fifteen seconds after a frozen client.
Force-killing the root helper itself with SIGKILL bypasses all process cleanup; recovery is `sudo pmset -a disablesleep 0`.
Hardware lid-close behavior must be checked on the actual Mac and power/display configuration.

## Structure

- `GlanceCore`: system sampling, stable volume identity, formatting and lease policy.
- `Glance`: native AppKit menu bar hosting a SwiftUI panel, persisted selections and session controls.
- `GlancePowerHelper`: narrowly scoped privileged sleep-session worker.
- `Tests`: sampling math, disconnected selections, missing readings and sleep-lease termination cases.

## Verification

```sh
swift test
dist/Glance.app/Contents/MacOS/Glance --diagnostics
codesign --verify --deep --strict dist/Glance.app
```

Manual acceptance: customize metrics, select none, reopen the app, verify connected drives, toggle keep-awake and display sleep, and confirm `pmset -g assertions` returns to normal after stopping or quitting.
For closed-lid acceptance, start a short background task, authorize a session, close the lid, and confirm uninterrupted timestamps after reopening; repeat across power changes and check that stopping restores sleep.
