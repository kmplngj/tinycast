import SwiftUI

struct ConfigurationReviewView: View {
    @Environment(ConfigurationCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(coordinator.differences.joined(separator: "\n")).textSelection(.enabled)
            if coordinator.status == .review {
                Text(coordinator.reviewText).font(.system(.caption, design: .monospaced)).textSelection(
                    .enabled)
                Button("Approve These Commands and Bindings") { Task { await coordinator.approve() } }
            } else {
                HStack {
                    Button("Keep This Mac") { Task { await coordinator.resolve(useFolder: false) } }
                    Button("Use Folder Version") { Task { await coordinator.resolve(useFolder: true) } }
                }
                Text(
                    "Or resolve settings.json externally, then Reload. Both versions remain in local recovery."
                )
                .foregroundStyle(.secondary)
            }
        }
        .disabled(coordinator.busy)
    }
}
