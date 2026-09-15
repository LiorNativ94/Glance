# Competitor improvement notes

Reviewed 2026-09-14 using official CodexBar and Vorssaint documentation, changelogs, and Glance's current README and relevant source.
This is a source-based product comparison, not a hands-on competitor benchmark.
Ideas below are proposals for Glance, not claims that either competitor implements the proposed wording or exact interaction.

## Existing Glance baseline

Glance already has configurable alerts, independent dashboard ordering and visibility, limiting AI windows and reset countdowns, stale-reading handling, and timed Keep Awake with quick extensions and display controls. ([Glance README](../README.md))
These should be extended rather than proposed as missing features.

## 1. Explain whether AI allowance will last

**Evidence:** CodexBar compares consumption with the elapsed quota window and shows reserve, deficit, and a run-out estimate, withholding estimates early in a window. ([Pace documentation](https://github.com/steipete/CodexBar/blob/main/docs/ui.md#pace-tracking))
Its changelog records historical Codex forecasting in 0.18.0, dated March 15, and subscription utilization charts in 0.19.0, dated March 23. ([Release history](https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md))

**Glance proposal:** Add one sentence beneath the existing remaining allowance: “On track until reset” or “At this pace, allowance may run out before Friday.”
Show the actual reset beside the estimate, clearly identify the estimate, and withhold it when timing or samples are insufficient.
Add an optional seven-day allowance chart with reset markers, then extend existing alerts to warn about a likely early exhaustion episode.
Start with quota snapshots; token-log scans and dollar-cost reporting would widen the feature substantially.
Saving history would change Glance's current promise that usage readings are not stored on disk, so make retention explicit and provide a clear-history control. ([Current data policy](../README.md#privacy-and-repository-hygiene))

## 2. Make connection state understandable

**Evidence:** CodexBar documents provider incident summaries, freshness, and status-page links, with an optional status-check setting. ([Status documentation](https://github.com/steipete/CodexBar/blob/main/docs/status.md))

**Glance proposal:** Distinguish “Provider incident,” “Sign-in expired,” “Offline,” and “Updated 4 minutes ago” in AI details, with the appropriate next action.
Replace the unconditional green “Live” header with a label whose meaning is scoped to the actual data freshness. ([Dashboard](../Sources/Glance/Dashboard.swift))
Use “remaining” consistently between the overview and expanded quota meters, or provide one shared used/remaining preference; expanded cards currently say “used.” ([Subscription cards](../Sources/Glance/SubscriptionCards.swift))
An incident should explain a failure only when relevant provider status evidence exists; it should not imply that credentials or quota readings are healthy.

## 3. Make hidden features quieter

**Evidence:** CodexBar's Adaptive mode varies refresh between two and thirty minutes using recent menu interaction, Low Power Mode, and thermal conditions; separate agent-aware detection is consent-gated. ([Refresh policy](https://github.com/steipete/CodexBar/blob/main/docs/refresh-loop.md))
The changelog records the initial Adaptive feature under 0.38.1, dated July 4. ([Release history](https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md))
Vorssaint describes stopping unloaded features while preserving preferences and showing the background work each feature requires. ([Modularity](https://github.com/vorssaint/vorssaint-utils#install-only-what-you-use))

**Glance proposal:** Collect each metric only when an icon, visible dashboard section, enabled alert, or active sleep session needs it; slow less urgent work while the panel is closed.
The current system read collects CPU, memory, and battery together, and subscriptions use a fixed five-minute timer. ([System reader](../Sources/GlanceCore/SystemReader.swift), [Subscription store](../Sources/Glance/SubscriptionStore.swift))
Preserve sufficient sampling for alerts and active Keep Awake safeguards, and refresh when opening the dashboard or passing a known reset.
Measure CPU and wakeups before claiming battery savings.

## 4. Add meaning to system readings

**Evidence:** Vorssaint's system-monitor reference includes swap, memory views, energy-consuming apps, a process-inspector shortcut, and battery health, cycles, remaining time, and power. ([System features](https://github.com/vorssaint/vorssaint-utils#know-what-your-mac-is-doing))

**Glance proposal:** Give the existing memory percentage an understandable pressure status and an “Open Activity Monitor” action.
Add battery health and estimated time in expanded details when reliable readings are available.
Prioritize these explanations over more permanently visible numbers.
Glance's current battery model reads charge fraction, charging state, and AC connection. ([System reader](../Sources/GlanceCore/SystemReader.swift))

## 5. Make Keep Awake follow explicit work conditions

**Evidence:** Vorssaint's stable 3.3.5 notes, dated September 6, include selected-app activation and pausing while locked. ([Stable release notes](https://github.com/vorssaint/vorssaint-utils/blob/main/CHANGELOG.md#335---2026-09-06))

**Glance proposal:** Offer an optional “While these apps are open” rule and “Pause when locked,” with a visible explanation such as “Awake because Xcode is open.”
Provide a maximum duration and retain the existing battery cutoff and Stop action.
App presence does not prove useful work is running, so present this as an explicit user-selected condition rather than inferred task activity.
Do not automatically enable the separately authorized closed-lid override.

## 6. Give new users a useful starting layout

**Evidence:** Vorssaint documents first-run bundles, individual feature selection, and requesting only permissions needed by the chosen features. ([First setup](https://github.com/vorssaint/vorssaint-utils#install-only-what-you-use))

**Glance proposal:** Offer three previewable starting layouts: AI work, Mac health, and Minimal.
Reuse the existing icon and dashboard settings, including a clear explanation that connecting an AI account and displaying its icon are separate choices. ([Current setup](../README.md#quick-start))
Make a combined connection-and-preview step so users can see the result before leaving setup.

## Release-status caveats

CodexBar's inspected changelog identifies 0.60.2 as September 14 and 0.60.3 as Unreleased; current main documentation can still contain changes beyond installed releases. ([Changelog](https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md))
Vorssaint lists Dynamic Island in Unreleased, so its current notch documentation is design inspiration rather than proof of a stable released feature. ([Unreleased notes](https://github.com/vorssaint/vorssaint-utils/blob/main/CHANGELOG.md#unreleased))
Vorssaint's modular onboarding and system-monitor details above are current README claims; their exact introduction release was not independently checked.
No measured battery-life, reliability, or performance advantage is claimed for either competitor.
