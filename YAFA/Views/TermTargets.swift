import SwiftUI

/// What a term is studied against, as a subtitle: the targets of its outgoing links.
///
/// Shared by every list which shows terms, so that a term reads the same whether it is being
/// browsed, suggested, or edited.
struct TermTargets: View {
    let term: Term
    var lineLimit: Int = 2

    var body: some View {
        // An anchored target is tinted the same colour its blank has in the text above, which is
        // what keeps the two readable as the same thing in a list of several.
        let targets = term.sortedOutgoingLinks.compactMap { link -> AttributedString? in
            guard let text = link.target?.text else { return nil }

            var result = AttributedString(text)

            if let color = anchorColor(of: link) {
                result.foregroundColor = color
            }

            return result
        }

        if !targets.isEmpty {
            Text(targets.reduce(into: AttributedString()) { joined, target in
                if !joined.characters.isEmpty {
                    joined += AttributedString(", ")
                }

                joined += target
            })
                .font(.subheadline)
                // Styled explicitly: a row's tint would otherwise colour this the way it colours
                // the editable term text above it.
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                // Without this the row gives the text a single line's height and truncates the
                // rest, whatever the line limit says.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
