import Foundation

struct ConversationTurn: Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var userText: String
    var assistantText: String
}
