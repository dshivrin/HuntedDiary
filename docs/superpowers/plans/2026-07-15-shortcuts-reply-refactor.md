# Automatic ChatGPT Shortcut Reply Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct OpenAI API usage with an automatic, user-owned iOS 26 Shortcut that uses Apple Intelligence’s ChatGPT Extension Model and returns exactly one durable reply to the active Tom’s Diary turn.

**Architecture:** Keep the existing 2.5-second canvas-idle, Apple Vision, `DiaryPromptBuilder`, local history, and reply-rendering path. After recognition, create a durable capability-protected request, launch the configured Shortcut, let two narrow App Intents exchange the prompt and reply, then reconcile the reply into history with an idempotent commit protocol. A setup probe uses the same round trip without creating diary history and is the only supported way to verify a configured Shortcut.

**Tech Stack:** Swift 5 project language mode, SwiftUI, PencilKit, Vision, App Intents, Shortcuts URL/x-callback URL scheme, CryptoKit, Swift Testing; iOS/iPadOS 26.0 deployment target and current nondeprecated iOS 26 APIs.

## Global Constraints

- Set every app, unit-test, and UI-test deployment target to iOS/iPadOS 26.0. Do not retain iOS 18 availability branches or deprecated compatibility APIs.
- Preserve automatic generation after `Constants.pencilCanvasIdleCommitDelay` (2,500 ms); add no Generate button.
- Preserve the canvas model and visible diary page through launch, failure, retry, and completion. Shortcuts may temporarily foreground while it runs, but returning must reveal the same uncleared canvas rather than a replacement result screen.
- Use Apple Vision only for handwriting recognition; never send the canvas image to OpenAI or Shortcuts.
- Keep `OpenAI/DiaryPromptBuilder.swift` unchanged. It is already a pure provider-neutral value builder; only its folder name is historical.
- Do not use an OpenAI API key, Responses API, streaming transport, image upload, or app-managed ChatGPT sign-in.
- ChatGPT account sign-in is optional. Require only that Apple Intelligence and its ChatGPT extension are enabled and available.
- The user creates and owns the Shortcut. Settings stores its exact display name and provides concise inline help plus a link to the setup guide.
- The Shortcut uses **Use Model → Extension Model → ChatGPT**, with **Follow Up** off. Shortcuts execution history is acceptable; Tom’s Diary must not add a result-display action.
- Treat the launch input as a bearer capability. Pass only an opaque request handle containing a UUID and 256-bit random secret; never put prompt, history, recognized text, or reply in a URL.
- Retain multiple durable request records. All state changes must be serialized, cancellation-aware, crash-safe, retryable, and idempotent.
- A retry reuses the same request, prompt, recognized text, and history identity, rotates its request and callback capabilities, increments its attempt metadata once, and can create at most one history turn after eventual success.
- The iPad mini 6 can run neither Apple Intelligence nor this iOS 26 Extension Model workflow; preserve an explicit compatibility message.

---

## Verified existing layer: `DiaryPromptBuilder`

`TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift` currently imports only Foundation, consumes `[ConversationTurn]`, the current recognized text, and `AppSettings`, and returns a pure `Prompt` value. It makes no network call, contains no API key, model identifier, request encoding, or OpenAI transport dependency. `DiaryTurnController` injects it, and its dedicated tests already cover persona instructions, history ordering, current input, language, and absence of image data.

**Decision:** preserve this file and its tests without modification. Do not move, rename, delete, or rewrite it during this refactor. Delete the other transport files under `OpenAI/`, but explicitly exclude `DiaryPromptBuilder.swift` and `DiaryPromptBuilderTests.swift`.

## File structure after the refactor

| Path | Change | Responsibility |
|---|---|---|
| `Diary/DiaryTurnController.swift` | Modify | Recognition, durable request creation, launch, reconciliation, idempotent retry, and history commit. |
| `Diary/DiaryPageView.swift` | Modify | Sends idle commits to `submit`, preserves the same canvas, and reconciles on activation. |
| `App/AppRootView.swift` | Modify | Strictly parses authenticated callback URLs. |
| `App/DependencyContainer.swift` | Modify | Owns the actor store, launcher, flow, recognizer, history, and settings. |
| `App/AppSettings.swift` | Modify | Stores Shortcut name and last successful setup-probe metadata. |
| `App/TheHuntedDiaryApp.swift` | Modify | Registers App Intent dependencies at process startup. |
| `Intents/GetPendingDiaryPromptIntent.swift` | Create | Validates a capability handle and returns its frozen prompt. |
| `Intents/CompleteDiaryReplyIntent.swift` | Create | Validates the same capability, stores one reply, and requests deferred foreground continuation. |
| `Shortcuts/DiaryReplyCapability.swift` | Create | Generates, encodes, hashes, and constant-time validates UUID plus 256-bit capability tokens. |
| `Shortcuts/PendingDiaryReply.swift` | Create | Versioned durable request, attempt, setup-probe, reply, and history-commit state. |
| `Shortcuts/PendingDiaryReplyStore.swift` | Create | Actor-isolated multi-record persistence and atomic compare-and-set transitions. |
| `Shortcuts/ShortcutReplyLauncher.swift` | Create | Builds and asynchronously opens authenticated Shortcuts x-callback URLs. |
| `Shortcuts/DiaryReplyFlow.swift` | Create | Validates callbacks and reconciles durable requests. |
| `Recognition/HandwritingRecognizer.swift` | Modify | Keeps the protocol and removes network fallback policy. |
| `Recognition/RecognitionResult.swift` | Modify | Creates only Apple Vision results while retaining legacy history decoding. |
| `History/ConversationTurn.swift` | Modify | Adds provider-neutral generation metadata and stable request identity. |
| `History/PlainTextHistoryStore.swift` | Modify | Idempotently appends by request UUID and reads old front matter. |
| `Settings/SettingsView.swift` | Modify | Shortcut name field, help tooltip/link, and Test Shortcut handshake button. |
| `Shared/AppError.swift` | Modify | Local recognition, setup, launch, callback, completion, and history errors. |
| `OpenAI/DiaryPromptBuilder.swift` | Preserve unchanged | Pure prompt construction. |
| `OpenAI/OpenAIClient.swift`, `OpenAI/OpenAIResponsesRequest.swift`, `OpenAI/OpenAIStreamParser.swift`, `Recognition/OpenAIImageRecognizer.swift`, `Settings/APIKeyStore.swift` | Delete | Remove API transport, image fallback, and credentials. |
| `TheHuntedDiary.xcodeproj/project.pbxproj` | Modify | iOS 26 targets, URL type, new sources, and removed sources. |

## Shortcut contract

The launcher supplies one opaque `Shortcut Input` string:

```text
<lowercase UUID>.<base64url 32-byte random capability>
```

The UUID is an index, not authorization. The random capability is generated with `SecRandomCopyBytes` or `CryptoKit`-backed secure randomness, stored only as a SHA-256 digest, redacted from logs, and checked in constant time. The Shortcut contains exactly:

1. **Get Pending Diary Prompt** — `Request Handle = Shortcut Input`.
2. **Use Model** — Extension Model → ChatGPT; prompt is action 1 output; Follow Up off.
3. **Complete Diary Reply** — `Request Handle = Shortcut Input`; `Reply = Use Model response`.

The same contract serves normal turns and setup probes. A setup probe stores completion/verification timestamps but never writes diary history.

## Stable interfaces

```swift
enum DiaryReplyRequestKind: String, Codable, Sendable {
    case diaryTurn
    case setupProbe
}

enum DiaryReplyRequestState: String, Codable, Sendable {
    case readyToLaunch
    case awaitingShortcut
    case replyStored
    case historyCommitted
    case cancelled
    case failed
    case expired
}

struct PendingDiaryReply: Codable, Equatable, Sendable, Identifiable {
    let schemaVersion: Int
    let id: UUID
    let kind: DiaryReplyRequestKind
    var capabilityDigest: Data
    var callbackCapabilityDigest: Data
    let recognizedText: String
    let recognitionSource: RecognitionResult.Source
    let prompt: String
    let createdAt: Date
    let expiresAt: Date
    var updatedAt: Date
    var state: DiaryReplyRequestState
    var attemptCount: Int
    var lastLaunchAt: Date?
    var assistantText: String?
    var historyCommittedAt: Date?
    var terminalReasonCode: String?
}

actor PendingDiaryReplyStore: Sendable {
    func create(_ request: PendingDiaryReply) async throws
    func prepareRetry(id: UUID, capabilityDigest: Data, callbackCapabilityDigest: Data, now: Date) async throws -> PendingDiaryReply
    func prompt(id: UUID, capability: Data, now: Date) async throws -> String
    func storeReply(id: UUID, capability: Data, text: String, now: Date) async throws
    func markHistoryCommitted(id: UUID, now: Date) async throws
    func markCancelled(id: UUID, capability: Data, now: Date) async throws
    func markFailed(id: UUID, capability: Data, code: String, now: Date) async throws
    func load(id: UUID) async throws -> PendingDiaryReply?
    func reconcilableRequests(now: Date) async throws -> [PendingDiaryReply]
    func removeExpiredAndCommitted(before: Date) async throws
    func flush() async throws
}

@MainActor
protocol ShortcutReplyLaunching {
    func launch(shortcutName: String, handle: String, callbacks: ShortcutCallbacks) async throws
}
```

`DiaryTurnPhase` becomes `.listening`, `.recognizing`, `.preparingShortcut`, `.awaitingShortcutReply`, `.committingHistory`, `.completed`, and `.failed(DiaryTurnFailure)`.

## Task 1: Raise the project to iOS 26 and remove obsolete compatibility assumptions

**Files:**
- Modify: `TheHuntedDiary.xcodeproj/project.pbxproj`
- Modify: `docs/architecture/2026-07-15-current-project-structure.md`
- Test: all project targets

- [ ] **Step 1: Write a deployment-setting check**

Add a CI/script assertion or test fixture that parses build settings and expects every `IPHONEOS_DEPLOYMENT_TARGET` to equal `26.0`.

- [ ] **Step 2: Change every app, unit-test, and UI-test target from `18.0` to `26.0`**

Do not leave target-level overrides at 18.0. Update architecture documentation from “iOS 18.0 / Swift 5” to the actual Xcode-selected Swift mode and iOS 26.0.

- [ ] **Step 3: Audit APIs after the target change**

Run:

```bash
rg -n "18\.0|iOS 18|iPadOS 18|#available\(iOS|@available\(iOS|openAppWhenRun" TheHuntedDiary TheHuntedDiaryTests docs TheHuntedDiary.xcodeproj/project.pbxproj
```

Expected after this plan is complete: no production iOS 18 compatibility branch and no `openAppWhenRun`. Historical plans may retain historical statements only when explicitly labeled historical.

- [ ] **Step 4: Build with current iOS 26 APIs**

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS'
```

Expected: `BUILD SUCCEEDED`, with deprecation warnings introduced by this refactor treated as failures during review.

## Task 2: Correct the automatic local-recognition entry point

**Files:** `Diary/DiaryPageView.swift`, `Recognition/HandwritingRecognizer.swift`, `Recognition/RecognitionResult.swift`, `Recognition/OpenAIImageRecognizer.swift`, `App/DependencyContainer.swift`, recognition and canvas tests.

- [ ] Add a failing seam test proving the 2.5-second idle callback invokes `submit`, not `testRecognizeText`, and the canvas model is not cleared.
- [ ] Replace the callback with `controller.submit(model: model, canvasSize: proxy.size)` and delete the diagnostic sheet/path.
- [ ] Inject `AppleVisionRecognizer` directly; remove `HandwritingRecognitionPipeline` and `OpenAIImageRecognizer`.
- [ ] Preserve legacy `recognition: openAI` decoding only in history parsing.
- [ ] Test empty/low-confidence local results, cancellation by a new stroke, and no network fallback.
- [ ] Run the Diary and Recognition test groups and commit the focused change.

## Task 3: Add cryptographic request capabilities

**Files:**
- Create: `Shortcuts/DiaryReplyCapability.swift`
- Create: `TheHuntedDiaryTests/Shortcuts/DiaryReplyCapabilityTests.swift`

- [ ] Test 32-byte secure token generation, base64url round-trip, malformed handles, lowercase/uppercase UUID parsing, SHA-256 storage, constant-time comparison behavior, and redacted descriptions.
- [ ] Implement `DiaryReplyCapability.generate()` using a system CSPRNG; never `UUID`, `RandomNumberGenerator` assumptions, or timestamps for the secret.
- [ ] Define strict maximum handle length and reject whitespace, extra separators, duplicate fields, and invalid base64url.
- [ ] Verify logs/errors expose only the request UUID prefix, never the capability.

## Task 4: Build actor-isolated multi-request persistence

**Files:**
- Create: `Shortcuts/PendingDiaryReply.swift`
- Create: `Shortcuts/PendingDiaryReplyStore.swift`
- Create: `TheHuntedDiaryTests/Shortcuts/PendingDiaryReplyStoreTests.swift`

- [ ] Write failing tests for multiple simultaneous records, versioned decoding, expiry, capability rejection, valid transitions, duplicate completion, conflicting completion, retry preparation, setup probes, reconciliation, cleanup, and corrupt storage quarantine.
- [ ] Persist a versioned collection under Application Support, not a single JSON record. Use file protection appropriate for private diary content.
- [ ] Serialize every read/modify/write through the actor. Write to a sibling temporary file, fsync/close it, atomically replace the destination, and update in-memory state only after durable replacement succeeds.
- [ ] Check cancellation before mutation and before the durable write. Once replacement starts, finish the atomic commit and report the committed state rather than pretending cancellation rolled it back.
- [ ] `flush()` waits for an in-flight write. App lifecycle hooks request a best-effort flush when entering background; process shutdown is not relied on for correctness because every transition is already durable.
- [ ] `prepareRetry` is idempotent for `readyToLaunch`, `awaitingShortcut`, `cancelled`, and retryable `failed`; it retains ID, prompt, recognized text, and assistant/history state, rotates both capability digests so late prior attempts are rejected, and increments `attemptCount` at most once per launch attempt.
- [ ] Reject completion after expiry/history commit, accept byte-identical duplicate completion as success, and reject a different second reply.

## Task 5: Expose only the two required App Intent actions

**Files:** `Intents/GetPendingDiaryPromptIntent.swift`, `Intents/CompleteDiaryReplyIntent.swift`, app startup/dependency files, and intent tests.

- [ ] Test explicit initializers with an injected in-memory store; do not make unit tests depend on global `AppDependencyManager` state.
- [ ] Both actions accept one `Request Handle: String`; completion also accepts `Reply: String`.
- [ ] Use `@AppDependency` with the actor-backed store registered at the earliest point in `TheHuntedDiaryApp.init()`.
- [ ] Use iOS 26 `supportedModes`, not deprecated `openAppWhenRun`. Completion supports background execution plus deferred foreground transition so storage succeeds before Tom’s Diary returns.
- [ ] Do not create `TomDiaryAppShortcuts.swift` or Siri phrases for these plumbing actions. Confirm the discoverable App Intents appear as actions in Shortcuts without publishing preconfigured App Shortcuts.
- [ ] Validate unknown, expired, malformed, wrong-capability, empty, oversized, duplicate, and conflicting replies.

## Task 6: Launch the Shortcut with authenticated callbacks

**Files:** `Shortcuts/ShortcutReplyLauncher.swift`, `Shortcuts/DiaryReplyFlow.swift`, `App/AppRootView.swift`, launcher/flow tests, project URL type.

- [ ] Build URLs with `URLComponents` for `shortcuts://x-callback-url/run-shortcut`, passing the opaque handle as text input.
- [ ] Add `x-cancel` and `x-error` URLs containing the same request UUID plus a separate 256-bit callback capability. Store only its digest.
- [ ] Make launcher completion asynchronous and treat `UIApplication.open` acceptance as “handed to Shortcuts,” not proof that the named Shortcut exists or succeeded.
- [ ] Strictly accept only the registered scheme and exact `shortcut-cancel`/`shortcut-error` hosts, no path, one UUID, one token, matching nonterminal request, valid capability, and unexpired timestamp.
- [ ] Map external error text to bounded internal reason codes; do not persist or display arbitrary `errorMessage` text.
- [ ] Test forged tokens, wrong IDs, replay after completion, duplicate query items, unexpected host/path, oversized values, callback after retry, and custom-scheme delivery while the scene is inactive.

## Task 7: Add a real Shortcut setup handshake and Settings guidance

**Files:** `App/AppSettings.swift`, `Settings/SettingsView.swift`, controller/flow/store files, settings and handshake tests, setup guide.

- [ ] Add a text field labeled **Reply Shortcut Name**, defaulting to `Tom’s Diary Reply`, plus a small info button/tooltip summarizing the three actions and a **Setup Guide** link.
- [ ] Add **Test Shortcut**. It creates a `.setupProbe` request with a harmless fixed prompt, launches the configured name through the production launcher, and uses the production intents/callback path.
- [ ] A completed setup probe records `lastVerifiedShortcutName`, `lastVerifiedAt`, and success UI but never appends history or changes the diary canvas/reply.
- [ ] Renaming the configured Shortcut clears the verified status. A launch URL being accepted does not mark verification successful.
- [ ] Test missing/blank name, renamed/missing Shortcut, cancellation, ChatGPT/action failure, app termination during probe, duplicate completion, and retry of the same probe.
- [ ] State that ChatGPT account sign-in is optional and never claim the app can detect subscription, extension state, region, or Shortcut existence before a real probe.

## Task 8: Refactor the turn controller for idempotent retry and history reconciliation

**Files:** `Diary/DiaryTurnController.swift`, `Diary/DiaryPageView.swift`, history files, controller/history tests.

- [ ] Freeze the prompt once using the unchanged `DiaryPromptBuilder`; create one durable `.diaryTurn` record before leaving the app.
- [ ] Keep the PencilKit model and reply page mounted while awaiting Shortcuts. Do not clear the canvas on launch, callback, failure, retry, or scene activation.
- [ ] Retry the same request ID and frozen prompt with freshly rotated request/callback capabilities. Retry does not rerun recognition, rebuild history context, create a new pending ID, or append history merely because launch was attempted again.
- [ ] Reconcile `replyStored` by idempotently appending `ConversationTurn(id: request.id, ...)`. `PlainTextHistoryStore.appendIfAbsent` returns whether it inserted; an existing matching request ID is success.
- [ ] Only after `appendIfAbsent` and pruning succeed, call `markHistoryCommitted`. A crash before the mark repeats an idempotent append; a crash after the mark does nothing.
- [ ] A setup probe bypasses history reconciliation entirely.
- [ ] On scene activation, reconcile all eligible records, not only an in-memory active ID. Preserve late completions and ignore terminal duplicates.
- [ ] Add tests for history write failure/relaunch, termination on both sides of append, repeated activation, repeated retry taps, cancellation racing completion, two outstanding records, late old completion, and exactly one final history entry.

## Task 9: Remove API billing, credentials, image fallback, and obsolete API types

**Files:** settings, errors, history schema, project file; delete transport/credential sources and tests while preserving prompt-builder files/tests.

- [ ] Migrate new history to `generationProvider: chatGPTExtensionShortcut` and retain old `model`, `openAIStoreEnabled`, and `recognition: openAI` parsing without rewriting user text.
- [ ] Remove API key/model/store settings and Keychain code, OpenAI client/request/stream parser, image recognizer, API errors, and their project references.
- [ ] Preserve `OpenAI/DiaryPromptBuilder.swift` and `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift` byte-for-byte.
- [ ] Search source, tests, build settings, plist/entitlements, dependencies, and docs for `api.openai.com`, API keys, upload code, obsolete models, `openAppWhenRun`, and iOS 18 compatibility.
- [ ] Verify any existing Keychain credential is deleted once during migration without logging its value.
- [ ] Run legacy history migration tests and the complete unit suite.

## Task 10: Update and physically validate the Shortcut guide

**Files:** `docs/guides/create-toms-diary-reply-shortcut.md`, `Settings/SettingsView.swift`.

- [ ] Require iOS/iPadOS 26, Apple Intelligence-compatible hardware, and the enabled ChatGPT extension; say account sign-in is optional.
- [ ] Document the exact three actions using `Shortcut Input` as the request handle.
- [ ] Explain that only the opaque capability handle enters the URL, that the app never sends the canvas image, and that Shortcuts may keep execution history.
- [ ] Explain that Shortcuts may temporarily appear, but Tom’s Diary preserves and returns to the same canvas.
- [ ] Document the Shortcut name field, tooltip/guide, Test Shortcut handshake, verified timestamp, rename behavior, and retry.
- [ ] Validate on a compatible physical iOS/iPadOS 26 device and separately verify iPad mini 6 receives unsupported-device guidance.

## Task 11: Full validation matrix

- [ ] Physical iOS/iPadOS 26 end-to-end normal turn and setup probe; do not treat Simulator as Extension Model proof.
- [ ] ChatGPT enabled without an account; signed-in free/paid accounts are optional variants.
- [ ] Extension disabled, Screen Time blocked, unsupported language/region, offline, model timeout, Shortcuts cancellation, renamed/missing Shortcut, and malformed Shortcut actions.
- [ ] App active/backgrounded/suspended/terminated at request creation, launch acceptance, prompt retrieval, reply storage, history append, history mark, and foreground return.
- [ ] Two overlapping records, late completion, identical/conflicting duplicate completion, rapid retry taps, new strokes during await, and cancellation/completion races.
- [ ] Forged callback, wrong/expired capability, replay, malformed URL, duplicate query keys, oversized prompt/reply/error, and verification that secrets/content are absent from logs and URLs.
- [ ] Corrupt store, schema migration, low disk, atomic replacement failure, file protection while locked, cleanup retention, and shutdown during write.
- [ ] Regression checks for 2.5-second idle timing, canvas preservation, Apple Vision only, prompt persona/history ordering, reply font, local history, pruning, and legacy history.
- [ ] Final commands:

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS'
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,name=iPhone 17'
rg -n "IPHONEOS_DEPLOYMENT_TARGET = 18|openAppWhenRun|api\.openai\.com|OpenAIClient|OpenAIImageRecognizer|APIKeyStore|sk-" TheHuntedDiary TheHuntedDiaryTests TheHuntedDiary.xcodeproj/project.pbxproj
```

Expected: build/tests pass; search finds no production transport, credential, deprecated foreground API, or iOS 18 target. The only allowed OpenAI-named production file is the unchanged pure `OpenAI/DiaryPromptBuilder.swift`, plus explicit legacy migration identifiers.

## Plan self-review

- **Platform:** The feature and all targets are iOS/iPadOS 26.0; no iOS 18 compatibility architecture remains.
- **Automatic UX:** Idle submission remains automatic and the same canvas is retained across the temporary Shortcuts handoff.
- **Security:** URLs carry only capability handles; capabilities are CSPRNG-generated, hashed at rest, redacted, expiring, and validated against replay.
- **Durability:** Multiple records, atomic actor-isolated I/O, per-transition persistence, cleanup, and cancellation/shutdown rules cover backgrounding and termination.
- **Idempotency:** Retry reuses the original request; reply storage and history commit are duplicate-safe and produce at most one history turn.
- **Handshake:** Setup verification is an actual production round trip, not URL-scheme or Shortcut-name inference.
- **Removal:** API billing, credentials, streaming, and image fallback are removed while local Vision, local history, fonts, and the unchanged prompt builder remain.
