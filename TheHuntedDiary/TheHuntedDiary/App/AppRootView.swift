//
//  AppRootView.swift
//  TheHuntedDiary
//
//  Created by Dima Shivrin on 07/07/2026.
//

import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var dependencies: DependencyContainer
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            DiaryView {
                isShowingSettings = true
            }
                .environmentObject(dependencies)
                .navigationTitle("Diary")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    NavigationStack {
                        SettingsView()
                            .navigationTitle("Settings")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        isShowingSettings = false
                                    }
                                }
                            }
                    }
                    .environmentObject(dependencies)
                }
        }
        .onOpenURL { url in
            Task {
                await dependencies.handleOpenURL(url)
            }
        }
        .task {
            await dependencies.shortcutSetupCoordinator.reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await dependencies.shortcutSetupCoordinator.reconcile()
            }
        }
    }
}

#Preview {
    let dependencies = DependencyContainer()
    AppRootView(dependencies: dependencies)
        .environmentObject(dependencies)
}
