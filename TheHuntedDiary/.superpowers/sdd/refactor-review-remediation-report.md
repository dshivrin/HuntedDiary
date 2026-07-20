# Review Remediation Report: Universal Device Support and Test Harness

## Status

DONE_WITH_CONCERNS

Implemented and committed the review-remediation checkpoint. App, unit-test, and UI-test target configurations now support iPhone and iPad while retaining iOS 26.0 deployment targets; the UI-test bundle has a real executable and smoke test; and programmatic canvas Clear explicitly cancels the pending 2.5-second idle callback through a single parent-owned committer.

Commit: `4d2282405391fb4d684cf83dfcd15c4415300a23 Fix universal support and test harness`

## Root-cause confirmation

- The project contained six `TARGETED_DEVICE_FAMILY = 2` assignments: Debug and Release for the app, unit tests, and UI tests.
- `TheHuntedDiaryUITests` was a file-system-synchronized group with no source file, so Xcode produced an `.xctest` bundle without an executable.
- `PencilCanvasIdleCommitter` could cancel only when a later drawing change arrived. The parent Clear button called only `canvasModel.clear()`, so the existing delayed closure remained armed.
- `PencilCanvasView` previously owned the committer internally, preventing the parent Clear action from cancelling that exact instance.

## RED evidence

### UI-test bundle executable

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationRedUITests -parallel-testing-enabled NO -only-testing:TheHuntedDiaryUITests
```

Result: exit 65, `** TEST FAILED **`.

Relevant failure:

```text
The bundle “TheHuntedDiaryUITests” couldn’t be loaded because its executable couldn’t be located.
```

Result bundle: `/private/tmp/TheHuntedDiaryRemediationRedUITests/Logs/Test/Test-TheHuntedDiary-2026.07.17_07-33-39-+0300.xcresult`

### Universal device-family assertion

The new `scripts/assert-universal-device-families.sh` assertion was added before changing the project file.

Command:

```bash
scripts/assert-universal-device-families.sh
```

Result: exit 1. It reported unexpected value `2` at all six project-setting lines (418, 449, 469, 490, 510, and 530).

### Programmatic Clear cancellation

The test `programmaticClearCancelsPendingIdleCommit()` was added before the production API and wiring.

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationRedClear -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/PencilCanvasIdleCancellationTask2Tests/programmaticClearCancelsPendingIdleCommit
```

Result: exit 65, `** TEST FAILED **`.

Relevant compile failure:

```text
PencilCanvasIdleCancellationTask2Tests.swift:52:25: error: type 'DiaryCanvasView' has no member 'clear'
```

Result bundle: `/private/tmp/TheHuntedDiaryRemediationRedClear/Logs/Test/Test-TheHuntedDiary-2026.07.17_07-34-53-+0300.xcresult`

## Implementation

- Changed all six app/test Debug and Release `TARGETED_DEVICE_FAMILY` settings from `2` to `"1,2"`.
- Added an executable project assertion that requires exactly six device-family assignments and requires every parsed value to equal `1,2`.
- Added `TheHuntedDiaryUITests.swift`, which launches the app and verifies the `Clear handwriting` and `Settings` controls are present.
- Added `PencilCanvasIdleCommitter.cancelPendingCommit()` and reused it when replacing an earlier idle task.
- Moved committer state ownership to `DiaryCanvasView`, beside its existing mounted `PencilCanvasModel` ownership. `PencilCanvasView` now observes the injected model and retains the injected committer without creating a second `@StateObject` owner.
- Routed the actual Clear button through `DiaryCanvasView.clear(_:using:)`, which cancels the exact mounted committer before clearing the exact mounted model.
- Added deterministic coverage proving a pending callback does not fire after programmatic Clear and that the drawing is cleared.

The existing `Constants.pencilCanvasIdleCommitDelay = .milliseconds(2500)` is unchanged. The same model instance continues from `DiaryCanvasView` into `PencilCanvasView` and into the idle callback.

## GREEN evidence

### Project settings

Commands and results:

```bash
./scripts/assert-ios-26-deployment-targets.sh
# Verified 8 IPHONEOS_DEPLOYMENT_TARGET settings at 26.0.

./scripts/assert-universal-device-families.sh
# Verified 6 TARGETED_DEVICE_FAMILY settings at 1,2.
```

Both exited 0.

### Focused Clear/idle suite on iPhone

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationGreen -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/PencilCanvasIdleCancellationTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; 2 tests in 1 suite passed, including `programmaticClearCancelsPendingIdleCommit()`.

Result bundle: `/private/tmp/TheHuntedDiaryRemediationGreen/Logs/Test/Test-TheHuntedDiary-2026.07.17_07-36-45-+0300.xcresult`

An earlier method-level filter returned exit 0 but executed zero Swift Testing cases. That result was rejected as evidence; the suite-level rerun above executed and counted both tests.

### UI smoke test on iPhone

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationGreen -parallel-testing-enabled NO -only-testing:TheHuntedDiaryUITests
```

Result: exit 0, `** TEST SUCCEEDED **`; 1 XCTest passed. The UI-test executable loaded, launched the app, and found both asserted controls.

Result bundle: `/private/tmp/TheHuntedDiaryRemediationGreen/Logs/Test/Test-TheHuntedDiary-2026.07.17_07-37-13-+0300.xcresult`

### Existing canvas and idle-submission coverage on iPad

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationIPad -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/PencilCanvasExportTests -only-testing:TheHuntedDiaryTests/PencilCanvasIdleCancellationTask2Tests -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; 12 tests in 3 suites passed. This includes 2.5-second timing, new-stroke cancellation, clear cancellation, export/clear behavior, the Apple Vision submission route, and mounted-model preservation.

Result bundle: `/private/tmp/TheHuntedDiaryRemediationIPad/Logs/Test/Test-TheHuntedDiary-2026.07.17_07-38-02-+0300.xcresult`

### Test-bundle compilation

Command:

```bash
xcodebuild build-for-testing -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationCompile
```

Result: exit 0, `** TEST BUILD SUCCEEDED **`; the app, unit-test bundle, and UI-test executable compiled together for iPhone.

### Unsigned generic iOS build

Command:

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationGeneric CODE_SIGNING_ALLOWED=NO
```

Result: exit 0, `** BUILD SUCCEEDED **`; asset compilation explicitly used both `--target-device iphone` and `--target-device ipad` with minimum deployment target 26.0.

### Full unit target

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' -derivedDataPath /private/tmp/TheHuntedDiaryRemediationGreen -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests
```

Result: exit 0, `** TEST SUCCEEDED **`; 60 tests in 14 suites passed. In this current dirty workspace, all four `APIKeyStoreTests` passed instead of producing the four obsolete failures anticipated by the brief. No APIKeyStore production or test file was modified or committed by this checkpoint.

## Commit scope

Commit `4d2282405391fb4d684cf83dfcd15c4415300a23` contains exactly these six paths:

- `TheHuntedDiary.xcodeproj/project.pbxproj`
- `TheHuntedDiary/Diary/DiaryCanvasView.swift`
- `TheHuntedDiary/Diary/PencilCanvasView.swift`
- `TheHuntedDiaryTests/Diary/PencilCanvasIdleCancellationTask2Tests.swift`
- `TheHuntedDiaryUITests/TheHuntedDiaryUITests.swift`
- `scripts/assert-universal-device-families.sh`

No other dirty tracked or untracked path was staged. In particular, neither `TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift` nor `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift`, any APIKeyStore path, Apple Vision implementation/test, reply-font path, history path, workspace user state, progress file, plan, brief, or report was committed.

Scope note: `DiaryCanvasView.swift` and `PencilCanvasView.swift` already held the uncommitted canvas foundation on top of skeleton versions in `HEAD`. Because the remediation changes ownership and cancellation inside those exact files, and the committed Task 2 tests already depend on their types, the commit records their current complete implementations. No unrelated file was absorbed.

## Self-review

- Confirmed exactly six target-level device-family assignments are `1,2`; no project-level device-family override exists.
- Confirmed exactly eight deployment-target assignments remain `26.0`.
- Confirmed available iOS 26.5 simulators included both `iPhone 17` and `iPad Air 11-inch (M4)` before selecting destinations.
- Confirmed only `DiaryCanvasView` has `@StateObject` ownership of the mounted model and committer; `PencilCanvasView` does not create duplicate state ownership.
- Confirmed Clear cancels before clearing and the regression advances the deterministic clock through the full 2,500 ms.
- Confirmed the idle delay constant and mounted model identity did not change.
- Confirmed the existing Apple Vision submission-route tests passed unchanged.
- Confirmed the UI-test synchronized group now contributes a real Swift source and executable.
- Confirmed the prompt builder implementation/test, reply font, and APIKeyStore files have no commit diff.
- `git diff --cached --check` passed before commit; `git diff --check` passed after commit for remaining workspace changes.

## Concerns

- The brief predicted exactly four obsolete APIKeyStore failures, but this workspace currently passes all four APIKeyStore tests and all 60 unit tests. The checkpoint did not alter those files; this is a pre-existing workspace-state discrepancy to reconcile with the Task 9 expectation.
- Verification still emits pre-existing warnings/runtime diagnostics: `UIScreen.main` is deprecated on iOS 26, SwiftUI logs two “Publishing changes from within view updates” messages during test-host launch, App Intents metadata extraction reports no framework dependency, and the iOS 26.5 UI-test runtime reports duplicate accessibility loader classes. None caused a focused failure and none was changed in this checkpoint.
- The report remains uncommitted by design, matching the existing SDD report workflow and keeping the implementation commit limited to remediation paths.
