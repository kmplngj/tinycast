import SwiftUI

struct ConfigurationSelectionView: View {
    @Environment(ConfigurationCoordinator.self) private var coordinator
    let selection: ConfigurationCoordinator.Selection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(selection.folder.appendingPathComponent("settings.json").path).textSelection(.enabled)
            Text("Layouts use primary, secondary and tertiary display roles on each Mac.")
                .foregroundStyle(.secondary)
            if selection.document == nil {
                Text("Use this folder to create settings.json from this Mac’s portable settings.")
                Button("Use This Folder") { Task { await coordinator.activate(replace: false) } }
            } else {
                Text("This folder already has settings. Choose which version to use.")
                Text(
                    coordinator.differences.isEmpty
                        ? "No portable differences." : coordinator.differences.joined(separator: "\n")
                )
                .textSelection(.enabled)
                if !coordinator.reviewText.isEmpty {
                    Text(
                        "Review the shell commands below. Using folder settings approves these revisions on this Mac."
                    )
                    Text(coordinator.reviewText).font(.system(.caption, design: .monospaced)).textSelection(
                        .enabled)
                }
                Button("Use Folder Settings") { Task { await coordinator.activate(replace: false) } }
                Button("Replace With This Mac’s Settings") {
                    Task { await coordinator.activate(replace: true) }
                }
                Text("Replacing keeps the previous file in local recovery.").foregroundStyle(.secondary)
            }
            Button("Cancel") { coordinator.cancelSelection() }
        }
        .disabled(coordinator.busy)
    }
}
