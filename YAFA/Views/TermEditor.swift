import SwiftData
import SwiftUI

/// A term's text, followed by everything studied from it: its outgoing links and its cloze blanks.
///
/// A term with exactly one link -- the common case, and every migrated flashcard -- looks like the
/// old flashcard screen, with the "back" text moved into the link list as a single row.
struct TermEditor: View {
    let term: Term
    let autoFocus: Bool

    /// The term whose screen this one was opened from, if any.
    var cameFrom: Term? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("prefer_relative_date") private var relativeDate = false

    /// The progress to open, set by the swipe action and context menu.
    ///
    /// Driven from state rather than a `NavigationLink` inside the swipe action or menu: a link
    /// nested in a row which is itself a link activates both, pushing two screens at once.
    @State private var openedProgress: Progress?

    /// The term to open, set by a link row's chevron. Driven from state for the same reason as
    /// `openedProgress`: those rows cannot be `NavigationLink`s themselves.
    @State private var openedTerm: TermDestination?

    var body: some View {
        Form {
            Section(header: Text("Term")) {
                TermTextField(focusedTerm: .constant(nil), term: term, autoFocus: autoFocus)
            }

            LinksSection()
            ClozesSection()

            Section(header: Text("Tags")) {
                TagSelectionList(
                    selectedTags: term.tags ?? [],
                    addTag: { term.add(tag: $0) },
                    removeTags: { term.remove(tagOffsets: $0) }
                )
            }

            Section(header: Text("Notes")) {
                TextField(
                    "Notes",
                    text: bindToProperty(of: term, \.notes),
                    axis: .vertical
                )
            }

            if term.modelContext != nil {
                Section(header: Text("Information")) {
                    LabeledContent {
                        DateText(date: term.creationDate, relative: $relativeDate)
                    } label: {
                        Text("Created")
                    }
                    LabeledContent {
                        DateText(date: term.modificationDate, relative: $relativeDate)
                    } label: {
                        Text("Modified")
                    }
                }
                .monospacedDigit()
            }
        }
        .navigationDestination(item: $openedProgress) { progress in
            ProgressEditor(progress: progress, cameFrom: term)
        }
        .navigationDestination(item: $openedTerm) { destination in
            TermEditor(
                term: destination.term,
                autoFocus: false,
                cameFrom: destination.cameFrom
            )
        }
        .environment(\.openTerm) { openedTerm = $0 }
        .dismissKeyboardToolbar {
            Button {
                term.delete()
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .navigationTitle("Term")
        .onChange(of: term.text) { term.touch() }
        .onChange(of: term.notes) { term.touch() }
    }

    /// Everything connecting this term to another, in either direction.
    ///
    /// Backlinks live here rather than in a section of their own: they are part of how a term sits
    /// in the graph, and the arrow on each row says which way it is studied.
    @ViewBuilder
    private func LinksSection() -> some View {
        let related = term.relatedLinks

        Section(header: Text("Links")) {
            ForEach(Array(related.enumerated()), id: \.element.id) { (index, entry) in
                // Links sharing a progress are adjacent, so the separator between two of them is
                // where the sharing is shown -- no per-row marker needed.
                let sharesWithPrevious =
                    index > 0 && shareProgress(related[index - 1], entry)
                let sharesWithNext =
                    index + 1 < related.count && shareProgress(entry, related[index + 1])

                if sharesWithPrevious {
                    SharedRowSeparator(label: "Shares progress with the link above")
                }

                LinkRow(
                    entry: entry,
                    origin: term,
                    spine: sharesWithPrevious
                        ? (sharesWithNext ? .middle : .last)
                        : (sharesWithNext ? .first : nil),
                    goesBack: entry.other.persistentModelID == cameFrom?.persistentModelID
                )
                .listRowSeparator(sharesWithPrevious ? .hidden : .automatic, edges: .top)
                .progressSwipeAction(of: entry.link) { openedProgress = $0 }
                // An explicit swipe action rather than `onDelete`, whose offsets would be thrown
                // off by the separator rows interleaved above.
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(entry)
                    }
                    // The app tints the whole stack, and a swipe action takes that tint over the
                    // colour its destructive role would otherwise give it.
                    .tint(.red)
                }
                .contextMenu {
                    ProgressMenuItem(progress: entry.link.progress) { openedProgress = $0 }

                    ShareProgressMenu(studiable: entry.link, term: term)

                    Button("Delete link", systemImage: "trash", role: .destructive) {
                        delete(entry)
                    }
                }
            }

            NewLinkRow(term: term)
        }
    }

    /// Whether two entries are scheduled against the same progress.
    private func shareProgress(_ a: RelatedLink, _ b: RelatedLink) -> Bool {
        guard let lhs = a.link.progress?.persistentModelID else { return false }

        return lhs == b.link.progress?.persistentModelID
    }

    /// Deletes an entry, which for a mutual pair means both of its links.
    private func delete(_ entry: RelatedLink) {
        for link in entry.links {
            link.delete()
        }
    }

    @ViewBuilder
    private func ClozesSection() -> some View {
        let blanks = (term.clozeBlanks ?? []).sorted {
            $0.promptText.localizedCaseInsensitiveCompare($1.promptText) == .orderedAscending
        }

        if !blanks.isEmpty {
            Section(header: Text("Clozes")) {
                ForEach(blanks) { blank in
                    ClozeBlankRow(blank: blank)
                        .progressSwipeAction(of: blank) { openedProgress = $0 }
                        .contextMenu {
                            ProgressMenuItem(progress: blank.progress) { openedProgress = $0 }

                            ShareProgressMenu(studiable: blank, term: term)
                        }
                }
            }
        }
    }
}

/// One row of the links list: the term at the other end, which way the link is studied, and when
/// it is next due.
///
/// The term's text is editable in place. It is the same `Term` object everywhere it appears, so a
/// rename here is a rename everywhere -- which is the point: a term has one name, and correcting a
/// typo shouldn't mean opening the term first.
private struct LinkRow: View {
    let entry: RelatedLink
    let origin: Term
    var spine: GroupSpine.Position? = nil
    /// Whether this row leads back to the screen this one was opened from.
    let goesBack: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GroupedRow(spine: spine) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Term",
                        text: bindToProperty(of: entry.other, \.text),
                        axis: .vertical
                    )
                    .onChange(of: entry.other.text) { entry.other.touch() }

                    // The direction rides along with the due date rather than taking a column of
                    // its own on the left, where it cost every row an indent.
                    HStack(spacing: 6) {
                        DueText(progress: entry.link.progress)

                        LinkDirectionIcon(direction: entry.direction)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The text field takes the row's taps for its caret, so navigation moves to an
                // explicit control of its own.
                NavigateButton(
                    destination: entry.other,
                    origin: origin,
                    goesBack: goesBack,
                    dismiss: dismiss
                )
            }
        }
    }
}

/// The trailing chevron opening the term a row points at, or returning to it when that is the
/// screen this one was opened from.
///
/// A plain `Button` rather than a `NavigationLink`: a link inside a `Form` row draws a disclosure
/// indicator of its own, which would sit next to this one.
private struct NavigateButton: View {
    let destination: Term
    let origin: Term
    let goesBack: Bool
    let dismiss: DismissAction

    @Environment(\.openTerm) private var openTerm

    var body: some View {
        Button {
            if goesBack {
                dismiss()
            } else {
                openTerm(TermDestination(destination, cameFrom: origin))
            }
        } label: {
            chevron(goesBack ? "chevron.left" : "chevron.right")
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func chevron(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 32, height: 36)
            .contentShape(.rect)
    }
}

/// One row of the cloze list: the sentence with this blank hidden, and when it is next due.
private struct ClozeBlankRow: View {
    let blank: ClozeBlank

    var body: some View {
        // A blank has no term to navigate to: the term is the one whose screen this already is.
        RowLayout(destination: nil) {
            Text(blank.promptText)

            DueText(progress: blank.progress)
        }
    }
}

/// A row whose label navigates to `destination`, when there is one.
///
/// A row leading back to the screen this one was opened from pops the stack instead of pushing a
/// second copy of that screen, and shows a back-facing chevron to say so.
private struct RowLayout<Content: View>: View {
    let destination: Term?
    var origin: Term? = nil
    var goesBack: Bool = false
    var spine: GroupSpine.Position? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let label = GroupedRow(spine: spine) {
            VStack(alignment: .leading, spacing: 2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if goesBack {
            Button {
                dismiss()
            } label: {
                HStack {
                    label

                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .tint(.primary)
        } else if let destination {
            NavigationLink(value: TermDestination(destination, cameFrom: origin)) { label }
        } else {
            label
        }
    }
}

extension View {
    /// Adds a leading swipe opening a studiable's progress.
    ///
    /// Progress is edited rarely, so it gets no permanent room in the row; the context menu offers
    /// the same destination via `ProgressMenuItem`.
    fileprivate func progressSwipeAction(
        of studiable: some Studiable,
        open: @escaping (Progress) -> Void
    ) -> some View {
        modifier(ProgressSwipeAction(progress: studiable.progress, open: open))
    }
}

private struct ProgressSwipeAction: ViewModifier {
    let progress: Progress?
    let open: (Progress) -> Void

    func body(content: Content) -> some View {
        if let progress {
            content.swipeActions(edge: .leading) {
                Button("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                    open(progress)
                }
                .tint(.accentColor)
            }
        } else {
            content
        }
    }
}

/// The context-menu entry opening a studiable's progress.
private struct ProgressMenuItem: View {
    let progress: Progress?
    let open: (Progress) -> Void

    var body: some View {
        if let progress {
            Button {
                open(progress)
            } label: {
                Label(
                    progress.sharers.count > 1 ? "Shared progress" : "Progress",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
        }
    }
}

private struct DueText: View {
    let progress: Progress?

    var body: some View {
        if let progress {
            RelativeDueText(date: progress.nextReviewDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// A "share progress with..." menu, listing the other things studied from `term`.
///
/// Sharing is deliberately an explicit action: two studiables get their own progress by default,
/// and joining them means reviewing either one advances both.
private struct ShareProgressMenu<S: Studiable>: View {
    let studiable: S
    let term: Term

    var body: some View {
        let others = term.studiables.filter { $0.persistentModelID != studiable.persistentModelID }

        if !others.isEmpty {
            Menu("Share progress with...", systemImage: "link") {
                ForEach(others, id: \.persistentModelID) { other in
                    if other.progress?.persistentModelID == studiable.progress?.persistentModelID {
                        Button(other.answerText, systemImage: "checkmark") {
                            unshare()
                        }
                    } else {
                        Button(other.answerText) {
                            share(with: other)
                        }
                    }
                }
            }
        }
    }

    private func share(with other: any Studiable) {
        guard let shared = other.progress else { return }

        studiable.join(progress: shared)
    }

    private func unshare() {
        studiable.leaveSharedProgress()
    }
}

/// The "add link" field at the end of a term's link list, plus the matching terms it suggests.
///
/// Typing filters existing terms, listed underneath as ordinary rows -- so a suggestion can be
/// inspected, or opened from its context menu, before it is linked to. Submitting creates a new
/// term: adding something new is the common case and shouldn't need a menu.
private struct NewLinkRow: View {
    let term: Term

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Term.text) private var allTerms: [Term]

    @State private var newTargetText = ""
    @State private var termsSearch: SearchDictionary<Term> = .init()
    @State private var matches: [Term] = []
    @FocusState private var adding: Bool

    var body: some View {
        TextField("Add link", text: $newTargetText, axis: .vertical)
            .focused($adding)
            .onSubmit { link(to: newTerm()) }
            .onChange(of: allTerms, initial: true) {
                termsSearch = .init(allTerms, by: \.text)
                updateMatches()
            }
            .onChange(of: newTargetText) { updateMatches() }
            // Losing focus with text still in the field commits it, the same as submitting would.
            .onChange(of: adding) { _, focused in
                if !focused { link(to: newTerm()) }
            }

        // Suggestions are a hint under the field, not rows of the list: submitting creates a new
        // term, and these offer the existing ones which match instead.
        SuggestionsCard(items: matches) { match in
            SuggestedTermRow(term: match, matching: trimmedText) { link(to: match) }
        }
    }

    /// Existing terms which could be linked to instead of creating a new one.
    ///
    /// A term is excluded once it is already linked, and so is the term being edited: a link from a
    /// term to itself has nothing to study.
    private func updateMatches() {
        let text = trimmedText

        guard !text.isEmpty else {
            matches = []
            return
        }

        // Both directions count as already linked: a term shown in the list above, whether the link
        // points at it or back from it, should not also be offered as something to add.
        let linked = Set(term.relatedLinks.map(\.other.persistentModelID))

        matches = termsSearch.including(text)
            .filter { $0.persistentModelID != term.persistentModelID }
            .filter { !linked.contains($0.persistentModelID) }
            .prefix(10)
            .map { $0 }
    }

    private var trimmedText: String {
        newTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the term to link to when the text is submitted as-is.
    ///
    /// An exact match is reused rather than duplicated -- that is what makes two terms pointing at
    /// one definition synonyms rather than unrelated cards -- but anything else creates a term.
    private func newTerm() -> Term? {
        let text = trimmedText

        guard !text.isEmpty else { return nil }

        if let existing = allTerms.first(where: { $0.text == text }) {
            return existing
        }

        let target = Term(text: text, tags: term.tags ?? [])

        modelContext.insert(target)

        return target
    }

    private func link(to target: Term?) {
        guard let target, target.persistentModelID != term.persistentModelID else { return }

        term.link(to: target)
        term.touch()

        newTargetText = ""
        updateMatches()
    }
}

/// A term to open, remembering what was open when it was tapped.
///
/// Carrying the origin lets the destination recognise the row leading back where you came from, so
/// following a link and then following it back returns to the same screen instead of pushing a
/// second copy of it onto the stack.
struct TermDestination: Hashable {
    let term: Term
    let cameFrom: Term?

    init(_ term: Term, cameFrom: Term? = nil) {
        self.term = term
        self.cameFrom = cameFrom
    }

    // Identity, not contents: a synthesized `==` compares the models field by field, so two
    // distinct terms which happen to hold the same text would be treated as the same destination
    // and the stack would reuse the screen already on it.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.term.persistentModelID == rhs.term.persistentModelID
            && lhs.cameFrom?.persistentModelID == rhs.cameFrom?.persistentModelID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(term.persistentModelID)
        hasher.combine(cameFrom?.persistentModelID)
    }
}

/// Navigation value used to bring up a `NewTermEditor`.
struct NewTerm: Hashable {}

struct NewTermEditor: View {
    let text: String
    let definition: String
    let notes: String
    let tags: [Tag]

    init(text: String = "", definition: String = "", tags: [Tag] = [], notes: String = "") {
        self.text = text
        self.definition = definition
        self.notes = notes
        self.tags = tags
    }

    @Environment(\.modelContext) private var modelContext

    @State private var pendingTerm: Term = .init()
    @State private var pendingDefinition: Term?

    var body: some View {
        TermEditor(term: pendingTerm, autoFocus: true)
            .onChange(of: pendingTerm.text, initial: true, handleChange)
            .onChange(of: pendingTerm.notes, handleChange)

            .onAppear {
                pendingTerm = .init(text: text, notes: notes, tags: tags)

                if !definition.isEmpty {
                    let definitionTerm = Term(text: definition, tags: tags)

                    pendingDefinition = definitionTerm
                    modelContext.insert(pendingDefinition!)
                    modelContext.insert(pendingTerm)
                    pendingTerm.link(to: definitionTerm)
                }
            }
    }

    /// Only commits the term once it has some content, so that backing out of the editor doesn't
    /// leave an empty term behind.
    private func handleChange() {
        if pendingTerm.text.isEmpty && pendingTerm.notes.isEmpty {
            modelContext.delete(pendingTerm)

            if let pendingDefinition {
                modelContext.delete(pendingDefinition)
            }
        } else {
            modelContext.insert(pendingTerm)
        }
    }
}

private func reviewDateFormatter(relative: Bool) -> DateFormatter {
    let dateFormatter = DateFormatter()

    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .short
    dateFormatter.doesRelativeDateFormatting = relative

    return dateFormatter
}

struct DateText: View {
    let date: Date
    @Binding var relative: Bool

    /// Whether tapping the date switches between absolute and relative formatting.
    ///
    /// Off inside a row which is itself tappable: there the tap belongs to the row, and swallowing
    /// it to reformat a date would be a surprise.
    let tappable: Bool

    init(date: Date, relative: Binding<Bool>, tappable: Bool = true) {
        self.date = date
        self._relative = relative
        self.tappable = tappable
    }

    private static let dateFormatter = reviewDateFormatter(relative: false)
    private static let relativeDateFormatter = reviewDateFormatter(relative: true)

    var body: some View {
        let text = Text(
            (relative ? Self.relativeDateFormatter : Self.dateFormatter).string(from: date)
        )

        if tappable {
            text.onTapGesture { relative = !relative }
        } else {
            text
        }
    }
}

/// One link, like every migrated flashcard: the old screen minus the second text field.
#Preview("One recall") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("한국어", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

/// A homograph: one term, two outgoing links, each independently schedulable.
#Preview("Homograph") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("차", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

/// Several links, two of them sharing a progress, so the shared separator is visible between them.
#Preview("Shared links") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("먹다", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

/// A term two synonyms point at, so its links are all incoming.
#Preview("Incoming links") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("큰", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

/// A term which is both linked and used as a cloze blank.
#Preview("Cloze blank") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("학교", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

#Preview("New term") {
    NavigationStack {
        NewTermEditor()
    }
    .modelContainer(previewModelContainer())
}
