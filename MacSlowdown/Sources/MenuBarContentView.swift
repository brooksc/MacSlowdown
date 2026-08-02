import SwiftUI

/// Compact persistent status surface (FR-001).
///
/// Render-only: it reads from the store and opens windows. No sampling or state
/// transitions happen here.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacSlowdown")
                .font(.headline)

            Text("Monitoring is not running yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Open MacSlowdown") {
                openWindow(id: MainWindow.id)
                ActivationPolicy.mainWindowOpened()
            }
            .keyboardShortcut("o")

            Button("Quit MacSlowdown") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}
