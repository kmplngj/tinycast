import SwiftUI

struct ConfigurationSettingsSection: View {
    @Environment(ConfigurationCoordinator.self) private var coordinator

    var body: some View {
        Section {
            LabeledContent {
                Menu {
                    Button("This Mac — current storage") { Task { await coordinator.useThisMac() } }
                    Button("Dotfiles folder") {
                        Task { await coordinator.prepare(coordinator.preset, isPreset: true) }
                    }
                    Button("Custom folder…") { Task { await coordinator.chooseCustomFolder() } }
                } label: {
                    Text(coordinator.folder == nil ? "This Mac — current storage" : "Folder")
                }
                .accessibilityLabel("Configuration location")
                .accessibilityValue(coordinator.folder == nil ? "This Mac — current storage" : "Folder")
                .disabled(coordinator.busy)
            } label: {
                SettingsRowTitle(.configurationLocation, "Configuration location")
                Text(
                    "Changes are saved here automatically. Use yadm or a folder sync service to share this folder between Macs."
                )
            }
            if let folder = coordinator.folder {
                Text(folder.appendingPathComponent("settings.json").path)
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") { coordinator.reveal() }
                    Button("Reload") { coordinator.reload() }.disabled(coordinator.busy)
                    Spacer()
                    if coordinator.busy { ProgressView().controlSize(.small) }
                    Text(coordinator.status.rawValue).foregroundStyle(.secondary)
                }
            }
            Text(
                "Clipboard history, notes, snippets and learning stay on this Mac. "
                    + "They are not written to the configuration folder."
            )
            .foregroundStyle(.secondary)
            Text(coordinator.message).foregroundStyle(.secondary)
            if let selection = coordinator.selection {
                ConfigurationSelectionView(selection: selection)
            } else if coordinator.status == .conflict || coordinator.status == .review {
                ConfigurationReviewView()
            }
            if coordinator.status == .unavailable || coordinator.status == .invalid
                || coordinator.status == .conflict
            {
                Button("Reveal recovery files") { coordinator.revealRecovery() }
            }
        } header: {
            SettingsSectionHeader(.configurationLocation)
        }
    }
}
