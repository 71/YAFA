import SwiftUI

/// Which way a link is studied, as an arrow.
///
/// Pointing away means this term is the prompt; pointing back means it is the answer, and the
/// recall is scheduled against the other term.
struct LinkDirectionIcon: View {
    let direction: RelatedLink.Direction

    var body: some View {
        // Bolder than the due date it sits beside: the row's text is what the eye lands on, and
        // this has to stay legible at a glance without competing with it.
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }

    private var systemImage: String {
        switch direction {
        case .outgoing: "arrow.right"
        case .incoming: "arrow.left"
        case .mutual: "arrow.left.arrow.right"
        }
    }

    private var label: LocalizedStringKey {
        switch direction {
        case .outgoing: "Studied from this term"
        case .incoming: "Studied from the other term"
        case .mutual: "Studied in both directions"
        }
    }
}
