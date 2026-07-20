import SwiftUI

struct DiaryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    private let onRequestSettings: () -> Void

    init(onRequestSettings: @escaping () -> Void = {}) {
        self.onRequestSettings = onRequestSettings
    }

    var body: some View {
        DiaryTurnContentView(
            dependencies: dependencies,
            onRequestSettings: onRequestSettings
        )
    }
}

private struct DiaryTurnContentView: View {
    @ObservedObject private var dependencies: DependencyContainer
    @StateObject private var controller: DiaryTurnController
    private let onRequestSettings: () -> Void

    init(dependencies: DependencyContainer, onRequestSettings: @escaping () -> Void) {
        self.dependencies = dependencies
        self.onRequestSettings = onRequestSettings
        _controller = StateObject(wrappedValue: DiaryTurnController(dependencies: dependencies))
    }

    var body: some View {
        DiaryPageView(
            controller: controller,
            replyFontName: dependencies.settings.selectedFontName,
            onRequestSettings: onRequestSettings
        )
    }
}

#Preview {
    DiaryView()
        .environmentObject(DependencyContainer())
}
