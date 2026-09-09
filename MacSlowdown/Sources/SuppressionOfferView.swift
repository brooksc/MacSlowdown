import Metrics
import SwiftUI

/// Design 5f's sheet: three complete sentences, ordered by how much they give up.
///
/// Every option is a whole sentence and a plain button — no pickers, no steppers,
/// no severity floor. Someone reaching this is mid-annoyance, and the design's
/// judgement is that the subject of the rule should be whatever just interrupted
/// them rather than something they have to specify.
struct SuppressionOfferView: View {
    let offer: SuppressionOffer
    /// Called with the choice after it has been applied, so a caller can refresh a
    /// list without having to re-derive what happened.
    var onChoose: (SuppressionOffer.Choice) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SuppressionOffer.title).font(.headline)
                Text(offer.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(offer.options) { option in
                Button {
                    SuppressionOfferAction.apply(option.choice, offer: offer)
                    onChoose(option.choice)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(option.title). \(option.detail)")
            }

            Text(SuppressionOffer.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
