# Review Remediation: Universal Device Support and Test Harness

## Requirements

- Support both iPhone (iOS 26.0) and iPad (iPadOS 26.0) in app, unit-test, and UI-test configurations; every `IPHONEOS_DEPLOYMENT_TARGET` remains exactly `26.0`.
- Add a failing project-setting assertion proving every applicable `TARGETED_DEVICE_FAMILY` is `1,2`, then update all app/test configurations and run it green.
- Add a minimal real UI smoke test so the synchronized `TheHuntedDiaryUITests` target has an executable and `-only-testing:TheHuntedDiaryUITests` runs rather than failing bundle load.
- Add a failing test proving programmatic Clear cancels the existing 2.5-second idle callback; implement an explicit cancellation/reset path without changing the 2,500 ms delay.
- Preserve the same mounted `PencilCanvasModel`, existing Apple Vision route, reply font, prompt builder files, and unrelated dirty changes.
- Do not patch obsolete Keychain tests; their code/tests are removed in Task 9 as planned.
- Run focused setting, canvas, UI smoke, unit compilation, and unsigned generic iOS build checks. Commit only remediation files after focused checks pass.
