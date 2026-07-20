# Task 1 Report — iOS 26 Deployment Baseline

## Status

Implemented the focused Task 1 changes. Every explicit project, app, unit-test, and UI-test deployment setting is now iOS 26.0, the deployment assertion passes, the compatibility audit has no production-source/test/project-file matches, and an unsigned generic-device build compiles successfully with the iOS 26.5 SDK. The exact signed generic-device build remains blocked by the pre-existing absence of a development team.

## Implementation

- Added `scripts/assert-ios-26-deployment-targets.sh` as an executable, standalone deployment-setting assertion.
  - It parses every explicit `IPHONEOS_DEPLOYMENT_TARGET` assignment in `project.pbxproj`.
  - It fails when no assignments exist.
  - It fails and reports grouped unexpected values when any assignment differs from `26.0`.
  - It reports the number of verified assignments on success.
- Changed all eight explicit `IPHONEOS_DEPLOYMENT_TARGET` values from `18.0` to `26.0`:
  - Project Debug and Release.
  - App Debug and Release.
  - Unit-test Debug and Release.
  - UI-test Debug and Release.
- Updated the current architecture document to state the live iOS/iPadOS 26.0 baseline and the actual Xcode-selected Swift 5 language mode (`SWIFT_VERSION = 5.0`) under Xcode 26.6.
- Kept the former iOS 18.0 baseline only as an explicitly historical architecture statement.

## Focused files

- `TheHuntedDiary.xcodeproj/project.pbxproj`
- `docs/architecture/2026-07-15-current-project-structure.md`
- `scripts/assert-ios-26-deployment-targets.sh`
- `.superpowers/sdd/refactor-task-1-report.md`

No unrelated source files were edited for Task 1. In particular, the existing dirty/untracked user work in `TheHuntedDiary/OpenAI/DiaryPromptBuilder.swift` and `TheHuntedDiaryTests/OpenAI/DiaryPromptBuilderTests.swift` was not staged or altered by this task.

## TDD evidence

### RED

The assertion was added before changing the project settings.

Command:

```bash
scripts/assert-ios-26-deployment-targets.sh
```

Result: exit 1, expected failure.

```text
error: expected every IPHONEOS_DEPLOYMENT_TARGET to equal 26.0; found:
   8 18.0
```

The failure was the intended behavioral failure: all eight existing settings still used the obsolete deployment target.

### GREEN

After changing only the eight deployment values:

```bash
scripts/assert-ios-26-deployment-targets.sh
```

Result: exit 0.

```text
Verified 8 IPHONEOS_DEPLOYMENT_TARGET settings at 26.0.
```

## API compatibility audit

Command (verbatim from the task brief):

```bash
rg -n "18\.0|iOS 18|iPadOS 18|#available\(iOS|@available\(iOS|openAppWhenRun" TheHuntedDiary TheHuntedDiaryTests docs TheHuntedDiary.xcodeproj/project.pbxproj
```

Result: exit 0 because documentation matches remain. There were no matches in `TheHuntedDiary`, `TheHuntedDiaryTests`, or `TheHuntedDiary.xcodeproj/project.pbxproj`. The matches were confined to:

- The dated 2026-07-08 implementation plan's historical iPadOS 18 baseline.
- The current refactor plan's requirements, audit command, and explanatory references to removing iOS 18 compatibility and `openAppWhenRun`.
- The architecture document's explicitly labeled historical baseline and project-history summary.

Therefore the audit found no live production iOS 18 compatibility branch, no availability annotation, and no production `openAppWhenRun` use.

## Build evidence

### Required command

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS'
```

Sandboxed result: exit 65 before compilation because the sandbox could not write Xcode DerivedData or access simulator services.

The same exact command was rerun outside the sandbox. Result: exit 65 during `GatherProvisioningInputs`:

```text
TheHuntedDiary.xcodeproj: error: Signing for "TheHuntedDiary" requires a development team.
** BUILD FAILED **
```

This is a project-signing/environment prerequisite, not a compiler or iOS 26 API failure. Task 1 did not change signing settings.

### Focused compilation without signing

Command:

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Result: exit 0, `** BUILD SUCCEEDED **`.

Evidence from the build invocation:

- SDK: `iPhoneOS26.5.sdk`
- Target triple: `arm64-apple-ios26.0`
- Swift mode: `-swift-version 5`
- Asset-catalog minimum deployment target: `26.0`
- App Intents metadata deployment target: `26.0`

No deprecation warning was introduced. The only emitted warning was the existing informational App Intents metadata warning that extraction was skipped because the current target has no `AppIntents.framework` dependency.

## Self-review

- Confirmed the assertion watched the old configuration fail before implementation.
- Confirmed the same assertion passes after implementation and counts all eight explicit settings.
- Reviewed the project diff: it contains only eight `18.0` to `26.0` substitutions.
- Reviewed the architecture update: it changes the live baseline without changing the approved architecture.
- Ran `git diff --check`; it reported no whitespace errors.
- Inspected focused status to avoid staging the heavily dirty worktree or the protected prompt-builder files.
- Did not modify or stage the existing historical implementation plan, current refactor plan, application source, unit-test source, UI-test source, resources, workspace UI state, or progress files.

## Concerns

- The exact signed generic iOS build cannot complete until a development team is configured. The same build compiles and links successfully with signing disabled.
- The exact audit intentionally returns documentation matches from the preserved historical implementation plan and the active refactor plan's requirements/search examples. It returns no production-source, test-source, or project-setting matches.
- The repository remains heavily dirty with unrelated user changes. The focused commit must stage only the four Task 1 files listed above.
- The known baseline APIKeyStore test failures and UI-test runner bundle error were not exercised or changed by Task 1.

## Review follow-up — hardened deployment assertion

This section supersedes the earlier assertion-coverage and commit-scope statements where they differ. Review identified that the first parser matched only unquoted, unconditional assignments and accepted any nonzero number of matches. The hardened assertion now:

- Inspects every textual occurrence of `IPHONEOS_DEPLOYMENT_TARGET`.
- Accepts the complete normal or quoted/conditional assignment-key syntax.
- Rejects any occurrence whose complete assignment cannot be parsed.
- Rejects every parsed value other than exactly `26.0`.
- Requires exactly eight occurrences, covering project, app, unit-test, and UI-test Debug/Release configurations.

Focused fixtures cover exactly eight valid settings, a ninth quoted conditional obsolete override, an incomplete seven-setting project, and an unparseable key occurrence.

### Review RED before parser fix

The focused regression suite was added while the original `sed` parser was still present.

Command:

```bash
scripts/tests/assert-ios-26-deployment-targets-tests.sh
```

Result: exit 1 for the intended defect.

```text
error: quoted conditional obsolete override unexpectedly passed
```

This proved that the old assertion ignored:

```text
"IPHONEOS_DEPLOYMENT_TARGET[sdk=iphoneos*]" = 18.0;
```

### Review GREEN after parser fix

Command:

```bash
scripts/tests/assert-ios-26-deployment-targets-tests.sh
```

Result: exit 0.

```text
Verified deployment assertion accepts exact coverage and rejects conditional, incomplete, and unparseable settings.
```

Direct conditional-fixture command:

```bash
scripts/assert-ios-26-deployment-targets.sh scripts/tests/fixtures/conditional-obsolete-override.pbxproj
```

Result: exit 1.

```text
error: scripts/tests/fixtures/conditional-obsolete-override.pbxproj:9: found unexpected value 18.0 for IPHONEOS_DEPLOYMENT_TARGET
error: expected exactly 8 IPHONEOS_DEPLOYMENT_TARGET assignments; found 9 in scripts/tests/fixtures/conditional-obsolete-override.pbxproj
```

Real-project command:

```bash
scripts/assert-ios-26-deployment-targets.sh
```

Result: exit 0.

```text
Verified 8 IPHONEOS_DEPLOYMENT_TARGET settings at 26.0.
```

### Corrected commit ownership

The final amended Task 1 commit intentionally excludes `docs/architecture/2026-07-15-current-project-structure.md` and `.superpowers/sdd/refactor-task-1-report.md`. Both files remain present with their Task 1 content as user-owned, untracked working-tree files. The focused commit contains only the project deployment changes, the deployment assertion, and its dedicated regression suite/fixtures.

### Final review verification before amend

```bash
scripts/tests/assert-ios-26-deployment-targets-tests.sh
```

Exit 0: `Verified deployment assertion accepts exact coverage and rejects conditional, incomplete, and unparseable settings.`

```bash
scripts/assert-ios-26-deployment-targets.sh
```

Exit 0: `Verified 8 IPHONEOS_DEPLOYMENT_TARGET settings at 26.0.`

```bash
git diff --check
git diff HEAD^ --cached --check
```

Both commands exited 0 with no output.

```bash
xcodebuild build -project TheHuntedDiary.xcodeproj -scheme TheHuntedDiary -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Exit 0: `** BUILD SUCCEEDED **` using `iPhoneOS26.5.sdk`.

### Post-amend integrity evidence

Amended commit:

```text
f65eb0719c22d31fbd8c9751c0aff8b8224a38a6 Raise deployment target to iOS 26
```

`git show --name-status HEAD` lists only `TheHuntedDiary.xcodeproj/project.pbxproj`, the assertion script, the focused test runner, and its four fixtures. The architecture document and this report both appear as `??` in focused `git status`, confirming that they remain present but untracked.

The focused parser suite and real-project assertion were rerun after the amend and both exited 0. The unsigned generic iOS build was also rerun after the amend and exited 0 with `** BUILD SUCCEEDED **` against `iPhoneOS26.5.sdk` and target `arm64-apple-ios26.0`.
