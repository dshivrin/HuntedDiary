import SwiftUI

struct DiaryPageView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            DiaryCanvasView()
            ReplyTextView(text: "")
        }
    }
}
