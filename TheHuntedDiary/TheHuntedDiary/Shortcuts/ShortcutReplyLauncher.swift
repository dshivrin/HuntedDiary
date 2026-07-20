import CryptoKit
import Foundation
import UIKit

@MainActor
protocol ShortcutReplyLaunching {
    func launch(shortcutName: String, handle: String, callbacks: ShortcutCallbacks) async throws
}

nonisolated struct ShortcutCallbacks: Sendable, CustomStringConvertible, CustomReflectable {
    static let callbackScheme = "toms-diary"

    let requestID: UUID
    let callbackCapabilityDigest: Data
    let cancelURL: URL
    let errorURL: URL

    init(requestID: UUID, callbackCapability: Data) throws {
        let authorization: DiaryReplyCapability
        do {
            authorization = try DiaryReplyCapability(
                requestID: requestID,
                capability: callbackCapability
            )
        } catch {
            throw InitializationError.invalidCapability
        }

        let token = String(
            authorization.handle.suffix(DiaryReplyCapability.encodedCapabilityLength)
        )
        guard let cancelURL = Self.makeCallbackURL(
            host: "shortcut-cancel",
            requestID: requestID,
            token: token
        ), let errorURL = Self.makeCallbackURL(
            host: "shortcut-error",
            requestID: requestID,
            token: token
        ) else {
            throw InitializationError.urlConstructionFailed
        }

        self.requestID = requestID
        self.callbackCapabilityDigest = Data(SHA256.hash(data: callbackCapability))
        self.cancelURL = cancelURL
        self.errorURL = errorURL
    }

    static func generate(requestID: UUID) throws -> Self {
        let capability = try DiaryReplyCapability.generate(requestID: requestID)
        return try Self(requestID: requestID, callbackCapability: capability.capability)
    }

    var description: String {
        "ShortcutCallbacks(request: \(requestPrefix)…)"
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["request": "\(requestPrefix)…"],
            displayStyle: .struct
        )
    }

    enum InitializationError: Error, Equatable {
        case invalidCapability
        case urlConstructionFailed
    }

    private var requestPrefix: String {
        String(requestID.uuidString.lowercased().prefix(8))
    }

    private static func makeCallbackURL(
        host: String,
        requestID: UUID,
        token: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "id", value: requestID.uuidString.lowercased()),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url
    }
}

nonisolated enum ShortcutReplyLauncherError: Error, Equatable, CaseIterable, CustomStringConvertible, LocalizedError {
    case invalidShortcutName
    case shortcutNameTooLong
    case invalidRequestHandle
    case callbackRequestMismatch
    case urlConstructionFailed
    case handoffRejected

    var description: String {
        switch self {
        case .invalidShortcutName:
            return "The reply Shortcut name is required."
        case .shortcutNameTooLong:
            return "The reply Shortcut name is too long."
        case .invalidRequestHandle:
            return "The diary reply request handle is invalid."
        case .callbackRequestMismatch:
            return "The Shortcut callbacks do not match the diary reply request."
        case .urlConstructionFailed:
            return "The Shortcut launch URL could not be created."
        case .handoffRejected:
            return "The Shortcuts app did not accept the launch request."
        }
    }

    var errorDescription: String? { description }
}

@MainActor
struct ShortcutReplyLauncher: ShortcutReplyLaunching {
    static let maximumShortcutNameUTF8Length = 128
    static let maximumLaunchURLUTF8Length = 4_096

    typealias OpenURL = @MainActor @Sendable (URL) async -> Bool
    typealias MakeURL = @MainActor @Sendable (URLComponents) -> URL?

    private let openURL: OpenURL
    private let makeURL: MakeURL

    init(
        openURL: @escaping OpenURL = { url in
            await UIApplication.shared.open(url, options: [:])
        },
        makeURL: @escaping MakeURL = { $0.url }
    ) {
        self.openURL = openURL
        self.makeURL = makeURL
    }

    func launch(
        shortcutName: String,
        handle: String,
        callbacks: ShortcutCallbacks
    ) async throws {
        guard !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShortcutReplyLauncherError.invalidShortcutName
        }
        guard shortcutName.utf8.count <= Self.maximumShortcutNameUTF8Length else {
            throw ShortcutReplyLauncherError.shortcutNameTooLong
        }

        let authorization: DiaryReplyCapability
        do {
            authorization = try DiaryReplyCapability(handle: handle)
        } catch {
            throw ShortcutReplyLauncherError.invalidRequestHandle
        }
        guard authorization.handle == handle else {
            throw ShortcutReplyLauncherError.invalidRequestHandle
        }
        guard authorization.requestID == callbacks.requestID else {
            throw ShortcutReplyLauncherError.callbackRequestMismatch
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: handle),
            URLQueryItem(name: "x-cancel", value: callbacks.cancelURL.absoluteString),
            URLQueryItem(name: "x-error", value: callbacks.errorURL.absoluteString),
        ]

        guard let url = makeURL(components),
              url.absoluteString.utf8.count <= Self.maximumLaunchURLUTF8Length else {
            throw ShortcutReplyLauncherError.urlConstructionFailed
        }
        guard await openURL(url) else {
            throw ShortcutReplyLauncherError.handoffRejected
        }
    }
}
