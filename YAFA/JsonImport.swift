import Foundation

/// A flashcard read from a JSON export, as plain values.
///
/// The JSON export is the app's most complete one -- it carries dates, tags, and the full review
/// history, where the CSV carries only text -- which makes it the format a backup is restored from.
struct ImportedFlashcard {
    var front: String
    var back: String
    var notes: String
    var creationDate: Date
    var nextReviewDate: Date
    var tags: [String]
    var reviews: [(date: Date, outcome: FlashcardReview.Outcome)]
}

enum JsonImportError: LocalizedError {
    case notAnArray
    case notAnObject(index: Int)
    case missingText(index: Int)

    var errorDescription: String? {
        switch self {
        case .notAnArray:
            String(localized: "Expected a list of flashcards.")
        case .notAnObject(let index):
            String(localized: "Entry \(index + 1) is not a flashcard.")
        case .missingText(let index):
            String(localized: "Entry \(index + 1) has no front or back text.")
        }
    }
}

/// Parses the app's JSON export.
///
/// Everything but the text is optional: an export from a future version, or one edited by hand, is
/// worth importing for what it does carry rather than rejecting wholesale.
func parseJsonFlashcards(_ text: String) throws -> [ImportedFlashcard] {
    let json = try JSONSerialization.jsonObject(with: Data(text.utf8))

    guard let entries = json as? [Any] else { throw JsonImportError.notAnArray }

    return try entries.enumerated().map { (index, entry) in
        guard let entry = entry as? [String: Any] else {
            throw JsonImportError.notAnObject(index: index)
        }

        let front = entry["front"] as? String ?? ""
        let back = entry["back"] as? String ?? ""

        guard !front.isEmpty || !back.isEmpty else {
            throw JsonImportError.missingText(index: index)
        }

        let creationDate = date(entry["created"]) ?? .now

        return ImportedFlashcard(
            front: front,
            back: back,
            notes: entry["notes"] as? String ?? "",
            creationDate: creationDate,
            nextReviewDate: date(entry["nextReview"]) ?? creationDate,
            tags: (entry["tags"] as? [Any] ?? []).compactMap {
                ($0 as? [String: Any])?["name"] as? String
            },
            reviews: (entry["reviews"] as? [Any] ?? []).compactMap { review in
                guard
                    let review = review as? [String: Any],
                    let date = date(review["date"])
                else { return nil }

                return (date, outcome(review["rating"] as? String))
            }
        )
    }
}

/// Reads an ISO 8601 date, with or without fractional seconds, since the two are hard to tell apart
/// by eye and an export edited by hand may carry either.
///
/// The formatters are built per call rather than shared: `ISO8601DateFormatter` is not `Sendable`,
/// and importing happens rarely enough that the allocation does not matter.
private func date(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }

    let formatter = ISO8601DateFormatter()

    if let date = formatter.date(from: text) { return date }

    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return formatter.date(from: text)
}

/// Reads a rating, which the export writes as the name of the outcome.
private func outcome(_ value: String?) -> FlashcardReview.Outcome {
    switch value {
    case "fail": .fail
    case "easy": .easy
    case "hard": .hard
    default: .ok
    }
}
