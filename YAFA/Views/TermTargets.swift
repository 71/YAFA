import SwiftUI

/// What a term is studied against, as a subtitle: the targets of its outgoing links.
///
/// Shared by every list which shows terms, so that a term reads the same whether it is being
/// browsed, suggested, or edited.
struct TermTargets: View {
    let term: Term
    var lineLimit: Int = 2

    var body: some View {
        let targets = term.sortedOutgoingLinks.compactMap { $0.target?.text }

        if !targets.isEmpty {
            Text(targets.joined(separator: ", "))
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
