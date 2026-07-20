import Foundation

protocol DiaryHistoryStoring {
    func loadRecent(limit: Int) throws -> [ConversationTurn]
    func append(_ turn: ConversationTurn) throws
    func pruneOldestTurns(keepingMaximum maximumStoredTurns: Int) throws
}

struct PlainTextHistoryStore: DiaryHistoryStoring {
    let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("History", isDirectory: true)
        }
    }

    func append(_ turn: ConversationTurn) throws {
        try ensureDirectoryExists()
        let data = markdown(for: turn).data(using: .utf8) ?? Data()
        try data.write(to: fileURL(for: turn.id), options: [.atomic])
    }

    func loadAll() throws -> [ConversationTurn] {
        try ensureDirectoryExists()
        return try historyFileURLs()
            .map { try loadTurn(from: $0) }
            .sortedByCreatedAtAndID()
    }

    func loadRecent(limit: Int) throws -> [ConversationTurn] {
        guard limit > 0 else { return [] }
        let turns = try loadAll()
        return Array(turns.suffix(limit))
    }

    func deleteTurn(id: String) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteAll() throws {
        for url in try historyFileURLs() {
            try fileManager.removeItem(at: url)
        }
    }

    func pruneOldestTurns(keepingMaximum maximumStoredTurns: Int) throws {
        guard maximumStoredTurns > 0 else {
            try deleteAll()
            return
        }

        let turns = try loadAll()
        let deleteCount = turns.count - maximumStoredTurns
        guard deleteCount > 0 else { return }

        for turn in turns.prefix(deleteCount) {
            try deleteTurn(id: turn.id)
        }
    }
}

private extension PlainTextHistoryStore {
    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func historyFileURLs() throws -> [URL] {
        try ensureDirectoryExists()
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "md" }
    }

    func fileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent(id, isDirectory: false).appendingPathExtension("md")
    }

    func loadTurn(from url: URL) throws -> ConversationTurn {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parseTurn(from: contents)
    }

    func markdown(for turn: ConversationTurn) -> String {
        let providerFrontMatter: String
        switch turn.generationProvider {
        case .chatGPTExtensionShortcut:
            providerFrontMatter = "generationProvider: chatGPTExtensionShortcut"
        case let .legacyOpenAI(model, storeEnabled):
            providerFrontMatter = "model: \(escapeFrontMatter(model))\nopenAIStoreEnabled: \(storeEnabled)"
        }
        return """
        ---
        id: \(escapeFrontMatter(turn.id))
        createdAt: \(ISO8601DateFormatter.history.string(from: turn.createdAt))
        recognition: \(escapeFrontMatter(turn.recognitionSource.rawValue))
        \(providerFrontMatter)
        ---

        User:
        \(normalizeLineEndings(turn.userText))

        Assistant:
        \(normalizeLineEndings(turn.assistantText))
        """
        + "\n"
    }

    func parseTurn(from contents: String) throws -> ConversationTurn {
        let normalized = normalizeLineEndings(contents)
        guard normalized.hasPrefix("---\n") else {
            throw PlainTextHistoryStoreError.invalidFormat
        }

        let frontMatterSearchStart = normalized.index(normalized.startIndex, offsetBy: 4)
        guard let frontMatterEnd = normalized.range(
            of: "\n---\n",
            range: frontMatterSearchStart..<normalized.endIndex
        ) else {
            throw PlainTextHistoryStoreError.invalidFormat
        }

        let frontMatter = String(normalized[frontMatterSearchStart..<frontMatterEnd.lowerBound])
        let fields = parseFrontMatter(frontMatter)

        guard
            let id = fields["id"].map(unescapeFrontMatter),
            let createdAtString = fields["createdAt"].map(unescapeFrontMatter),
            let createdAt = ISO8601DateFormatter.history.date(from: createdAtString),
            let recognitionRawValue = fields["recognition"].map(unescapeFrontMatter),
            let recognitionSource = RecognitionResult.Source(rawValue: recognitionRawValue),
            let generationProvider = generationProvider(from: fields)
        else {
            throw PlainTextHistoryStoreError.invalidFormat
        }

        let body = String(normalized[frontMatterEnd.upperBound...])
        guard
            let userMarker = body.range(of: "\nUser:\n"),
            let assistantMarker = body.range(
                of: "\n\nAssistant:\n",
                range: userMarker.upperBound..<body.endIndex
            )
        else {
            throw PlainTextHistoryStoreError.invalidFormat
        }

        let userText = String(body[userMarker.upperBound..<assistantMarker.lowerBound])
        var assistantText = String(body[assistantMarker.upperBound...])
        if assistantText.hasSuffix("\n") {
            assistantText.removeLast()
        }

        return ConversationTurn(
            id: id,
            createdAt: createdAt,
            recognitionSource: recognitionSource,
            generationProvider: generationProvider,
            userText: userText,
            assistantText: assistantText
        )
    }

    func generationProvider(
        from fields: [String: String]
    ) -> ConversationTurn.GenerationProvider? {
        if fields["generationProvider"].map(unescapeFrontMatter) == "chatGPTExtensionShortcut" {
            return .chatGPTExtensionShortcut
        }
        guard let model = fields["model"].map(unescapeFrontMatter),
              let storeString = fields["openAIStoreEnabled"].map(unescapeFrontMatter),
              let storeEnabled = Bool(storeString) else {
            return nil
        }
        return .legacyOpenAI(model: model, storeEnabled: storeEnabled)
    }

    func parseFrontMatter(_ frontMatter: String) -> [String: String] {
        frontMatter
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(into: [String: String]()) { fields, line in
                guard let separatorIndex = line.firstIndex(of: ":") else { return }
                let key = String(line[..<separatorIndex])
                let valueStart = line.index(after: separatorIndex)
                let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
    }

    func normalizeLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func escapeFrontMatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    func unescapeFrontMatter(_ value: String) -> String {
        var result = ""
        var isEscaping = false

        for character in value {
            if isEscaping {
                switch character {
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                default:
                    result.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }
}

private extension Array where Element == ConversationTurn {
    func sortedByCreatedAtAndID() -> [ConversationTurn] {
        sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }
}

enum PlainTextHistoryStoreError: Error, Equatable {
    case invalidFormat
}
