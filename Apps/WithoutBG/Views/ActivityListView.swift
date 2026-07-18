import SwiftUI

/// Scrollable list of recent HTTP requests.
struct ActivityListView: View {
    enum Style {
        case standalone
        case embedded
    }

    @Environment(RecentActivity.self) private var activity

    var style: Style = .standalone

    var body: some View {
        Group {
            if activity.entries.isEmpty {
                emptyState
            } else if style == .standalone {
                standaloneList
            } else {
                embeddedList
            }
        }
        .safeAreaInset(edge: .bottom) {
            if style == .standalone, !activity.entries.isEmpty {
                clearButtonBar
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Activity Yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Send a request to your endpoint to see activity here.")
        }
    }

    private var standaloneList: some View {
        List {
            ForEach(activity.entries) { entry in
                ActivityRow(entry: entry)
            }
        }
        .listStyle(.inset)
    }

    private var embeddedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activity.entries) { entry in
                ActivityRow(entry: entry)
                if entry.id != activity.entries.last?.id {
                    Divider()
                }
            }

            Button("Clear Activity") {
                activity.clear()
            }
        }
    }

    private var clearButtonBar: some View {
        HStack {
            Spacer()
            Button("Clear Activity") {
                activity.clear()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(entry.method) \(entry.path)")
                    .font(.caption.monospaced())
                    .lineLimit(1)

                Spacer(minLength: 8)

                statusBadge

                if let latencyMs = entry.latencyMs {
                    Text("\(latencyMs) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let detail = entry.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(entry.isSuccess ? Color.secondary : Color.red)
                    .lineLimit(2)
            }

            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text("\(entry.statusCode)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch entry.statusCode {
        case 200..<300:
            return .green
        case 400..<500:
            return .orange
        default:
            return .red
        }
    }
}
