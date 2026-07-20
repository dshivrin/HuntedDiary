import SwiftUI

struct ReplyTextView: View {
    let text: String
    let fontName: String
    let animatesReveal: Bool

    @State private var visibleText = ""

    init(text: String, fontName: String, animatesReveal: Bool = true) {
        self.text = text
        self.fontName = fontName
        self.animatesReveal = animatesReveal
        _visibleText = State(initialValue: animatesReveal ? "" : text)
    }

    var body: some View {
        Group {
            if visibleText.isEmpty {
                EmptyView()
            } else {
                Text(visibleText)
                    .font(.custom(fontName, size: 34, relativeTo: .title2))
                    .lineSpacing(7)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 36)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                    .transition(.opacity)
            }
        }
        .onAppear {
            AppSettings.registerBundledHandwritingFonts()
        }
        .task(id: text) {
            if animatesReveal {
                await reveal(text)
            } else {
                visibleText = text
            }
        }
    }

    @MainActor
    private func reveal(_ targetText: String) async {
        guard targetText.isEmpty == false else {
            visibleText = ""
            return
        }

        if targetText.hasPrefix(visibleText) == false {
            visibleText = ""
        }

        var nextText = visibleText
        for character in targetText.dropFirst(nextText.count) {
            nextText.append(character)
            visibleText = nextText

            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
        }
    }
}

#Preview {
    ReplyTextView(
        text: "The ink stirs, slowly, as if it has been waiting for your hand.",
        fontName: AppSettings().selectedFontName
    )
}
