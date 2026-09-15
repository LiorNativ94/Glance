# Additional subscription usage data

Reviewed 2026-09-15 from official CodexBar source and provider documentation.
This supplements [the initial comparison](codexbar-usage-research.md) with details beyond quota bars.
All example values below are hypothetical design examples, not this user's data.
No accounts, credentials, or private session files were accessed.

## 1. Codex: where usage went

CodexBar's web scraper extracts a daily series with `day`, `services[{service, creditsUsed}]`, and `totalCreditsUsed`, retaining up to thirty dates.
Recognized service labels include CLI, Desktop, VS Code, and GitHub Code Review; labels are read from the source rather than a fixed local/cloud split.
It selects the Usage breakdown or Personal usage chart and explicitly rejects charts labelled threads, turns, clients, skills, or invocations.
This is stronger evidence for a **usage by tool** panel than for a message-count panel. ([Scraper](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardScrapeScript.swift))

**Example:** “Usage by tool · last 7 days: Desktop 420 credits, CLI 180, VS Code 90, GitHub Code Review 30.”
Shares such as “Desktop 58% of recorded credits” would be Glance calculations over that series, not percentages of the weekly subscription allowance.
Do not infer how many messages those credits represent.
Do not label the entire series as purchased-credit spending.

The dashboard model deliberately separates the Usage breakdown chart from the credits-history ledger.
Both have daily service totals, but the latter comes from credit events and the former from the usage chart. ([Dashboard model](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIDashboardModels.swift))
Credit event rows provide date, service, and credits used; the parser also obtains code-review remaining percentage and its reset where present. ([Dashboard parser](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardParser.swift))

**Dependency:** Additional account-matched browser-session integration.
CodexBar's web extras are opt-in and can incur additional energy/network work; this data is not part of Glance's current OAuth usage parsing.
Actual availability for a particular plan requires verification. ([Codex source documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md#openai-web-dashboard-optional-off-by-default))

## 2. Claude: product and model allowances

The current parser reads scoped weekly limits with model ID, model display name, percentage, and reset date.
It also recognizes several Routines/Cowork aliases, presenting them as Daily Routines while mapping the window to seven days.
That is a separate allowance when supplied, not a history of Cowork tasks or proof that all Cowork activity is independently metered. ([Additional-window parser](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebExtraRateWindowParser.swift))

**Example:** “Fable weekly allowance: 32% used” alongside “Routines allowance: 8% used.”
Model allowances are separate constraints; they are not additive shares of total usage.
The inspected Claude web fetcher exposes quota windows, extra usage, account email, organization, and plan metadata.
It does not expose a Codex-like daily usage-by-product series or per-conversation quota consumption. ([Claude web fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift))

**Dependency:** Dynamic model and Routines fields are also supported in the existing OAuth response shape.
No browser integration is required to start supporting those optional fields. ([Claude OAuth decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift))

## 3. Codex: reset inventory and subscription context

The reset-credit response contains an available count plus individual status, type, grant date, expiry, redemption timestamps, optional title, and description.
This uses a separate request with the existing OAuth identity. ([Reset-credit decoder](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift))

**Example:** “2 usage resets available · next expires September 30.”
CodexBar also retains plan, account identity, and optional subscription renewal/expiration dates; the latter depend on web billing metadata. ([Dashboard model](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/OpenAIDashboardModels.swift))
These are useful context and actions, not a replacement for a richer usage breakdown.

## 4. Both: observed allowance history

CodexBar supports saved plan-utilization charts, with account isolation for Claude and separate quota-window history for Codex. ([Release history](https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md))

**Glance proposal, derived:** Plot timestamped readings of the same weekly allowance, with reset boundaries and gaps.
Show “Observed increase today: 18 percentage points” only when the starting and ending samples belong to the same account, plan, and quota cycle.
This is not an exact daily usage total: rounding, reporting delays, missing samples, and resets can affect differences.
A daily series needs ongoing local retention and cannot reconstruct prior days from the current percentage.
Across resets, show separate cycles instead of subtracting percentages or summing incompatible window capacities.

## 5. Local activity: explain work volume without claiming quota attribution

CodexBar's local session model supports session ID, last activity, token categories, total tokens, optional request count, and model breakdowns.
Project breakdowns include name/path, daily totals, and models. ([Local data model](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/CostUsageModels.swift))
Its fetcher populates session/project breakdowns for Codex only and removes session detail when external Pi activity is merged.
Claude supplies daily/model token totals here; Claude top-conversation grouping would require additional implementation. ([Fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/CostUsageFetcher.swift))

**Example:** “Most token-intensive local sessions: Session A · 850k tokens.”
Keep this explicitly labelled “On this Mac”; tokens and model requests cannot be converted into a reliable share of subscription quota.
Native hourly history and human-readable conversation titles are not established by these models.

## 6. Richer official analytics with narrower availability

- **OpenAI:** Eligible Enterprise/Edu environments offer Work/Codex analytics; documented Usage & billing requires an eligible credit-based Enterprise workspace and administrator-controlled visibility.
  It offers seven/thirty-day groupings by surface, model, reasoning, and speed, plus locally available high-usage chats.
  Do not promise this for individual Plus/Pro or assume CodexBar imports every field. ([OpenAI documentation](https://help.openai.com/en/articles/20001478))
- **Claude monthly recap:** Free/Pro/Max users with memory enabled can see chat activity and themes, but Code and Cowork are excluded.
  No integration endpoint was verified; consider a link instead of an embedded data promise. ([Recap documentation](https://support.claude.com/en/articles/15672559-see-your-monthly-recap))
- **Claude organization analytics:** Product/model/skill analytics depend on the organization plan and permissions; per-member personal breakdowns require usage-based Enterprise and administrator enablement.
  This is not a verified individual Max feature. ([Analytics documentation](https://support.claude.com/en/articles/12883420-view-usage-analytics-for-team-and-enterprise-plans))

## Recommendation

Make **allowance history** the primary new section for both providers.
Add **Codex usage by tool** when the account's dashboard supplies it.
Offer **local model/session activity** as a clearly separated explanation of work volume.
Use provider-specific sections instead of showing Claude a fabricated equivalent of Codex's breakdown.
