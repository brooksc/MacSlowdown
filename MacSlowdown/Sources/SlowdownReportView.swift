import Metrics
import SwiftUI

/// Which part of the report gesture the popover is showing (design 5d, 6d).
///
/// A state on the popover rather than a sheet or a window, deliberately. Someone
/// who has just told us their Mac feels slow is trying to get back to work; putting
/// the reply behind a window that has to be found, moved and closed would cost them
/// more attention than the report did.
enum SlowdownReportFlow: Equatable {
    /// The popover's ordinary content.
    case none
    /// "It was slow a few minutes ago…" — the three buckets of design 6d.
    case picking
    /// The reply to a report just filed.
    case reply(SlowdownReport)
    /// Every report kept, so the record can be reviewed and withdrawn.
    case list
}

/// The reply, the picker and the list (FR-064, design 5d and 6d).
///
/// Render-only, like the rest of the popover: every sentence comes from
/// `SlowdownReportPresentation` and every figure from the report's own recorded
/// evidence. Nothing here samples, and nothing re-derives what was measured — a
/// report describes the machine the user was complaining about, not this one.
struct SlowdownReportPanel: View {
    let store: MonitorStore
    @Binding var flow: SlowdownReportFlow

    var body: some View {
        switch flow {
        case .none:
            EmptyView()
        case .picking:
            picker
        case .reply(let report):
            reply(report)
        case .list:
            list
        }
    }

    // MARK: - The reply (design 5d, right)

    private func reply(_ report: SlowdownReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SlowdownReportPresentation.recordedHeadline(at: report.reportedAt))
                .font(.headline)

            // The order is the argument: what we saw, then what that does and does
            // not mean, then what was kept. Reversing it would open with a
            // limitation and read as an excuse.
            Text(SlowdownReportPresentation.acknowledgement(report))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text(SlowdownReportPresentation.keptReadings(report))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            evidence(report)

            if let pattern = SlowdownReportPatterns.pattern(in: store.reportedSlowdowns) {
                comparison(pattern)
            }

            Divider()

            replyActions(report)
        }
    }

    /// "What you told us" — the one list in the product where a user-provided fact
    /// and a measured one sit together, so each says which it is (FR-038).
    private func evidence(_ report: SlowdownReport) -> some View {
        let rows = SlowdownReportPresentation.evidenceRows(
            for: report, allReports: store.reportedSlowdowns)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(SlowdownReportPresentation.evidenceHeading)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                Text(SlowdownReportPresentation.evidenceQualifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                    // Yours or ours is never carried by weight alone: the spoken
                    // label below says which, and so does the symbol.
                    Image(systemName: row.isYours ? "person.fill" : "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                // The evidence class in words, from the model's own label — the
                // same vocabulary the rest of the app speaks (FR-038).
                .accessibilityLabel("\(row.evidence.label), \(row.time). \(row.text)")
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    /// What the reports have in common — a coincidence, and it says so.
    private func comparison(_ pattern: SlowdownReportPattern) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(SlowdownReportPresentation.patternHeading(pattern))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(SlowdownReportPresentation.patternDetail(pattern))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }

    private func replyActions(_ report: SlowdownReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(SlowdownReportPresentation.keepTitle) { flow = .none }
                    .buttonStyle(.borderedProminent)
                Button(SlowdownReportPresentation.seeAllTitle(store.reportedSlowdowns.count)) {
                    flow = .list
                }
            }
            // A withdrawal, not a correction: the record is the user's own
            // statement, so nothing asks them to justify taking it back.
            Button(SlowdownReportPresentation.deleteTitle) {
                store.deleteReportedSlowdown(id: report.id)
                flow = .none
            }
            .buttonStyle(.link)
            .font(.caption)

            Text(SlowdownReportPresentation.storageAssurance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The picker (design 6d, left)

    private var picker: some View {
        let choices = SlowdownReportPresentation.retrospectiveChoices()
        let hours = SlowdownReportPresentation.earlierTodayChoices()
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SlowdownReportPresentation.pickerTitle).font(.headline)
                Text(SlowdownReportPresentation.pickerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(choices) { choice in
                Button {
                    file(.recently(secondsAgo: choice.secondsAgo))
                } label: {
                    HStack {
                        Text(choice.title)
                        Spacer(minLength: 8)
                        // The window this button will actually keep, computed by the
                        // policy that files it.
                        Text(choice.window)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("\(choice.title), keeping \(choice.window)")
            }

            // Omitted rather than offered empty just after midnight (FR-062).
            if !hours.isEmpty {
                Menu {
                    ForEach(hours) { hour in
                        Button("\(hour.title) · \(hour.window)") {
                            file(.recently(secondsAgo: hour.secondsAgo))
                        }
                    }
                } label: {
                    HStack {
                        Text(SlowdownReportPresentation.earlierTodayTitle)
                        Spacer(minLength: 8)
                        Text(SlowdownReportPresentation.earlierTodayHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.button)
            }

            Text(SlowdownReportPresentation.pickerFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Cancel") { flow = .none }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private func file(_ timing: SlowdownReportTiming) {
        flow = .reply(store.reportSlowdown(timing: timing))
    }

    // MARK: - Every report kept (design 5d's "See all reports", 6d's "Review…")

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SlowdownReportPresentation.listTitle(store.reportedSlowdowns.count))
                .font(.headline)

            if store.reportedSlowdowns.isEmpty {
                Text(SlowdownReportPresentation.emptyList)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.reportedSlowdowns) { report in
                            listRow(report)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Text(SlowdownReportPresentation.storageAssurance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(SlowdownReportPresentation.retentionNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Done") { flow = .none }
                .buttonStyle(.borderedProminent)
        }
    }

    private func listRow(_ report: SlowdownReport) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(SlowdownReportPresentation.listRow(report))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                store.deleteReportedSlowdown(id: report.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(SlowdownReportPresentation.deleteTitle)
        }
        .accessibilityElement(children: .combine)
    }
}
