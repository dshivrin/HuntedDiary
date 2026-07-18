import SwiftUI

nonisolated enum ShortcutSetupCopy {
    static let replyShortcutNameLabel = "Reply Shortcut Name"
    static let testShortcutButton = "Test Shortcut"
    static let setupGuideLink = "Setup Guide"
    static let help = "Create a Shortcut with Get Pending Diary Prompt, Use Model set to the ChatGPT Extension Model, and Complete Diary Reply, in that order."
    static let accountGuidance = "A ChatGPT account is optional. A complete Test Shortcut round trip is the only verification; Tom’s Diary cannot inspect account, subscription, extension, region, or Shortcut availability in advance."
    static let compatibilityGuidance = "iPad mini 6 cannot run this workflow because it does not support Apple Intelligence."
}

struct ShortcutSettingsSection: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @State private var isShowingHelp = false

    var body: some View {
        ShortcutSettingsContent(
            dependencies: dependencies,
            coordinator: dependencies.shortcutSetupCoordinator,
            isShowingHelp: $isShowingHelp
        )
    }
}

private struct ShortcutSettingsContent: View {
    @ObservedObject var dependencies: DependencyContainer
    @ObservedObject var coordinator: ShortcutSetupCoordinator
    @Binding var isShowingHelp: Bool

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                TextField(
                    ShortcutSetupCopy.replyShortcutNameLabel,
                    text: Binding(
                        get: { dependencies.settings.replyShortcutName },
                        set: dependencies.updateReplyShortcutName
                    )
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

                Button {
                    isShowingHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shortcut Setup Help")
            }

            if isShowingHelp {
                Text(ShortcutSetupCopy.help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            NavigationLink(ShortcutSetupCopy.setupGuideLink) {
                ShortcutSetupGuideView()
            }

            Button(ShortcutSetupCopy.testShortcutButton) {
                Task {
                    await coordinator.testShortcut()
                }
            }
            .disabled(coordinator.state.isBusy)

            setupStatus
        } header: {
            Text("Shortcut Reply")
        } footer: {
            Text(ShortcutSetupCopy.accountGuidance)
        }
        .task {
            await coordinator.reconcile()
        }
    }

    @ViewBuilder
    private var setupStatus: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .preparing:
            HStack {
                ProgressView()
                Text("Preparing Shortcut test…")
            }
        case .awaitingReply:
            Text("Waiting for the Shortcut to complete…")
                .foregroundStyle(.secondary)
        case let .verified(name, date):
            VStack(alignment: .leading, spacing: 2) {
                Label("Verified: \(name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(date, format: .dateTime.year().month().day().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case let .failed(failure):
            Text(failure.description)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutSetupGuideView: View {
    var body: some View {
        List {
            Section("Shortcut actions") {
                Text("1. Get Pending Diary Prompt — Request Handle = Shortcut Input")
                Text("2. Use Model — Extension Model → ChatGPT; Follow Up off")
                Text("3. Complete Diary Reply — Request Handle = Shortcut Input; Reply = Use Model response")
            }

            Section("Requirements") {
                Text("Use an Apple Intelligence-compatible iPhone or iPad with iOS or iPadOS 26 and the ChatGPT extension enabled.")
                Text(ShortcutSetupCopy.compatibilityGuidance)
                Text("A ChatGPT account is optional.")
            }

            Section("Verification") {
                Text("Return to Settings and choose Test Shortcut. Opening Shortcuts alone does not verify the setup; the complete probe must return successfully.")
            }
        }
        .navigationTitle("Setup Guide")
    }
}
