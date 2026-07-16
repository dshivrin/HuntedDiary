import SwiftUI

struct DiaryPageView: View {
    @ObservedObject private var controller: DiaryTurnController
    private let replyFontName: String
    private let onRequestSettings: () -> Void

    init(
        controller: DiaryTurnController,
        replyFontName: String,
        onRequestSettings: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.replyFontName = replyFontName
        self.onRequestSettings = onRequestSettings
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(.systemBackground)
                DiaryCanvasView(
                    isRecognitionRunning: controller.isBusy,
                    onIdleCommit: Self.idleSubmissionRoute(
                        controller: controller,
                        canvasSize: proxy.size
                    ).handler
                )
                ReplyTextView(text: controller.replyText, fontName: replyFontName)

                if let recovery = controller.activeRecovery {
                    RecoveryBanner(
                        recovery: recovery,
                        onRetry: {
                            Task {
                                await controller.retry()
                            }
                        },
                        onOpenSettings: onRequestSettings
                    )
                    .padding(.bottom, 24)
                }
            }
        }
        .onChange(of: controller.shouldPresentSettings) { _, shouldPresentSettings in
            if shouldPresentSettings {
                onRequestSettings()
            }
        }
    }

    static func idleSubmissionRoute(
        controller: DiaryTurnController,
        canvasSize: CGSize
    ) -> DiaryPageIdleSubmissionRoute {
        DiaryPageIdleSubmissionRoute(controller: controller, canvasSize: canvasSize)
    }
}

@MainActor
struct DiaryPageIdleSubmissionRoute {
    let handler: PencilCanvasIdleCommitHandler

    init(controller: DiaryTurnController, canvasSize: CGSize) {
        handler = { model in
            controller.submit(model: model, canvasSize: canvasSize)
        }
    }

    func drawingDidChange(
        _ model: PencilCanvasModel,
        using committer: PencilCanvasIdleCommitter
    ) {
        committer.drawingDidChange {
            handler(model)
        }
    }
}

private struct RecoveryBanner: View {
    let recovery: AppErrorRecovery
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(recovery.message)
                .font(recovery.action == .none ? .footnote : .callout)
                .foregroundStyle(recovery.action == .none ? .secondary : .primary)
                .multilineTextAlignment(.center)

            if let actionTitle = recovery.actionTitle {
                Button(actionTitle) {
                    performAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
    }

    private func performAction() {
        switch recovery.action {
        case .none:
            break
        case .openSettings:
            onOpenSettings()
        case .retryDrawing, .retryReply:
            onRetry()
        }
    }
}

private extension DiaryTurnController {
    var isBusy: Bool {
        switch phase {
        case .recognizing, .sending, .streamingReply:
            return true
        case .listening, .completed, .failed:
            return false
        }
    }
}
