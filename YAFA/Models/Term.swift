import Foundation
import SwiftData

// Note: All attributes must either be optional or have default values for CloudKit integration.
//       Similarly, relationships must be optional and have explicit inverses.

/// A piece of textual knowledge: a word, phrase, or definition.
///
/// A term has no direction and no front/back; those are properties of ``Link``s. It has no
/// scheduling state either -- that lives in the ``Progress`` of the links and cloze blanks which
/// point to it.
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

    /// Cloze blanks answered by this term.
    @Relationship(deleteRule: .cascade, inverse: \ClozeBlank.term)
    private(set) var clozeBlanks: [ClozeBlank]?

    init(text: String = "", notes: String = "", creationDate: Date = .now, tags: [Tag] = []) {
        self.text = text
        self.notes = notes
        self.creationDate = creationDate
        self.modificationDate = creationDate
        self.tags = tags
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
            && (clozeBlanks?.isEmpty ?? true)
    }

    /// Whether anything is studied *from* this term, and so whether it earns a row in a due list.
    var isStudied: Bool {
        !(outgoingLinks?.isEmpty ?? true) || !(clozeBlanks?.isEmpty ?? true)
    }

    /// Everything scheduled against this term: its outgoing links and its cloze blanks.
    ///
    /// Incoming links are excluded: they are studied by showing *another* term, and so belong to
    /// that term's view.
    var studiables: [any Studiable] {
        (outgoingLinks ?? []) as [any Studiable] + (clozeBlanks ?? []) as [any Studiable]
    }

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
    /// Mutual pairs come first, then outgoing links, then incoming ones; within each run the order
    /// is alphabetical by the other term. A link and its reverse collapse into a single mutual
    /// entry, so no pair of terms is ever listed twice.
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

        var mutual: [RelatedLink] = []
        var forward: [RelatedLink] = []
        var pairedIncoming = Set<PersistentIdentifier>()

        for link in outgoing {
            guard let other = link.target else { continue }

            if let reverse = incomingBySource[other.persistentModelID] {
                pairedIncoming.insert(reverse.persistentModelID)
                mutual.append(.init(link: link, reverse: reverse, other: other, direction: .mutual))
            } else {
                forward.append(.init(link: link, reverse: nil, other: other, direction: .outgoing))
            }
        }

        let backward = incoming.compactMap { link -> RelatedLink? in
            guard
                !pairedIncoming.contains(link.persistentModelID),
                let other = link.source
            else { return nil }

            return .init(link: link, reverse: nil, other: other, direction: .incoming)
        }

        func sorted(_ links: [RelatedLink]) -> [RelatedLink] {
            links.sorted {
                $0.other.text.localizedCaseInsensitiveCompare($1.other.text) == .orderedAscending
            }
        }

        return sorted(mutual) + sorted(forward) + sorted(backward)
    }

    /// Outgoing links, alphabetical by what they are studied against, except that links sharing a
    /// progress are kept adjacent.
    ///
    /// Grouping shared links together is what lets the list show sharing as adjacency -- a mark
    /// between two neighbouring rows -- instead of tagging every row with an identifier the reader
    /// has to match up by eye. A relationship also hands its elements back in no particular order,
    /// so some sort is needed regardless.
    var sortedOutgoingLinks: [Link] {
        let links = outgoingLinks ?? []

        func precedes(_ a: String, _ b: String) -> Bool {
            a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        // Each group is ordered internally, and groups are ordered by their first member, so the
        // list stays alphabetical wherever sharing doesn't force otherwise. A link with no progress
        // is keyed by its own id so that such links don't all collapse into one group.
        let groups = Dictionary(grouping: links) { $0.progress?.persistentModelID ?? $0.persistentModelID }
            .values
            .map { $0.sorted { precedes($0.answerText, $1.answerText) } }

        return groups
            .sorted { precedes($0[0].answerText, $1[0].answerText) }
            .flatMap { $0 }
    }

    func touch() {
        modificationDate = .now
    }

    /// Deletes this term, along with the progress of everything studied from it which nothing else
    /// was sharing.
    ///
    /// Deleting the term cascades to its links and cloze blanks, but their progress is nullified
    /// rather than cascaded (so that sharing survives deleting one sharer), so the progresses left
    /// with nothing pointing at them have to be collected here.
    func delete() {
        let context = modelContext
        let orphaned = studiables.compactMap(\.progress).filter { progress in
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

    /// Adds a link from this term to `target`, reusing an existing one if there is one.
    @discardableResult
    func link(to target: Term) -> Link {
        if let existing = outgoingLinks?.first(where: { $0.target == target }) {
            return existing
        }

        let link = Link(source: self, target: target)

        modelContext?.insert(link)

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
        }
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

    private(set) var terms: [Term]?
    private(set) var clozes: [Cloze]?

    init(name: String, isStudying: Bool = true) {
        self.name = name
        self.rawNotStudying = isStudying ? nil : true
    }

    var isStudying: Bool {
        get { rawNotStudying != true }
        set { rawNotStudying = newValue ? nil : true }
    }

    var committedTerms: [Term] {
        terms?.filter { !$0.isEmpty } ?? []
    }
}
