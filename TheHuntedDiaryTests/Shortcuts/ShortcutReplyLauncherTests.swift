import Foundation
import Testing
@testable import TheHuntedDiary

@MainActor
struct ShortcutReplyLauncherTests {
    private let requestID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!

    @Test func buildsExactShortcutsRunURLWithOpaqueInputAndAuthenticatedNestedCallbacks() async throws {
        let requestCapability = try DiaryReplyCapability(
            requestID: requestID,
            capability: Data(repeating: 0x11, count: 32)
        )
        let callbacks = try ShortcutCallbacks(
            requestID: requestID,
            callbackCapability: Data(repeating: 0x22, count: 32)
        )
        let recorder = URLRecorder(result: true)
        let launcher = ShortcutReplyLauncher(openURL: recorder.open)

        try await launcher.launch(
            shortcutName: "Tom’s Diary Reply",
            handle: requestCapability.handle,
            callbacks: callbacks
        )

        let url = try #require(recorder.urls.first)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "shortcuts")
        #expect(components.host == "x-callback-url")
        #expect(components.path == "/run-shortcut")
        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.port == nil)
        #expect(components.fragment == nil)

        let items = try uniqueItems(components)
        #expect(Set(items.keys) == ["name", "input", "text", "x-cancel", "x-error"])
        #expect(items["name"] == "Tom’s Diary Reply")
        #expect(items["input"] == "text")
        #expect(items["text"] == requestCapability.handle)

        let cancel = try callbackComponents(items["x-cancel"])
        let failure = try callbackComponents(items["x-error"])
        try expectCallback(cancel, host: "shortcut-cancel", callbacks: callbacks)
        try expectCallback(failure, host: "shortcut-error", callbacks: callbacks)

        #expect(!url.absoluteString.contains("recognized diary words"))
        #expect(!url.absoluteString.contains("frozen prompt"))
        #expect(!url.absoluteString.contains("assistant reply"))
        #expect(!url.absoluteString.contains("external error message"))
    }

    @Test func preservesTheConfiguredShortcutNameExactly() async throws {
        let fixture = try launcherFixture(openResult: true)
        try await fixture.launcher.launch(
            shortcutName: "  Exact Name  ",
            handle: fixture.handle,
            callbacks: fixture.callbacks
        )

        let url = try #require(fixture.recorder.urls.first)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(try uniqueItems(components)["name"] == "  Exact Name  ")
    }

    @Test(arguments: ["", "  \n\t"])
    func rejectsBlankShortcutNames(_ name: String) async throws {
        let fixture = try launcherFixture(openResult: true)
        await expectLauncherError(.invalidShortcutName) {
            try await fixture.launcher.launch(
                shortcutName: name,
                handle: fixture.handle,
                callbacks: fixture.callbacks
            )
        }
        #expect(fixture.recorder.urls.isEmpty)
    }

    @Test func rejectsOversizedShortcutNameBeforeOpeningURL() async throws {
        let fixture = try launcherFixture(openResult: true)
        let name = String(repeating: "a", count: ShortcutReplyLauncher.maximumShortcutNameUTF8Length + 1)
        await expectLauncherError(.shortcutNameTooLong) {
            try await fixture.launcher.launch(
                shortcutName: name,
                handle: fixture.handle,
                callbacks: fixture.callbacks
            )
        }
        #expect(fixture.recorder.urls.isEmpty)
    }

    @Test(arguments: ["", "not-a-handle", String(repeating: "a", count: 81)])
    func rejectsBlankMalformedAndOversizedHandles(_ handle: String) async throws {
        let fixture = try launcherFixture(openResult: true)
        await expectLauncherError(.invalidRequestHandle) {
            try await fixture.launcher.launch(
                shortcutName: "Tom’s Diary Reply",
                handle: handle,
                callbacks: fixture.callbacks
            )
        }
        #expect(fixture.recorder.urls.isEmpty)
    }

    @Test func rejectsCallbacksForAnotherRequest() async throws {
        let fixture = try launcherFixture(openResult: true)
        let otherCallbacks = try ShortcutCallbacks(
            requestID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            callbackCapability: Data(repeating: 0x22, count: 32)
        )
        await expectLauncherError(.callbackRequestMismatch) {
            try await fixture.launcher.launch(
                shortcutName: "Tom’s Diary Reply",
                handle: fixture.handle,
                callbacks: otherCallbacks
            )
        }
        #expect(fixture.recorder.urls.isEmpty)
    }

    @Test func rejectsURLConstructionFailureWithoutCallingTheOpener() async throws {
        let fixture = try launcherFixture(openResult: true, makeURL: { _ in nil })
        await expectLauncherError(.urlConstructionFailed) {
            try await fixture.launcher.launch(
                shortcutName: "Tom’s Diary Reply",
                handle: fixture.handle,
                callbacks: fixture.callbacks
            )
        }
        #expect(fixture.recorder.urls.isEmpty)
    }

    @Test func falseOpenResultMeansHandoffWasRejected() async throws {
        let fixture = try launcherFixture(openResult: false)
        await expectLauncherError(.handoffRejected) {
            try await fixture.launcher.launch(
                shortcutName: "Tom’s Diary Reply",
                handle: fixture.handle,
                callbacks: fixture.callbacks
            )
        }
        #expect(fixture.recorder.urls.count == 1)
    }

    @Test func launchAwaitsTheAsynchronousOpenResult() async throws {
        let gate = URLGate()
        let fixture = try launcherFixture(openResult: true, openURL: gate.open)
        let completion = CompletionFlag()

        let task = Task {
            try await fixture.launcher.launch(
                shortcutName: "Tom’s Diary Reply",
                handle: fixture.handle,
                callbacks: fixture.callbacks
            )
            await completion.markCompleted()
        }

        await gate.waitUntilOpened()
        #expect(await completion.isCompleted == false)
        gate.resume(with: true)
        try await task.value
        #expect(await completion.isCompleted)
    }

    @Test func diagnosticsAreBoundedAndRedactCapabilitiesAndInput() async throws {
        let callbacks = try ShortcutCallbacks(
            requestID: requestID,
            callbackCapability: Data(repeating: 0xAB, count: 32)
        )
        let secretToken = try callbackToken(callbacks)
        let diagnostic = String(reflecting: callbacks)

        #expect(!diagnostic.contains(secretToken))
        #expect(diagnostic.count < 128)
        for error in ShortcutReplyLauncherError.allCases {
            #expect(error.description.count < 128)
            #expect(!error.description.contains(secretToken))
            #expect(!error.description.contains("diary text"))
        }
    }

    private func launcherFixture(
        openResult: Bool,
        openURL: (@MainActor @Sendable (URL) async -> Bool)? = nil,
        makeURL: @escaping @MainActor @Sendable (URLComponents) -> URL? = { $0.url }
    ) throws -> (
        launcher: ShortcutReplyLauncher,
        recorder: URLRecorder,
        handle: String,
        callbacks: ShortcutCallbacks
    ) {
        let capability = try DiaryReplyCapability(
            requestID: requestID,
            capability: Data(repeating: 0x11, count: 32)
        )
        let callbacks = try ShortcutCallbacks(
            requestID: requestID,
            callbackCapability: Data(repeating: 0x22, count: 32)
        )
        let recorder = URLRecorder(result: openResult)
        return (
            ShortcutReplyLauncher(openURL: openURL ?? recorder.open, makeURL: makeURL),
            recorder,
            capability.handle,
            callbacks
        )
    }

    private func expectCallback(
        _ components: URLComponents,
        host: String,
        callbacks: ShortcutCallbacks
    ) throws {
        #expect(components.scheme == ShortcutCallbacks.callbackScheme)
        #expect(components.host == host)
        #expect(components.path.isEmpty)
        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.port == nil)
        #expect(components.fragment == nil)
        let items = try uniqueItems(components)
        let expectedToken = try callbackToken(callbacks)
        #expect(Set(items.keys) == ["id", "token"])
        #expect(items["id"] == requestID.uuidString.lowercased())
        #expect(items["token"] == expectedToken)
    }

    private func callbackComponents(_ value: String?) throws -> URLComponents {
        let value = try #require(value)
        let url = try #require(URL(string: value))
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    private func callbackToken(_ callbacks: ShortcutCallbacks) throws -> String {
        let url = callbacks.cancelURL
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return try #require(uniqueItems(components)["token"])
    }

    private func uniqueItems(_ components: URLComponents) throws -> [String: String] {
        let items = try #require(components.queryItems)
        var result: [String: String] = [:]
        for item in items {
            #expect(result[item.name] == nil)
            guard let value = item.value else {
                Issue.record("Expected a callback query value")
                continue
            }
            result[item.name] = value
        }
        return result
    }
}

@MainActor
private final class URLRecorder {
    let result: Bool
    private(set) var urls: [URL] = []

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) async -> Bool {
        urls.append(url)
        return result
    }
}

@MainActor
private final class URLGate {
    private var openContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<Bool, Never>?
    private var didOpen = false

    func open(_ url: URL) async -> Bool {
        didOpen = true
        openContinuation?.resume()
        openContinuation = nil
        return await withCheckedContinuation { resultContinuation = $0 }
    }

    func waitUntilOpened() async {
        guard !didOpen else { return }
        await withCheckedContinuation { openContinuation = $0 }
    }

    func resume(with result: Bool) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private actor CompletionFlag {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

@MainActor
private func expectLauncherError(
    _ expected: ShortcutReplyLauncherError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected launcher error \(expected)")
    } catch let error as ShortcutReplyLauncherError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected bounded launcher error type")
    }
}
