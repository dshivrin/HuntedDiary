# Task 2 Report: Correct the automatic local-recognition entry point

## Status

Implemented and verified. The automatic 2.5-second PencilKit idle path now enters `DiaryTurnController.submit(model:canvasSize:)`, retains the mounted canvas model and its drawing, uses the directly injected Apple Vision recognizer, and has no OpenAI image-recognition fallback or diagnostic result sheet/path.

Commit: `052edef Use local recognition for automatic diary submissions`

## Implementation

- Added `DiaryPageView.idleSubmissionRoute(controller:canvasSize:)` as the testable UI seam and made the rendered `DiaryCanvasView` use that route's handler.
- The route composes the real 2.5-second `PencilCanvasIdleCommitter` with `controller.submit(model:canvasSize:)`; it neither clears nor replaces the supplied `PencilCanvasModel`.
- Removed the Vision diagnostic sheet, `VisionTextRecognitionResult`, `testRecognizeText`, and the separate diagnostic recognizer dependency.
- Replaced the recognizer factory with one directly injected `any HandwritingRecognizer`; the production dependency is `DependencyContainer.appleVisionRecognizer`.
- Removed `HandwritingRecognitionPipeline` from the working tree and deleted `OpenAIImageRecognizer.swift`, eliminating network fallback from handwriting recognition. The OpenAI reply transport remains for Task 9.
- Retained `RecognitionResult.Source.openAI` solely for existing on-disk history decoding and documented that purpose in the enum.
- Added focused coverage for the idle seam/model preservation, empty Vision output, low-confidence nonempty Vision output, no second image-recognition path, and cancellation of an earlier idle callback by a new stroke.
- Added per-turn identity guards so cancellation-ignoring recognition or reply work from an older turn cannot mutate the current turn, history, or reply.

## Files

Production files in the Task 2 commit:

- `TheHuntedDiary/App/DependencyContainer.swift`
- `TheHuntedDiary/Diary/DiaryPageView.swift`
- `TheHuntedDiary/Diary/DiaryTurnController.swift`
- `TheHuntedDiary/Recognition/AppleVisionRecognizer.swift`
- `TheHuntedDiary/Recognition/RecognitionResult.swift`
- `TheHuntedDiary/Recognition/OpenAIImageRecognizer.swift` (deleted)

Focused test files in the Task 2 commit:

- `TheHuntedDiaryTests/Diary/DiaryIdleSubmissionTask2Tests.swift`
- `TheHuntedDiaryTests/Diary/PencilCanvasIdleCancellationTask2Tests.swift`
- `TheHuntedDiaryTests/Recognition/LocalRecognitionTask2Tests.swift`

`TheHuntedDiary/Recognition/HandwritingRecognizer.swift` is intentionally not in the commit: removing the uncommitted fallback pipeline restored that tracked file exactly to `HEAD`, leaving only the protocol and therefore no staged diff.

The pre-existing untracked `DiaryTurnControllerTests.swift` was compatibility-edited in the working tree to remove its diagnostic-only test and use the direct recognizer initializer. It is not staged, so unrelated controller coverage is not absorbed by this task. The obsolete untracked `RecognitionFallbackTests.swift` was replaced by the focused staged `LocalRecognitionTask2Tests.swift`.

## RED evidence

### Idle callback seam

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2DerivedData -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests
```

Expected RED result: exit 65, `** TEST FAILED **`.

Relevant failure:

```text
DiaryIdleSubmissionTask2Tests.swift:22:40: error: type 'DiaryPageView' has no member 'idleCommitHandler'
```

This proved the test required a real UI-to-controller seam that did not yet exist.

### Direct local recognizer dependency

Command: the same focused command after changing the test to require `recognizer:`.

Expected RED result: exit 65, `** TEST FAILED **`.

Relevant failures:

```text
error: extra argument 'recognizer' in call
error: missing arguments for parameters 'recognizerFactory', 'visionTestRecognizer' in call
```

This proved the controller still exposed the fallback-capable factory and diagnostic dependency.

### Reviewer regressions

The mandatory reviewer found that the first `submit(model:)` implementation created an `activeTask` and then delegated to `submit(image:)`, which cancelled that same task. Two tests were added before changing production code.

Expected RED result: exit 65, `** TEST FAILED **`.

Relevant runtime failures:

```text
automaticSubmissionDoesNotCancelItsOwnRecognitionTask: phase was .failed(...recognitionFailed); observedCancellation was true
staleRecognitionCompletionCannotOverwriteNewerTurn: recognizedText became "Stale local ink."; history contained both newest and stale turns
```

This proved both self-cancellation and mutation by a cancellation-ignoring stale completion.

The reviewer also requested that the idle seam cover timing and page wiring together. The integration test was changed first to require `DiaryPageView.idleSubmissionRoute` and drive a real `PencilCanvasIdleCommitter` through it.

Expected RED result: exit 65, `** TEST FAILED **`.

Relevant compile failure:

```text
Type 'DiaryPageView' has no member 'idleSubmissionRoute'
```

## GREEN evidence

### Initial seam GREEN

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2DerivedData -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; the seam test passed and verified one local-recognizer call, reply streaming/history append, and byte-for-byte unchanged PencilKit drawing data.

### Reviewer regressions GREEN

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2FocusedDerivedData -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; 5 tests passed. Automatic recognition observed no cancellation, a deliberately cancellation-ignoring older recognition could not overwrite the newer turn, and the page-owned route did not submit at 2499 ms but submitted after the final millisecond while preserving the drawing bytes.

### Local recognition policy GREEN

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2DerivedData -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests -only-testing:TheHuntedDiaryTests/LocalRecognitionTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; 5 focused tests passed. Empty local text failed with `.emptyRecognitionResult` before reply transport, while confidence `0.12` nonempty text completed with `.appleVision` history metadata.

### New-stroke cancellation GREEN

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2DerivedData -only-testing:TheHuntedDiaryTests/PencilCanvasIdleCancellationTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; only the newest 2.5-second idle callback fired. The first run exposed a test-harness scheduling race (`latestCommitCount` was checked after only one yield); the xcresult showed that exact assertion. The harness was corrected to use a bounded scheduler drain, with no production-code change.

### Focused Diary and Recognition groups

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2FocusedDerivedData -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/DiaryTurnControllerTests -only-testing:TheHuntedDiaryTests/DiaryIdleSubmissionTask2Tests -only-testing:TheHuntedDiaryTests/PencilCanvasExportTests -only-testing:TheHuntedDiaryTests/PencilCanvasIdleCancellationTask2Tests -only-testing:TheHuntedDiaryTests/AppleVisionRecognizerTests -only-testing:TheHuntedDiaryTests/LocalRecognitionTask2Tests
```

Result: exit 0, `** TEST SUCCEEDED **`; 22 tests in 6 suites passed in 0.111 seconds.

### Legacy history compatibility

Command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,OS=26.5,name=iPad Air 11-inch (M4)' -derivedDataPath /private/tmp/TheHuntedDiaryTask2FocusedDerivedData -parallel-testing-enabled NO -only-testing:TheHuntedDiaryTests/PlainTextHistoryStoreTests
```

Result: exit 0, `** TEST SUCCEEDED **`; 7 tests passed in 0.013 seconds, including the `.openAI` recognition-source round trip used for legacy history compatibility.

### Unsigned generic iOS build

Command:

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/TheHuntedDiaryTask2GenericBuild CODE_SIGNING_ALLOWED=NO
```

Result: exit 0, `** BUILD SUCCEEDED **`.

The first sandboxed generic build attempt was blocked by the Swift preview macro plugin sandbox (`sandbox_apply: Operation not permitted`). Re-running the identical command with the required out-of-sandbox permission succeeded.

## Structural verification

The following search returned no matches in production or tests:

```bash
rg -n 'testRecognizeText|VisionTextRecognitionResult|HandwritingRecognitionPipeline|OpenAIImageRecognizer|openAIImageRecognizer' TheHuntedDiary TheHuntedDiaryTests
```

`RecognitionResult.Source.openAI` remains in production only as the commented enum case needed by `PlainTextHistoryStore` raw-value decoding. No production recognizer constructs an OpenAI recognition result.

## Self-review

- Confirmed the view uses the same page-owned route exercised by the 2499/2500 ms integration test.
- Confirmed `submit(model:canvasSize:)` exports from but never clears or replaces the mounted model.
- Confirmed the 2.5-second constant and idle committer implementation were not changed.
- Confirmed low confidence is metadata only; nonempty Apple Vision text is not rejected or escalated to another recognizer.
- Confirmed empty Apple Vision text fails locally and reply transport is not invoked.
- Confirmed automatic submission does not cancel its own task and older cancellation-ignoring work is rejected by active-turn identity checks.
- Confirmed `DependencyContainer` has no OpenAI image recognizer and the controller has only one recognizer dependency.
- Confirmed diagnostic UI/controller symbols and fallback symbols are absent.
- Confirmed reply font, local history append/pruning, and Apple Vision aggregation behavior were not changed.
- Confirmed `TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift` and `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift` were not modified by Task 2.
- `git diff --check` passed.

## Commit scope

Only the nine production/test paths listed above are intended for staging. All other tracked and untracked workspace changes remain unstaged.

`DiaryPageView.swift`, `DiaryTurnController.swift`, and `AppleVisionRecognizer.swift` contained large pre-existing uncommitted implementations on top of skeleton files in `HEAD`. Their whole relevant implementations are necessary to represent and exercise this task, so those focused files are included as permitted by the task brief. No unrelated settings, transport, prompt-builder, history, font, or canvas implementation file is staged.

## Concerns

- A sandboxed verification attempt could not connect to `CoreSimulatorService`, and a sandboxed generic build could not launch the Swift preview macro plugin. The identical commands passed outside the sandbox; these were environmental permission failures, not product failures.
- The working tree already emits unrelated warnings from pre-existing uncommitted code/tests: `UIScreen.main` deprecation in `PencilCanvasView.swift`, actor-isolation warnings in `AppleVisionRecognizerTests.swift` and `OpenAIClientTests.swift`, and SwiftUI runtime messages about publishing during view updates. Task 2 introduced no warning in its changed files.
- Broader OpenAI reply transport/API-key removal is intentionally deferred to Task 9, per the brief.
