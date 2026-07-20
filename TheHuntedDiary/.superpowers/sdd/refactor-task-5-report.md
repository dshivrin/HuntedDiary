# Task 5 Report: iOS 26 App Intents

## Status

Implemented the two plumbing App Intents, injected-store unit seams, shared dependency registration at app initialization, reply validation, safe error mapping, and post-storage deferred foreground continuation.

## RED

Command:

```bash
xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryTask5Red -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/DiaryReplyIntentTests
```

Result: exit 65, `** TEST FAILED **`, with the expected missing `DiaryReplyIntentError`/intent symbols before production implementation.

## Implementation

- `GetPendingDiaryPromptIntent` uses `@AppDependency`, accepts exactly one **Request Handle**, validates the strict capability, and returns the frozen prompt.
- `CompleteDiaryReplyIntent` accepts **Request Handle** and **Reply**, rejects blank or replies above 65,536 UTF-8 bytes, durably stores the reply, and only then requests foreground continuation.
- Both intents have explicit injected-store initializers; tests never use global dependency state.
- `TheHuntedDiaryApp.init()` constructs the shared container and registers its actor store with `AppDependencyManager.shared` before the scene body is built.
- Errors contain no handle, capability, prompt, or reply content.
- Current iOS 26 APIs are used: prompt `.background`; completion `[.background, .foreground(.deferred)]` plus `continueInForeground(alwaysConfirm: false)`. No deprecated `openAppWhenRun` or `ForegroundContinuableIntent`.
- No `AppShortcutsProvider`, Siri phrases, or preconfigured App Shortcuts were added.

## GREEN

Focused intent suite: exit 0 on iPhone 17 / iOS 26.5, including prompt retrieval, durable-before-foreground ordering, blank/oversized replies, malformed/unknown/expired/wrong capabilities for both actions, duplicate/conflicting completion, redaction, and execution modes.

Combined command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryTask5Combined -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/DiaryReplyCapabilityTests -only-testing:TheHuntedDiaryTests/PendingDiaryReplyStoreTests -only-testing:TheHuntedDiaryTests/DiaryReplyIntentTests
```

Final rerun after adding completion error-path coverage: exit 0; 53 declared tests in 3 suites passed (76 parameterized invocations: 23 capability, 44 store, 9 intent).

Build-for-testing:

```bash
xcodebuild build-for-testing -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryTask5Build
```

Result: exit 0. The synchronized source lists contain all three intent production files and the intent test file. `Metadata.appintents/extract.actionsdata` contains **Get Pending Diary Prompt**, **Complete Diary Reply**, **Request Handle**, and **Reply**.

Security search for `openAppWhenRun`, `ForegroundContinuableIntent`, `AppShortcutsProvider`, app-shortcut phrases, and Siri phrases under the new production surface returned no matches.

Prompt builder SHA-256 values remain:

- Source: `e76b2f3930d07bbe98dd948b9c458241ec876ab88a5b385db0c79ff7fe6ef1ce`
- Tests: `41fbc4a579ee61edb70035a05f1d1f9f84c55aa99014a0ba889a4cc2faf2b8bf`

## Notes

- Simulator verifies compilation, metadata extraction, and intent/store logic. It does not prove the physical-device Extension Model workflow.
- Pre-existing warnings remain in the canvas, capability helper isolation, Apple Vision tests, and direct OpenAI tests; Task 9 removes the obsolete OpenAI paths.
