import Combine
import PencilKit
import SwiftUI
import UIKit

typealias PencilCanvasIdleCommitHandler = @MainActor @Sendable (PencilCanvasModel) -> Void

@MainActor
final class PencilCanvasModel: ObservableObject {
    @Published private(set) var drawing: PKDrawing

    init(drawing: PKDrawing = PKDrawing()) {
        self.drawing = drawing
    }

    var hasDrawing: Bool {
        drawing.strokes.isEmpty == false
    }

    func updateDrawing(_ drawing: PKDrawing) {
        self.drawing = drawing
    }

    func clear() {
        drawing = PKDrawing()
    }

    func exportImage(canvasSize: CGSize, scale: CGFloat? = nil) -> UIImage? {
        guard hasDrawing, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let exportScale = scale ?? UIScreen.main.scale
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(bounds)
            drawing.image(from: bounds, scale: exportScale).draw(in: bounds)
        }
    }
}

protocol PencilCanvasClock: Sendable {
    nonisolated func sleep(for duration: Duration) async throws
}

struct ContinuousPencilCanvasClock: PencilCanvasClock {
    nonisolated init() {}

    nonisolated func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
final class PencilCanvasIdleCommitter: ObservableObject {
    private let delay: Duration
    private let clock: any PencilCanvasClock
    private var task: Task<Void, Never>?

    @MainActor init(
        delay: Duration = .milliseconds(2500),
        clock: any PencilCanvasClock = ContinuousPencilCanvasClock()
    ) {
        self.delay = delay
        self.clock = clock
    }

    deinit {
        task?.cancel()
    }

    func drawingDidChange(_ commit: @escaping @MainActor @Sendable () -> Void) {
        cancelPendingCommit()
        task = Task { [clock, delay] in
            do {
                try await clock.sleep(for: delay)
                guard Task.isCancelled == false else {
                    return
                }
                commit()
            } catch {
                return
            }
        }
    }

    func cancelPendingCommit() {
        task?.cancel()
        task = nil
    }
}

enum PencilCanvasInputPolicy {
    static var defaultDrawingPolicy: PKCanvasViewDrawingPolicy {
        #if targetEnvironment(simulator)
        .anyInput
        #else
        .pencilOnly
        #endif
    }
}

struct PencilCanvasView: View {
    @ObservedObject private var model: PencilCanvasModel
    private let idleCommitter: PencilCanvasIdleCommitter
    private let isRecognitionRunning: Bool
    private let onIdleCommit: PencilCanvasIdleCommitHandler

    @MainActor init(
        model: PencilCanvasModel,
        isRecognitionRunning: Bool = false,
        idleCommitter: PencilCanvasIdleCommitter,
        onIdleCommit: @escaping PencilCanvasIdleCommitHandler = { _ in }
    ) {
        self.model = model
        self.idleCommitter = idleCommitter
        self.isRecognitionRunning = isRecognitionRunning
        self.onIdleCommit = onIdleCommit
    }

    var body: some View {
        PencilCanvasRepresentable(
            drawing: Binding(
                get: { model.drawing },
                set: { drawing in
                    model.updateDrawing(drawing)
                    idleCommitter.drawingDidChange {
                        onIdleCommit(model)
                    }
                }
            ),
            isUserInteractionEnabled: isRecognitionRunning == false
        )
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let isUserInteractionEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = PencilCanvasInputPolicy.defaultDrawingPolicy
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvasView.isUserInteractionEnabled = isUserInteractionEnabled

        if canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvasView.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasRepresentable

        init(parent: PencilCanvasRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
