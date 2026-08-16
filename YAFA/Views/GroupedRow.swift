import SwiftUI

/// The width of the gutter holding the spine joining grouped rows.
///
/// Narrow on purpose: it is indentation taken away from the text on every grouped row, so it holds
/// a hairline and an icon and nothing more.
let groupGutterWidth: CGFloat = 22

/// The short run of spine drawn between two rows of a group, carrying the link icon.
struct SharedRowSeparator: View {
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // The spine runs the full height of this row so it meets the segments drawn by the
                // rows on either side.
                GroupSpine(position: .middle)

                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: groupGutterWidth)

            Spacer(minLength: 0)
        }
        // A list row is otherwise given a minimum height meant for tappable content, which would
        // stretch this one into a tall gap.
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
        .listRowInsets(.init(top: 0, leading: 20, bottom: 0, trailing: 20))
        // The spine is continuous across the group, so the list's own rule would cut it.
        .listRowSeparator(.hidden)
        .accessibilityLabel(label)
    }
}

/// One row's worth of the vertical spine bracketing a group of rows.
///
/// Every segment spans its row's full height, so consecutive rows join into one unbroken line; the
/// ends are rounded off at the first and last row to close the bracket.
struct GroupSpine: View {
    enum Position {
        /// The first row of a group: the spine starts at the row's text and runs down.
        case first
        /// A row between two others: the spine runs the full height.
        case middle
        /// The last row of a group: the spine runs down to the row's text and stops.
        case last
    }

    let position: Position

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let width = 1 / displayScale
        /// How far in from a row's edge the bracket turns, so it ends beside the text rather than
        /// at the very top or bottom of the row.
        let cap: CGFloat = 11

        GeometryReader { proxy in
            let height = proxy.size.height

            Path { path in
                switch position {
                case .first:
                    path.move(to: .init(x: 0, y: min(cap, height)))
                    path.addLine(to: .init(x: 0, y: height))
                case .middle:
                    path.move(to: .init(x: 0, y: 0))
                    path.addLine(to: .init(x: 0, y: height))
                case .last:
                    path.move(to: .init(x: 0, y: 0))
                    path.addLine(to: .init(x: 0, y: max(height - cap, 0)))
                }
            }
            .stroke(Color(uiColor: .opaqueSeparator), lineWidth: width)
            .offset(x: width / 2)
        }
        .frame(width: width)
    }
}

/// Lays a row out in the grouped form: a spine gutter on the left, then the row's own content.
///
/// Rows which are not part of a group get no gutter, so the indentation is only paid where it
/// carries meaning.
struct GroupedRow<Content: View>: View {
    let spine: GroupSpine.Position?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            if let spine {
                GroupSpine(position: spine).frame(width: groupGutterWidth)
            }

            content()
        }
    }
}
