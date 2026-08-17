import SwiftData
import SwiftUI

/// A term's text, followed by everything studied from it.
///
/// A term with exactly one link -- the common case, and every migrated flashcard -- looks like the
/// old flashcard screen, with the "back" text moved into the link list as a single row.
///
/// A term whose text is a sentence or a definition is the same screen: the words inside it which
/// are terms of their own are anchored links, blanked out when studied, and shown tinted in the
/// text above the rows which study them.
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

    /// What is selected in the term's text, which decides whether **Blank** is offered and which
    /// anchor is drawn more strongly.
    @State private var selection: TextSelection?

    /// The link row whose anchors are brought forward, because it holds the keyboard.
    @State private var focusedLink: Link?

    /// The link whose hint line was opened from the context menu, so that a row with no hint yet
    /// has somewhere to type one without first focusing its term.
    @State private var hintedLink: Link?

    /// The span being blanked, which the "add link" field is anchored over once a target is picked.
    /// Set by **Blank**, cleared when the link is made or the field is abandoned.
    ///
    /// Held as offsets rather than as a `Range<String.Index>`: the text can be edited between
    /// choosing what to blank and choosing what it points at, and an index into a string which has
    /// since changed addresses nothing. Offsets at least survive to be re-resolved, and are moved
    /// along by the same edit the anchors are.
    @State private var blanking: AnchorRange?

    var body: some View {
        // The selection points at an anchor only while nothing else is being pointed at: a focused
        // row is a deliberate act, where a caret merely landing somewhere is not.
        let anchoring = anchoring(of: selection, in: term)
        let emphasised = focusedLink ?? anchoring.emphasised

        Form {
            Section(header: Text("Term")) {
                TermTextField(
                    focusedTerm: .constant(nil),
                    term: term,
                    autoFocus: autoFocus,
                    selection: $selection,
                    emphasising: emphasised
                )
            }

            LinksSection(emphasised: emphasised)

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
        // Lifted so the mark joining two links which share a progress can be a row of its own
        // without being padded out to a tappable height; every row which needs the usual height
        // asks for it. Same as the progress screen, whose list has the same mark in it.
        .environment(\.defaultMinListRowHeight, 0)
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
        // Only in the selection's own edit menu, next to Cut and Copy. A button in the keyboard bar
        // is detached from the selection it acts on, so it has to explain itself; sitting in the
        // menu the selection brings up, "Blank" is read as being about those words.
        .blankEditMenuAction(for: anchoring.blankableRange) { blank($0) }
        .navigationTitle("Term")
        .onChange(of: term.notes) { term.touch() }
        // A pending blank is moved by an edit exactly as a committed anchor is, so that typing
        // between choosing the words and choosing what they point at still anchors the right ones.
        .onChange(of: term.text) { previous, current in
            guard blanking != nil, let edit = TextEdit(from: previous, to: current) else { return }

            blanking = blanking?.adjusted(for: edit)
        }
    }

    /// Starts blanking `range`: the "add link" field takes over, seeded with the selected text, and
    /// anchors the link over this range once a target is picked.
    ///
    /// Seeding rather than committing is what makes a conjugated form work: blanking 갔다 seeds the
    /// field with "갔다", which matches no term, and typing back to 가다 finds the one it belongs to.
    private func blank(_ range: Range<String.Index>) {
        blanking = AnchorRange(range, in: term.text)
        selection = nil
    }

    /// Everything connecting this term to another, in either direction.
    ///
    /// Backlinks live here rather than in a section of their own: they are part of how a term sits
    /// in the graph, and the arrow on each row says which way it is studied.
    @ViewBuilder
    private func LinksSection(emphasised: Link?) -> some View {
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
                    JoinedRowsMark.sharingProgress()
                }

                LinkRow(
                    entry: entry,
                    origin: term,
                    goesBack: entry.other.persistentModelID == cameFrom?.persistentModelID,
                    emphasised: entry.link.persistentModelID == emphasised?.persistentModelID,
                    focusedLink: $focusedLink,
                    hinting: $hintedLink
                )
                // Between two sharing rows, the mark is the separator.
                .listRowSeparator(sharesWithPrevious ? .hidden : .automatic, edges: .top)
                .listRowSeparator(sharesWithNext ? .hidden : .automatic, edges: .bottom)
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

                    ShareProgressMenu(link: entry.link, term: term)

                    // Only for what is studied *from* this term: an incoming link is prompted by
                    // the other term, so its hint is written on that term's screen.
                    if entry.direction != .incoming, entry.link.hint.isEmpty {
                        Button("Add hint", systemImage: "lightbulb") {
                            hintedLink = entry.link
                        }
                    }

                    // Unanchoring is offered even though editing the text does it on its own when
                    // the anchored words go away: a re-anchor left over text nobody would have
                    // chosen has to be recoverable without deleting the link and its history.
                    if entry.link.isAnchored {
                        Button("Unanchor", systemImage: "rectangle.slash") {
                            entry.link.unanchor()
                            term.touch()
                        }
                    }

                    Button("Delete link", systemImage: "trash", role: .destructive) {
                        delete(entry)
                    }
                }
            }

            NewLinkRow(term: term, blanking: $blanking)
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
    /// Whether this row leads back to the screen this one was opened from.
    let goesBack: Bool
    /// Whether this row's anchors are the ones being pointed at above.
    var emphasised: Bool = false
    /// The link whose row holds the keyboard, which this row sets while its field is focused.
    @Binding var focusedLink: Link?
    /// The link whose hint line was opened from the context menu, which this row clears once it has
    /// taken the keyboard.
    @Binding var hinting: Link?

    @Environment(\.dismiss) private var dismiss

    @FocusState private var focused: Bool
    @FocusState private var hintFocused: Bool

    /// Whether the hint line is shown at all: a written hint is always there to be read and
    /// corrected, and an empty one only appears while the row is being worked on.
    private var showsHint: Bool {
        guard entry.direction != .incoming else { return false }

        return !entry.link.hint.isEmpty || focused || hintFocused
            || hinting?.persistentModelID == entry.link.persistentModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row

            if showsHint {
                TextField("Hint", text: bindToProperty(of: entry.link, \.hint), axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .focused($hintFocused)
                    // Opened from the context menu, the line has to take the keyboard itself:
                    // nothing else on the row was focused to bring it up.
                    .onChange(of: hinting, initial: true) {
                        guard hinting?.persistentModelID == entry.link.persistentModelID else {
                            return
                        }

                        hintFocused = true
                        hinting = nil
                    }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // An incoming anchored link is studied from the row's own title -- the sentence
                // this term sits inside -- so the anchor is highlighted in place, exactly as it is
                // in the field above. Quoting it underneath would print a span of the title a
                // second line down from the title itself.
                //
                // Still editable: the field which renders the tint is the same one the term
                // section uses, so showing the highlight costs nothing in what can be typed.
                if entry.direction == .incoming, entry.link.isAnchored {
                    // Focus is reported through `focusedTerm` rather than a `.focused` here: the
                    // field owns its own focus state, which an outer binding cannot reach.
                    TermTextField(
                        focusedTerm: Binding {
                            focusedLink?.persistentModelID == entry.link.persistentModelID
                                ? entry.other : nil
                        } set: {
                            if $0 != nil {
                                focusedLink = entry.link
                            } else if focusedLink?.persistentModelID
                                == entry.link.persistentModelID
                            {
                                focusedLink = nil
                            }
                        },
                        term: entry.other,
                        autoFocus: false,
                        emphasising: emphasised ? entry.link : nil,
                        highlighting: entry.link
                    )
                } else {
                    TextField(
                        "Term",
                        text: bindToProperty(of: entry.other, \.text),
                        axis: .vertical
                    )
                    .focused($focused)
                    .onChange(of: entry.other.text) { entry.other.touch() }
                }

                // The quote rides on the subtitle line rather than above it: the term is what the
                // row is about, and which words it was taken from is the sort of detail the due
                // date and the direction already live on. An incoming row has no quote -- its
                // title carries the highlight instead.
                //
                // The direction rides along here too rather than taking a column of its own on the
                // left, where it cost every row an indent.
                HStack(spacing: 6) {
                    if entry.direction != .incoming {
                        AnchorQuote(link: entry.link, emphasised: emphasised)
                    }

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
        .onChange(of: focused) {
            if focused {
                focusedLink = entry.link
            } else if focusedLink?.persistentModelID == entry.link.persistentModelID {
                focusedLink = nil
            }
        }
    }
}

/// The text an anchored link covers in its source, quoted on its row's subtitle line.
///
/// Tinted the same colour as the blank above it, which is what says the two are the same thing --
/// and, in the common case where the anchored text *is* the target's text, why the row appears to
/// say it twice.
///
/// Clipped aggressively: it is there to be recognised, not read, and the term it points at is on the
/// line above.
private struct AnchorQuote: View {
    let link: Link
    let emphasised: Bool

    var body: some View {
        if let color = anchorColor(of: link), let text = quoted {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.subheadline)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    AnchorTint.background(color, emphasised: emphasised),
                    in: .rect(cornerRadius: 5)
                )
                // No width of its own: the tint wraps the text, so what follows sits right after it
                // rather than at a column of its own. A long anchor is truncated by the line limit
                // above once the row runs out of room, which is what keeps the due date on screen.
                .layoutPriority(1)
        }
    }

    /// The anchored text, with several anchors joined by an ellipsis so the row says there is more
    /// than one without spelling each out.
    private var quoted: String? {
        guard let source = link.source else { return nil }

        let spans = link.anchors.map { String(source.text[$0]) }

        return spans.isEmpty ? nil : spans.joined(separator: " … ")
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

extension View {
    /// Adds a leading swipe opening a link's progress.
    ///
    /// Progress is edited rarely, so it gets no permanent room in the row; the context menu offers
    /// the same destination via `ProgressMenuItem`.
    fileprivate func progressSwipeAction(
        of link: Link,
        open: @escaping (Progress) -> Void
    ) -> some View {
        modifier(ProgressSwipeAction(progress: link.progress, open: open))
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

/// The context-menu entry opening a link's progress.
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
/// Sharing is deliberately an explicit action: two links get their own progress by default, and
/// joining them means reviewing either one advances both.
private struct ShareProgressMenu: View {
    let link: Link
    let term: Term

    var body: some View {
        let others = term.studiedLinks.filter { $0.persistentModelID != link.persistentModelID }

        if !others.isEmpty {
            Menu("Share progress with...", systemImage: "link") {
                ForEach(others, id: \.persistentModelID) { other in
                    if other.progress?.persistentModelID == link.progress?.persistentModelID {
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

    private func share(with other: Link) {
        guard let shared = other.progress else { return }

        link.join(progress: shared)
    }

    private func unshare() {
        link.leaveSharedProgress()
    }
}

/// The "add link" field at the end of a term's link list, plus the matching terms it suggests.
///
/// Typing filters existing terms, listed underneath as ordinary rows -- so a suggestion can be
/// inspected, or opened from its context menu, before it is linked to. Submitting creates a new
/// term: adding something new is the common case and shouldn't need a menu.
///
/// **Blank** comes here too. It does not decide the target on its own: it seeds this field with the
/// text it selected and remembers the range, so blanking is the same act as adding a link, with the
/// link ending up anchored over what was selected.
private struct NewLinkRow: View {
    let term: Term

    /// The span being blanked, when this field was opened by **Blank** rather than tapped. Offsets
    /// rather than indices, since the text can change while the field is open.
    @Binding var blanking: AnchorRange?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Term.text) private var allTerms: [Term]

    @State private var newTargetText = ""
    @State private var termsSearch: SearchDictionary<Term> = .init()
    @State private var matches: [Term] = []
    @FocusState private var adding: Bool

    var body: some View {
        TextField(blanking == nil ? "Add link" : "Blank", text: $newTargetText, axis: .vertical)
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
            // **Blank** hands the range over by setting `blanking`; the field takes the keyboard and
            // the selected text so that picking a target is all that is left to do.
            .onChange(of: blanking) { _, span in
                guard let range = span?.range(in: term.text) else { return }

                newTargetText = String(term.text[range])
                adding = true
                updateMatches()
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
        // points at it or back from it, should not also be offered as something to add. Blanking is
        // the exception -- a word appearing twice in a sentence is blanked twice, against the link
        // which is already there -- so nothing is excluded then.
        let linked =
            blanking == nil ? Set(term.relatedLinks.map(\.other.persistentModelID)) : []

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
        guard let target, target.persistentModelID != term.persistentModelID else {
            // Abandoning the field gives the range back rather than holding onto it, so the next
            // thing typed here is an ordinary link.
            blanking = nil
            return
        }

        // Resolved against the text as it stands now, not as it stood when **Blank** was tapped:
        // an edit in between moves the offsets, and one which removed the span outright leaves
        // nothing to anchor over, so the link is simply made unanchored.
        term.link(to: target, anchoredOver: blanking?.range(in: term.text))
        term.touch()

        blanking = nil
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

/// A sentence with two anchored links and one unanchored one: the mixed case, where each row hides
/// only its own words and the last is studied against the whole thing.
#Preview("Anchored links") {
    let container = previewModelContainer()

    NavigationStack {
        TermEditor(term: previewTerm("고양이가 학교에 갔다", in: container), autoFocus: false)
    }
    .modelContainer(container)
}

/// A term which is studied on its own *and* anchored into a sentence, so its links list has an
/// incoming anchored link alongside its own.
#Preview("Anchored target") {
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
