import SwiftUI

struct ExportSheet: View {
    let terms: Set<Term>

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
                    terms: terms,
                    format: format,
                    separator: separator,
                    quoteValues: quoteValues,
                    includeNotes: includeNotes
                )
            }
        }
        .onChange(of: terms, initial: true) { updatePreviewText() }
        .onChange(of: separator) { updatePreviewText() }
        .onChange(of: format) { updatePreviewText() }
        .onChange(of: quoteValues) { updatePreviewText() }
        .onChange(of: includeNotes) { updatePreviewText() }

        .onAppear {
            if terms.contains(where: { !$0.notes.isEmpty }) {
                includeNotes = true
            }
        }
    }

    private func updatePreviewText() {
        previewText = exportToText(
            terms.prefix(4),
            separator: separator,
            format: format,
            quoteValues: quoteValues,
            includeNotes: includeNotes
        )
    }
}

#Preview {
    let container = previewModelContainer()
    let terms: [Term] = try! container.mainContext.fetch(.init())

    ExportSheet(terms: .init(terms)).modelContainer(container)
}

private struct ExportLink: View {
    let terms: Set<Term>
    let format: Format
    let separator: Separator
    let quoteValues: Bool
    let includeNotes: Bool

    private var title: String {
        terms.count == 1
            ? String(localized: "Export term")
            : String(localized: "Export \(terms.count) terms")
    }
    private var computeExportedText: () -> Data {
        {
            exportToText(
                terms,
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
                preview: SharePreview("terms.json")
            )
        } else if separator == .comma {
            ShareLink(
                title,
                item: Csv(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("terms.csv")
            )
        } else if separator == .tab {
            ShareLink(
                title,
                item: Tsv(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("terms.tsv")
            )
        } else {
            ShareLink(
                title,
                item: Delimited(computeExportedText: computeExportedText),
                message: Text(""),
                preview: SharePreview("terms.csv")
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

/// Exports terms in the two-column format, one row per outgoing link.
///
/// The format predates terms and cannot express a term with several outgoing links as one record,
/// so a term with synonyms exports as several rows sharing a front. It cannot express an anchor
/// either, so an anchored link exports as its source's whole text against its target -- the anchor
/// is dropped, and a round trip loses it.
private func exportToText<S: Sequence>(
    _ terms: S,
    separator: Separator,
    format: Format,
    quoteValues: Bool,
    includeNotes: Bool
) -> String where S.Element == Term {
    let rows = terms.flatMap { term in
        (term.outgoingLinks ?? []).compactMap { link -> (Term, Link, Term)? in
            guard let target = link.target else { return nil }

            return (term, link, target)
        }
    }

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

        for (term, _, target) in rows {
            let fields = if includeNotes {
                [term.text, target.text, term.notes]
            } else {
                [term.text, target.text]
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
        let rowsAsJson = rows.map { (term, link, target) in
            [
                "front": term.text,
                "back": target.text,
                "notes": term.notes,
                "created": term.creationDate.ISO8601Format(),
                "nextReview": (link.progress?.nextReviewDate ?? term.creationDate).ISO8601Format(),
                "tags": term.tags?.map { tag in ["name": tag.name] } ?? [],
                "reviews": link.progress?.reviews?.map { review in
                    [
                        "date": review.date.ISO8601Format(),
                        "rating": review.outcome.description,
                    ]
                } ?? [],
            ]
        }
        let resultData = try! JSONSerialization.data(
            withJSONObject: rowsAsJson,
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
