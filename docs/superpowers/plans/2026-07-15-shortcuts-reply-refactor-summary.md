# Shortcuts Reply Refactor — Implementation Summary

**Plan:** `docs/superpowers/plans/2026-07-15-shortcuts-reply-refactor.md`  
**Implementation completed:** July 18, 2026  
**Summary prepared:** July 20, 2026

## Outcome

Tom's Diary now obtains diary replies through a user-owned iOS 26 Shortcut using Apple Intelligence's ChatGPT Extension Model. The app no longer connects directly to OpenAI or manages API credentials.

The existing handwriting experience remains intact: Apple Vision performs local recognition after 2.5 seconds of handwriting inactivity, the same canvas stays mounted and uncleared throughout the request lifecycle, history remains local, and replies retain the existing bundled handwriting font.

All application, unit-test, and UI-test configurations target iOS/iPadOS 26.0 and support both iPhone and iPad device families.

## Implemented Work

- Added cryptographically random, expiring bearer handles for Shortcut requests and separate authenticated callback capabilities. Only capability digests are stored.
- Added actor-isolated, versioned, multi-request persistence with atomic writes, file protection, corruption quarantine, expiry, and serialized state transitions.
- Added the two required App Intents:
  - **Get Pending Diary Prompt**
  - **Complete Diary Reply**
- Used current iOS 26 `supportedModes` APIs. No deprecated `openAppWhenRun`, Siri phrases, `AppShortcutsProvider`, or preconfigured App Shortcuts were added.
- Added asynchronous Shortcuts x-callback handoff and strict validation of cancellation and error callbacks.
- Added a production setup handshake, exact Shortcut-name setting, inline help, setup-guide link, verification status, compatibility guidance, and **Test Shortcut** workflow.
- Added durable request creation before handoff, frozen prompt data, same-identity retries, capability rotation, interrupted-launch recovery, and cancellation-safe behavior.
- Added two-phase history reconciliation: idempotent append, pruning, then durable history-commit marking. A retry cannot create a new history identity or duplicate history.
- Added recovery for multiple outstanding requests, late completions, backgrounding, termination, and crash boundaries without clearing or remounting the canvas.
- Added provider-neutral history metadata while retaining read-only compatibility with legacy OpenAI history front matter.
- Added a delete-only migration for the legacy OpenAI Keychain credential.
- Added the Extension Model Shortcut setup guide and explicit iPad mini 6 incompatibility guidance.

## Removed

- `TheHuntedDiary/OpenAI/OpenAIClient.swift`
- `TheHuntedDiary/OpenAI/OpenAIResponsesRequest.swift`
- `TheHuntedDiary/OpenAI/OpenAIStreamParser.swift`
- `TheHuntedDiary/Recognition/OpenAIImageRecognizer.swift`
- `TheHuntedDiary/Settings/APIKeyStore.swift`

This removed direct API transport, API billing and credential handling, Keychain API-key storage, streaming response parsing, and the network image-recognition fallback.

## Preserved Unchanged

- `TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift`
- `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift`

Their expected SHA-256 hashes were rechecked after implementation.

## Verification Results

- Generic iOS device build: **passed** for `arm64-apple-ios26.0` using the iOS 26.5 SDK.
- Complete iPhone 17 Simulator test run on iOS 26.5: **passed**.
  - 160 declared tests
  - 187 invocations including parameterized cases
  - 0 failures
  - 0 skipped
- UI launch and inactive-scene callback tests: **passed**.
- Focused capability, persistence, App Intent, setup, retry, reconciliation, migration, recognition, history, and settings tests: **passed**.
- Deployment assertion: **passed**, verifying all eight deployment-target settings are 26.0.
- Universal-device assertion: **passed**, verifying all six target device-family settings are `1,2`.
- Generated source membership includes the new intents, persistence, and migration sources and excludes the deleted transport and credential sources.
- `git diff --check`: **passed**.

## Security and Removal Checks

- No direct OpenAI endpoint, `URLSession` transport, bearer authorization header, API-key prefix, streaming parser, multipart/image transport, or Keychain read/write code remains.
- The only remaining Keychain operation is the exact delete-only legacy migration using `SecItemDelete`.
- Launch handoff contains no diary text, history, or reply content. It carries only the approved opaque request handle and authenticated callback URLs required by the capability-protected Shortcuts architecture.
- Raw capabilities are never logged and are stored only as SHA-256 digests.
- No deprecated App Intents execution mode, Siri phrases, or App Shortcuts provider exists.

## Focused Commits

The implementation was divided into 22 focused commits, beginning with `f65eb07` (iOS 26 deployment target) and ending with `d8847c7` (Shortcut setup guide). Unrelated pre-existing worktree changes were preserved and excluded from those commits.

## Physical-Device Validation Still Required

Simulator testing does not prove that Apple's Extension Model workflow works on physical hardware. The following checks remain pending:

- Complete setup probe and normal diary reply on a compatible iOS 26 iPhone.
- Complete setup probe and normal diary reply on a compatible iPadOS 26 iPad.
- Confirm operation without signing into a ChatGPT account.
- Validate disabled Apple Intelligence, regional/restriction unavailability, offline, timeout, cancellation, renamed Shortcut, and malformed Shortcut behavior.
- Validate backgrounding, foregrounding, and termination recovery during a real Shortcuts handoff.
- Confirm the same canvas remains visible and unchanged throughout the physical-device workflow.
- Confirm the explicit incompatibility message on an iPad mini 6.

There are no known implementation or automated-test blockers. Access to compatible physical devices is the only remaining validation dependency.
