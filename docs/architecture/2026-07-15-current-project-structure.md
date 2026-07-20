# The Hunted Diary — Current Project Structure

> **Document status (2026-07-18): Pre-refactor historical snapshot.** This file records the repository as scanned before the approved Shortcut reply refactor was executed. Its API-key, direct OpenAI transport, streaming, billing, and image-fallback descriptions are retained only as migration provenance and are not the current application architecture. The implemented architecture is defined by `docs/superpowers/plans/2026-07-15-shortcuts-reply-refactor.md` and the current setup workflow by `docs/guides/create-toms-diary-reply-shortcut.md`.

**Scanned:** 2026-07-15
**Project:** `TheHuntedDiary/TheHuntedDiary.xcodeproj`
**Current deployment target:** iOS/iPadOS 26.0 / Swift 5 language mode (`SWIFT_VERSION = 5.0`) under Xcode 26.6

**Historical baseline:** Before the Shortcut refactor, the app and test configurations explicitly targeted iOS 18.0. All project, app, unit-test, and UI-test configurations now use `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; the refactor removes obsolete iOS 18 compatibility branches and deprecated foreground-intent APIs.

## Purpose and current behaviour

The Hunted Diary is a SwiftUI/PencilKit diary. A person writes on a canvas; after a 2.5-second idle period, the app exports the drawing as a `UIImage`, recognizes handwriting, builds a prompt from the recognised text and local history, streams a reply, displays it in a handwriting font, and persists the completed turn locally.

The app currently contains an OpenAI Responses API implementation for two roles:

1. GPT-based fallback handwriting recognition when Apple Vision is empty, low-confidence, or mostly one-character lines.
2. Streaming reply generation using an API key stored in the Keychain.

## Project history and provenance

The nested `TheHuntedDiary` repository has one Git commit:

| Date | Commit | Message | What it contains |
|---|---|---|---|
| 2026-07-08 | `f7316f3` | `initial commit` | Xcode project shell, placeholder feature files, the original implementation plan, and initial history test scaffolding. |

The present implementation is substantially ahead of that committed snapshot. `git status` shows the completed app logic as uncommitted modifications and new files, so the Git log alone is not a reliable description of the current design.

The preserved planning/work records explain the intended sequence:

1. **App shell and iPadOS baseline** — iPadOS 18.0 target, app root, dependency container, and Settings presentation.
2. **Plain-text history** — per-turn Markdown history with pruning and front-matter tests.
3. **Prompt construction** — fixed diary persona instructions plus oldest-first recent history.
4. **API-key Settings** — Keychain storage, model/store controls, privacy copy, font picker.
5. **OpenAI Responses transport** — request encoding, SSE parser, streaming reply client, and image transcription fallback.
6. **Canvas and recognition** — PencilKit idle commit after 2.5 seconds, Apple Vision recognition, and OpenAI fallback thresholds.
7. **Turn/recovery UI** — the `DiaryTurnController` state machine, streamed reply display, local history write, retries, and font support.

`docs/superpowers/plans/2026-07-08-app-logic-implementation.md` marks all ten original stages complete; `.superpowers/sdd/progress.md` separately notes completed work on the app shell, history, and OpenAI unit/build verification. The documents conflict only on the repository state at the time they were written (the progress file says no initial commit, while Git now has one); the code and plan agree on the implemented architecture.

### Refactor relevance

The previous plan intentionally made OpenAI a first-class app service. The Shortcut refactor is therefore a replacement of the original core generation boundary, not an additive integration. It must remove the Settings, Keychain, recognition fallback, transport, error, test, and history metadata assumptions introduced by stages 4–8 while preserving the local-first parts from stages 1, 2, 6, 7, and 9.

## Directory map

| Area | Files | Responsibility |
|---|---|---|
| App composition | `App/TheHuntedDiaryApp.swift`, `App/AppRootView.swift`, `App/DependencyContainer.swift`, `App/AppSettings.swift` | Starts the app, owns process-wide dependencies, displays the diary and Settings sheet. |
| Diary UI and input | `Diary/DiaryView.swift`, `Diary/DiaryPageView.swift`, `Diary/DiaryCanvasView.swift`, `Diary/PencilCanvasView.swift`, `Diary/ReplyTextView.swift` | Owns the canvas, idle detection, reply rendering, error banner, and settings navigation. |
| Turn orchestration | `Diary/DiaryTurnController.swift` | Main-actor state machine for export, recognition, prompt creation, API streaming, history writes, and retries. |
| Handwriting recognition | `Recognition/AppleVisionRecognizer.swift`, `Recognition/HandwritingRecognizer.swift`, `Recognition/OpenAIImageRecognizer.swift`, `Recognition/RecognitionResult.swift` | Apple Vision OCR and the OpenAI image fallback pipeline. |
| Prompt and API transport | `OpenAI/DiaryPromptBuilder.swift`, `OpenAI/OpenAIClient.swift`, `OpenAI/OpenAIResponsesRequest.swift`, `OpenAI/OpenAIStreamParser.swift` | Builds the Tom Riddle prompt, encodes Responses API requests, and parses server-sent text deltas. |
| Local history | `History/ConversationTurn.swift`, `History/PlainTextHistoryStore.swift`, `History/HistoryListView.swift`, `History/HistoryPruner.swift` | Writes one Markdown file per turn under Application Support and reads/prunes it. |
| Settings and secrets | `Settings/SettingsView.swift`, `Settings/APIKeyStore.swift`, `Settings/FontPickerView.swift` | Edits the API key, model, OpenAI `store` flag, font, and local history. |
| Shared support | `Shared/AppError.swift`, `Shared/Constants.swift`, `Shared/AsyncState.swift` | Error-to-recovery mapping, timing and confidence constants, async support. |
| Tests | `TheHuntedDiaryTests/**` | Swift Testing coverage for the prompt, transport/parser, turn controller, recognition, history, settings, and canvas timing. |

## Current automatic input path

```text
PencilKit stroke changes
  -> PencilCanvasIdleCommitter cancels/restarts a 2,500 ms task
  -> PencilCanvasView.onIdleCommit(PencilCanvasModel)
  -> DiaryPageView callback
  -> DiaryTurnController
  -> exported UIImage
  -> handwriting recognizer
  -> prompt builder + local history
  -> OpenAI Responses API stream
  -> ReplyTextView + Markdown history file
```

### Exact runtime wiring today

`PencilCanvasIdleCommitter` uses `Constants.pencilCanvasIdleCommitDelay`, currently `.milliseconds(2500)`. New strokes cancel the previous task, so only an idle canvas commits.

`DiaryPageView` currently calls:

```swift
controller.testRecognizeText(model: model, canvasSize: proxy.size)
```

That method deliberately invokes only `AppleVisionRecognizer`, places the recognised text in `visionTextRecognitionResult`, presents a diagnostic sheet, and returns to `.listening`. It does **not** call `DiaryTurnController.submit(model:canvasSize:)`, so the automatic UI path does not presently build a prompt or generate a reply. `submit` is covered by controller tests and is the path that implements the intended recognition-to-reply flow.

## Turn controller state and dependencies

`DiaryTurnController` is a `@MainActor ObservableObject` created once per `DiaryTurnContentView` through `@StateObject`.

| State/data | Meaning |
|---|---|
| `DiaryTurnPhase` | `.listening`, `.recognizing`, `.sending`, `.streamingReply`, `.completed`, or `.failed`. |
| `recognizedText` | Trimmed text returned by recognition. |
| `replyText` | Appended response deltas, rendered by `ReplyTextView`. |
| `retainedImage` / `retainedRecognition` | Input retained for retry without losing the user’s writing. |
| `historyStore` | Reads the latest 12 turns by default and writes/prunes completed turns. |
| `openAIClient` | Streams reply deltas and transcribes the fallback image. |
| `apiKeyStore` | Loads `OpenAIAPIKey` from Keychain before both recognition and reply generation. |

`DiaryPromptBuilder` creates a fixed Tom Riddle instruction string and interleaves each stored user/assistant turn before the current recognised user text.

## Current persistence model

`ConversationTurn` persists:

- `id` and `createdAt`
- recognition source: `.appleVision` or `.openAI`
- model string
- `openAIStoreEnabled`
- user text and assistant text

`PlainTextHistoryStore` stores each record as a Markdown file with YAML-like front matter in Application Support/History. It has no pending-turn concept; a turn is written only after reply streaming completes.

## OpenAI-specific surfaces to remove or replace

- `OpenAI/OpenAIClient.swift`, `OpenAI/OpenAIResponsesRequest.swift`, and `OpenAI/OpenAIStreamParser.swift` transport files.
- Preserve `OpenAI/DiaryPromptBuilder.swift` unchanged: despite its folder, it is a pure provider-neutral builder with no network, API-key, model, encoding, or transport dependency.
- `Recognition/OpenAIImageRecognizer.swift` and fallback behavior in `HandwritingRecognitionPipeline`.
- API-key dependency and settings UI.
- `AppSettings.replyModel` and `AppSettings.openAIStoreEnabled`.
- OpenAI error stages, recovery messages, history metadata, tests, and project file references.

## Existing test seams worth preserving

- `HandwritingRecognizer` is protocol-based and easily replaced with a local-only recognizer.
- `DiaryHistoryStoring` supports fake storage in controller tests.
- `PencilCanvasClock` makes the idle delay deterministic in tests.
- `DiaryPromptBuilder` is pure and already tested independently.
- The controller’s collaborator injection enables a URL/Shortcut launcher and pending-reply store to be tested without launching Shortcuts.

## Implications for the Shortcut refactor

The new design must keep the 2.5-second idle trigger, image export, Apple Vision recognition, the existing unchanged `DiaryPromptBuilder`, local history, reply rendering, and retry semantics. It must replace only the external generation step with a user-owned iOS 26 Shortcut that invokes Apple’s ChatGPT Extension Model and calls back into the application.

The handoff must be asynchronous: the controller cannot wait on an API stream. It needs actor-isolated, multi-record durable storage, cryptographic bearer capabilities, an end-to-end setup probe, and idempotent history reconciliation so completion safely survives backgrounding, retries, duplicate delivery, and process reconstruction.
