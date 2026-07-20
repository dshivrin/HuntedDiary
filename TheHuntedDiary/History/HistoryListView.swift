import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @State private var turns: [ConversationTurn] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(turn.userText)
                        .font(.headline)
                        .lineLimit(2)
                    Text(turn.assistantText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteTurns)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear") {
                    clearHistory()
                }
                .disabled(turns.isEmpty)
            }
        }
        .task {
            loadHistory()
        }
    }
}

private extension HistoryListView {
    func loadHistory() {
        do {
            turns = try dependencies.historyStore.loadAll()
            errorMessage = nil
        } catch {
            errorMessage = "History could not be loaded."
        }
    }

    func deleteTurns(at offsets: IndexSet) {
        do {
            for offset in offsets {
                try dependencies.historyStore.deleteTurn(id: turns[offset].id)
            }
            loadHistory()
        } catch {
            errorMessage = "History could not be updated."
        }
    }

    func clearHistory() {
        do {
            try dependencies.historyStore.deleteAll()
            loadHistory()
        } catch {
            errorMessage = "History could not be cleared."
        }
    }
}
