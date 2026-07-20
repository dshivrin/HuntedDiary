import SwiftUI

struct DiaryCanvasView: View {
    @StateObject private var canvasModel: PencilCanvasModel
    @StateObject private var idleCommitter: PencilCanvasIdleCommitter
    let isRecognitionRunning: Bool
    let onIdleCommit: PencilCanvasIdleCommitHandler

    @MainActor init(
        canvasModel: PencilCanvasModel? = nil,
        idleCommitter: PencilCanvasIdleCommitter? = nil,
        isRecognitionRunning: Bool = false,
        onIdleCommit: @escaping PencilCanvasIdleCommitHandler = { _ in }
    ) {
        _canvasModel = StateObject(wrappedValue: canvasModel ?? PencilCanvasModel())
        _idleCommitter = StateObject(wrappedValue: idleCommitter ?? PencilCanvasIdleCommitter())
        self.isRecognitionRunning = isRecognitionRunning
        self.onIdleCommit = onIdleCommit
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PencilCanvasView(
                model: canvasModel,
                isRecognitionRunning: isRecognitionRunning,
                idleCommitter: idleCommitter,
                onIdleCommit: { model in
                    onIdleCommit(model)
                }
            )

            HStack(spacing: 12) {
                if isRecognitionRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Recognizing handwriting")
                }

                Button {
                    Self.clear(canvasModel, using: idleCommitter)
                } label: {
                    Image(systemName: "eraser.line.dashed")
                }
                .buttonStyle(.bordered)
                .disabled(canvasModel.hasDrawing == false || isRecognitionRunning)
                .accessibilityLabel("Clear handwriting")
            }
            .padding()
        }
    }

    static func clear(
        _ model: PencilCanvasModel,
        using committer: PencilCanvasIdleCommitter
    ) {
        committer.cancelPendingCommit()
        model.clear()
    }
}
