# Usage detail panels for Glance

Research and recommendations, 2026-09-15.
This proposal does not change application behavior.
CodexBar findings and source links are in [the companion research note](codexbar-usage-research.md).

## User feedback after the mockups

The CPU and Memory visual direction and revised subscription mockup are accepted.
The implementation plan is [Glance metric detail dashboards](metric-details-implementation-plan.md).
The priority is understanding included subscription usage, rather than displaying API-equivalent costs.
Keep financial details in an optional secondary section.
The accepted system concept is [CPU and Memory details](mockups/cpu-memory-details.png).
Further source research is recorded in [Subscription data options](subscription-data-options.md).

The accepted [revised AI design](mockups/subscription-details-v2.png) emphasizes these questions:

- How much of this week's allowance did I consume today, and how does that compare with yesterday?
- Where is usage happening, when the provider exposes a breakdown by tool?
- Which local tasks and models have the most recorded activity?
- Did I use most of my allowance in previous quota periods, or leave it unused?

Daily changes and completed-period comparisons require timestamped quota snapshots, reset handling, and sufficient coverage.
Show incomplete coverage as unknown instead of claiming a complete day or week.
Local token activity is not an exact allocation of provider quota and must be labelled separately.

## Recommendation

Give Claude, Codex, CPU, and Memory their own detail page inside the existing dropdown.
Open the same page from that metric's dashboard row, menu-bar icon, or notch icon.
Keep the compact icon readings, and put the richer information behind the click.

## What Glance already has

- AI: reported plan, session and weekly usage, Claude Sonnet/Opus weekly windows when supplied, reset countdowns, freshness, refresh, and provider usage-page links.
- Overview: the most constrained reported AI window and its remaining percentage.
- System: total CPU and memory readings with short recent-history graphs.
- Navigation: all menu-bar metrics are drawn into one button; the notch strip is also one button; the AI overview section is one button opening both providers.
- No per-process measurements or dedicated CPU, Memory, Claude, or Codex destinations exist yet.

Sources: [usage model](../Sources/GlanceCore/SubscriptionUsage.swift), [subscription cards](../Sources/Glance/SubscriptionCards.swift), [menu bar](../Sources/Glance/App.swift), [notch](../Sources/Glance/NotchController.swift), [dashboard](../Sources/Glance/Dashboard.swift), [system reader](../Sources/GlanceCore/SystemReader.swift).

## Exact click behavior

| Entry point | Destination |
| --- | --- |
| Claude row under AI subscriptions | Claude details |
| Claude icon and adjacent percentage, in either display mode | The same Claude details |
| Codex row or icon and percentage | Codex details |
| CPU dashboard row or icon and percentage | CPU details, sorted by CPU usage |
| Memory dashboard row or icon and percentage | Memory details, sorted by memory usage |
| AI subscriptions section heading | Provider list and connection management |
| Glance fallback icon | Overview |

- Clicking the currently open metric again closes the dropdown.
- Clicking a different metric switches directly to its page in the same dropdown.
- Provide an always-visible **‹ Back to Glance** control on every detail page and tab, outside scrolling content; it always returns directly to the normal overview regardless of entry point.
- Escape and outside clicks close the dropdown.
- Hiding a dashboard section must not disable a selected icon's detail page.
- Hiding a provider icon must not remove its row or detail page from AI subscriptions.
- Treat each icon plus percentage as one accessible control with a provider/metric-specific label.
- Keep the dropdown in a stable position while switching metrics, preserving the existing camera gap and screen-edge handling.
- Show the latest reading immediately and refresh if stale, respecting provider cooldowns; do not make opening a page wait for the network.

## AI panel contents

### Shared layout

1. Provider, reported plan, and account/workspace identity when reliably available.
2. A clear headline: remaining allowance, its limiting window, and the next reset.
3. All reported quota windows, each with a bar, remaining percentage, reset countdown, and exact local reset date/time.
4. Recent subscription consumption and historical comparisons where enough observations exist.
5. Last successful update and actionable connection state.
6. Refresh and Open usage page actions.

Use remaining percentage consistently with the icons; expose used percentage as secondary text if useful.
Identify model-specific windows clearly and do not present them as independent pools of interchangeable allowance.
Never convert quota percentages into remaining messages or tokens without a provider-supplied conversion.
Do not render missing fields as zero, and distinguish unavailable readings from exhausted limits.

### Add first

- **Claude:** dynamic model-specific weekly limits and Routines/Cowork limits when supplied, alongside the existing five-hour and weekly windows.
- **Codex:** additional separately limited buckets, alongside the existing session and weekly windows.
- **Both:** exact reset dates, clearer account context when available, and a dedicated provider page reachable in one click.
- **Both:** observed daily quota consumption and completed-period history, with honest coverage labels.

Only show fields supported by the active data source and account.
CodexBar's richer views combine several data sources; the companion note distinguishes those from fields supplied by Glance's existing OAuth connections.

### Add next

- A pace sentence explaining whether current consumption is ahead of the elapsed quota window, explicitly marked as an estimate.
- Codex reset-credit count and expirations through a separate read-only request, if relevant to the account.
- Optional local activity by session and model, without dollar figures in the subscription panel.
- Codex usage by tool through optional account-matched web dashboard integration.
- Optional extra-usage spending, purchased balances, and monthly spend caps only for accounts that need these secondary details.

Local log totals cover activity recorded on this Mac, while subscription quotas describe provider-reported allowance.
Estimated API-equivalent cost is not the subscription bill, extra-usage spending, or purchased credits.
History requires an explicit retention choice and a clear-history action because Glance currently promises not to save usage readings to disk.
See [the current privacy description](../README.md#privacy-and-repository-hygiene).

## CPU details

- Total CPU usage and the existing recent-history graph.
- The top five processes, highest current CPU use first, with a Show 10 option.
- Each row: process/app name, app icon when available, CPU percentage, and memory used.
- Sample on a roughly two-second cadence while this panel is visible, using CPU-time differences between samples so the ranking reflects recent activity.
- Show a brief measuring state until the first CPU interval is available.
- Use a clearly defined percentage scale: recommend process CPU as a share of one logical core, with a short explanation that a process can exceed 100%; keep the existing total-machine reading on its 0–100% scale.
- Keep process identity stable across refreshes; use PID and process start identity internally, with PID as secondary detail for duplicate names.
- Provide Open Activity Monitor for deeper inspection.

Optional later addition: grouping reliably associated helper processes under their app, with an expandable process list.
Start with actual processes to avoid hiding a resource-heavy helper or guessing ownership for terminal tools.
Apple's CPU guide explains total system/user/idle readings and recent CPU history: [View CPU activity](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac).

## Memory details

- Used and total memory, plus the recent-history graph.
- A prominent memory-pressure status, backed by the macOS signal rather than derived from percent used.
- Swap used and compressed memory; app/wired/cache breakdown can be secondary detail.
- The top five processes by measured memory use, with a Show 10 option.
- Each row: process/app name, app icon when available, memory in MB/GB, and CPU percentage.
- Use one documented memory measure consistently; prefer physical footprint where available and label any fallback accurately.
- Do not imply that adding process rows equals total memory used, or promise exact agreement with Activity Monitor without validating the chosen measurement.
- Provide Open Activity Monitor.

Memory pressure adds context because macOS uses memory for caching and compression; high used memory alone should not be labeled a problem.
Apple defines pressure, app/wired/compressed memory, cached files, and swap in [View memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac).

## Implementation boundaries

Reuse one navigation destination and one detail view per metric across all entry points.
Replace the menu bar's single flattened click target with individually accessible metric controls inside the existing strip, and make each notch metric a separate button.
Keep a single dropdown, rather than creating four independent windows.
Extend the existing subscription data model to retain supported additional fields, rather than adding a second provider-fetching system.
Collect process readings off the UI thread only while CPU or Memory details need them, and pause that sampling when the panel closes.
Handle processes exiting between samples and unavailable measurements without displaying misleading zeros.
Keep process termination controls outside the initial feature; Open Activity Monitor supplies the established inspection and management path.

## Recommended order

1. Direct metric navigation, richer subscription limits and observed usage history, and CPU/Memory top-process lists.
2. Local task/model activity and optional provider breakdowns by tool, with source and coverage clearly identified.
3. Optional financial details for accounts that need them.

## Acceptance checks for a future implementation

- Each of four metrics opens the correct page from both dashboard and selected menu-bar/notch icons.
- Same-icon clicks close; different-icon clicks switch; back, Escape, and outside click behave consistently.
- Odd/even icon counts, hidden sections, scrolling, display changes, and switching menu-bar/notch mode preserve usable positioning and navigation.
- Missing provider data, expired resets, stale readings, changed accounts, sign-in errors, and cooldowns remain distinguishable.
- Additional balances and quota buckets appear only when supplied, with credits and spending clearly labeled.
- A controlled CPU-heavy process rises in CPU ranking; a controlled memory allocation rises in memory ranking; exited processes disappear.
- Process sampling stops when details close and does not block UI interactions.
- Keyboard navigation and accessibility identify every metric separately.
