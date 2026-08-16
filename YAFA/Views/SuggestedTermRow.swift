import SwiftUI

/// The terms matching what has been typed, offered instead of creating a new one.
///
/// Modelled on the suggestions Reminders shows under a new reminder: one card holding every match,
/// with internal dividers, rather than a list row each. Being a single row lets the entries be much
/// shorter than a list row's minimum height, and keeps them visibly a hint attached to the field
/// rather than more items in the list.
///
/// Creating stays the default on submit, so it needs no row of its own to advertise it.
struct SuggestionsCard<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { (index, item) in
                    if index != 0 {
                        Divider()
                    }

                    content(item)
                        .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 12)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 10))
            // The card is the hint; the row hosting it adds nothing of its own. It sits close to
            // the field it belongs to, with more air below to separate it from what follows.
            .listRowInsets(.init(top: 0, leading: 16, bottom: 16, trailing: 16))
            .listRowSeparator(.hidden)
            .selectionDisabled()
        }
    }
}

/// One term inside a ``SuggestionsCard``.
struct SuggestedTermRow: View {
    let term: Term
    /// The text typed so far, highlighted wherever it appears.
    let matching: String
    let link: () -> Void

    var body: some View {
        Button(action: link) {
            VStack(alignment: .leading, spacing: 1) {
                highlighted(term.text)

                let targets = term.sortedOutgoingLinks.compactMap { $0.target?.text }

                if !targets.isEmpty {
                    // Smaller rather than dimmer: a further step down in colour would be
                    // `.tertiary`, which fades the text more than it needs.
                    highlighted(targets.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Opening before linking: a suggestion may need checking, and this is the only route
            // to it without leaving the editor first.
            NavigationLink(value: term) {
                Label("Open term", systemImage: "arrow.forward")
            }

            Button("Add link", systemImage: "link", action: link)
        }
    }

    /// `text` with every occurrence of the search text in bold, so the reason for the match is
    /// visible rather than left to be inferred.
    private func highlighted(_ text: String) -> Text {
        Text(highlight(text, matching: matching))
    }
}

/// One tag inside a ``SuggestionsCard``.
struct SuggestedTagRow: View {
    let tag: Tag
    let matching: String
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack {
                Text(highlight(tag.name, matching: matching))

                Spacer()

                Text("\(tag.terms?.count ?? 0)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Returns `text` with every occurrence of `matching` picked out in bold.
///
/// Matching ignores case, diacritics, and width, the same way the search which produced these
/// results does, so what is highlighted is what actually matched.
func highlight(_ text: String, matching: String) -> AttributedString {
    var result = AttributedString(text)

    result.foregroundColor = .secondary

    guard !matching.isEmpty else { return result }

    var searched = result.startIndex..<result.endIndex

    while
        let range = result[searched].range(
            of: matching,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        )
    {
        result[range].inlinePresentationIntent = .stronglyEmphasized
        result[range].foregroundColor = .primary

        guard range.upperBound < searched.upperBound else { break }

        searched = range.upperBound..<searched.upperBound
    }

    return result
}
