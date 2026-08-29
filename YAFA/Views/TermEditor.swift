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

    /// Whether the "add link" row is blanking a selection which matches no term, reported up from
    /// the row so the section's footer can explain it.
    @State private var blankingUnmatched = false

    /// Changing which way a link is studied.
    ///
    /// One submenu whichever way it currently goes, listing the three states a pair of terms can be
    /// in -- studied one way, the other way, or both -- with the current one checked. A menu whose
    /// items depend on the state it is in makes the reader find the option again each time; this
    /// one always says the same three things and marks where they are.
    ///
    /// Both directions of a pair share one progress, so dropping to a single direction leaves it
    /// with the schedule the two were building together rather than starting over.
    @ViewBuilder
    private func DirectionMenu(entry: RelatedLink) -> some View {
        let link = entry.link
        let other = entry.other.text

        // Turning a single link around drops its anchor -- the range points into the text which is
        // about to become the answer -- where a mutual pair just loses the half not wanted. Said in
        // the menu rather than discovered after the fact.
        let reversingDropsBlank = link.reverse == nil && link.isAnchored

        Menu("Direction", systemImage: "arrow.left.arrow.right") {
            Button {
                studyOnly(.outgoing, of: entry)
            } label: {
                Label(
                    entry.direction != .outgoing && reversingDropsBlank
                        ? "Study \"\(other)\" from this term, dropping the blank"
                        : "Study \"\(other)\" from this term",
                    systemImage: entry.direction == .outgoing ? "checkmark" : "arrow.right"
                )
            }

            Button {
                studyOnly(.incoming, of: entry)
            } label: {
                Label(
                    entry.direction != .incoming && reversingDropsBlank
                        ? "Study this term from \"\(other)\", dropping the blank"
                        : "Study this term from \"\(other)\"",
                    systemImage: entry.direction == .incoming ? "checkmark" : "arrow.left"
                )
            }

            Button {
                // No-op when it is already both ways, the same as the other two: the checkmark is
                // what says which one you are on. Disabling only this one made it the single grey
                // row in the menu, which read as unavailable rather than as current.
                guard entry.direction != .mutual else { return }

                link.addReverse()
                term.touch()
            } label: {
                Label(
                    "Study both ways",
                    systemImage: entry.direction == .mutual
                        ? "checkmark" : "arrow.left.arrow.right"
                )
            }
        }
        .tint(.primary)
    }

    /// Leaves `entry` studied in `direction` alone, whichever way it goes now.
    ///
    /// From a mutual pair this deletes the half not wanted. From a single link going the other way
    /// it turns that link around, which keeps its progress and review history where deleting and
    /// recreating would throw both away -- at the cost of its anchor, which pointed into the text
    /// that is now the answer.
    private func studyOnly(_ direction: RelatedLink.Direction, of entry: RelatedLink) {
        guard entry.direction != direction else { return }

        if let reverse = entry.link.reverse {
            // A mutual pair: the half to drop is whichever one is not the direction asked for.
            (direction == .outgoing ? reverse : entry.link).delete()
        } else {
            entry.link.swapDirection()
        }

        term.touch()
    }

    /// Takes tags off this term, and offers to delete any which that leaves on nothing.
    ///
    /// A tag applied to no term is invisible everywhere except the tag list, where it sits as a row
    /// which filters nothing. Keeping one is reasonable -- a tag made ahead of the terms it is for
    /// -- so this asks rather than tidies.
    private func untag(_ offsets: IndexSet) {
        let removed = (term.tags ?? []).enumerated()
            .filter { offsets.contains($0.offset) }
            .map(\.element)

        // Counted before the removal: reading a relationship straight after writing it is the
        // unreliable read the orphaned-term path also avoids.
        let leftEmpty = removed.filter { ($0.terms ?? []).count == 1 }

        term.remove(tagOffsets: offsets)

        unusedTag = leftEmpty.first
    }

    /// A tag left applied to nothing by the untagging just done, offered for deletion.
    @State private var unusedTag: Tag?

    /// A term left with no links at all by the deletion just made, offered for deletion too.
    @State private var orphaned: Term?

    @Environment(\.showTips) private var showTips


    /// Which tips this screen decided to show when it appeared.
    ///
    /// Sampled once rather than read from the term as it stands: the conditions are all about what
    /// the term is missing, so acting on a tip is what makes its condition false. Left reactive, the
    /// tip would vanish the instant the first link or tag landed -- animating an explanation away at
    /// exactly the moment the reader looks to see what their action did. Freezing costs the reverse
    /// case, where emptying a term does not bring its tip back until the screen is opened again, and
    /// that is the better trade: a tip appearing mid-edit is as distracting as one leaving.
    @State private var tip = TermTips()

    /// Whether ``tip`` has been decided yet, so it is decided once rather than again on every
    /// change of the term's identity.
    @State private var sampledTip = false

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

            Section {
                TagSelectionList(
                    selectedTags: term.tags ?? [],
                    addTag: { term.add(tag: $0) },
                    removeTags: { untag($0) }
                )
            } header: {
                Text("Tags")
            } footer: {
                if tip.tags {
                    Tip("Tag this term so you can choose when to study it.")
                }
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
        .confirmationDialog(
            "Delete this tag?",
            isPresented: Binding { unusedTag != nil } set: { if !$0 { unusedTag = nil } },
            titleVisibility: .visible,
            presenting: unusedTag
        ) { tag in
            Button("Delete tag", role: .destructive) {
                modelContext.delete(tag)
                unusedTag = nil
            }

            Button("Keep", role: .cancel) { unusedTag = nil }
        } message: { tag in
            Text("\"\(tag.name)\" is no longer applied to any term.")
        }
        .confirmationDialog(
            "Delete this term too?",
            isPresented: Binding { orphaned != nil } set: { if !$0 { orphaned = nil } },
            titleVisibility: .visible,
            presenting: orphaned
        ) { other in
            Button("Delete term", role: .destructive) {
                other.delete()
                orphaned = nil
            }

            Button("Keep", role: .cancel) { orphaned = nil }
        } message: { other in
            Text(
                "\"\(other.text)\" is no longer linked to anything, so there is nothing to study from it."
            )
        }
        .navigationTitle("Term")
        // Sampled here rather than read inline, so that acting on a tip does not animate it away
        // while the reader is looking at what their action did. See `tip`.
        .onChange(of: term.persistentModelID, initial: true) { tip = chooseTip() }
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

        Section {
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
                // Menu icons pick up the app's tint, which is the green the answer buttons use --
                // it reads as though every item were an affirmative action. Stated per item, since
                // the destructive one still wants red.
                .contextMenu {
                    ProgressMenuItem(progress: entry.link.progress) { openedProgress = $0 }
                        .tint(.primary)

                    ShareProgressMenu(link: entry.link, term: term)
                        .tint(.primary)

                    DirectionMenu(entry: entry)

                    // Only for what is studied *from* this term: an incoming link is prompted by
                    // the other term, so its hint is written on that term's screen.
                    if entry.direction != .incoming, entry.link.hint.isEmpty {
                        Button("Add hint", systemImage: "lightbulb") {
                            hintedLink = entry.link
                        }
                        .tint(.primary)
                    }

                    // Unanchoring is offered even though editing the text does it on its own when
                    // the anchored words go away: a re-anchor left over text nobody would have
                    // chosen has to be recoverable without deleting the link and its history.
                    if entry.link.isAnchored {
                        Button("Unanchor", systemImage: "rectangle.slash") {
                            entry.link.unanchor()
                            term.touch()
                        }
                        .tint(.primary)
                    }

                    Button("Delete link", systemImage: "trash", role: .destructive) {
                        delete(entry)
                    }
                    .tint(.red)
                } preview: {
                    // With tips off there is nothing to preview, and an empty card is worse than
                    // the plain lift the row gets without one.
                    if showTips {
                        LinkExplanation(entry: entry)
                    }
                }
            }

            NewLinkRow(
                term: term,
                blanking: $blanking,
                blankingUnmatched: $blankingUnmatched
            )
        } header: {
            Text("Links")
        } footer: {
            // What is happening right now wins over what the section has to teach: a reader partway
            // through blanking a word needs to know the field can be edited, not what a link is.
            if blankingUnmatched {
                Tip("Edit the text above to find the term these words belong to.")
            } else if tip.links == .whatALinkIs {
                // The word "link" is the app's, not the reader's. What they came to add is a
                // meaning.
                Tip(
                    "Link this term to a meaning, translation, definition, or example sentence to study it."
                )
            } else if tip.links == .howToBlank {
                Tip(
                    "Select a word and tap $1 to study this sentence with this word hidden.",
                    // The edit menu's own action, taken from the catalog rather than written again
                    // here, so the tip names the button by whatever the menu is calling it.
                    value: String(
                        localized: "Blank",
                        comment: "Edit menu action which blanks out the selected text."
                    ),
                    // A footer is drawn at `.footnote`, and the emphasised run has to be given the
                    // same style or it comes out at the `.body` default -- larger than the sentence
                    // around it.
                    font: .footnote
                )
            }
        }
    }

    /// Reads the term and decides which tip, if any, this screen shows for as long as it is open.
    ///
    /// The order matters: someone whose term has no links has not yet met the idea that an answer
    /// is a link, and telling them about blanking on top of that is two new things at once. So the
    /// first tip gives way to the second, which gives way to nothing.
    private func chooseTip() -> TermTips {
        let related = term.relatedLinks

        // At most one per section, not one per screen: the two sit under different headings and
        // explain different things, so showing both is not the wall of text the one-at-a-time rule
        // was guarding against. Ordering them into a single queue meant a new term -- no links, no
        // tags -- showed the links tip and hid the tags one until a link existed, which on an empty
        // database is the first screen the reader ever sees.
        let links: TermTips.Links? =
            if related.isEmpty {
                .whatALinkIs
            } else if !related.contains(where: { $0.link.isAnchored }), isSentence {
                .howToBlank
            } else {
                nil
            }

        return .init(links: links, tags: term.tags?.isEmpty != false)
    }

    /// Whether the term's text is long enough that blanking part of it is a sensible thing to
    /// offer.
    ///
    /// A blank works by leaving something to read around, so the test is that there is more than
    /// one word -- not how many characters, which would ask the wrong question of a language that
    /// does not space its words the way English does.
    private var isSentence: Bool {
        term.text.split(whereSeparator: \.isWhitespace).count >= Self.wordsWorthBlanking
    }

    /// How many words a term needs before blanking one of them is worth suggesting.
    ///
    /// Blanking works by leaving enough around the gap to think from, which two words do not give:
    /// hiding one of them asks the reader to recall half of a pair they are already studying whole.
    /// A sentence is where the tip earns its place.
    private static let wordsWorthBlanking = 4

    /// Says, in the menu of a row whose progress is shared, what that sharing means and with what.
    ///
    /// A menu rather than a line in the list: the mark between two rows is a rule an icon sits on,
    /// with no room for words which would have to be read around every time the list is scanned.
    /// A menu is asked for, has room for a whole sentence, and can name the other link instead of
    /// pointing vaguely at "these".
    ///
    /// What the row's arrow and its sharing mark mean, shown above the menu rather than inside it.
    ///
    /// A menu item is about twenty-five characters wide before it truncates, which a sentence
    /// naming a term does not fit into -- the first attempt put these in the item list and they
    /// were cut off mid-word. The preview is as wide as the row, wraps freely, and is where the eye
    /// lands first when the menu opens.
    ///
    /// Laid out as the term this link points at, then a line per thing the row says about it, each
    /// led by the same symbol the row draws. The symbols are the point: the arrow on a row means
    /// nothing until something puts it beside the sentence it stands for, and this is the only
    /// place the two ever appear together.
    @ViewBuilder
    private func LinkExplanation(entry: RelatedLink) -> some View {
        let others = entry.link.progress?.sharers.filter {
            $0.persistentModelID != entry.link.persistentModelID
        } ?? []

        VStack(alignment: .leading, spacing: 12) {
            // The term at the other end, as the row shows it. An anchored link quotes the words it
            // was taken from on its own line below, which is what the row does too.
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.other.text)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if entry.direction != .incoming, entry.link.isAnchored {
                    AnchorQuote(link: entry.link, emphasised: false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ExplanationRow(direction: entry.direction) {
                    switch entry.direction {
                    case .outgoing:
                        Tip(
                            "Studied by recalling \"$2\" from \"$1\"",
                            values: [term.text, entry.other.text],
                            font: .subheadline
                        )
                    case .incoming:
                        Tip(
                            "Studied by recalling \"$1\" from \"$2\"",
                            values: [term.text, entry.other.text],
                            font: .subheadline
                        )
                    case .mutual:
                        Tip(
                            "Studied in both directions: \"$1\" from \"$2\", and \"$2\" from \"$1\"",
                            values: [term.text, entry.other.text],
                            font: .subheadline
                        )
                    }
                }

                if others.count == 1, let other = others.first {
                    ExplanationRow(systemImage: "link") {
                        Tip(
                            "Shares progress with \"$1\". Reviewing either advances both.",
                            value: other.answerText,
                            font: .subheadline
                        )
                    }
                } else if !others.isEmpty {
                    ExplanationRow(systemImage: "link") {
                        Tip(
                            "Shares progress with $1 other links. Reviewing any of them advances all.",
                            value: "\(others.count)",
                            font: .subheadline
                        )
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        // Without a width the preview shrinks to its longest unbreakable run, which for a one-line
        // tip is a card narrower than the row it came from.
        .frame(width: 280, alignment: .leading)
    }

    /// One line of ``LinkExplanation``: the symbol the row draws, and what it means.
    ///
    /// The symbol keeps a fixed width so the sentences line up with each other rather than with
    /// their own icons, and is hidden from VoiceOver -- the sentence beside it already says what
    /// the symbol would have been read out as.
    @ViewBuilder
    private func ExplanationRow(
        systemImage: String,
        @ViewBuilder text: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                // Matching the sentence it leads rather than sitting under it: this is the symbol
                // the reader came here to have explained, so it should not be the faintest thing
                // on the card.
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            text()
                // Preview content is measured before it is laid out, and a line's worth of height
                // is what the first pass gives it -- one tip wrapped, two truncated. Saying there
                // is no limit, and that the text may grow vertically, is what makes both wrap.
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The same row, taking its symbol from a link's direction so the arrow matches the one drawn
    /// on the row itself.
    @ViewBuilder
    private func ExplanationRow(
        direction: RelatedLink.Direction,
        @ViewBuilder text: () -> some View
    ) -> some View {
        let systemImage =
            switch direction {
            case .outgoing: "arrow.right"
            case .incoming: "arrow.left"
            case .mutual: "arrow.left.arrow.right"
            }

        ExplanationRow(systemImage: systemImage, text: text)
    }

    /// Whether two entries are scheduled against the same progress.
    private func shareProgress(_ a: RelatedLink, _ b: RelatedLink) -> Bool {
        guard let lhs = a.link.progress?.persistentModelID else { return false }

        return lhs == b.link.progress?.persistentModelID
    }

    /// Deletes an entry, which for a mutual pair means both of its links.
    private func delete(_ entry: RelatedLink) {
        let other = entry.other
        let removed = Set(entry.links.map(\.persistentModelID))

        // Asked before the delete, not after: a relationship read once its links are gone is the
        // unreliable read `Link.delete()` warns about, so what survives is worked out from the list
        // as it stands and the set about to be removed.
        //
        // A term reached only through the link being deleted is left unreachable and unstudiable:
        // it sits in the list with nothing pointing at it and nothing to recall it from. That is a
        // legitimate thing to want -- a term kept for later -- so it is offered rather than done.
        let willBeOrphaned = !other.relatedLinks.contains {
            !removed.contains($0.link.persistentModelID)
        }

        for link in entry.links {
            link.delete()
        }

        if willBeOrphaned, other.modelContext != nil {
            orphaned = other
        }
    }
}

/// The explanations a term's screen offers, chosen when it opens.
///
/// One per section at most. Within the Links section they are ordered: someone whose term has no
/// links has not yet met the idea that an answer is a link, and telling them about blanking on top
/// of that is two new things at once.
private struct TermTips {
    enum Links {
        /// What a link is for, on a term which has none.
        case whatALinkIs
        /// How to blank part of the text, on a linked term long enough to have something to blank.
        case howToBlank
    }

    var links: Links?
    /// Whether to say what tags are for, on a term which has none.
    var tags = false
}

/// How many characters of `link`'s target are the words the link is anchored over, when the target
/// simply starts with them.
///
/// An anchored row quotes the blanked span underneath its title, which is worth a line when the two
/// differ -- 갔다 blanked against the term 가다 -- and pure noise when they do not: 고양이 quoted
/// under 고양이 prints the title twice. So when the span is a prefix of the target, the row tints
/// that prefix in the title instead and drops the quote.
///
/// A prefix rather than a substring anywhere: "mange" opening "manger" is the conjugated form the
/// term is stored under, where the same letters in the middle of a longer word are a coincidence.
/// A single anchor only, since two spans cannot both be the start of one term.
private func anchoredPrefixLength(of link: Link) -> Int? {
    guard
        let source = link.source,
        let target = link.target,
        link.anchors.count == 1,
        let anchor = link.anchors.first
    else { return nil }

    let span = String(source.text[anchor])

    guard !span.isEmpty, target.text.hasPrefix(span) else { return nil }

    return span.count
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

    /// The span to light in this row's title, when the words blanked in the sentence above are just
    /// the opening of the term this row points at.
    ///
    /// Only for a row studied *from* this term: an incoming row's title is the sentence itself, and
    /// already highlights its anchor in place.
    private var tintedPrefix: (length: Int, color: Color)? {
        guard
            entry.direction != .incoming,
            let color = anchorColor(of: entry.link)
        else { return nil }

        // Zero-length rather than `nil` once the text stops matching: which branch draws this row
        // is decided by whether there is a tint at all, and flipping between the two mid-edit gives
        // the row a different view identity, which takes the keyboard away after one keystroke. The
        // field stays put and simply has nothing lit.
        return (anchoredPrefixLength(of: entry.link) ?? 0, color)
    }

    /// Whether the hint line is shown at all: a written hint is always there to be read and
    /// corrected, and an empty one only appears while the row is being worked on.
    private var showsHint: Bool {
        guard entry.direction != .incoming else { return false }

        // `focused` covers the plain title field; `focusedLink` covers the tinted one, which owns
        // its focus state internally and reports it outwards rather than through a `@FocusState`
        // this view can read.
        let titleFocused =
            focused || focusedLink?.persistentModelID == entry.link.persistentModelID

        return !entry.link.hint.isEmpty || titleFocused || hintFocused
            || hinting?.persistentModelID == entry.link.persistentModelID
    }

    var body: some View {
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
                } else if let prefix = tintedPrefix {
                    // The blanked words are the start of this term, so they are lit here instead of
                    // being quoted underneath -- the quote would have repeated the title's own
                    // opening back to it.
                    //
                    // Focus is reported through `focusedTerm` rather than a `.focused` here, the
                    // same as the incoming branch above: the field owns its own focus state, which
                    // an outer binding cannot reach. Without it the row would still edit, but the
                    // hint line would not open on a tap and the term's anchors would not brighten
                    // to say which blank this row is.
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
                        tintingPrefix: prefix
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

                // Between the term and the footer: the hint is about the term above it, where the
                // due date and direction below are about the schedule. Sitting under the footer it
                // read as a third line belonging to neither.
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

                // The quote rides on the subtitle line rather than above it: the term is what the
                // row is about, and which words it was taken from is the sort of detail the due
                // date and the direction already live on. An incoming row has no quote -- its
                // title carries the highlight instead.
                //
                // The direction rides along here too rather than taking a column of its own on the
                // left, where it cost every row an indent.
                HStack(spacing: 6) {
                    if entry.direction != .incoming, (tintedPrefix?.length ?? 0) == 0 {
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

    /// Set while this row is blanking a selection which matches no existing term, so the section's
    /// footer can say so. Reported outwards rather than drawn here: the sentence belongs under the
    /// section with the others, not in a row of its own halfway up the list.
    @Binding var blankingUnmatched: Bool

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
            .onChange(of: matches.isEmpty, initial: true) { reportBlankingUnmatched() }
            .onChange(of: blanking) { reportBlankingUnmatched() }
            // The predicate reads the field's text too, so emptying it has to be heard: without
            // this the flag stays true over an empty field and the footer keeps explaining a blank
            // nobody is making any more.
            .onChange(of: trimmedText.isEmpty) { reportBlankingUnmatched() }
            .onDisappear { blankingUnmatched = false }
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

    /// Tells the section whether this row is blanking a selection nothing matches -- the "sert"
    /// against "servir" case, where the way out is to keep typing.
    private func reportBlankingUnmatched() {
        blankingUnmatched = blanking != nil && matches.isEmpty && !trimmedText.isEmpty
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

        // The term being edited is not a candidate, even on an exact match: blanking a word which
        // is the whole of this term's text -- or simply typing its name -- would otherwise resolve
        // to itself, and a link from a term to itself has nothing to study. Suggestions already
        // leave it out; this is the same rule for the text submitted as typed.
        if let existing = allTerms.first(where: {
            $0.text == text && $0.persistentModelID != term.persistentModelID
        }) {
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

#Preview("Empty database") {
    NavigationStack {
        NewTermEditor()
    }
    // Its own empty container rather than `previewModelContainer()`, which seeds terms: this is the
    // screen as it looks on first launch, which is where the tips have the most to say. Without a
    // container at all, the `@Query`s here and in `NewLinkRow` have nothing to read and trap.
    .modelContainer(
        try! ModelContainer(
            for: Schema(appModels),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    )
}
