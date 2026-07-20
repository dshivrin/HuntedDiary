## Task 2: Correct the automatic local-recognition entry point

**Files:** `Diary/DiaryPageView.swift`, `Recognition/HandwritingRecognizer.swift`, `Recognition/RecognitionResult.swift`, `Recognition/OpenAIImageRecognizer.swift`, `App/DependencyContainer.swift`, recognition and canvas tests.

- [ ] Add a failing seam test proving the 2.5-second idle callback invokes `submit`, not `testRecognizeText`, and the canvas model is not cleared.
- [ ] Replace the callback with `controller.submit(model: model, canvasSize: proxy.size)` and delete the diagnostic sheet/path.
- [ ] Inject `AppleVisionRecognizer` directly; remove `HandwritingRecognitionPipeline` and `OpenAIImageRecognizer`.
- [ ] Preserve legacy `recognition: openAI` decoding only in history parsing.
- [ ] Test empty/low-confidence local results, cancellation by a new stroke, and no network fallback.
- [ ] Run the Diary and Recognition test groups and commit the focused change.

