import Testing
@testable import TheHuntedDiary

@MainActor
struct PencilCanvasIdleCancellationTask2Tests {
    @Test func newStrokeCancelsEarlierIdleCommit() async {
        let clock = IdleCancellationClock()
        let committer = PencilCanvasIdleCommitter(
            delay: .milliseconds(2500),
            clock: clock
        )
        var firstCommitCount = 0
        var latestCommitCount = 0

        committer.drawingDidChange {
            firstCommitCount += 1
        }
        await clock.waitForSleepers(count: 1)

        committer.drawingDidChange {
            latestCommitCount += 1
        }
        await clock.waitForSleepers(count: 2)

        await clock.advance(by: .milliseconds(2500))
        for _ in 0 ..< 100 where latestCommitCount == 0 {
            await Task.yield()
        }

        #expect(firstCommitCount == 0)
        #expect(latestCommitCount == 1)
    }
}

private actor IdleCancellationClock: PencilCanvasClock {
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
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(Sleeper(deadline: elapsed + duration, continuation: continuation))
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
