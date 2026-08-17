import SwiftUI

/// Drawn between two rows to say they belong together, in place of the divider which would
/// otherwise separate them.
///
/// A rule with an icon sitting on it, taking one row's worth of height and no more. A bracket down
/// the side of the group was tried first and read as a tall empty gap with an icon floating in it --
/// the rows it joins are already adjacent, so the spine was drawing a relationship the layout had
/// already made obvious.
///
/// The list hosting one of these has to lift `defaultMinListRowHeight`, or it is padded out to a
/// tappable height and becomes the gap it is meant to avoid.
struct JoinedRowsMark: View {
    let systemImage: String
    let label: LocalizedStringKey

    /// Two links scheduled against one progress: reviewing either advances both.
    static func sharingProgress() -> Self {
        .init(systemImage: "link", label: "Shares progress with the link above")
    }

    /// The two directions of one pair of terms.
    static func bothDirections() -> Self {
        .init(systemImage: "arrow.up.arrow.down", label: "Studied in both directions")
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // The rule sits behind, starting after the icon so the two don't overlap.
            Divider().padding(.leading, 22)

            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 0)
        .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }
}
