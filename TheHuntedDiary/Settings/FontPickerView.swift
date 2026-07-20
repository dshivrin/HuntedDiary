import SwiftUI

struct FontPickerView: View {
    @Binding var selectedFontName: String
    var fonts = AppSettings.availableHandwritingFonts

    var body: some View {
        Picker("Reply font", selection: $selectedFontName) {
            ForEach(fonts) { font in
                Text(font.displayName)
                    .tag(font.fontName)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedFontName = AppSettings().selectedFontName

    Form {
        FontPickerView(selectedFontName: $selectedFontName)
    }
}
