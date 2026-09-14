# Vorssaint reference notes for Glance

Reviewed 2026-09-14 against Vorssaint's official website, repository documentation, changelog, and one source file.
This is a reference review, not a hands-on test of Vorssaint or a verified gap analysis of Glance.
Suggestions below are design judgments for Glance's compact system-monitoring scope.

## 1. Make alerts selective and actionable

Vorssaint documents optional alerts for sustained CPU load, temperatures, memory pressure, low storage, and low battery. ([Feature reference](https://github.com/vorssaint/vorssaint-utils#know-what-your-mac-is-doing))
For Glance, start with memory pressure, critically low storage, and the user's AI allowance approaching exhaustion.
Require a sustained condition, suppress repeated alerts, and open the affected metric when clicked.
The AI allowance adaptation and suppression policy are proposals, not claims about Vorssaint.
These turn a passive display into timely assistance while preserving a quiet desktop.

## 2. Make disabled features genuinely idle

Vorssaint says removed features stop loading, retain their preferences, and carry energy badges; onboarding offers a battery-oriented preset. ([Feature installation](https://github.com/vorssaint/vorssaint-utils#install-only-what-you-use))
Its changelog also describes less monitoring work with the panel closed or fewer visible readings, without claiming measured battery-life gains. ([Changelog](https://github.com/vorssaint/vorssaint-utils/blob/main/CHANGELOG.md))
For Glance, tie monitoring frequency to visible metrics and required alerts, and stop unused collectors.
Explain consequential background activity beside its setting.
Measure idle CPU and wakeups before presenting energy savings as a product claim.

## 3. Treat notch opening as an interaction contract

The documented Dynamic Island design distinguishes rest, hover preview, and click expansion, and suppresses reopening after dismissal until the pointer leaves and returns. ([Dynamic Island reference](https://github.com/vorssaint/vorssaint-utils#everyday-tools))
The changelog currently lists Dynamic Island under Unreleased. ([Release status](https://github.com/vorssaint/vorssaint-utils/blob/main/CHANGELOG.md#unreleased))
For Glance, test dismissal, pointer crossings, fullscreen use, multiple displays, and keyboard escape as explicit behaviors.
Keep the resting surface small and let users choose their most useful persistent reading.

## 4. Give measurements useful context

The official site pairs memory usage with pressure and places battery health, cycles, charging state, and power together. ([Website demonstration](https://vorssaint.com/))
For Glance, prioritize understandable pressure and charge context over adding more isolated percentages.
Use one concise status sentence, then offer details on demand.
Hardware-dependent readings should clearly show unavailable rather than a misleading zero.

## 5. Make Keep Awake visibly temporary

The website demonstrates quick duration extensions. ([Keep Awake demonstration](https://vorssaint.com/))
The inspected source separates system and display sleep, tracks a session deadline, and can end a session below a configured battery threshold. ([KeepAwakeManager](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/KeepAwakeManager.swift))
For Glance, expose a countdown, quick extension, display-sleep choice, and an unmistakable Stop action together.
App-based activation and pausing on lock are documented in the stable changelog and are reasonable later additions. ([Stable feature notes](https://github.com/vorssaint/vorssaint-utils/blob/main/CHANGELOG.md#335---2026-09-06))
