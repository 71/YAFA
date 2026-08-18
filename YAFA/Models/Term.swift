import Foundation
import SwiftData

// Note: All attributes must either be optional or have default values for CloudKit integration.
//       Similarly, relationships must be optional and have explicit inverses.

/// A piece of textual knowledge: a word, phrase, or definition.
///
/// A term has no direction and no front/back; those are properties of ``Link``s. It has no
/// scheduling state either -- that lives in the ``Progress`` of the links which point to it.
///
/// A term's text may be a word, but it may equally be a sentence or a definition whose parts are
/// themselves terms, reached by the anchored links studied from it.
@Model
final class Term {
    var text: String = ""
    var notes: String = ""

    private(set) var creationDate: Date = Date(timeIntervalSince1970: .zero)
    private(set) var modificationDate: Date = Date(timeIntervalSince1970: .zero)

    @Relationship(inverse: \Tag.terms)
    var tags: [Tag]?

    /// Links whose *source* is this term, i.e. the ones studied by showing this term.
    @Relationship(deleteRule: .cascade, inverse: \Link.source)
    private(set) var outgoingLinks: [Link]?
    /// Links whose *target* is this term, i.e. the ones studied by grading recall of this term.
    @Relationship(deleteRule: .cascade, inverse: \Link.target)
    private(set) var incomingLinks: [Link]?

    init(text: String = "", notes: String = "", creationDate: Date = .now, tags: [Tag] = []) {
        self.text = text
        self.notes = notes
        self.creationDate = creationDate
        self.modificationDate = creationDate
        self.tags = tags

        // Creating a term with tags is applying them, the same as adding one later.
        for tag in tags {
            tag.markUsed()
        }
    }

    var isEmpty: Bool {
        text.isEmpty && notes.isEmpty && (outgoingLinks?.isEmpty ?? true)
    }

    /// Whether nothing connects this term to the rest of the graph.
    ///
    /// A term which is only ever a target is not unlinked: it is the answer to somebody else's
    /// link, and is already accounted for by the row which studies it. One with no links in either
    /// direction is unfinished work -- there is nothing to study, and nothing that reaches it.
    var isUnlinked: Bool {
        (outgoingLinks?.isEmpty ?? true)
            && (incomingLinks?.isEmpty ?? true)
    }

    /// Whether anything is studied *from* this term, and so whether it earns a row in a due list.
    var isStudied: Bool {
        !(outgoingLinks?.isEmpty ?? true)
    }

    /// Everything scheduled against this term.
    ///
    /// Incoming links are excluded: they are studied by showing *another* term, and so belong to
    /// that term's view.
    var studiedLinks: [Link] { outgoingLinks ?? [] }

    /// Links pointing *at* this term, alphabetical by the term they are studied from.
    ///
    /// These are not studied from this term -- they are somebody else's outgoing links -- so they
    /// schedule that term rather than this one.
    var sortedIncomingLinks: [Link] {
        (incomingLinks ?? []).sorted {
            $0.promptText.localizedCaseInsensitiveCompare($1.promptText) == .orderedAscending
        }
    }

    /// Everything linking this term to another, in either direction.
    ///
    /// Anchored links come first, in the order their anchors appear in the text, so that the list
    /// reads along the sentence above it; then mutual pairs, then the remaining outgoing links,
    /// then incoming ones, each run alphabetical by the other term except that links sharing a
    /// progress are kept adjacent. A link and its reverse collapse into a single mutual entry, so no
    /// pair of terms is ever listed twice.
    var relatedLinks: [RelatedLink] {
        let outgoing = outgoingLinks ?? []
        let incoming = incomingLinks ?? []

        // A reverse is only mutual if *both* directions exist; index the incoming ones by their
        // source so each outgoing link can look for its counterpart.
        var incomingBySource = [PersistentIdentifier: Link]()

        for link in incoming {
            if let source = link.source {
                incomingBySource[source.persistentModelID] = link
            }
        }

        var anchored: [RelatedLink] = []
        var mutual: [RelatedLink] = []
        var forward: [RelatedLink] = []
        var pairedIncoming = Set<PersistentIdentifier>()

        for link in outgoing {
            guard let other = link.target else { continue }

            let reverse = incomingBySource[other.persistentModelID]

            if let reverse {
                pairedIncoming.insert(reverse.persistentModelID)
            }

            let entry = RelatedLink(
                link: link,
                reverse: reverse,
                other: other,
                direction: reverse == nil ? .outgoing : .mutual
            )

            // Anchored links are listed in the order they run through the text, so they go into a
            // run of their own rather than into the alphabetical ones below.
            if link.isAnchored {
                anchored.append(entry)
            } else if reverse == nil {
                forward.append(entry)
            } else {
                mutual.append(entry)
            }
        }

        let backward = incoming.compactMap { link -> RelatedLink? in
            guard
                !pairedIncoming.contains(link.persistentModelID),
                let other = link.source
            else { return nil }

            return .init(link: link, reverse: nil, other: other, direction: .incoming)
        }

        /// Alphabetical by the term at the other end, except that entries sharing a progress are
        /// kept adjacent -- which is what lets the list show sharing as a mark between neighbouring
        /// rows rather than tagging each one with an identifier to match up by eye.
        ///
        /// Without this a third, unshared link landing alphabetically between two sharers separates
        /// them, and the mark disappears: "to consume" and "to eat" share, "to drink" sorts between
        /// them, and nothing on screen says the first and last belong together.
        func sorted(_ links: [RelatedLink]) -> [RelatedLink] {
            func precedes(_ a: RelatedLink, _ b: RelatedLink) -> Bool {
                a.other.text.localizedCaseInsensitiveCompare(b.other.text) == .orderedAscending
            }

            // An entry with no progress is keyed by its own id, so that such entries don't all
            // collapse into a single group.
            let groups = Dictionary(grouping: links) {
                $0.link.progress?.persistentModelID ?? $0.id
            }
            .values
            .map { $0.sorted(by: precedes) }

            // Groups ordered by their first member, so the list stays alphabetical wherever sharing
            // doesn't force otherwise.
            return groups
                .sorted { precedes($0[0], $1[0]) }
                .flatMap { $0 }
        }

        let byPosition = anchored.sorted {
            ($0.link.anchorOffsets.first?.lower ?? 0) < ($1.link.anchorOffsets.first?.lower ?? 0)
        }

        return byPosition + sorted(mutual) + sorted(forward) + sorted(backward)
    }

    /// Outgoing links, anchored ones first in the order they appear in the text and the rest
    /// alphabetical by what they are studied against, except that links sharing a progress are kept
    /// adjacent.
    ///
    /// Grouping shared links together is what lets the list show sharing as adjacency -- a mark
    /// between two neighbouring rows -- instead of tagging every row with an identifier the reader
    /// has to match up by eye. A relationship also hands its elements back in no particular order,
    /// so some sort is needed regardless.
    var sortedOutgoingLinks: [Link] {
        let links = outgoingLinks ?? []

        // Each group is ordered internally, and groups are ordered by their first member, so the
        // list stays in order wherever sharing doesn't force otherwise. A link with no progress
        // is keyed by its own id so that such links don't all collapse into one group.
        let groups = Dictionary(grouping: links) { $0.progress?.persistentModelID ?? $0.persistentModelID }
            .values
            .map { $0.sorted(by: linkPrecedes) }

        return groups
            .sorted { linkPrecedes($0[0], $1[0]) }
            .flatMap { $0 }
    }

    /// Whether `a` is listed before `b` among the links studied from this term.
    ///
    /// Anchored links come first, in the order their anchors appear in the text, so that the list
    /// reads left to right along the sentence above it. Everything else is alphabetical by the term
    /// it is studied against.
    private func linkPrecedes(_ a: Link, _ b: Link) -> Bool {
        switch (a.anchorOffsets.first, b.anchorOffsets.first) {
        case (let anchorA?, let anchorB?): anchorA.lower < anchorB.lower
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil):
            a.answerText.localizedCaseInsensitiveCompare(b.answerText) == .orderedAscending
        }
    }

    func touch() {
        modificationDate = .now
    }

    /// Deletes this term, along with the progress of everything studied from it which nothing else
    /// was sharing.
    ///
    /// Deleting the term cascades to its links, but their progress is nullified rather than
    /// cascaded (so that sharing survives deleting one sharer), so the progresses left with nothing
    /// pointing at them have to be collected here.
    func delete() {
        let context = modelContext
        let orphaned = studiedLinks.compactMap(\.progress).filter { progress in
            progress.sharers.allSatisfy { sharer in
                sharer.owningTerm?.persistentModelID == persistentModelID
            }
        }

        context?.delete(self)

        for progress in orphaned {
            context?.delete(progress)
        }
    }

    // MARK: Links

    /// Moves the anchors of everything studied from this term to follow an edit of its text.
    ///
    /// Anchors are offsets into text the user can edit, so they only stay over the right words if
    /// they are maintained as it changes. The edit is recovered from the old and new text rather
    /// than observed, since SwiftUI reports the text after the fact.
    func adjustAnchors(from oldText: String) {
        guard let edit = TextEdit(from: oldText, to: text) else { return }

        for link in outgoingLinks ?? [] {
            link.adjustAnchors(for: edit)
        }
    }

    /// Adds a link from this term to `target`, reusing an existing one if there is one.
    ///
    /// `anchoredOver`, when given, is where the target appears in this term's text; the link is
    /// studied by blanking it out. An existing link is re-anchored rather than left alone, which is
    /// what lets blanking a second occurrence of a word already linked add to it instead of
    /// silently doing nothing.
    @discardableResult
    func link(to target: Term, anchoredOver anchor: Range<String.Index>? = nil) -> Link {
        if let existing = outgoingLinks?.first(where: { $0.target == target }) {
            if let anchor {
                existing.anchor(over: existing.anchors + [anchor])
            }

            return existing
        }

        let link = Link(source: self, target: target)

        modelContext?.insert(link)

        if let anchor {
            link.anchor(over: [anchor])
        }

        if outgoingLinks == nil {
            outgoingLinks = [link]
        } else {
            outgoingLinks!.append(link)
        }

        return link
    }

    // MARK: Tags

    func has(tag: Tag) -> Bool {
        tags?.contains(tag) == true
    }

    func has(tagIn tags: Set<Tag>) -> Bool {
        self.tags?.contains { tags.contains($0) } ?? false
    }

    func add(tag: Tag) {
        if tags == nil {
            tags = [tag]
        } else if !tags!.contains(tag) {
            tags!.append(tag)
        } else {
            // Already applied, so nothing was used.
            return
        }

        tag.markUsed()
    }

    func remove(tag: Tag) {
        if let index = tags?.firstIndex(of: tag) {
            tags!.remove(at: index)
        }
    }

    func remove(tagOffsets: IndexSet) {
        tags?.remove(atOffsets: tagOffsets)
    }
}

/// A term's connection to another, as seen from that term's own screen.
///
/// Wraps the underlying ``Link`` (and its reverse, when the pair is mutual) together with the
/// direction it reads in, so a list can show both what a term is studied against and what is
/// studied against it, without listing a mutual pair twice.
struct RelatedLink: Identifiable {
    enum Direction {
        /// Studied by showing this term and recalling the other.
        case outgoing
        /// Studied by showing the other term and recalling this one.
        case incoming
        /// Both directions exist, as two links.
        case mutual
    }

    /// The link studied *from* this term for `.outgoing` and `.mutual`, or the one studied from the
    /// other term for `.incoming`.
    let link: Link
    /// For a mutual pair, the link in the opposite direction.
    let reverse: Link?
    /// The term at the other end.
    let other: Term
    let direction: Direction

    var id: PersistentIdentifier { link.persistentModelID }

    /// Both underlying links, so that deleting a mutual entry removes the whole pair.
    var links: [Link] {
        reverse.map { [link, $0] } ?? [link]
    }
}

/// A label applied to ``Term``s.
///
/// Unlike the `FlashcardTag` it replaces, a tag has no study direction: which directions are
/// studied is decided per term by which ``Link``s exist.
@Model
final class Tag {
    var name: String = "New tag"

    /// Whether terms carrying this tag are included in the study queue.
    ///
    /// Stored inverted so that the CloudKit default (`nil`) means "studying", matching the previous
    /// schema where a tag with no explicit study mode was studied.
    private var rawNotStudying: Bool?

    /// When this tag was last applied to a term, for offering the tags most recently used before
    /// anything has been typed.
    ///
    /// Optional because CloudKit requires it, and because a tag which predates this field has no
    /// answer: it sorts last rather than pretending to a date it never recorded.
    ///
    /// Recorded on being *applied* rather than derived from the terms holding it. A term's
    /// modification date moves whenever its text is edited, so leaning on that made renaming a term
    /// look exactly like tagging one -- and made taking a tag *off* a term promote it.
    private(set) var lastUsedDate: Date?

    private(set) var terms: [Term]?

    init(name: String, isStudying: Bool = true) {
        self.name = name
        self.rawNotStudying = isStudying ? nil : true
    }

    /// Records that this tag has just been applied to something.
    func markUsed() {
        lastUsedDate = .now
    }

    var isStudying: Bool {
        get { rawNotStudying != true }
        set { rawNotStudying = newValue ? nil : true }
    }

    var committedTerms: [Term] {
        terms?.filter { !$0.isEmpty } ?? []
    }
}
