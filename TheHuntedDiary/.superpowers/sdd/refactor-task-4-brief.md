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

