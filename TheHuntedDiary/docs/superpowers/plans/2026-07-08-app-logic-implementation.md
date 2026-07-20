# The Hunted Diary App Logic Implementation Plan

> **Historical plan:** This direct-API MVP plan is retained only for project provenance. It was superseded by `2026-07-15-shortcuts-reply-refactor.md`; its API-key, direct transport, streaming, billing, image-fallback, and iOS 18 statements do not describe the current app.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP app logic for an iPadOS diary: user writes with Apple Pencil, the app recognizes English handwriting, sends text and recent history to OpenAI with the user's API key, streams a diary-style reply, renders it with a handwriting font, and stores editable plain-text history locally.

**Architecture:** Keep the app native and local-first. `Diary` owns the user flow and state machine, `Recognition` owns Apple Vision plus OpenAI fallback transcription, `OpenAI` owns request construction and stream parsing, `History` owns plain-text local storage, and `Settings` owns key storage and future font selection. No backend is used.

**Tech Stack:** SwiftUI, PencilKit, Vision, Security/Keychain, URLSession, Swift Testing, local Markdown files, bundled OFL fonts.

## Global Constraints

- Do not implement a backend.
- Store the user's OpenAI API key in Keychain only.
- Store conversation history as plain text, divided by turn so the user and automatic pruning can delete parts of it.
- Store text history only for MVP, not images.
- Recognition is English-only for MVP.
- Use Apple handwriting/text recognition first, OpenAI image transcription as fallback.
- Let the user choose OpenAI `store` behavior in Settings. Default to `store: false`, but support `store: true` for user testing.
- Render assistant replies with bundled handwriting-style fonts, not generated handwriting strokes.
- Use one free handwriting-style font for MVP, suitable for public redistribution, with the license file committed beside the font file. Add more fonts later without changing the app flow.
- Product decision: the internal model instructions may directly reference Tom Riddle's spirit from the Harry Potter books. Based on the project review so far, this internal prompt reference is accepted as not violating copyright by itself. Public-facing app copy should still avoid official franchise naming unless a later legal/product decision explicitly approves it.
- Target iPadOS 18.0 minimum and keep iPadOS 26-only APIs optional.
- Target iPad only. Remove iPhone support from project settings, app assumptions, previews, and UI test launch assumptions unless a future requirement explicitly adds iPhone support.
- Remove template leftovers that do not support this goal, including SwiftData sample files, stale sample tests, old target membership, and generated config references that keep deleted sample files alive.
- Build verification should use `/private/tmp` for DerivedData to avoid file-provider extended attributes under Documents.

## Domain Model Rules

- `ConversationTurn.id` is a stable string safe for filenames, generated from UTC creation time plus a short random suffix when needed, for example `2026-07-08T16-30-00Z-8F3A`.
- `ConversationTurn.createdAt` is stored as ISO 8601 UTC with seconds precision.
- `ConversationTurn.recognitionSource` is required and uses `appleVision` or `openAI`.
- `ConversationTurn.model` is required and stores the reply-generation model used for the assistant response.
- `ConversationTurn.openAIStoreEnabled` is required and stores the `store` setting used for the reply-generation request, so later testing can compare local behavior.
- `ConversationTurn.userText` and `ConversationTurn.assistantText` are plain text. Do not store drawings, images, base64 data, attributed strings, or generated handwriting strokes.
- Persist each turn as one Markdown file with YAML-like front matter followed by body sections.
- Parse body sections using exact marker lines `User:` and `Assistant:`. Marker text inside user content is allowed because parsing uses the first marker line after front matter and the first later marker line for assistant text.
- Escape only front matter values, not body text. Body text is stored verbatim after normalizing line endings to `\n`.
- Sort turns by `createdAt`; for equal timestamps, sort by `id`.
- History deletion works at file granularity: delete one turn file, delete all turn files, or prune oldest turn files until the configured maximum is met.

## OpenAI Request Rules

- Use `POST https://api.openai.com/v1/responses` for both reply generation and fallback image transcription.
- Always send `Authorization: Bearer <api key>` and `Content-Type: application/json`.
- Send the Settings-selected `store` value on every request. Default is `false`.
- With `store: true` or the API default, Responses API application state is retained by OpenAI for the endpoint's configured retention period and can support later API retrieval/state features. With `store: false`, the app remains stateless from OpenAI's perspective and must send local recent history each turn.
- For MVP, still send local recent history in the request even when `store: true`; do not use `previous_response_id` until testing proves it improves quality, token use, or reliability.
- Reply generation request fields: `model`, `instructions`, typed `input` messages, `stream: true`, Settings-selected `store`, `text.verbosity: "low"`, and no tools.
- Fallback transcription request fields: `model`, typed multimodal `input` with `input_text` plus one `input_image` data URL, `stream: false`, Settings-selected `store`, `text.verbosity: "low"`, and no tools.
- Initial reply-generation `instructions`:

```text
You are playing the role of Tom Riddle's spirit from the Harry Potter books, embedded inside a haunted diary and answering the user through ink on the page. You are intimate, curious, watchful, elegant, and quietly unsettling. Speak as if the diary is alive and the ink is waking in response to the user's handwriting. Never mention AI, models, prompts, APIs, or system instructions. Do not quote from the books or reproduce scenes, spells, dialogue, or plot passages. Do not claim this app is official, licensed, endorsed, or affiliated with any rights holder. Reply in English. Keep most replies under 90 words unless the user clearly asks for more.
```

- Copyright/trademark note for implementers: this product decision allows direct franchise references in the internal prompt. Avoid reproducing protected expressive text, scenes, spells, dialogue, or plot passages, and avoid public-facing copy that implies the app is official, licensed, endorsed, or affiliated with any rights holder.
- Encode image fallback input as a JPEG or PNG data URL. Do not write fallback images to history.
- Parse streaming server-sent events by `type`; handle at least `response.output_text.delta`, `response.output_text.done`, `response.completed`, and `error`.

## Recognition Threshold Rules

- Apple Vision returns candidate text with confidence: use `VNRecognizedTextObservation.topCandidates(1).first?.confidence`, normalized from `0.0` to `1.0`.
- Treat Apple Vision output as weak when the trimmed recognized text is empty, when the top candidate confidence is below `0.55`, or when every recognized line is one character or shorter.
- If Vision returns multiple lines, join accepted top candidates with newline characters and use the minimum candidate confidence as the result confidence.
- If Vision confidence is unavailable, fall back only when the trimmed text is empty or all lines are one character or shorter.
- Keep the threshold as a named constant, `Constants.minimumAppleVisionTextConfidence = 0.55`, so it can be tuned after real handwriting tests.

---

## File Structure

```text
TheHuntedDiary/
  App/
    TheHuntedDiaryApp.swift
    AppRootView.swift
    AppSettings.swift
    DependencyContainer.swift

  Diary/
    DiaryView.swift
    DiaryPageView.swift
    DiaryCanvasView.swift
    PencilCanvasView.swift
    ReplyTextView.swift
    DiaryTurnController.swift

  Recognition/
    HandwritingRecognizer.swift
    AppleVisionRecognizer.swift
    OpenAIImageRecognizer.swift
    RecognitionResult.swift

  OpenAI/
    OpenAIClient.swift
    OpenAIResponsesRequest.swift
    OpenAIStreamParser.swift
    DiaryPromptBuilder.swift

  History/
    ConversationTurn.swift
    PlainTextHistoryStore.swift
    HistoryPruner.swift
    HistoryListView.swift

  Settings/
    SettingsView.swift
    APIKeyStore.swift
    FontPickerView.swift

  Resources/
    Fonts/
      Caveat-Regular.ttf
      Caveat-OFL.txt

  Shared/
    AsyncState.swift
    AppError.swift
    Constants.swift
```

Tests:

```text
TheHuntedDiaryTests/
  App/
    AppSettingsTests.swift
  History/
    PlainTextHistoryStoreTests.swift
  OpenAI/
    DiaryPromptBuilderTests.swift
    OpenAIResponsesRequestTests.swift
    OpenAIStreamParserTests.swift
    OpenAIClientTests.swift
  Recognition/
    AppleVisionRecognizerTests.swift
    RecognitionFallbackTests.swift
  Diary/
    PencilCanvasExportTests.swift
    DiaryTurnControllerTests.swift
  Settings/
    APIKeyStoreTests.swift
  Shared/
    AppErrorTests.swift
```

## Stage Tracking

Each task is also a stage. Agentic workers must update the stage metadata as they work:

- `Completed: false` means the task has not passed its listed verification.
- Change `Completed` to `true` only after the task's code, tests, and build checks pass.
- Work stages in ascending numeric order unless the user explicitly changes the order.
- `Must complete first` is blocking. Do not start a task until every listed prerequisite task is marked `Completed: true`.
- Keep both tracking locations in sync: update the stage table row and the task's own `Completed` metadata in the same edit. If they disagree, the task is not complete.

| Stage | Task | Completed | Must complete first |
| --- | --- | --- | --- |
| 1 | Project Settings and App Shell | true | None |
| 2 | Plain Text History | true | Task 1 |
| 3 | Prompt Builder | true | Task 2 |
| 4 | API Key Storage and Settings | true | Task 1, Task 2 |
| 5 | OpenAI Responses Client | true | Task 3, Task 4 |
| 6 | Pencil Canvas | true | Task 1 |
| 7 | Recognition Pipeline | true | Task 5, Task 6 |
| 8 | Diary Turn Controller | true | Task 2, Task 3, Task 5, Task 6, Task 7 |
| 9 | Reply Rendering and Fonts | true | Task 1, Task 4 |
| 10 | Error and Recovery UX | true | Task 4, Task 8 |

## Task 1: Project Settings and App Shell

**Stage:** 1
**Completed:** true
**Must complete first:** None

**Files:**
- Modify: `TheHuntedDiary.xcodeproj/project.pbxproj`
- Modify: `TheHuntedDiary/App/TheHuntedDiaryApp.swift`
- Modify: `TheHuntedDiary/App/AppRootView.swift`
- Modify: `TheHuntedDiary/App/AppSettings.swift`
- Modify: `TheHuntedDiary/App/DependencyContainer.swift`

**Interfaces:**
- Produces: `AppSettings`, `DependencyContainer`, root wiring for app services.
- Consumes: existing `DiaryView`.

**Tests / Verification:**
- Build with the stage build command below.
- Confirm `project.pbxproj` has `IPHONEOS_DEPLOYMENT_TARGET = 18.0` for app, unit tests, and UI tests.
- Confirm `TARGETED_DEVICE_FAMILY = 2`.
- Confirm stale SwiftData/template files are absent from disk and target membership.

- [x] Set the iPadOS deployment target to `18.0`.
- [x] Set the app, unit test, and UI test deployment targets to `18.0`.
- [x] Set `TARGETED_DEVICE_FAMILY = 2` for iPad-only support.
- [x] Remove iPhone supported-interface settings unless Xcode requires harmless generated defaults.
- [x] Remove any remaining SwiftData sample assumptions from the app shell.
- [x] Delete stale sample files and tests, including `ContentView.swift`, `Item.swift`, old root-level `TheHuntedDiaryApp.swift`, and `TheHuntedDiaryTests.swift`, if they still exist on disk or in target membership.
- [x] Remove stale target membership, build settings, or generated config references that keep deleted sample files active.
- [x] Add a small app-level dependency container for settings, history store, API key store, recognition, and OpenAI client.
- [x] Keep `AppRootView` focused on app-level navigation and settings presentation.
- [x] Verify with:

```bash
xcodebuild \
  -project "/Users/dima/Documents/Tom's Diary/TheHuntedDiary/TheHuntedDiary.xcodeproj" \
  -scheme TheHuntedDiary \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /private/tmp/TheHuntedDiaryDerivedData \
  build
```

## Task 2: Plain Text History

**Stage:** 2
**Completed:** true
**Must complete first:** Task 1 completed: true

**Files:**
- Modify: `TheHuntedDiary/History/ConversationTurn.swift`
- Modify: `TheHuntedDiary/History/PlainTextHistoryStore.swift`
- Modify: `TheHuntedDiary/History/HistoryPruner.swift`
- Modify: `TheHuntedDiary/History/HistoryListView.swift`
- Modify: `TheHuntedDiaryTests/History/PlainTextHistoryStoreTests.swift`

**Interfaces:**
- Produces: `ConversationTurn`, `PlainTextHistoryStore`, recent-turn loading, single-turn deletion, all-history deletion, max-count pruning, and the Markdown persistence rules from `Domain Model Rules`.
- Consumes: Foundation file APIs.

**Tests:**
- `PlainTextHistoryStoreTests.testAppendCreatesOneMarkdownFilePerTurn`
- `PlainTextHistoryStoreTests.testLoadRecentReturnsOldestFirstWithinLimit`
- `PlainTextHistoryStoreTests.testDeleteOneRemovesOnlyMatchingTurn`
- `PlainTextHistoryStoreTests.testDeleteAllRemovesAllTurnFiles`
- `PlainTextHistoryStoreTests.testPruneOldestTurnsKeepsMaximumStoredTurns`
- `PlainTextHistoryStoreTests.testRoundTripPreservesBodyMarkersAndFrontMatterDelimiters`
- `PlainTextHistoryStoreTests.testRoundTripPersistsRecognitionModelAndOpenAIStoreFlag`

- [x] Store each conversation turn as one Markdown file under Application Support.
- [x] Use one file per turn so user deletion and automatic deletion are simple.
- [x] Update `ConversationTurn` to include `id: String`, `createdAt: Date`, `recognitionSource: RecognitionResult.Source`, `model: String`, `openAIStoreEnabled: Bool`, `userText: String`, and `assistantText: String`.
- [x] Use a stable file format:

```markdown
---
id: 2026-07-08T16-30-00Z
createdAt: 2026-07-08T16:30:00Z
recognition: appleVision
model: gpt-5.5
openAIStoreEnabled: false
---

User:
What did you write before?

Assistant:
I remember enough to know you are curious.
```

- [x] Add tests for append, load recent, delete one, delete all, and prune oldest turns.
- [x] Add tests for body text containing `---`, `User:`, and `Assistant:` so front matter and body parsing stay stable.
- [x] Do not store drawings or image data in history.

## Task 3: Prompt Builder

**Stage:** 3
**Completed:** true
**Must complete first:** Task 2 completed: true

**Files:**
- Modify: `TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift`
- Create: `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift`

**Interfaces:**
- Consumes: `[ConversationTurn]`, current recognized user text, app settings.
- Produces: request-ready prompt input for `OpenAIClient`.

**Tests:**
- `DiaryPromptBuilderTests.testIncludesTomRiddleDiaryInstructions`
- `DiaryPromptBuilderTests.testIncludesCopyrightAndAffiliationGuardrails`
- `DiaryPromptBuilderTests.testRecentTurnsAreIncludedOldestFirst`
- `DiaryPromptBuilderTests.testCurrentRecognizedTextIsLastUserInput`
- `DiaryPromptBuilderTests.testPromptIsEnglishOnlyForMVP`
- `DiaryPromptBuilderTests.testPromptDoesNotContainImageData`

- [x] Use the initial reply-generation `instructions` from `OpenAI Request Rules`, including the Tom Riddle spirit role and the guardrails against quoting source text or implying official affiliation.
- [x] Include recent turns oldest-first.
- [x] Include the current recognized text as the current user message.
- [x] Keep prompt language English-only for MVP.
- [x] Add tests that verify persona inclusion, recent-turn ordering, current user text, and absence of image data.

## Task 4: API Key Storage and Settings

**Stage:** 4
**Completed:** true
**Must complete first:** Task 1 completed: true; Task 2 completed: true

**Files:**
- Modify: `TheHuntedDiary/Settings/APIKeyStore.swift`
- Modify: `TheHuntedDiary/Settings/SettingsView.swift`
- Modify: `TheHuntedDiary/App/AppSettings.swift`

**Interfaces:**
- Produces: Keychain-backed `save`, `load`, and `delete` API key operations.
- Consumes: Security framework.

**Tests:**
- `APIKeyStoreTests.testSaveThenLoadReturnsStoredKey`
- `APIKeyStoreTests.testOverwriteReplacesStoredKey`
- `APIKeyStoreTests.testDeleteRemovesStoredKey`
- `APIKeyStoreTests.testDeleteMissingKeyDoesNotThrow`
- `AppSettingsTests.testDefaultsUseOpenAIStoreOff`
- `AppSettingsTests.testCanToggleOpenAIStoreOnAndOff`

- [x] Store API keys in Keychain, not `UserDefaults`.
- [x] Add settings fields for API key and model.
- [x] Add a Settings toggle for OpenAI response storage, labeled plainly, defaulting to off. Suggested label: `Allow OpenAI response storage`.
- [x] Add helper copy under the toggle: `Off sends store: false. On sends store: true so you can compare quality, token use, and behavior during testing.`
- [x] Add clear-history action.
- [x] Add short privacy copy that handwriting/text is sent to OpenAI for transcription fallback and reply generation, the OpenAI storage toggle controls `store`, and local plain-text history is stored on device.
- [x] Keep font picker minimal or hidden until font files are added.

## Task 5: OpenAI Responses Client

**Stage:** 5
**Completed:** true
**Must complete first:** Task 3 completed: true; Task 4 completed: true

**Files:**
- Modify: `TheHuntedDiary/OpenAI/OpenAIClient.swift`
- Modify: `TheHuntedDiary/OpenAI/OpenAIResponsesRequest.swift`
- Modify: `TheHuntedDiary/OpenAI/OpenAIStreamParser.swift`
- Create: `TheHuntedDiaryTests/OpenAI/OpenAIStreamParserTests.swift`

**Interfaces:**
- Consumes: API key, model, prompt input, optional image data for fallback transcription, and the `OpenAI Request Rules`.
- Produces: async stream of text deltas and final completion.

**Tests:**
- `OpenAIResponsesRequestTests.testReplyRequestEncodesInstructionsTypedInputStreamAndStoreFalse`
- `OpenAIResponsesRequestTests.testReplyRequestEncodesStoreTrueWhenEnabled`
- `OpenAIResponsesRequestTests.testImageTranscriptionRequestEncodesInputImageDataURL`
- `OpenAIResponsesRequestTests.testRequestsDoNotIncludeTools`
- `OpenAIClientTests.testRequestAddsBearerAuthorizationAndJSONContentType`
- `OpenAIClientTests.testReplyStreamYieldsTextDeltasUntilCompletion`
- `OpenAIStreamParserTests.testParsesOutputTextDelta`
- `OpenAIStreamParserTests.testParsesOutputTextDone`
- `OpenAIStreamParserTests.testParsesCompleted`
- `OpenAIStreamParserTests.testParsesErrorEvent`
- `OpenAIStreamParserTests.testIgnoresUnknownEvents`

- [x] Use `URLSession`.
- [x] Call `POST https://api.openai.com/v1/responses`.
- [x] Model requests with enough structure for both text reply generation and image fallback transcription. Do not keep `OpenAIResponsesRequest` as only `{ model, input: String }`.
- [x] Add request fields for `instructions`, typed message input, optional image data URL content, `stream`, `store`, and `text.verbosity`.
- [x] Set `store` from the Settings toggle on every request.
- [x] Add tests proving both `store: false` and `store: true` encode correctly.
- [x] Keep OpenAI-hosted tools disabled for MVP.
- [x] Support `stream: true` for reply generation.
- [x] Parse `response.output_text.delta`, `response.output_text.done`, `response.completed`, and `error` events.
- [x] Keep model configurable through settings.
- [x] Add parser tests for text delta, completion, and error events.

## Task 6: Pencil Canvas

**Stage:** 6
**Completed:** true
**Must complete first:** Task 1 completed: true

**Files:**
- Modify: `TheHuntedDiary/Diary/PencilCanvasView.swift`
- Modify: `TheHuntedDiary/Diary/DiaryCanvasView.swift`
- Modify: `TheHuntedDiary/Diary/DiaryPageView.swift`

**Interfaces:**
- Produces: `PKDrawing` updates, exported handwriting image, clear/reset actions.
- Consumes: PencilKit.

**Tests:**
- `PencilCanvasExportTests.testEmptyDrawingExportReturnsNilOrBlankRejectedImage`
- `PencilCanvasExportTests.testNonEmptyDrawingExportsImage`
- `PencilCanvasExportTests.testClearRemovesDrawingBeforeNextExport`
- `PencilCanvasExportTests.testIdleCommitFiresAfterConfiguredDelayUsingTestClock`

- [x] Wrap `PKCanvasView` in SwiftUI.
- [x] Capture drawing changes.
- [x] Add an idle commit timer, roughly 2.5 seconds after the last drawing change.
- [x] Export the current drawing area as an image for recognition fallback.
- [x] Keep the canvas visible while recognition is running so the user does not lose work on failure.

## Task 7: Recognition Pipeline

**Stage:** 7
**Completed:** true
**Must complete first:** Task 5 completed: true; Task 6 completed: true

**Files:**
- Modify: `TheHuntedDiary/Recognition/HandwritingRecognizer.swift`
- Modify: `TheHuntedDiary/Recognition/AppleVisionRecognizer.swift`
- Modify: `TheHuntedDiary/Recognition/OpenAIImageRecognizer.swift`
- Modify: `TheHuntedDiary/Recognition/RecognitionResult.swift`
- Create: `TheHuntedDiaryTests/Recognition/RecognitionFallbackTests.swift`

**Interfaces:**
- Consumes: exported handwriting image.
- Produces: `RecognitionResult`.

**Tests:**
- `AppleVisionRecognizerTests.testAggregatesMultipleRecognizedLinesWithNewlines`
- `AppleVisionRecognizerTests.testUsesMinimumCandidateConfidence`
- `RecognitionFallbackTests.testEmptyAppleTextUsesOpenAIFallback`
- `RecognitionFallbackTests.testLowAppleConfidenceBelowThresholdUsesOpenAIFallback`
- `RecognitionFallbackTests.testAppleConfidenceAtThresholdSkipsOpenAIFallback`
- `RecognitionFallbackTests.testUnavailableConfidenceWithNonEmptyTextSkipsFallback`
- `RecognitionFallbackTests.testOpenAIResultTracksOpenAISource`

- [x] Implement Apple Vision recognition first.
- [x] Fallback to OpenAI image transcription when Apple Vision returns empty or weak text according to `Recognition Threshold Rules`.
- [x] Use this OpenAI fallback instruction:

```text
Transcribe the handwritten English text in this image. Return only the user's words. If illegible, return your best attempt.
```

- [x] Track recognition source as `appleVision` or `openAI`.
- [x] Add tests with mock recognizers to verify fallback behavior for empty text, low confidence below `0.55`, usable confidence at or above `0.55`, and unavailable confidence with non-empty text.

## Task 8: Diary Turn Controller

**Stage:** 8
**Completed:** true
**Must complete first:** Task 2 completed: true; Task 3 completed: true; Task 5 completed: true; Task 6 completed: true; Task 7 completed: true

**Files:**
- Modify: `TheHuntedDiary/Diary/DiaryTurnController.swift`
- Modify: `TheHuntedDiary/Diary/DiaryView.swift`
- Modify: `TheHuntedDiary/Diary/DiaryPageView.swift`
- Modify: `TheHuntedDiary/Shared/AsyncState.swift`
- Modify: `TheHuntedDiary/Shared/AppError.swift`

**Interfaces:**
- Consumes: canvas image export, recognizer, prompt builder, OpenAI client, history store.
- Produces: UI state for listening, recognizing, sending, streaming reply, completed, and failed states.

**Tests:**
- `DiaryTurnControllerTests.testSuccessfulTurnRecognizesBuildsPromptStreamsAndSavesHistory`
- `DiaryTurnControllerTests.testMissingAPIKeyMovesToFailedStateAndRequestsSettings`
- `DiaryTurnControllerTests.testRecognitionFailurePreservesDrawingAndAllowsRetry`
- `DiaryTurnControllerTests.testOpenAIFailurePreservesRecognizedTextAndAllowsRetry`
- `DiaryTurnControllerTests.testHistoryWriteFailureIsVisibleButDoesNotDiscardReply`
- `DiaryTurnControllerTests.testRetryUsesExistingDrawingOrRecognizedTextDependingOnFailureStage`

- [x] Model the flow as a small explicit state machine.
- [x] On idle commit, export image and run recognition.
- [x] Build prompt from recognized text and recent history.
- [x] Stream reply text into UI state.
- [x] Append completed turn to history.
- [x] On failure, keep the drawing and expose retry.

## Task 9: Reply Rendering and Fonts

**Stage:** 9
**Completed:** true
**Must complete first:** Task 1 completed: true; Task 4 completed: true

**Files:**
- Modify: `TheHuntedDiary/Diary/ReplyTextView.swift`
- Modify: `TheHuntedDiary/Settings/FontPickerView.swift`
- Add: `TheHuntedDiary/Resources/Fonts/<font>.ttf`
- Add: `TheHuntedDiary/Resources/Fonts/<font>-OFL.txt`

**Interfaces:**
- Consumes: streamed assistant text and selected font name.
- Produces: handwriting-style text rendering.

**Tests / Verification:**
- Build verification proves the font file and license are included without target membership errors.
- `AppSettingsTests.testDefaultFontIsBundledCaveatRegular`
- `AppSettingsTests.testOnlyBundledFontIsExposedForMVP`
- Manual UI check: `ReplyTextView` renders non-empty reply text with the bundled font and no text clipping on iPad simulator.

- [x] Add exactly one OFL font for MVP: Caveat Regular.
- [x] Commit `Caveat-OFL.txt` beside `Caveat-Regular.ttf`.
- [x] Register fonts in the app bundle as needed.
- [x] Render reply text with a handwriting-style font.
- [x] Animate reveal by character, word, or line.
- [x] Keep font selection data-driven but expose only the single bundled font in MVP. Additional fonts can be added later by extending the font list and committing each license.

## Task 10: Error and Recovery UX

**Stage:** 10
**Completed:** true
**Must complete first:** Task 4 completed: true; Task 8 completed: true

**Files:**
- Modify: `TheHuntedDiary/Shared/AppError.swift`
- Modify: `TheHuntedDiary/Diary/DiaryView.swift`
- Modify: `TheHuntedDiary/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: errors from Keychain, recognition, OpenAI, and history writing.
- Produces: user-visible recovery paths.

**Tests:**
- `AppErrorTests.testMissingAPIKeyMessageIsConciseAndNonTechnical`
- `AppErrorTests.testRecognitionFailureMessageMentionsRetryWithoutLosingDrawing`
- `AppErrorTests.testOpenAIFailureMessageMentionsRetryWithoutLosingText`
- `AppErrorTests.testHistoryWriteFailureMessageIsNonBlocking`
- `DiaryTurnControllerTests.testErrorRecoveryRoutesMatchAppErrorCases`

- [x] Missing API key opens settings.
- [x] Recognition failure preserves drawing and offers retry.
- [x] OpenAI failure preserves recognized text and offers retry.
- [x] History write failure is non-blocking and visible.
- [x] Keep errors concise and non-technical.

## Verification

Use this build command:

```bash
xcodebuild \
  -project "/Users/dima/Documents/Tom's Diary/TheHuntedDiary/TheHuntedDiary.xcodeproj" \
  -scheme TheHuntedDiary \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /private/tmp/TheHuntedDiaryDerivedData \
  build
```

Use Swift Testing for pure logic:

- `PlainTextHistoryStoreTests`: append, load recent, delete one, delete all, prune.
- `DiaryPromptBuilderTests`: Tom Riddle instructions, guardrails, recent turns, current user text, no image data.
- `OpenAIResponsesRequestTests`: typed text/image request encoding, `store: false`, `store: true`, no tools.
- `OpenAIClientTests`: headers and streaming client behavior with a mocked URL protocol.
- `OpenAIStreamParserTests`: text delta, text done, completion, error, unknown events.
- `RecognitionFallbackTests`: weak Apple result triggers OpenAI fallback.
- `AppleVisionRecognizerTests`: line joining and confidence aggregation.
- `APIKeyStoreTests`: save, load, overwrite, delete.
- `DiaryTurnControllerTests`: success, failure, retry, non-blocking history write.
- `AppSettingsTests`: default model, default store toggle off, bundled font list.
- `AppErrorTests`: concise user-facing recovery messages.

## Milestones

Milestones follow the stage table. A milestone is complete only when every included task has `Completed: true` in both the stage table and the task metadata.

### Milestone 1: Durable Backbone

Complete Stages 1-4:

1. Project settings and app shell.
2. Plain text history store with the domain model rules above.
3. Prompt builder using the Tom Riddle diary instructions and guardrails.
4. Keychain API key store and Settings storage controls.

This creates the durable app backbone before touching PencilKit, Vision, live OpenAI streaming, or visual polish.

### Milestone 2: Input and OpenAI Plumbing

Complete Stages 5-7:

1. OpenAI request models, client, streaming parser, and store toggle encoding.
2. Pencil canvas wrapper, drawing capture, idle commit, and image export.
3. Recognition pipeline with Apple Vision first and OpenAI image fallback.

This creates a testable path from handwriting image to recognized text and OpenAI response plumbing without yet wiring the full user turn.

### Milestone 3: End-to-End Diary Turn

Complete Stage 8:

1. Diary turn controller state machine.
2. End-to-end flow from idle drawing commit through recognition, prompt construction, streaming reply, and local history append.
3. Retry behavior for recognition and OpenAI failures.

This is the first milestone where the core diary interaction should work end to end.

### Milestone 4: Presentation and Recovery

Complete Stages 9-10:

1. One bundled handwriting font, Caveat Regular, with license committed beside it.
2. Reply rendering with handwriting-style text and reveal animation.
3. Error and recovery UX for missing key, recognition failure, OpenAI failure, and history write failure.

This completes the MVP app logic and user-facing recovery paths.
