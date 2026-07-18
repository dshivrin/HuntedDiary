# Shortcut Reply Refactor — Task 7 Report

Date: 2026-07-18

## Implemented

- Persisted the exact configured Shortcut name, successful verification name/date, and active setup-probe identity/name in `AppSettings`.
- Invalidated verification and the active probe when the configured name changes, while preserving metadata for an exact no-op assignment.
- Added a production `@MainActor` setup coordinator that creates a durable `.setupProbe`, generates separate request and callback capabilities, launches the configured Shortcut, reconstructs after termination, and reconciles on app launch, callback delivery, and scene activation.
- Retried cancelled and retryable failed probes with the same UUID while rotating both capabilities and incrementing attempt metadata through `PendingDiaryReplyStore.prepareRetry`.
- Kept URL-open acceptance as handoff only. Verification is recorded only after the durable request reaches `.replyStored`.
- Kept setup probes outside diary history reconciliation; setup completion changes neither canvas nor diary reply state.
- Added Settings UI with the exact `Reply Shortcut Name` label, `Tom’s Diary Reply` default, inline three-action help, in-app `Setup Guide`, `Test Shortcut`, and verified-name/date status.
- Documented in UI that a ChatGPT account is optional and that the app cannot pre-detect account, subscription, extension, region, Shortcut existence, or availability.

## Test-first evidence

- Initial RED command: focused `ShortcutAppSettingsTests` and `ShortcutSetupCoordinatorTests`; exit 65 with the expected missing `ShortcutSetupCoordinator`, `ShortcutSetupSettingsOwning`, `ShortcutSetupCapabilities`, and `AppSettings.persist` symbols.
- Final focused command:
  - `xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryTask7Green2 -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/ShortcutAppSettingsTests -only-testing:TheHuntedDiaryTests/ShortcutSetupCoordinatorTests`
  - Exit 0; xcresult: 16 declared tests, 17 invocations, 0 failures, 0 skips.
- Combined Tasks 3–7 command:
  - `xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryTask3Through7 -parallel-testing-enabled NO` with capability, store, intent, launcher, flow, settings, and setup suites selected.
  - Exit 0; xcresult: 93 declared tests, 120 invocations, 0 failures, 0 skips.
- Generic device build:
  - `xcodebuild build -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TheHuntedDiaryTask7Build CODE_SIGNING_ALLOWED=NO`
  - Exit 0.

## Coverage added

- Default, persistence, rename invalidation, exact-name preservation, and malformed/mismatched settings metadata.
- Blank names and accepted launches that never verify by themselves.
- Successful probe completion without history eligibility.
- Cancellation, action failure, launch rejection, duplicate completion, and duplicate reconciliation.
- Same-UUID retry with independently rotated request and callback capabilities.
- Rename during an in-flight probe and stale UI-state clearing.
- Termination/reconstruction from persisted settings and the live pending-request store.
- Required Settings copy and optional-account/no-preflight-detection language.

## Security and project checks

- New Task 7 production files contain no `print`, `NSLog`, `os_log`, or `Logger` calls.
- UserDefaults stores only the configured/verified Shortcut names, timestamps, and setup UUID; it stores no prompt, recognized text, history, reply, or capability secret.
- The setup probe prompt is a fixed harmless constant and diary content is never used for it.
- Source and test roots are filesystem-synchronized; the focused tests compiled the new production and test files.
- All app and test deployment settings found in the project remain `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; app targets retain `TARGETED_DEVICE_FAMILY = "1,2"` for iPhone and iPad.
- `DiaryPromptBuilder.swift` SHA-256 remains `e76b2f3930d07bbe98dd948b9c458241ec876ab88a5b385db0c79ff7fe6ef1ce`.
- `DiaryPromptBuilderTests.swift` SHA-256 remains `41fbc4a579ee61edb70035a05f1d1f9f84c55aa99014a0ba889a4cc2faf2b8bf`.
- `git diff --cached --check` passed.

## Pending physical-device validation

The Extension Model workflow still requires a compatible physical iPhone or iPad running iOS/iPadOS 26 with the ChatGPT extension enabled. Simulator tests and builds do not prove Extension Model availability or the physical Shortcuts round trip, so this item remains pending.

## Deviations

- The Setup Guide is implemented as a native in-app navigation destination colocated with the Settings component, rather than a separate new guide source file. It contains the plan’s exact three-action contract and compatibility/account guidance.
- No approved architecture was replaced. Existing unrelated dirty changes were left unstaged.
