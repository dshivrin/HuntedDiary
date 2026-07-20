# Shortcuts Reply Refactor Progress

Plan: `docs/superpowers/plans/2026-07-15-shortcuts-reply-refactor.md`
Baseline: generic iOS build passed; existing suite had four APIKeyStore failures and one UI-test runner bundle error.

Task 1: complete (commits f7316f3..f65eb07, review clean; architecture document update intentionally remains untracked)
Task 2: complete (commits f65eb07..052edef; local Apple Vision automatic-idle route implemented and independently reviewed)
Review remediation: complete (commits 052edef..494230b; iPhone/iPad universal support, UI-test executable, Clear cancellation, and hidden idle-delay dependency reviewed clean)
Task 3: complete (commits 494230b..1ae17e; 256-bit capability generation, canonical parsing, digest validation, and reflection redaction reviewed clean)
Task 4: complete (commits 1ae17e..e97a268; actor-isolated durable multi-request store, retry rotation, expiry split, cancellation, corruption quarantine, and two-phase-ready reply retention reviewed clean)
Task 5: complete (commit 5fcdaf8; two injected App Intents, iOS 26 execution modes, earliest shared-store registration, metadata extraction, and safe completion validation reviewed clean)
Task 6: complete (commits 86a802d..e1b8ffa; authenticated Shortcuts/x-callback launch, strict custom-scheme routing, capability-first serialized callback authorization, inactive-scene UI delivery, iPhone/iPad bundle metadata, and review remediation verified)
