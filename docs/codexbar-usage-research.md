# CodexBar usage details research

Reviewed 2026-09-15 against the official CodexBar repository's current `main` documentation and selected source files.
The inspected changelog lists 0.60.3 dated 2026-09-15; this is a source review, not verification of an installed release. ([Changelog](https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md))
A commit hash could not be resolved through the available network tools, so links identify the reviewed branch rather than an immutable revision.

## Verified CodexBar presentation

### Shared details

CodexBar renders each available quota window with a percentage and reset countdown or absolute reset time.
Its Overview rows open provider details.
Pace compares consumption against the window's expected rate, showing reserve, deficit, and estimated exhaustion or whether allowance lasts until reset.
It withholds most pace estimates until 3% of the window has elapsed; weekly menu-bar pace can appear after 1%.
It also supports account switchers, stacked account cards, manual refresh, and optional local storage breakdowns. ([UI documentation](https://github.com/steipete/CodexBar/blob/main/docs/ui.md))

### Claude

Claude details can show the five-hour and weekly allowances, model-specific weekly allowances, Daily Routines/Cowork allowance, account email, plan, extra-usage monthly spending and limit, and remaining prepaid Usage credits.
These fields depend on the account and selected source.
OAuth covers quotas and extra usage; prepaid Usage credits require the web source.
An Anthropic administrator key enables separate organization spending, messages, and token summaries for today, seven days, and thirty days.
Some organization or Education accounts supply no numerical quota, which CodexBar leaves unavailable instead of inferring from token totals. ([Claude documentation](https://github.com/steipete/CodexBar/blob/main/docs/claude.md))

### Codex

Codex details can show session and weekly allowances, additional model allowances such as Spark, account and plan, purchased credits, and available reset credits with expiry dates.
Optional web extras add code-review allowance, usage breakdown, credits history, and subscription renewal or expiration date.
Workspace credit pools and individual monthly caps remain distinct.
Web extras use a hidden browser and are disabled by default because of network and energy overhead.
Reset credits are displayed without redemption. ([Codex documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md))

### Token and cost history

Usage & Spend offers seven-, thirty-, and ninety-day ranges plus All within a 365-day scan window.
It includes token categories, sessions, Codex projects, coverage information, and a yearly token heatmap.
Amounts are estimated list-price equivalents unless the source separately reports metered spending.
Missing scan coverage is a gap, not zero consumption.
The view stays local. ([History documentation](https://github.com/steipete/CodexBar/blob/main/docs/providers.md#usage--spend-settings))
The cost output exposes daily totals, input/output/cache tokens, models used, model costs, and aggregate token and estimated-cost totals. ([CLI schema](https://github.com/steipete/CodexBar/blob/main/docs/cli.md#cost-json-payload))

## What Glance can obtain through its existing connections

Glance already parses plan, Claude five-hour/weekly/Sonnet/Opus windows, Codex primary/secondary windows, and reset timestamps.
Its current usage model has no credit, spending, identity, or history fields. ([Current parser](../Sources/GlanceCore/SubscriptionUsage.swift))

| Addition | Source boundary | Evidence |
| --- | --- | --- |
| Claude extra-usage enabled state, monthly limit, used amount, utilization, currency | Additional fields in the existing OAuth usage response: `extra_usage` | [Claude decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift) |
| Claude dynamic model limits and Routines/Cowork windows | Additional fields in that response: `limits` and routines aliases | [Claude decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift) |
| Claude account email and organization identity | Additional OAuth profile request, using the same sign-in | [Claude profile fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift) |
| Codex purchased credit balance and unlimited state | Additional fields in existing usage response: `credits` | [Codex decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) |
| Codex model quotas and individual monthly cap | `additional_rate_limits`, `individual_limit`, and `spend_control`; cap can include used, limit, remaining percentage, reset | [Codex decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) |
| Codex reset-credit count and expiries | Additional OAuth request to the reset-credit endpoint | [Codex fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) |
| Codex workspace balance or monthly spending detail | Separate account-scoped OAuth requests; permission-dependent | [Codex fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) |

This confirms CodexBar's supported fields, not that every Glance account currently receives them.
Preserve unknown or unavailable values and verify monetary units against the provider mapping before displaying currency.

## Sources that would expand Glance's scope

- **Web sessions:** Claude prepaid balance and Codex dashboard extras require browser-session integration, including account matching and source-specific failures. ([Claude sources](https://github.com/steipete/CodexBar/blob/main/docs/claude.md), [Codex sources](https://github.com/steipete/CodexBar/blob/main/docs/codex.md))
- **Local logs:** Claude and Codex token/cost estimates require scanning supported session transcripts; they cover recorded local activity rather than the entire subscription across devices. ([Claude log scanner](https://github.com/steipete/CodexBar/blob/main/docs/claude.md#cost-usage-local-log-scan), [Codex log scanner](https://github.com/steipete/CodexBar/blob/main/docs/codex.md#cost-usage-local-log-scan))
- **History:** A retained allowance chart needs stored snapshots; Glance currently states that usage readings are not stored on disk. ([Glance privacy policy](../README.md#privacy-and-repository-hygiene))

## Proposed priority for Glance

First expose a consistent provider detail view from the subscription row and its menu-bar or notch icon.
Enrich that view with available credits, extra spending, additional model windows, account identity, and both relative and absolute resets.
Keep purchased credits, reset credits, monthly spending, and quota percentages as separately labelled facts.
Add a clearly marked pace estimate when enough window timing is available.
Evaluate optional token history and web-only extras separately because they add data collection and integration requirements.
These priorities are proposals; the interaction and CPU/memory process details are specified separately in [Usage detail proposal](usage-detail-proposal.md).
