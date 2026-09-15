# CodexBar implementation reference

Reviewed 2026-09-15 for the approved Glance subscription and system detail implementation plan.
Source inspected at immutable commit [`62e71bb60ab1be6a3a94df3941a5f2d89530ecb7`](https://github.com/steipete/CodexBar/tree/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7).
This is a source review; upstream tests were inspected, not executed.
No account credentials or private usage records were accessed.

## History: borrow isolation and reset handling, adapt aggregation

[PlanUtilizationHistoryStore.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/PlanUtilizationHistoryStore.swift) stores timestamped percentage/reset observations in versioned account buckets and named window series.
It canonicalizes slightly varying five-hour and weekly durations.
[UsageStore+PlanUtilization.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/UsageStore+PlanUtilization.swift) waits for persisted history to load before selecting it, avoids borrowing unscoped history for an explicit account, and coalesces hourly samples into segment peaks.
A meaningful reset boundary preserves both the peak before the reset and the next segment; small reset corrections use a two-minute tolerance.
Missing reset metadata can be filled from a compatible sample.

Glance should reuse those boundary rules and asynchronous-load safeguards, with raw baseline/latest observations retained for daily differences.
Hourly peak coalescing alone cannot establish exact consumption before midnight or the final utilization of an unobserved cycle.
The plan correctly calls these observed percentage-point increases, shows gaps, and labels the previous period “Last observed.”
Ninety-day opt-in retention and plan epochs are Glance choices, not CodexBar defaults.

[CodexHistoryOwnership.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/CodexHistoryOwnership.swift) prefers a stable provider account identifier and falls back to normalized hashed email, refusing ambiguous legacy ownership.
[CodexAccountUsageSnapshotStore.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/CodexAccountUsageSnapshotStore.swift) validates email plus workspace identity, writes an atomic versioned cache with private permissions, and retains original reading timestamps.
Glance needs the account/workspace boundary, but does not need upstream legacy-cache migration machinery.

[CodexWeeklyResetConfirmation.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/Providers/Codex/CodexWeeklyResetConfirmation.swift) stages suspicious near-zero weekly readings and checks timestamps/reset evidence before publication.
Do not classify every downward percentage correction as a new quota period.

## Provider parsing and credential boundaries

[CodexOAuthUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) decodes ordinary and additional rate limits plus optional credits and reset inventory.
Reset records include status, type, grant/expiry/redeemed timestamps and descriptive metadata.
Optional decoding and enrichment must not erase a healthy base allowance reading.

[ClaudeOAuthUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift) and [ClaudeWebExtraRateWindowParser.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebExtraRateWindowParser.swift) handle optional model/scoped windows and Routines naming variants.
Preserve scope and source labels; a feature-specific exhausted window must not imply that ordinary chat is exhausted.
Do not promise optional windows on every plan.

[CodexProviderDescriptor.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift) explicitly leaves native refresh-token ownership with Codex CLI and fails closed for read-only external credential sources.
Reset enrichment uses the winning in-memory credential context rather than rereading a potentially changed file.
[ClaudeOAuthDelegatedRefreshCoordinator.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthDelegatedRefreshCoordinator.swift) contains prompt-policy, cooldown and delegated-CLI machinery.
Keep Glance’s existing credential policy; importing that Claude machinery would conflict with its prohibition on launching agent sessions for usage collection.

## Dashboard enrichment research (excluded from Glance)

[OpenAIDashboardScrapeScript.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardScrapeScript.swift) extracts dated service/credit series from the actual usage chart and rejects unrelated skill/thread/turn charts.
[OpenAIDashboardModels.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/OpenAIDashboardModels.swift) keeps usage breakdown separate from credit-event history.
These credits cannot be converted into subscription-quota percentages.
This requires website data and is excluded: Glance uses existing provider connections and local records only.

[OpenAIDashboardFetcher+ReturnableData.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardFetcher%2BReturnableData.swift) guards snapshot reuse by account where available, while accommodating legacy personal snapshots without account IDs.
Glance does not include a separate web sign-in or dashboard scraper.

## Local activity: reuse correctness cases, omit cost infrastructure

[CostUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/CostUsageFetcher.swift) performs cancellable scanning away from the UI and preserves stale snapshot timestamps and coverage.
[CostUsageModels.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/CostUsageModels.swift) exposes Codex session/project/model token metadata; the session model does not supply a trustworthy conversation title.
[CostUsageScanner+Claude.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner%2BClaude.swift) bounds JSONL lines, resumes by offset, checks cancellation, and keeps the last cumulative streaming usage for a message/request pair.
Missing identifiers remain distinct rather than being deduplicated by coincidentally equal text or counts.
Glance should adapt incremental cursors, file replacement/truncation detection and fork-aware deduplication, while caching only necessary metadata.
Local tokens establish recorded activity on this Mac, not exact task-level quota consumption or account-wide history.

## Shared UI and useful regression references

[MenuCardView+ModelInput.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/MenuCardView%2BModelInput.swift) uses a shared presentation input with independent sources, freshness, refresh state and an injected clock.
[StatusItemController+OverviewSubmenus.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/StatusItemController%2BOverviewSubmenus.swift) routes provider selection centrally.
[MenuSessionCoordinator.swift](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Sources/CodexBar/MenuSessionCoordinator.swift) separates data changes from structural rebuilds and rejects stale interaction callbacks.
Reuse those principles in Glance’s persistent SwiftUI hosts; its pinned Back to Glance button and icon routing are product-specific requirements.
Importing upstream NSMenu controllers or its entire provider/settings architecture is unnecessary.

Inspected upstream test cases worth porting into focused Glance fixtures:

- [History reset coalescing](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/UsageStorePlanUtilizationResetCoalescingTests.swift): timestamp drift, missing metadata, same-hour reset, separate named windows.
- [Claude identity boundaries](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/UsageStorePlanUtilizationClaudeIdentityBoundaryTests.swift): token rotation, unknown owner, account change during capture.
- [OAuth reset enrichment](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/CodexOAuthResetCreditFetchTests.swift): winning credentials, cancellation and empty enrichment.
- [Dashboard parser](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/OpenAIDashboardParserTests.swift): locale numbers, missing series, review aliases and partial windows.
- [Scanner](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/CostUsageScannerTests.swift) and [Claude regressions](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/Tests/CodexBarTests/CostUsageScannerClaudeRegressionTests.swift): append/truncate/replace, stale cumulative counters, copied forks, streamed updates and missing identifiers.

## Reuse and attribution

The reviewed [LICENSE](https://github.com/steipete/CodexBar/blob/62e71bb60ab1be6a3a94df3941a5f2d89530ecb7/LICENSE) is MIT, copyright 2026 Peter Steinberger, requiring preservation of its copyright and permission notice in copies or substantial portions.
Glance already packages a CodexBar notice.
Record exact revision, paths and adapted tests for copied portions, and check any separately vendored component’s own provenance before importing it.
Prefer bounded parsing and aggregation helpers plus regression fixtures over a wholesale application dependency.

## Implemented adaptations (2026-09-15)

- `SubscriptionUsage.swift` adapts provider window mappings and reset inventory interpretation into Glance's existing models.
  General allowance is separate from named model/feature limits.
  `MetricDataTests` covers malformed sibling entries, identity, expired reset inventory, scoped exhaustion, and independent optional-source failures.
- `LocalActivity.swift` is a token-only reader informed by the upstream Claude streaming and Codex fork/cumulative regression cases.
  It retains metadata in memory, resumes by byte offset, checks file replacement/truncation, and bounds files, bytes, lines, and retained events.
  It excludes inherited counters without a trustworthy fork baseline and reports partial coverage.
  `LocalActivityTests` covers streaming duplicates, missing IDs, incremental reads, replacement, forks, truncated counters, malformed data, model attribution, and retention limits.
- `QuotaHistory.swift` uses fine-grained local observations rather than copying upstream hourly peaks.
  It isolates provider/account/plan epochs and reset cycles, tolerates two-minute reset timestamp jitter, retains last observations, and excludes uncertain intervals from daily changes.
  History is explicitly partial and opt-in, with atomic local storage and a 90-day retention limit.

The packaged `CodexBar-LICENSE.txt` covers the adapted MIT components.
No upstream billing/cost database, cookie importer, agent-session launcher, or credential-refresh writer was imported.
