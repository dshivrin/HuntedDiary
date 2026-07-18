import Foundation

struct ConversationTurn: Identifiable, Equatable {
    nonisolated enum GenerationProvider: Equatable {
        case chatGPTExtensionShortcut
        case legacyOpenAI(model: String, storeEnabled: Bool)
    }

    var id: String
    var createdAt: Date
    var recognitionSource: RecognitionResult.Source
    var generationProvider: GenerationProvider
    var userText: String
    var assistantText: String

    init(
        id: String? = nil,
        createdAt: Date = Date(),
        recognitionSource: RecognitionResult.Source,
        generationProvider: GenerationProvider,
        userText: String,
        assistantText: String
    ) {
        self.createdAt = createdAt
        self.id = id ?? Self.makeID(createdAt: createdAt)
        self.recognitionSource = recognitionSource
        self.generationProvider = generationProvider
        self.userText = userText
        self.assistantText = assistantText
    }

    init(
        id: String? = nil,
        createdAt: Date = Date(),
        recognitionSource: RecognitionResult.Source,
        model: String,
        openAIStoreEnabled: Bool,
        userText: String,
        assistantText: String
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            recognitionSource: recognitionSource,
            generationProvider: .legacyOpenAI(
                model: model,
                storeEnabled: openAIStoreEnabled
            ),
            userText: userText,
            assistantText: assistantText
        )
    }

    private static func makeID(createdAt: Date) -> String {
        let timestamp = Self.idDateFormatter.string(from: createdAt)
        let suffix = UUID().uuidString.prefix(4)
        return "\(timestamp)-\(suffix)"
    }

    private static let idDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }()
}

extension ISO8601DateFormatter {
    static var history: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
