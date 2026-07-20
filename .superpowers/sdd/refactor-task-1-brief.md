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

