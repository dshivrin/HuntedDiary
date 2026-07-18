//
//  TheHuntedDiaryApp.swift
//  TheHuntedDiary
//
//  Created by Dima Shivrin on 07/07/2026.
//

import AppIntents
import SwiftUI

@main
struct TheHuntedDiaryApp: App {
    @StateObject private var dependencies: DependencyContainer

    init() {
        let dependencies = DependencyContainer()
        AppDependencyManager.shared.add(dependency: dependencies.pendingDiaryReplyStore)
        _dependencies = StateObject(wrappedValue: dependencies)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
                .environmentObject(dependencies)
        }
    }
}
