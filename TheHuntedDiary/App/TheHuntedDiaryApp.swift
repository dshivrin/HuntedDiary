//
//  TheHuntedDiaryApp.swift
//  TheHuntedDiary
//
//  Created by Dima Shivrin on 07/07/2026.
//

import SwiftUI

@main
struct TheHuntedDiaryApp: App {
    @StateObject private var dependencies = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
                .environmentObject(dependencies)
        }
    }
}
