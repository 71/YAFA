import SwiftUI

struct ExportSheet: View {
    let flashcards: Set<Flashcard>

    @State private var format = Format.csv
    @State private var separator = Separator.comma
    @State private var quoteValues = true
    @State private var includeNotes = false

    @State private var previewText = ""

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section(header: Text("Options")) {
                    Picker("Format", selection: $format) {
                        Text("CSV").tag(Format.csv)
                        Text("JSON").tag(Format.json)
                    }

                    if format == .csv {
                        Picker("Separator", selection: $separator) {
                            Text("Comma").tag(Separator.comma)
                            Text("Semicolon").tag(Separator.semicolon)
                            Text("Tab").tag(Separator.tab)
                            Divider()
                            Text("Custom").tag(Separator.text(""))
                        }

                        if case .text(let string) = separator {
                            TextField(
                                "Custom separator",
                                text: Binding {
                                    string
                                } set: {
                                    separator = .text($0)
                                }
                            )
                        }

                        Toggle(isOn: $quoteValues) {
                            Text("Quote values")
                        }

                        Toggle(isOn: $includeNotes) {
                            Text("Include notes")
                        }
                    }
                }

                Section(header: Text("Preview")) {
                    TextEditor(text: .constant(previewText))
                        .monospaced()
                }

                ExportLink(
                    flashcards: flashcards,
                    format: format,
                    separator: separator,
                    quoteValues: quoteValues,
                    includeNotes: includeNotes
                )
            }
        }
        .onChange(of: flashcards, initial: true) { updatePreviewText() }
        .onChange(of: separator) { updatePreviewText() }
        .onChange(of: format) { updatePreviewText() }
        .onChange(of: quoteValues) { updatePreviewText() }
        .onChange(of: includeNotes) { updatePreviewText() }

        .onAppear {
            if flashcards.contains(where: { !$0.notes.isEmpty }) {
                includeNotes = true
            }
        }
    }

    private func updatePreviewText() {
        previewText = exportToText(
            flashcards.prefix(4),
            separator: separator,
            format: format,
            quoteValues: quoteValues,
            includeNotes: includeNotes
        )
    }
}

#Preview {
    let container = previewModelContainer()
    let flashcards: [Flashcard] = try! container.mainContext.fetch(.init())

    ExportSheet(flashcards: .init(flashcards)).modelContainer(container)
}

private struct ExportLink: View {
    let flashcards: Set<Flashcard>
    let format: Format
    let separator: Separator
    let quoteValues: Bool
    let includeNotes: Bool

    private var title: String {
        flashcards.count == 1
            ? "Export flashcard" : "Export \(flashcards.count) flashcards"
    }
    private var computeExportedText: () -> Data {
        {
            exportToText(
                flashcards,
                separator: separator,
                format: format,
                quoteValues: quoteValues,
                includeNotes: includeNotes
            ).data(using: .utf8)!
        }
    }

    var body: some View {
        // Note: we must specify a `message:` to get iOS to display a "Copy" action:
        // https://stackoverflow.com/a/75910083. Unfortunately, this means "Save to Files" will
        // save an additional empty text file, but what else are we supposed to do?
        if format == .json {
            ShareLink(
                title,
                item: Json(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("flashcards.json")
            )
        } else if separator == .comma {
            ShareLink(
                title,
                item: Csv(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("flashcards.csv")
            )
        } else if separator == .tab {
            ShareLink(
                title,
                item: Tsv(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("flashcards.tsv")
            )
        } else {
            ShareLink(
                title,
                item: Delimited(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("flashcards.csv")
            )
        }
    }

    private struct Json: Transferable {
        let computeExportedText: () -> Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .json) {
                $0.computeExportedText()
            }
        }
    }
    private struct Csv: Transferable {
        let computeExportedText: () -> Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .commaSeparatedText) {
                $0.computeExportedText()
            }
        }
    }
    private struct Tsv: Transferable {
        let computeExportedText: () -> Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .tabSeparatedText) {
                $0.computeExportedText()
            }
        }
    }
    private struct Delimited: Transferable {
        let computeExportedText: () -> Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .delimitedText) {
                $0.computeExportedText()
            }
        }
    }
}

private enum Separator: Hashable {
    case comma, semicolon, tab
    case text(String)
}

private enum Format: Hashable {
    case csv, json
}

private func exportToText<S: Sequence>(
    _ flashcards: S,
    separator: Separator,
    format: Format,
    quoteValues: Bool,
    includeNotes: Bool
) -> String where S.Element == Flashcard {
    var result = ""

    switch format {
    case .csv:
        let sep =
            switch separator {
            case .comma: ","
            case .semicolon: ";"
            case .tab: "\t"
            case .text(let text): text
            }

        for flashcard in flashcards {
            let fields = if includeNotes {
                [flashcard.front, flashcard.back, flashcard.notes]
            } else {
                [flashcard.front, flashcard.back]
            }

            for (i, field) in fields.enumerated() {
                if quoteValues {
                    quoteForCsv(to: &result, field)
                } else {
                    result.append(field)
                }
                result.append(i == fields.count - 1 ? "\n" : sep)
            }
        }
    case .json:
        let flashcardsAsJson = flashcards.map { flashcard in
            [
                "front": flashcard.front,
                "back": flashcard.back,
                "notes": flashcard.notes,
                "created": flashcard.creationDate.ISO8601Format(),
                "nextReview": flashcard.nextReviewDate.ISO8601Format(),
                "tags": flashcard.tags?.map { tag in ["name": tag.name] } ?? [],
                "reviews": flashcard.reviews?.map { review in
                    [
                        "date": review.date.ISO8601Format(),
                        "rating": review.outcome.description,
                    ]
                } ?? [],
            ]
        }
        let resultData = try! JSONSerialization.data(
            withJSONObject: flashcardsAsJson,
            options: [.prettyPrinted]
        )

        result = .init(decoding: resultData, as: UTF8.self)
    }

    return result
}

private func quoteForCsv(to buffer: inout String, _ text: String) {
    buffer.append("\"")

    for char in text {
        if char == "\"" {
            buffer.append("\"\"")
        } else {
            buffer.append(char)
        }
    }

    buffer.append("\"")
}
