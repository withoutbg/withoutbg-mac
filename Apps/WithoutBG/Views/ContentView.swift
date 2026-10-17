import SwiftUI

/// Sidebar destinations for the main window.
enum AppDestination: String, Hashable, CaseIterable, Identifiable {
    case backgroundRemoval
    case productPlacement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgroundRemoval: "Background Removal"
        case .productPlacement: "Product Placement"
        }
    }

    var systemImage: String {
        switch self {
        case .backgroundRemoval: "person.and.background.dotted"
        case .productPlacement: "cube"
        }
    }
}

/// Root content. Native macOS sidebar + detail for each feature area.
struct ContentView: View {
    @State private var destination: AppDestination? = .backgroundRemoval

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                ForEach(AppDestination.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            switch destination ?? .backgroundRemoval {
            case .backgroundRemoval:
                BackgroundRemovalView()
            case .productPlacement:
                ProductPlacementView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
