import Metrics
import SwiftUI

/// The mute sheet (design 1g, middle panel).
///
/// The design draws this as a popup menu with a footer. It is built as a sheet
/// because the footer is load-bearing — it is the sentence that stops "mute" from
/// reading as "stop watching" — and an `NSMenu` gives no reliable place to put a
/// paragraph a person will actually read.
///
/// Selection is shown with a checkmark **and** a filled row, never colour alone
/// (FR-034).
struct MuteAlertsView: View {
    let store: MonitorStore
    @Environment(\.dismiss) private var dismiss

    /// Fixed at the moment the sheet appears. Rebuilding the options on every
    /// redraw would make "Until 6:00 PM" a moving target and would make the
    /// checkmark flicker as the remaining minutes drifted past the tolerance.
    @State private var openedAt = Date()

    private var choices: [MuteAlerts.Choice] { MuteAlerts.choices(now: openedAt) }
    private var selection: MuteAlerts.Choice.ID? {
        MuteAlerts.selection(for: store.mute, choices: choices, now: openedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MuteAlerts.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ForEach(choices) { choice in
                choiceRow(choice)
            }

            Divider().padding(.vertical, 10)

            Text(MuteAlerts.footer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            HStack {
                if selection != nil {
                    Button("Turn alerts back on") {
                        store.clearMute()
                        dismiss()
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .padding(.vertical, 16)
        .frame(width: 340)
    }

    @ViewBuilder
    private func choiceRow(_ choice: MuteAlerts.Choice) -> some View {
        let isSelected = selection == choice.id
        Button {
            store.mute(forMinutes: choice.minutes)
            dismiss()
        } label: {
            HStack {
                Text(choice.title)
                Spacer()
                // Shape, not colour: the checkmark carries the state on its own.
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(.selection)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(isSelected ? "\(choice.title), current" : choice.title)
    }
}

/// Where the mute sheet is asked for.
///
/// A shared flag rather than a binding threaded through the interface: the sheet
/// is raised from places that have no view of their own — a notification action,
/// a menu command — and each one only needs to say "show it".
@MainActor
@Observable
final class MuteSheetPresenter {
    static let shared = MuteSheetPresenter()
    var isPresented = false

    func present() { isPresented = true }
}

extension View {
    /// Hosts the mute sheet. Applied once, to the main window.
    func muteAlertsSheet(store: MonitorStore) -> some View {
        modifier(MuteAlertsSheetHost(store: store))
    }
}

private struct MuteAlertsSheetHost: ViewModifier {
    let store: MonitorStore
    @Bindable private var presenter = MuteSheetPresenter.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presenter.isPresented) {
            MuteAlertsView(store: store)
        }
    }
}
