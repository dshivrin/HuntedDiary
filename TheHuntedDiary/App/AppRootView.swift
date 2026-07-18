//
//  AppRootView.swift
//  TheHuntedDiary
//
//  Created by Dima Shivrin on 07/07/2026.
//

import SwiftUI

struct AppRootView: View {
    @ObservedObject var dependencies: DependencyContainer
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            DiaryView()
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
                _ = await dependencies.diaryReplyFlow.handle(url)
            }
        }
    }
}

#Preview {
    let dependencies = DependencyContainer()
    AppRootView(dependencies: dependencies)
        .environmentObject(dependencies)
}
