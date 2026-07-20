import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import TheHuntedDiary

@MainActor
struct PencilCanvasExportTests {
    @Test func testEmptyDrawingExportReturnsNilOrBlankRejectedImage() {
        let model = PencilCanvasModel()

        let image = model.exportImage(canvasSize: CGSize(width: 500, height: 700), scale: 1)

        #expect(image == nil)
    }

    @Test func testNonEmptyDrawingExportsImage() {
        let model = PencilCanvasModel()
        model.updateDrawing(Self.makeDrawing())

        let image = model.exportImage(canvasSize: CGSize(width: 500, height: 700), scale: 1)

        #expect(image != nil)
        #expect(image?.size.width == 500)
        #expect(image?.size.height == 700)
    }

    @Test func testClearRemovesDrawingBeforeNextExport() {
        let model = PencilCanvasModel()
        model.updateDrawing(Self.makeDrawing())

        model.clear()

        #expect(model.drawing.strokes.isEmpty)
        #expect(model.exportImage(canvasSize: CGSize(width: 500, height: 700), scale: 1) == nil)
    }

    @Test func testSimulatorCanvasAcceptsIndirectInputForManualTesting() {
        #if targetEnvironment(simulator)
        #expect(PencilCanvasInputPolicy.defaultDrawingPolicy == .anyInput)
        #else
        #expect(PencilCanvasInputPolicy.defaultDrawingPolicy == .pencilOnly)
        #endif
    }

    @Test func testIdleCommitFiresAfterConfiguredDelayUsingTestClock() async {
        let clock = TestClock()
        let committer = PencilCanvasIdleCommitter(
            delay: .milliseconds(2500),
            clock: clock
        )
        var commitCount = 0

        committer.drawingDidChange {
            commitCount += 1
        }
        await clock.waitForSleepers(count: 1)

        await clock.advance(by: .milliseconds(2499))
        #expect(commitCount == 0)

        await clock.advance(by: .milliseconds(1))
        await Task.yield()

        #expect(commitCount == 1)
    }

    private static func makeDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 100, y: 100),
                timeOffset: 0,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 220, y: 160),
                timeOffset: 0.2,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        return PKDrawing(strokes: [stroke])
    }
}

private actor TestClock: PencilCanvasClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var elapsed: Duration = .zero
    private var sleepers: [Sleeper] = []
    private var sleeperWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func sleep(for duration: Duration) async throws {
        try await isolatedSleep(for: duration)
    }

    private func isolatedSleep(for duration: Duration) async throws {
        let deadline = elapsed + duration
        if deadline <= elapsed {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(Sleeper(deadline: deadline, continuation: continuation))
            resumeReadySleeperWaiters()
        }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        let ready = sleepers.filter { $0.deadline <= elapsed }
        sleepers.removeAll { $0.deadline <= elapsed }
        for sleeper in ready {
            sleeper.continuation.resume()
        }
    }

    func waitForSleepers(count: Int) async {
        if sleepers.count >= count {
            return
        }

        await withCheckedContinuation { continuation in
            sleeperWaiters.append((count: count, continuation: continuation))
        }
    }

    private func resumeReadySleeperWaiters() {
        let ready = sleeperWaiters.filter { sleepers.count >= $0.count }
        sleeperWaiters.removeAll { sleepers.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
