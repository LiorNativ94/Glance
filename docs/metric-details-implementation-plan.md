# Glance metric detail dashboards: implementation plan

Status: implemented in the working tree, 2026-09-15.
The sections below preserve the approved design contract.
Implementation and verification notes are recorded at the end.

## Outcome

Build dedicated Claude, Codex, CPU, and Memory dashboards matching the approved [subscription concept](mockups/subscription-details-v2.png) and [system concept](mockups/cpu-memory-details.png).
The same dashboard opens from its overview row, subscription row, menu-bar icon, or notch icon.
Every dashboard has an always-visible **‹ Back to Glance** button that returns directly to the normal overview in one click.

Use CodexBar's provider parsing, history, local-log processing, and regression cases as implementation references.
Keep Glance's native dashboard, display modes, settings, and existing provider connections.
The [implementation reference](codexbar-implementation-reference.md) records the inspected upstream code and adaptation decisions.
The source review is pinned to [CodexBar commit 62e71bb](https://github.com/steipete/CodexBar/tree/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7).

## 1. Product and navigation contract

### Return to the regular dashboard

- Put **‹ Back to Glance** at the leading edge of every detail header, with a visible label rather than an unexplained arrow.
- Keep that header outside the scrolling content in both menu-bar and notch mode.
- The button always opens Glance's main overview, including when details were opened from the provider list, an alert, or another metric.
- Preserve the user's dashboard section order and hidden-section preferences.
- Summary, Activity, History, model-limit detail, and process lists must all retain the same direct route home.
- Move keyboard focus to the overview heading after returning, and expose an accessibility identifier for this action.
- Provider connection management remains reachable from the overview's AI subscriptions heading and Settings.

This intentionally replaces the earlier proposal's origin-dependent back destination.
Returning to the provider list must never be a required intermediate step on the way home.

### Click routing

| User action | Result |
| --- | --- |
| Click Claude or Codex overview/subscription row | Open that provider's Summary |
| Click CPU or Memory overview row | Open that metric's process dashboard |
| Click the selected metric's icon or percentage | Open the same detail dashboard |
| Click another metric while details are open | Switch within the existing dropdown |
| Click the currently open metric's icon again | Close the dropdown |
| Click Back to Glance | Show the normal overview without closing the dropdown |
| Click a metric icon while overview is open | Open its details |
| Press Escape or click outside | Close the dropdown |
| Reopen Glance itself or click its fallback logo | Open the normal overview |
| Switch Menu bar / Notch while open | Preserve the destination and selected detail tab |

CPU, Memory, Claude, and Codex are the detail destinations in this feature.
Existing storage, battery, and keep-awake icons continue to open the overview; adding new detail features for them is outside this plan.
Selected icons remain usable when their overview section is hidden.
Connected AI accounts remain accessible through the provider list when their icons are not selected.
Keep provider connection toggles separate from the row action so opening details never changes sign-in settings.

### Panel layout

Use one detail shell with a pinned header, optional provider tabs, and one scrolling content region.
Use 360-point outer width for new detail pages and keep the existing 320-point overview width.
Have both presentation controllers consume the same route-dependent preferred size, rather than keeping independent hard-coded widths.
Keep the dropdown anchored to the strip's center while switching metrics; clamp its height to the available screen area, with 600 points as the existing maximum baseline.
Keep the camera area clear and the compact icon widths stable.
Use independent native controls for each icon plus percentage, including keyboard and accessibility support.
Test pointer events against the existing outside-click handlers so switching menu-bar icons does not first dismiss the dropdown and lose the intended selection.

## 2. Approved dashboard contents

### Claude and Codex: Summary

1. Provider, reported plan, last successful update, Refresh, and Back to Glance.
2. Compact five-hour/session and weekly allowance rows with remaining percentages and reset information.
3. A Model & feature limits disclosure showing applicable additional provider windows.
4. Today and Yesterday cards showing the observed increase in weekly usage, measured in percentage points.
5. Daily observed-consumption bars for the current quota period.
6. The previous completed quota period's last observed utilization, with coverage and capture time available.
7. Claude and Codex local activity by model; Codex also groups by session and project.
8. Codex available reset count and expiry when supplied, with no redemption action in this feature.
9. All activity and Open usage page actions.

Keep prices, API-equivalent costs, and spend estimates out of these subscription dashboards.
Retain provider names for models and extra windows; do not hard-code the mockup's example plan, model, or feature names.
Keep ordinary account-wide allowance separate from model- and feature-specific constraints.
An exhausted Routines or model-specific allowance must not become a claim that all Claude usage is exhausted.
Explicitly classify which windows constrain the icon's general allowance; update its explanatory text and existing alert tests consistently.

### Activity

- Claude: local recorded tokens by day and model, with Today / 7 days / 30 days selectors.
- Codex: local recorded tokens grouped by model, session, or project.
- Codex local sessions may be ranked by recorded token volume; use a session identifier when a trustworthy human-readable name is unavailable.
- Label local views **On this Mac** and distinguish the selected reporting interval from lifetime session totals.
- Define displayed token totals without counting cached input or reasoning output twice when they are already included in broader categories.
- Label dashboard credits as reported usage units; they are neither dollar charges nor a percentage of the weekly quota.
- Do not promise a Claude conversation ranking, personal Enterprise analytics, or exact per-task quota allocation from the current sources.

### History

Show the current and previous observed quota periods and a daily view within a selected period.
Keep each account, workspace, plan epoch, and quota window isolated.
Missing coverage must remain visible as a gap, not a zero-height usage bar.
The History tab provides Enable history / Clear history controls and the start of available coverage.
The Summary chart opens the corresponding History period.
All activity opens the Activity tab, and model-limit disclosure remains inside the same detail shell.

### CPU and Memory

| CPU | Memory |
| --- | --- |
| Total CPU and existing recent graph | Used/total RAM and existing recent graph |
| Top five processes sorted by recent CPU use | Top five processes sorted by memory use |
| Name, CPU %, memory | Name, memory, CPU % |
| Show 10 and Open Activity Monitor | Pressure, swap, compressed memory, Show 10, Open Activity Monitor |

Retain actual process rows in the first implementation; app/helper grouping is deferred.
Use stable process identity and include PID in secondary detail when names collide.
Explain that per-process 100% means one logical core, while total CPU remains normalized across the machine.
Memory pressure must have normal/warning/critical/unknown states, rather than treating high RAM usage as pressure.
Before the first usable CPU interval or pressure observation, show a measuring/unavailable state instead of an invented value.

## 3. How to build on CodexBar

Study and selectively adapt the upstream components that solve the same problem.
Do not introduce CodexBar's entire application/provider system as a dependency.
For copied or closely adapted code, record its upstream commit, path, adaptation purpose, and associated regression cases in the repository.
Preserve the upstream MIT notice in source distributions and the packaged app; Glance already includes [CodexBar-LICENSE.txt](../Sources/Glance/Resources/CodexBar-LICENSE.txt).
Verify the notice and provenance for each copied component, including any separately licensed dependency.

| Area | Upstream behavior to reuse | Glance adaptation |
| --- | --- | --- |
| Provider responses | Additional window decoding, duration/reset interpretation, optional values, reset inventory | Extend the existing parser and models |
| History | Account isolation, window boundaries, last-observed values, coverage | Add a small local quota-history store and daily calculations |
| Local activity | Incremental reads, event deduplication, token normalization, bounded caches | Token-only reports without the cost UI |
| UI | Shared data feeding overview and provider details; refresh-safe rendering | Reuse a single Glance detail view across menu bar and notch |
| Tests | Real response edge cases, malformed data, history boundaries, duplicate log events | Sanitized fixtures and focused Glance tests |

Resolve and record a fixed upstream revision before importing implementation code.
Use the pinned revision above as the initial baseline; update it deliberately if later upstream fixes are adopted.
Earlier exploratory research linked current main; preserve immutable source references for the actual adapted implementation.
CodexBar's maturity makes its edge cases and tests valuable, but does not prove any optional field is available on the user's account.

## 4. Data architecture and correctness

### Shared navigation and presentation

Extend `AppModel.Page` with typed CPU, Memory, and provider detail destinations and a small provider-tab state.
Centralize open-metric and return-home actions in `AppModel` so AppKit and SwiftUI use the same routing rules.
Keep the existing popover/notch hosting views alive while changing page content.
Separate panel visibility from destination state so returning home, closing, or changing display mode reliably stops detail-only work.
Route AI alerts to the appropriate provider when their payload identifies it, and memory alerts to Memory details.

### Subscription readings

Extend `SubscriptionUsage` with stable window identity, duration, applicability, and source/account metadata.
Obtain a stable provider account/workspace identifier before storing persistent quota history; never use a rotating access token as the identity key.
Unknown identity may show live data but must not inherit another account's history.
Use separate snapshots and freshness/error states for live quota, reset inventory, and local activity.
A failed optional reset inventory request must not discard a successful OAuth allowance reading.
Clear or replace in-flight results when account selection changes or a provider disconnects.

Preserve Glance's existing credential policy: reuse the owning CLI's sign-in, never rewrite or refresh its source credential file, and never launch an agent session merely to collect usage.
Keep background Keychain reads noninteractive.
Reuse the current provider cooldown and single-flight request behavior.
Keep the five-minute quota polling baseline, refresh after wake, and request a refresh on detail open when stale and permitted.

### Quota history

Use a small versioned, atomic local store under Glance's Application Support directory, with serialized access.
Proposed default: history off until enabled, then retain ninety days with Clear history and Disable history controls.
This changes the current promise that usage readings are never stored, so update the UI explanation and README privacy section in the same milestone.
Store only usage snapshots and identity/cycle metadata, not credentials or conversation text.
CodexBar's inspected history coalesces hourly peak utilization while preserving reset segments.
Reuse its account/cycle isolation and reset-tolerance lessons, but retain finer baseline/latest readings for Glance's daily-delta cards rather than treating hourly peaks as exact daily totals.

Each snapshot records captured time, provider, stable account/workspace identity, plan epoch, window ID, known window duration/reset, used percentage, and source.
Use the provider's window identity and reset semantics to segment cycles; handle minor reset corrections without fabricating a new cycle for every timestamp change.
Never derive a negative consumption value from a reset, plan change, provider correction, or account switch.
Calculate daily increases only between compatible readings with adequate coverage, and use local calendar boundaries rather than fixed 24-hour arithmetic.
Do not interpolate an entire overnight gap as known usage or assign an interval crossing midnight wholly to one day.
Label partial observations as partial; retain raw readings for audit and future calculation changes.

The mockup's “78% used · 22% unused” is not necessarily an exact end-of-week fact.
Unless the provider supplies a final total, use **Last observed: 78% used** with the capture time and coverage, and describe the remaining portion as observed remaining allowance.
After enabling history, show a genuine first-run state; do not synthesize past days or completed weeks from the current reading.

### Local activity

Add explicit Enable local activity controls and use the provider's configured local directory.
Read only the metadata and usage fields needed for counts, models, dates, and supported session/project identifiers.
Do not copy transcript bodies, prompts, tool outputs, or source code into Glance's cache.
Use incremental parsing, stable deduplication, file-change detection, cancellation, and bounded retention, adapting verified CodexBar behavior and tests.
Start with the last thirty days; retain enough file cursor metadata to avoid full rescans on each refresh.
Show scan progress, incomplete coverage, last update, and unsupported records clearly.
Do not associate local activity with a specific subscription identity unless the records establish that association; local data can span different sign-ins.
Refreshing an open local-activity view can trigger a throttled incremental scan, at most once per minute; keep it independent of quota polling.

### Existing connections only

Use the existing provider sign-in for quota, supported model/feature limits, resets, and read-only reset inventory.
Local activity and quota history require no additional account connection.
Do not add a website sign-in, embedded browser, cookie importer, or website-only analytics.
This supersedes the earlier optional web-enrichment proposal at the user's request.

### Process sampling

Add a native macOS process reader using CPU-time differences and a consistent documented memory measure.
Validate physical-footprint availability for other processes before choosing the final memory column; use a clearly labelled consistent fallback if necessary.
Handle processes exiting between reads, reused PIDs, inaccessible measurements, and counter resets.
Run sampling on the existing utility queue or a dedicated serialized worker, never on the UI thread.
Sample roughly every two seconds only while CPU or Memory details are visible; both use the same process snapshot.
Cancel or pause this work on close, Back to Glance, or navigation to another feature.
Cap displayed rows, reuse app icons, and avoid launching a shell process for every refresh.

The current memory-pressure listener runs only when alerts are enabled and collapses warning/critical into a Boolean.
Extend it so Memory details can request pressure monitoring independently of alerts, without enabling notifications.
Initialize pressure from a validated current observation where available; until then display Unknown rather than defaulting to Normal.

## 5. Work sequence and verification

| Milestone | Deliverable | Exit check |
| --- | --- | --- |
| 1. Establish the baseline | Current app UI capture; fixed CodexBar source revision and adaptation inventory; sanitized provider fixtures | Existing tests/build pass; optional data boundaries documented |
| 2. Navigation and detail shell | Individual icon controls, four destinations, tabs, pinned Back to Glance | Every entry point opens the right panel and returns home in one click in both display modes |
| 3. CPU and Memory | Live sorted process lists, pressure/swap/compression, bounded sampling | Controlled CPU and memory workloads rise in rankings; sampling stops when closed |
| 4. Subscription limits and history | Rich window decoding, reset inventory, account-safe history and observed daily charts | Fixture tests cover resets, identity changes, incomplete days, and first-run/clear states |
| 5. Activity sources | Claude daily/model activity, Codex local model/session/project activity | Dedupe and token totals verified; failures isolated |
| 6. Visual and release verification | Approved layouts rendered with real and deterministic sample data; docs updated | E2E navigation, accessibility, sizing, performance checks, tests, and universal build pass |

All approved sections are part of the complete feature; this sequence is not a declaration that the work is finished after basic quota bars ship.
Account-dependent sections can legitimately show connection or unavailable states, but must have implemented and tested data paths.

## 6. Expected code changes

| Existing area | Changes |
| --- | --- |
| [AppModel.swift](../Sources/Glance/AppModel.swift) | Routes, provider tabs, visible-detail lifecycle, shared sizing, pressure demand |
| [App.swift](../Sources/Glance/App.swift) | Independent status-strip controls, metric routing, popover lifecycle and anchoring |
| [NotchController.swift](../Sources/Glance/NotchController.swift) | Individual metric buttons, pinned detail shell, shared dimensions, switching/close handling |
| [Dashboard.swift](../Sources/Glance/Dashboard.swift) | Clickable overview rows and provider rows, shared direct-home action, detail destinations |
| [SubscriptionCards.swift](../Sources/Glance/SubscriptionCards.swift) | Reuse quota rows and separate connection management from richer provider views |
| [SubscriptionStore.swift](../Sources/Glance/SubscriptionStore.swift) | Account metadata, additional independent sources, generation/cooldown handling |
| [SubscriptionUsage.swift](../Sources/GlanceCore/SubscriptionUsage.swift) | Additional provider fields, stable window identity and applicability |
| [SystemReader.swift](../Sources/GlanceCore/SystemReader.swift), [Models.swift](../Sources/GlanceCore/Models.swift) | Memory details and process reading models |
| [README.md](../README.md) | Click behavior, history/local opt-ins, data scope, retention, screenshots and attribution |

Add small dedicated files for the shared detail shell, provider dashboard, process dashboard/store, quota history, local activity.
Keep parsing/calculation models in GlanceCore and AppKit/SwiftUI lifecycle and UI in Glance.
Avoid a generalized plugin framework or unrelated application refactor.

## 7. Acceptance tests and completion criteria

### End-to-end navigation and appearance

- Exercise four metrics from dashboard, provider list where applicable, menu bar, and notch.
- From every tab, disclosure, loading state, and error state, Back to Glance is visible and returns to the regular dashboard without another click.
- Scroll to the bottom of long process/history/activity content and verify that the home control remains visible.
- Test same-icon close, different-icon switch, overview-to-detail, Escape, outside click, and display-mode switching.
- Test hidden overview sections, icons toggled off, no selected metrics, all sections hidden, and provider disconnect while open.
- Verify odd/even icon counts, both sides of the notch, secondary displays, screen edges, long model/process names, and light/dark appearance.
- Verify keyboard focus, meaningful per-icon accessibility labels, non-color-only status indicators, and usable text at actual 1× and 2× scale.
- Capture screenshots of overview plus all four detail dashboards; inspect alignment, clipping, bar proportions, scroll behavior, and typography against the approved concepts.

### Data and lifecycle regression tests

- Extend existing subscription tests with sanitized upstream examples of extra windows, unavailable/null values, duration changes, reset inventory, malformed responses, and rate limits.
- Inject a controllable clock for history tests; cover midnight, daylight-saving changes, reset corrections, account/workspace changes, plan changes, incomplete scans, duplicate samples, and retention cleanup.
- Test account-wide versus scoped-window applicability for icon values and AI alerts.
- Test local duplicate/replayed events, cumulative token counters, cached-token accounting, file truncation/rotation, cancellation, and unknown account scope.
- Test Codex wrong-account/wrong-workspace browser data, absent usage charts, changed chart labels, cooldowns, and independent source failures.
- Test CPU counter resets, PID reuse, process exit, denied measurements, first-sample state, stable sorting, and stopping the process reader.
- Test memory detail pressure without enabling alerts, and alerts without opening Memory details.

### Performance and delivery

Measure Glance's idle CPU, memory, and wakeups before and after the feature with optional sources off and on.
Verify no process sampling after detail closure, no recurring full transcript rescans, no additional sign-in or website analytics, and one in-flight operation per source.
Set any numeric performance budget from the measured baseline during milestone 1 and record the comparison in the completion report.
Run the existing Swift test suite and universal build, including the current popover/alignment and alert regressions.
Use real macOS interaction for the final click/scroll checks, beyond view construction and unit tests.
The final report should distinguish verified live sources, fixture-only compatibility, and account-specific unavailable features.

## Evidence and related notes

- [CodexBar implementation reference](codexbar-implementation-reference.md)
- [Additional subscription data and limitations](subscription-data-options.md)
- [Initial CodexBar comparison](codexbar-usage-research.md)
- [Accepted subscription mockup](mockups/subscription-details-v2.png)
- [Accepted CPU/Memory mockup](mockups/cpu-memory-details.png)


## Implementation and verification

Implemented the four shared detail destinations, independent menu-bar/notch metric controls, pinned Back to Glance, live process ranking, subscription Summary/Activity/History, extra limits, read-only reset inventory, local token reports.
History and local activity are opt-in.
The source-specific last-read times and partial-coverage labels remain visible.

Native app tests exercise icon opening, switching, closing, detail widths, display-mode transitions, hidden overview sections, alert routing, and the visible home action.
Synthetic fixtures cover provider variations, quota cycles/account/plan isolation, process intervals, local log retention/deduplication.
Live-account availability of optional provider windows remains provider-dependent.

Native CPU verification compares a real busy process against `getrusage` accounting.
Process counters use the machine timebase before calculating per-core percentages, matching Apple's [fill_taskprocinfo implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c).

Final verification: 60 tests passed in the full suite, followed by 11 affected tests passing after adding the native CPU-accounting regression (61 distinct tests overall).
The universal Apple-silicon/Intel app built successfully and passed signature verification.
Live UI checks covered CPU/Memory ranking, five/ten rows, scrolling with the pinned home control, provider tabs, live Codex allowance/reset inventory, display modes, and Escape dismissal.
The user's notch preference was restored after testing.


Follow-up fixes: notch pages now share the same opaque background through Back to Glance, including the surrounding scroll surface.
Activity headline, model/session/project rows, and daily chart now exclude cached input by default, with cached reuse and total processed counts displayed separately.
Actual local metadata confirmed cached input dominated the previously displayed inclusive totals.
Regression fixtures verify repeated cumulative records and repeated scans do not add the same event again, and that excluding-cache plus cached input equals total processed for both providers.
