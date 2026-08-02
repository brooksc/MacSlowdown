import SwiftUI

/// Shell for the main window. The Now / Apps & processes / Incidents / Storage
/// surfaces land in later tasks; this establishes the sidebar structure only.
struct MainWindowView: View {
    @State private var selection: Section = .now

    enum Section: String, CaseIterable, Identifiable {
        case now = "Now"
        case apps = "Apps & Processes"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .now: "gauge.with.dots.needle.33percent"
            case .apps: "square.grid.2x2"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ContentUnavailableView(
                selection.rawValue,
                systemImage: selection.symbol,
                description: Text("Not implemented yet.")
            )
        }
        .navigationTitle("MacSlowdown")
        .onAppear { ActivationPolicy.mainWindowOpened() }
        .onDisappear { ActivationPolicy.mainWindowClosed() }
    }
}
