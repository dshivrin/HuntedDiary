## Task 5: Expose only the two required App Intent actions

**Files:** `Intents/GetPendingDiaryPromptIntent.swift`, `Intents/CompleteDiaryReplyIntent.swift`, app startup/dependency files, and intent tests.

- [ ] Test explicit initializers with an injected in-memory store; do not make unit tests depend on global `AppDependencyManager` state.
- [ ] Both actions accept one `Request Handle: String`; completion also accepts `Reply: String`.
- [ ] Use `@AppDependency` with the actor-backed store registered at the earliest point in `TheHuntedDiaryApp.init()`.
- [ ] Use iOS 26 `supportedModes`, not deprecated `openAppWhenRun`. Completion supports background execution plus deferred foreground transition so storage succeeds before Tom’s Diary returns.
- [ ] Do not create `TomDiaryAppShortcuts.swift` or Siri phrases for these plumbing actions. Confirm the discoverable App Intents appear as actions in Shortcuts without publishing preconfigured App Shortcuts.
- [ ] Validate unknown, expired, malformed, wrong-capability, empty, oversized, duplicate, and conflicting replies.

Verified iOS 26.5 SDK/API note: `AppIntent.supportedModes` is the nondeprecated iOS 26 API. Apple documents completion-style handoff as `static let supportedModes: IntentModes = [.background, .foreground(.deferred)]`; `.deferred` starts in the background and transitions before `perform()` finishes. The SDK also exposes `continueInForeground(_:alwaysConfirm:)` for an explicit deferred transition when needed. Do not use deprecated `openAppWhenRun` or `ForegroundContinuableIntent`.
