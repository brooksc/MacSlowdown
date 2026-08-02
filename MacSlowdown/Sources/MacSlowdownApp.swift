import SwiftUI

@main
struct MacSlowdownApp: App {
    /// Scene wiring and dependency injection only — no business logic here.
    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            // Severity is never conveyed by colour alone (FR-034), so the menu bar
            // label leads with shape. A template symbol is a placeholder until the
            // designed icon system lands.
            Image(systemName: "gauge.with.dots.needle.33percent")
                .accessibilityLabel("MacSlowdown")
        }
        .menuBarExtraStyle(.window)

        Window("MacSlowdown", id: MainWindow.id) {
            MainWindowView()
        }
        .defaultSize(width: 900, height: 600)
    }
}

enum MainWindow {
    static let id = "main"
}
