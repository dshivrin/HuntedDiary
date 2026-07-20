## Task 6: Launch the Shortcut with authenticated callbacks

**Files:** `Shortcuts/ShortcutReplyLauncher.swift`, `Shortcuts/DiaryReplyFlow.swift`, `App/AppRootView.swift`, launcher/flow tests, project URL type.

- [ ] Build URLs with `URLComponents` for `shortcuts://x-callback-url/run-shortcut`, passing the opaque handle as text input.
- [ ] Add `x-cancel` and `x-error` URLs containing the same request UUID plus a separate 256-bit callback capability. Store only its digest.
- [ ] Make launcher completion asynchronous and treat `UIApplication.open` acceptance as “handed to Shortcuts,” not proof that the named Shortcut exists or succeeded.
- [ ] Strictly accept only the registered scheme and exact `shortcut-cancel`/`shortcut-error` hosts, no path, one UUID, one token, matching nonterminal request, valid capability, and unexpired timestamp.
- [ ] Map external error text to bounded internal reason codes; do not persist or display arbitrary `errorMessage` text.
- [ ] Test forged tokens, wrong IDs, replay after completion, duplicate query items, unexpected host/path, oversized values, callback after retry, and custom-scheme delivery while the scene is inactive.

