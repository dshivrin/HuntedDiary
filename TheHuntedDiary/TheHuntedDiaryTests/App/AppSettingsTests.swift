import Testing
@testable import TheHuntedDiary

struct AppSettingsTests {
    @Test func testDefaultFontIsBundledCaveatRegular() {
        let settings = AppSettings()

        #expect(settings.selectedFontName == "Caveat-Regular")
    }

    @Test func testOnlyBundledFontIsExposedForMVP() {
        #expect(AppSettings.availableHandwritingFonts == [
            AppSettings.HandwritingFont(displayName: "Caveat Regular", fontName: "Caveat-Regular", resourceName: "Caveat-Regular.ttf")
        ])
    }
}
