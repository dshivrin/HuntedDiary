# Task 4 implementation report

## Scope

Implemented the actor-isolated, versioned, multi-request pending diary reply store in exactly these Task 4 files:

- `TheHuntedDiary/Shortcuts/PendingDiaryReply.swift`
- `TheHuntedDiary/Shortcuts/PendingDiaryReplyStore.swift`
- `TheHuntedDiaryTests/Shortcuts/PendingDiaryReplyStoreTests.swift`

No other production or test source was changed for this task. The report remains uncommitted as SDD scratch material.

## RED evidence

Initial command:

```bash
xcodebuild test -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:TheHuntedDiaryTests/PendingDiaryReplyStoreTests
```

The first sandboxed attempt could not access CoreSimulator or DerivedData. The required escalated rerun reached compilation and failed with the expected missing Task 4 symbols: `DiaryReplyRequestState`, `DiaryReplyRequestKind`, `PendingDiaryReply`, and `PendingDiaryReplyStore`.

After the first implementation pass, three focused regressions produced a second genuine RED run. The failing tests were:

- `expiryDiscoveredDuringReplyStorageIsPersisted`
- `migratesVersionZeroDocumentsAndRecordsOnTheNextDurableTransition`
- `duplicateRetryPreparationWhileAwaitingDoesNotIncrementTheAttempt`

An overdue-cleanup regression then failed `cleanupRemovesOnlyOldTerminalRecordsAndRetainsActiveWork` until cleanup distinguished expired launch records from a diary reply awaiting history reconciliation.

## GREEN evidence

Fresh final command:

```bash
xcodebuild test -quiet -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:TheHuntedDiaryTests/DiaryReplyCapabilityTests -only-testing:TheHuntedDiaryTests/PendingDiaryReplyStoreTests
```

Result: exit 0. The first reported execution of each Swift Testing suite contained:

- `PendingDiaryReplyStoreTests`: 25/25 cases passed.
- `DiaryReplyCapabilityTests`: 23/23 cases passed.
- Total focused Task 3+4 verification: 48/48 cases passed.

Xcode's output listed the Swift Testing suites twice, but both listings passed. Remaining warnings were pre-existing isolation warnings in `OpenAIClientTests` and `AppleVisionRecognizerTests`; no Task 4 warning remained.

## Design notes

- The stable request fields and states are represented by nonisolated `Codable`, `Equatable`, and `Sendable` values.
- The actor stores a versioned collection, supports schema-0 migration, rejects a future schema without quarantining it, and quarantines corrupt data under a bounded UUID-only filename.
- Every read/modify/write operation owns a FIFO actor gate across suspension. A cancelled queued waiter hands ownership onward instead of stranding the gate.
- Cancellation is checked before mutation and immediately before starting the detached durable commit. Once the commit starts, cancellation of the caller does not cancel the commit or suppress the committed result.
- Live persistence creates a sibling private file, applies complete-until-first-user-authentication protection, uses a full POSIX write loop, fsyncs and closes it, atomically renames it over the destination, and fsyncs the containing directory. Actor memory changes only after that succeeds.
- Prompt/reply capability validation hashes the supplied token and compares its digest through `DiaryReplyCapability.constantTimeEqual`; callback transitions validate the separately stored callback digest.
- Prompt retrieval durably moves `readyToLaunch` to `awaitingShortcut`. `prepareRetry` rotates both digests for a new pair and increments once; the same pair is idempotent in `readyToLaunch` and `awaitingShortcut`.
- Expiry discovered by any request mutation is itself durably committed before `requestExpired` returns. Cleanup retains a diary `replyStored` request so two-phase history reconciliation cannot be lost.
- Setup probes can store a duplicate-safe reply but are excluded from reconciliation.

## Preservation checks

SHA-256 remained unchanged:

- `DiaryPromptBuilder.swift`: `e76b2f3930d07bbe98dd948b9c458241ec876ab88a5b385db0c79ff7fe6ef1ce`
- `DiaryPromptBuilderTests.swift`: `41fbc4a579ee61edb70035a05f1d1f9f84c55aa99014a0ba889a4cc2faf2b8bf`

## Independent review remediation

### RED

Fresh review regressions were added before the fix. The focused store command failed during compilation because the required retry/failure-code errors, closed failure-code type, pre-write seam, and committed-directory-sync outcome did not exist. The earlier implementation also failed the new behavioral expectations by inspection: every state expired before its transition switch, active retry calls accepted a competing pair, and decoded semantic invariants were not checked.

### Changes

- `.replyStored` and `.historyCommitted` records no longer expire. A diary reply received before expiry remains reconcilable and can be history-committed afterward; a completed setup probe remains duplicate-processable afterward.
- Active `readyToLaunch`/`awaitingShortcut` retry preparation returns the current attempt regardless of a competing pair. Only `cancelled` and explicitly retryable `failed` states prepare a new attempt, and both capability digests must differ from the prior pair.
- `DiaryReplyFailureCode` is a closed content-free identifier set. Retryable codes are `shortcut_error`, `shortcut_unavailable`, and `launch_rejected`; configuration, unsupported-device, extension-unavailable, and internal failures are nonretryable.
- Persistence has a deterministic post-encoding/pre-I/O seam and checks cancellation immediately after it and immediately before creating the detached commit task.
- A pre-replacement persistence failure leaves actor memory unchanged. A post-replacement directory-sync/open/close outcome is never ignored: live I/O opens the directory before rename, checks `fsync` and `close`, and emits a committed-but-not-confirmed-durable outcome after rename. The actor then adopts the replaced snapshot and throws `directorySyncFailedAfterCommit`, so it neither reports durable success nor pretends rollback.
- Decoded records now receive the same digest/date/attempt/state validation as newly created records. Negative schemas and semantic corruption are quarantined; only schema 0 migrates to 1; future store or record schemas remain unsupported and unquarantined.

### Remediation GREEN

The focused store suite passed 44/44 expanded cases on the iPhone 17 / iOS 26.5 simulator. The fresh combined Task 3+4 run passed 67/67 cases (44 store and 23 capability) on the same simulator destination.

## Completed-record bearer-expiry follow-up

- `prompt(id:capability:now:)` and `storeReply(id:capability:text:now:)` now each reject `now >= expiresAt` after capability validation, including when the record is already `.replyStored`.
- This bearer-expiry rejection does not mutate or delete the completed record. A diary reply remains locally reconcilable and can transition to `.historyCommitted` after expiry.
- The setup-probe regression now verifies local processing and loading after expiry without accepting a late duplicate callback.
- The fresh combined Task 3+4 suite passed 67/67 cases (44 store and 23 capability) on the iPhone 17 / iOS 26.5 simulator.
