# Task 6 Report: Authenticated Shortcut Launch and Callback Flow

## Status

Implemented the asynchronous Shortcuts x-callback launcher, separate callback capability values, strict durable callback flow, root URL delivery, shared dependency wiring, and the app callback URL registration.

## RED

The focused Task 6 tests were added before production implementation and run with:

```bash
xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' \
  -derivedDataPath /private/tmp/TheHuntedDiaryTask6Red2 \
  -parallel-testing-enabled NO \
  -only-testing:TheHuntedDiaryTests/ShortcutReplyLauncherTests \
  -only-testing:TheHuntedDiaryTests/DiaryReplyFlowTests
```

Result: exit 65, `** TEST FAILED **`. The corrected RED run failed only because `ShortcutCallbacks`, `ShortcutReplyLauncher`, `ShortcutReplyLauncherError`, `DiaryReplyFlow`, and the callback result types did not exist.

## Implementation

- `ShortcutReplyLauncher` conforms to the stable main-actor `ShortcutReplyLaunching` protocol and awaits an injected async URL opener. `true` means only that UIKit handed the URL to a handler; it does not verify that a named Shortcut exists or completed.
- The launcher uses `URLComponents` for the exact `shortcuts://x-callback-url/run-shortcut` shape with `name`, `input=text`, `text=<opaque request handle>`, `x-cancel`, and `x-error` only.
- `ShortcutCallbacks` creates a separate 32-byte callback capability, exposes only its digest for durable storage, redacts reflection/description, and puts the raw secret only in the nested callback URL's `token` field.
- Callback URLs contain the same canonical lowercase request UUID and use the registered `toms-diary` scheme with exact `shortcut-cancel` or `shortcut-error` hosts.
- `DiaryReplyFlow` accepts only bounded absolute URLs with no user, password, port, path, or fragment; exactly one lowercase UUID and canonical 32-byte token; no duplicate or unknown keys; and only bounded single `errorCode`/`errorMessage` fields on the error host.
- External error fields are discarded after structural validation and map only to the closed `shortcut_error` failure code. Arbitrary text is never persisted or returned.
- The flow uses the shared durable `PendingDiaryReplyStore`, rejects missing, forged, expired, terminal, replayed, and pre-retry callback capabilities, and returns bounded content-free handled/rejected results.
- `AppRootView.onOpenURL` dispatches directly to the durable flow without scene-phase or active in-memory request state. A reconstruction test handles a callback through a new flow and store instance loaded from disk.
- `DependencyContainer` owns one launcher and one flow built from its same pending-reply store.
- The app uses an explicit `Info.plist`; a synchronized-root membership exception prevents it from being copied as a resource. The plist preserves the prior scene, indirect-input, launch-screen, and iPad orientation values and registers one callback URL type.

## GREEN

Focused Task 6 suite:

- iPhone 17 / iOS 26.5 Simulator
- 22 declared tests, 25 parameterized invocations
- 0 failures, 0 skipped

Fresh final combined Task 3–6 suite:

```bash
xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' \
  -derivedDataPath /private/tmp/TheHuntedDiaryTask6CombinedFinal \
  -parallel-testing-enabled NO \
  -only-testing:TheHuntedDiaryTests/DiaryReplyCapabilityTests \
  -only-testing:TheHuntedDiaryTests/PendingDiaryReplyStoreTests \
  -only-testing:TheHuntedDiaryTests/DiaryReplyIntentTests \
  -only-testing:TheHuntedDiaryTests/ShortcutReplyLauncherTests \
  -only-testing:TheHuntedDiaryTests/DiaryReplyFlowTests
```

Result: exit 0. The xcresult records 75 declared tests, 101 parameterized invocations, 0 failures, and 0 skipped.

## Build and project verification

- Generic `iphoneos` build with `CODE_SIGNING_ALLOWED=NO`: exit 0.
- Simulator `build-for-testing`: exit 0.
- Generated build settings: `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY = 1,2`, `GENERATE_INFOPLIST_FILE = NO`, and `INFOPLIST_FILE = TheHuntedDiary/Info.plist`.
- Built app plist: `MinimumOSVersion = 26.0`; `UIDeviceFamily = [1, 2]`; exactly one `com.TheHuntedDiary.shortcut-callback` URL type with scheme `toms-diary`; prior scene, launch-screen, indirect-input, and iPad orientation values present.
- Generated app and test Swift file lists contain both launcher/flow sources and both focused test sources.

The build emits pre-existing warnings in `PencilCanvasView`, `DiaryReplyCapability`, `AppleVisionRecognizerTests`, and obsolete OpenAI tests. No Task 6 source warning was introduced. The obsolete OpenAI paths are removed by Task 9.

## Security checks

- The Task 6 production surface has no `print`, `debugPrint`, `dump`, `Logger`, `os_log`, or `NSLog` calls.
- The launch URL query is limited to the exact name, opaque request handle, and nested authenticated callback URLs. No prompt, recognized text, history, reply, image, or external error text is added.
- Callback diagnostics are bounded and content-free; callback capability reflection is redacted.
- `DiaryPromptBuilder.swift` SHA-256 remains `e76b2f3930d07bbe98dd948b9c458241ec876ab88a5b385db0c79ff7fe6ef1ce`.
- `DiaryPromptBuilderTests.swift` SHA-256 remains `41fbc4a579ee61edb70035a05f1d1f9f84c55aa99014a0ba889a4cc2faf2b8bf`.

## Limitations

Simulator verification proves URL construction, strict parsing, durable-store behavior, URL registration, and compilation. It does not prove physical iOS/iPadOS 26 Shortcuts or Extension Model handoff; that remains required in the plan's physical-device validation tasks.
