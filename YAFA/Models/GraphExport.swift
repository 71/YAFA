import FSRS
import Foundation
import SwiftData

extension CardState {
    /// Recovers a state from ``stringValue``, falling back to `.new` for anything unrecognized --
    /// a hand-edited or foreign export should not fail to import over this one field.
    init(stringValue: String) {
        self = Self.allCases.first { $0.stringValue == stringValue } ?? .new
    }

    static let allCases: [CardState] = [.new, .learning, .review, .relearning]
}

extension Review.Outcome {
    /// Recovers an outcome from ``description``, falling back to `.ok` for anything unrecognized --
    /// a hand-edited or foreign export should not fail to import over this one field.
    init(description: String) {
        self =
            switch description {
            case "fail": .fail
            case "easy": .easy
            case "hard": .hard
            default: .ok
            }
    }
}

/// The JSON shape terms, links, tags, and their scheduling state are exported to and imported from.
///
/// Unlike the CSV/TSV export -- one row per link, front/back/notes only -- this is graph-shaped: a
/// term with several outgoing links, an anchored link, a shared progress, or a tag's study mode all
/// round-trip. A term, tag, or progress is referred to elsewhere in the file by its index into
/// `terms`/`tags`/`progress` -- there is no separate id field, and the index says nothing about a
/// `PersistentIdentifier`.
struct TermGraph: Codable {
    static let currentVersion = 2

    var version: Int = Self.currentVersion
    var tags: [TagDTO] = []
    var terms: [TermDTO] = []
    var progress: [ProgressDTO] = []
    var links: [LinkDTO] = []

    /// An index into `terms`.
    typealias TermRef = Int
    /// An index into `progress`.
    typealias ProgressRef = Int

    struct TagDTO: Codable {
        var name: String
        var studying: Bool
    }

    struct TermDTO: Codable {
        var text: String
        var notes: String
        var created: Date
        var modified: Date
        /// Indices into the top-level `tags`.
        var tags: [Int]
    }

    struct CardDTO: Codable {
        var due: Date
        var stability: Double
        var difficulty: Double
        var elapsedDays: Double
        var scheduledDays: Double
        var reps: Int
        var lapses: Int
        /// The state's ``CardState/stringValue``, so the file reads "new"/"learning"/"review"/
        /// "relearning" rather than the raw `Int` its own `Codable` conformance would produce.
        var state: String
        var lastReview: Date?

        init(_ card: Card) {
            due = card.due
            stability = card.stability
            difficulty = card.difficulty
            elapsedDays = card.elapsedDays
            scheduledDays = card.scheduledDays
            reps = card.reps
            lapses = card.lapses
            state = card.state.stringValue
            lastReview = card.lastReview
        }

        var card: Card {
            Card(
                due: due,
                stability: stability,
                difficulty: difficulty,
                elapsedDays: elapsedDays,
                scheduledDays: scheduledDays,
                reps: reps,
                lapses: lapses,
                state: CardState(stringValue: state),
                lastReview: lastReview
            )
        }
    }

    struct ReviewDTO: Codable {
        var date: Date
        /// The outcome's ``Review/Outcome/description``, so the file reads "ok"/"fail"/"easy"/"hard"
        /// rather than the raw `Int` its own `Codable` conformance would produce.
        var outcome: String

        /// Which link was shown, as `[source, target]` term indices. `nil` once the link it
        /// recorded has been deleted, same as ``Review/link``.
        var link: [TermRef]?
    }

    struct ProgressDTO: Codable {
        var card: CardDTO
        var reviews: [ReviewDTO]
    }

    struct LinkDTO: Codable {
        var source: TermRef
        var target: TermRef
        var hint: String
        /// Flat `[lower, upper, lower, upper, ...]` UTF-16 offset pairs, same shape as
        /// ``AnchorRange/pack(_:)``.
        var anchors: [Int]
        var created: Date
        var progress: ProgressRef
    }
}

// MARK: - Export

extension TermGraph {
    /// Builds the graph export for `terms`, following their links out to whatever they reach.
    ///
    /// Only the given terms get an entry in `terms`, but a link's `target` may point at a term
    /// outside the set (e.g. an unstudied translation) -- such targets are pulled in too, since a
    /// link naming a term the file never defines would not round-trip.
    init(exporting terms: some Sequence<Term>) {
        var termIds: [PersistentIdentifier: TermRef] = [:]
        var progressIds: [PersistentIdentifier: ProgressRef] = [:]
        var tagIds: [ObjectIdentifier: Int] = [:]

        var tagDTOs: [TagDTO] = []
        var termDTOs: [TermDTO] = []
        var progressDTOs: [ProgressRef: ProgressDTO] = [:]
        var linkDTOs: [LinkDTO] = []

        func ref(for tag: Tag) -> Int {
            let key = ObjectIdentifier(tag)

            if let existing = tagIds[key] { return existing }

            let id = tagDTOs.count
            tagIds[key] = id
            tagDTOs.append(TagDTO(name: tag.name, studying: tag.isStudying))

            return id
        }

        func ref(for term: Term) -> TermRef {
            if let existing = termIds[term.persistentModelID] { return existing }

            let id = termDTOs.count
            termIds[term.persistentModelID] = id

            termDTOs.append(
                TermDTO(
                    text: term.text,
                    notes: term.notes,
                    created: term.creationDate,
                    modified: term.modificationDate,
                    tags: (term.tags ?? []).map(ref(for:))
                )
            )

            return id
        }

        func ref(for progress: Progress) -> ProgressRef {
            if let existing = progressIds[progress.persistentModelID] { return existing }

            let id = progressDTOs.count
            progressIds[progress.persistentModelID] = id

            return id
        }

        // Terms first, so every term named by a link -- including one reached only as a target --
        // gets an id and an entry, even if it isn't in the original set.
        var queue = Array(terms)
        var queued = Set(queue.map(\.persistentModelID))

        var index = 0
        while index < queue.count {
            let term = queue[index]
            index += 1

            _ = ref(for: term)

            for link in term.outgoingLinks ?? [] {
                guard let target = link.target else { continue }

                if queued.insert(target.persistentModelID).inserted {
                    queue.append(target)
                }
            }
        }

        for term in queue {
            let sourceRef = termIds[term.persistentModelID]!

            for link in term.outgoingLinks ?? [] {
                guard let target = link.target, let progress = link.progress else { continue }

                let progressRef = ref(for: progress)

                if progressDTOs[progressRef] == nil {
                    // A review's link may point at terms outside this progress's own sharers (a
                    // shared progress can be reviewed from either direction), so each side is
                    // resolved through `ref(for:)` itself rather than assumed to already have one.
                    let reviews = (progress.reviews ?? []).map { review -> ReviewDTO in
                        let studiedRefs = review.link.flatMap { studied -> [TermRef]? in
                            guard let studiedSource = studied.source, let studiedTarget = studied.target
                            else { return nil }

                            return [ref(for: studiedSource), ref(for: studiedTarget)]
                        }

                        return ReviewDTO(date: review.date, outcome: review.outcome.description, link: studiedRefs)
                    }

                    progressDTOs[progressRef] = ProgressDTO(card: CardDTO(progress.fsrsCard), reviews: reviews)
                }

                linkDTOs.append(
                    LinkDTO(
                        source: sourceRef,
                        target: ref(for: target),
                        hint: link.hint,
                        anchors: link.ranges,
                        created: link.creationDate,
                        progress: progressRef
                    )
                )
            }
        }

        self.tags = tagDTOs
        self.terms = termDTOs
        self.progress = (0..<progressDTOs.count).map { progressDTOs[$0]! }
        self.links = linkDTOs
    }

    /// Encodes this graph as pretty-printed, sorted-key JSON.
    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        return try! encoder.encode(self)
    }
}

/// One row of the flat JSON export this app used before terms became a graph: one row per link,
/// front/back/notes only. Kept only so those files can still be imported; new exports never
/// produce this shape.
struct LegacyExportRow: Codable {
    var front: String
    var back: String
    var notes: String
}

// MARK: - Import

extension TermGraph {
    /// The first non-whitespace byte of `data`, or `nil` if it is empty or all whitespace.
    ///
    /// `{` marks a graph export, `[` the old flat array-of-rows export; anything else is not JSON
    /// at all, and falls to the delimited-text importer.
    private static func firstSignificantByte(_ data: Data) -> UInt8? {
        data.first { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\n") && $0 != UInt8(ascii: "\t") }
    }

    static func looksLikeGraph(_ data: Data) -> Bool {
        firstSignificantByte(data) == UInt8(ascii: "{")
    }

    /// Whether `data` looks like the old flat array-of-rows JSON export.
    static func looksLikeLegacyExport(_ data: Data) -> Bool {
        firstSignificantByte(data) == UInt8(ascii: "[")
    }

    init(decoding data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self = try decoder.decode(Self.self, from: data)
    }

    /// Decodes the old flat array-of-rows JSON export.
    static func decodingLegacyExport(_ data: Data) throws -> [LegacyExportRow] {
        try JSONDecoder().decode([LegacyExportRow].self, from: data)
    }

    /// Applies this graph to `context`, reusing existing terms whose text matches (case-insensitive,
    /// same rule the plain-row importer uses) and creating the rest.
    ///
    /// Returns the number of terms and links actually created, for a summary to show the user.
    @discardableResult
    func apply(to context: ModelContext, existingTermsByText: [String: Term]) -> (
        termsCreated: Int, linksCreated: Int
    ) {
        var termsByText = existingTermsByText
        var tagsByName: [String: Tag] = [:]
        var resolvedTags: [Tag] = []
        var resolvedTerms: [Term] = []
        var resolvedProgress: [Progress] = []
        var termsCreated = 0
        var linksCreated = 0

        func existingTag(named name: String) -> Tag? {
            if let cached = tagsByName[name] { return cached }

            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
            let found = try? context.fetch(descriptor).first

            if let found {
                tagsByName[name] = found
            }

            return found
        }

        func resolvedTag(named name: String, studying: Bool) -> Tag {
            if let existing = existingTag(named: name) {
                return existing
            }

            let tag = Tag(name: name, isStudying: studying)

            context.insert(tag)
            tagsByName[name] = tag

            return tag
        }

        for tagDTO in tags {
            resolvedTags.append(resolvedTag(named: tagDTO.name, studying: tagDTO.studying))
        }

        for termDTO in terms {
            let key = termDTO.text.localizedLowercase
            let termTags = termDTO.tags.compactMap { resolvedTags[safe: $0] }

            if let existing = termsByText[key] {
                for tag in termTags where !existing.has(tag: tag) {
                    existing.add(tag: tag)
                }
                if existing.notes.isEmpty && !termDTO.notes.isEmpty {
                    existing.notes = termDTO.notes
                }

                resolvedTerms.append(existing)
                continue
            }

            let term = Term(
                text: termDTO.text,
                notes: termDTO.notes,
                creationDate: termDTO.created,
                tags: termTags
            )

            context.insert(term)
            termsByText[key] = term
            resolvedTerms.append(term)
            termsCreated += 1
        }

        for progressDTO in progress {
            let newProgress = Progress(creationDate: progressDTO.card.due)

            newProgress.fsrsCard = progressDTO.card.card
            newProgress.nextReviewDate = progressDTO.card.due

            context.insert(newProgress)
            resolvedProgress.append(newProgress)
        }

        for linkDTO in links {
            guard
                let source = resolvedTerms[safe: linkDTO.source],
                let target = resolvedTerms[safe: linkDTO.target]
            else { continue }

            let link = source.link(to: target)

            link.hint = linkDTO.hint
            link.anchor(over: AnchorRange.unpack(linkDTO.anchors).compactMap { $0.range(in: source.text) })

            if let progress = resolvedProgress[safe: linkDTO.progress] {
                link.join(progress: progress)
            }

            linksCreated += 1
        }

        // Reviews are replayed last, once every link they might reference has been created.
        for (progressIndex, progressDTO) in progress.enumerated() {
            guard let newProgress = resolvedProgress[safe: progressIndex] else { continue }

            for reviewDTO in progressDTO.reviews {
                let studiedLink = reviewDTO.link.flatMap { refs -> Link? in
                    guard
                        refs.count == 2,
                        let source = resolvedTerms[safe: refs[0]],
                        let target = resolvedTerms[safe: refs[1]]
                    else { return nil }

                    return (source.outgoingLinks ?? []).first { $0.target?.persistentModelID == target.persistentModelID }
                }

                guard let studiedLink else { continue }

                newProgress.record(
                    review: reviewDTO.date,
                    outcome: Review.Outcome(description: reviewDTO.outcome),
                    of: studiedLink,
                    in: context
                )
            }
        }

        return (termsCreated, linksCreated)
    }
}

extension Array {
    /// This element at `index`, or `nil` if `index` is out of bounds -- for indices read back from
    /// an imported file, which may not address this array at all if the file was hand-edited or
    /// corrupt.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
