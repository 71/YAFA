import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    enum Format: Hashable {
        case delimited, json
    }

    enum Separator: Hashable {
        case comma, semicolon, tab, text
    }

    struct ParsedRow: Identifiable {
        let row: UInt
        let front: String
        let back: String
        let notes: String
        let conflictsWith: Flashcard?
        /// Everything a JSON entry carries beyond the text, when the row came from one.
        let restoring: ImportedFlashcard?

        init(
            row: UInt,
            front: String,
            back: String,
            notes: String,
            flashcards: [String: Flashcard],
            restoring: ImportedFlashcard? = nil
        ) {
            self.row = row
            self.front = front
            self.back = back
            self.notes = notes
            self.conflictsWith =
                flashcards[front.localizedLowercase] ?? flashcards[back.localizedLowercase]
            self.restoring = restoring
        }

        var id: UInt { row }
    }

    struct ErrorRow: Identifiable {
        let row: UInt
        let error: String

        var id: UInt { row }
    }

    let initialData: String

    @State var selectedTags: [FlashcardTag]

    @Environment(\.modelContext) private var modelContext
    @Query private var allFlashcards: [Flashcard]

    @State private var flashcardsByText: [String: Flashcard] = [:]
    @State private var data = ""

    @State private var format = Format.delimited
    @State private var separatorStyle = Separator.comma
    @State private var separatorText = ""
    @State private var separatorValidationError: String?
    @State private var detectQuotes = true

    @State private var parsedRows: [ParsedRow] = []
    @State private var errorRows: [ErrorRow] = []

    @State private var choosingFile = false
    @State private var fileError: String?

    var body: some View {
        Form {
            FormatSection()
            TagsSection()

            Section(header: Text("Data")) {
                Button("Choose file...", systemImage: "folder") { choosingFile = true }

                if let fileError {
                    Label(fileError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                }

                TextEditor(text: $data)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 180)
                    .monospaced()
            }

            RowsSections()
        }
        .navigationTitle("Import")
        // The file's contents are loaded into the editor rather than parsed straight away, so that
        // what was picked can be checked -- and corrected -- like anything typed in.
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: [.json, .commaSeparatedText, .tabSeparatedText, .delimitedText, .text]
        ) { result in
            load(result)
        }
        .toolbar {
            Button {
                save()

                data = ""  // Will reset rows.
            } label: {
                Text("Save")
            }
            .disabled(
                separatorValidationError != nil || !errorRows.isEmpty
                    || parsedRows.isEmpty
            )
        }
        .onChange(of: data) { parseRows() }
        .onChange(of: format) { parseRows() }
        .onChange(of: separatorStyle) { parseRows() }
        .onChange(of: separatorText) { parseRows() }
        .onChange(of: allFlashcards, initial: true) {
            flashcardsByText.removeAll(keepingCapacity: true)
            flashcardsByText.reserveCapacity(allFlashcards.count * 2)

            // Insert flashcards by `back` first to prioritize `front`s below in case of conflict.
            for flashcard in allFlashcards {
                flashcardsByText[flashcard.back.localizedLowercase] = flashcard
            }
            for flashcard in allFlashcards {
                flashcardsByText[flashcard.front.localizedLowercase] = flashcard
            }
        }

        .onAppear {
            if (data.isEmpty) { data = initialData }
        }
    }

    @ViewBuilder
    private func FormatSection() -> some View {
        Section(header: Text("Format")) {
            Picker("Format", selection: $format) {
                Text("Delimited").tag(Format.delimited)
                Text("JSON").tag(Format.json)
            }

            if format == .json {
                Text("Restores the dates, tags, and review history each entry carries.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if format == .delimited {
            Picker("Separator", selection: $separatorStyle) {
                Text("Comma").tag(Separator.comma)
                Text("Semicolon").tag(Separator.semicolon)
                Text("Tab").tag(Separator.tab)
                Divider()
                Text("Custom").tag(Separator.text)
            }

            if separatorStyle == .text {
                TextField("Custom separator", text: $separatorText)
            }

            if let separatorValidationError {
                Label(
                    separatorValidationError,
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.yellow)
            }

            Toggle(isOn: $detectQuotes) {
                Text("Detect quotes")
            }
            }
        }
    }

    /// Reads a picked file into the editor, choosing the format from its type.
    private func load(_ result: Result<URL, any Error>) {
        fileError = nil

        do {
            let url = try result.get()

            // A file outside the app's own storage has to be opened for access explicitly.
            let scoped = url.startAccessingSecurityScopedResource()

            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            if url.pathExtension.lowercased() == "json" {
                format = .json
            } else {
                format = .delimited

                if url.pathExtension.lowercased() == "tsv" {
                    separatorStyle = .tab
                }
            }

            data = try String(contentsOf: url, encoding: .utf8)
        } catch {
            fileError = error.localizedDescription
        }
    }

    /// Inserts the parsed rows.
    ///
    /// A row from a JSON export is *restored* -- its dates and review history are written back as
    /// they were -- while one from a delimited file is a new flashcard, since that format carries
    /// nothing else.
    private func save() {
        var tagsByName = [String: FlashcardTag]()

        for tag in try! modelContext.fetch(FetchDescriptor<FlashcardTag>()) {
            tagsByName[tag.name] = tag
        }

        for parsedRow in parsedRows {
            guard let restoring = parsedRow.restoring else {
                modelContext.insert(
                    Flashcard(
                        front: parsedRow.front,
                        back: parsedRow.back,
                        notes: parsedRow.notes,
                        tags: selectedTags
                    )
                )
                continue
            }

            // Tags are matched by name, and created when the backup names one which is gone.
            let tags = selectedTags + restoring.tags.map { name in
                if let existing = tagsByName[name] { return existing }

                let tag = FlashcardTag(name: name)

                modelContext.insert(tag)
                tagsByName[name] = tag

                return tag
            }

            modelContext.insert(
                Flashcard.restored(
                    front: restoring.front,
                    back: restoring.back,
                    notes: restoring.notes,
                    creationDate: restoring.creationDate,
                    nextReviewDate: restoring.nextReviewDate,
                    reviews: restoring.reviews,
                    tags: tags.removingDuplicates()
                )
            )
        }
    }

    private func TagsSection() -> some View {
        Section(header: Text("Tags")) {
            TagSelectionList(
                selectedTags: selectedTags,
                addTag: { selectedTags.append($0) },
                removeTags: { selectedTags.remove(atOffsets: $0) }
            )
        }
    }

    @ViewBuilder
    private func RowsSections() -> some View {
        if !errorRows.isEmpty {
            Section(header: Text("Errors")) {
                let formatRow = numberFormatter(for: errorRows.map { $0.id })

                ForEach(errorRows) { row in
                    HStack {
                        Text(formatRow(row.row)).monospacedDigit()

                        VStack(alignment: .leading) {
                            Text(row.error)
                        }
                    }
                }
            }
        }

        if !parsedRows.isEmpty {
            Section(header: Text("Parsed")) {
                let formatRow = numberFormatter(for: parsedRows.map { $0.id })

                ForEach(parsedRows) { row in
                    HStack {
                        Text(formatRow(row.row)).monospacedDigit()

                        VStack(alignment: .leading) {
                            if !row.front.isEmpty {
                                Text(row.front)
                            } else {
                                Text("No front").foregroundStyle(.secondary)
                            }

                            if !row.back.isEmpty {
                                Text(row.back)
                            } else {
                                Text("No back").foregroundStyle(.secondary)
                            }

                            if !row.notes.isEmpty {
                                Text(row.notes).font(.subheadline)
                            }

                            // What a restore brings back beyond the text, so it is clear the
                            // scheduling is being kept rather than reset.
                            if let restoring = row.restoring {
                                Text(restoreSummary(of: restoring))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 12)

                        if let flashcard = row.conflictsWith {
                            Spacer()

                            NavigationLink(value: flashcard) {
                                Image(systemName: "exclamationmark.triangle")
                            }
                            .frame(width: 32)  // Make sure that we let the `Spacer()` do its job.
                            // `width: 0` results in a small arrow, so we give it more room.
                        }
                    }
                }
                .onDelete { (indices) in
                    parsedRows.remove(atOffsets: indices)
                }
            }
        }
    }

    private func parseRows() {
        parsedRows = []
        errorRows = []
        separatorValidationError = nil

        if format == .json {
            parseJson()
            return
        }

        switch separatorStyle {
        case .comma: parseLines(separatedBy: ",")
        case .semicolon: parseLines(separatedBy: ";")
        case .tab: parseLines(separatedBy: "\t")
        case .text:
            if separatorText.count != 1 {
                separatorValidationError =
                    String(localized: "Separator text must contain exactly one character.")
                return
            }

            parseLines(separatedBy: separatorText.first!)
        }
    }

    private func restoreSummary(of imported: ImportedFlashcard) -> String {
        var parts = [String]()

        if !imported.reviews.isEmpty {
            parts.append(String(localized: "\(imported.reviews.count) reviews"))
        }
        if !imported.tags.isEmpty {
            parts.append(imported.tags.joined(separator: ", "))
        }

        parts.append(
            String(
                localized: "due \(imported.nextReviewDate.formatted(date: .abbreviated, time: .omitted))"
            )
        )

        return parts.joined(separator: " · ")
    }

    private func parseJson() {
        let text = data.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return }

        do {
            for (index, imported) in try parseJsonFlashcards(text).enumerated() {
                parsedRows.append(
                    .init(
                        row: UInt(index + 1),
                        front: imported.front,
                        back: imported.back,
                        notes: imported.notes,
                        flashcards: flashcardsByText,
                        restoring: imported
                    )
                )
            }
        } catch {
            errorRows.append(.init(row: 1, error: error.localizedDescription))
        }
    }

    private func parseLines(separatedBy: Character) {
        var row: UInt = 1

        if !detectQuotes {
            data.enumerateLines { (line, _) in
                let fields = line.split(separator: separatedBy)

                if line.isEmpty {
                    // Skip.
                } else if fields.count < 2 {
                    errorRows.append(
                        .init(row: row, error: String(localized: "Missing definition"))
                    )
                } else if fields.count > 3 {
                    errorRows.append(.init(row: row, error: String(localized: "2 or 3 values were expected")))
                } else {
                    let front = String(fields[0])
                    let back = String(fields[1])
                    let notes = fields.count == 3 ? String(fields[2]) : ""

                    parsedRows.append(
                        .init(
                            row: row,
                            front: front,
                            back: back,
                            notes: notes,
                            flashcards: flashcardsByText
                        )
                    )
                }
                row += 1
            }
            return
        }

        var firstField: String?
        var secondField: String?
        var currentField = ""
        var chars = data.makeIterator()

        let addErrorAndRecover = { error in
            while let char = chars.next(), char != "\n" {
                // Keep skipping.
            }
            // Add error.
            errorRows.append(.init(row: row, error: error))
            // Update state.
            row += 1
            firstField = nil
            secondField = nil
            currentField = ""
        }
        let finishRecord = {
            if let firstField {
                let (back, notes) =
                    if let secondField {
                        (secondField, currentField)
                    } else {
                        (currentField, "")
                    }
                parsedRows.append(
                    .init(
                        row: row,
                        front: firstField,
                        back: back,
                        notes: notes,
                        flashcards: flashcardsByText
                    )
                )
            } else if currentField.isEmpty {
                // Ignore empty line.
            } else {
                errorRows.append(.init(row: row, error: String(localized: "Missing definition")))
            }
            row += 1
            firstField = nil
            secondField = nil
            currentField = ""
        }
        let finishField = {
            if firstField == nil {
                firstField = currentField
            } else if secondField == nil {
                secondField = currentField
            } else {
                addErrorAndRecover(String(localized: "2 or 3 values were expected"))
            }
            currentField = ""
        }

        while let char = chars.next() {
            switch char {
            case "\n":
                finishRecord()
            case "\r":
                continue

            case "\"":
                // Handle quote.
                if !currentField.isEmpty {
                    addErrorAndRecover(
                        String(localized: "Quote can only appear at start of field")
                    )
                    continue
                }

                // Parse quoted string.
                while let char = chars.next() {
                    if char != "\"" {
                        currentField.append(char)
                        continue
                    }

                    switch chars.next() {
                    case "\"":
                        currentField.append("\"")
                    case "\n", nil:
                        finishRecord()
                    case separatedBy:
                        finishField()
                    default:
                        addErrorAndRecover(
                            String(localized: "Quote must be followed by separator or end of line")
                        )
                    }
                    break
                }

            case separatedBy:
                finishField()
            case let char:
                currentField.append(char)
            }
        }

        finishRecord()
    }
}

private func numberFormatter(for numbers: [UInt]) -> (UInt) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.minimumIntegerDigits = "\(numbers.max()!)".count
    return {
        numberFormatter.string(from: NSNumber(value: $0))!
    }
}

#Preview {
    NavigationStack {
        ImportView(initialData: "", selectedTags: [])
    }
    .modelContainer(previewModelContainer())
}

extension Array where Element: AnyObject & Identifiable {
    /// Drops repeats, keeping the first of each. A tag named in the backup may also be selected in
    /// the form above, and a flashcard should not carry it twice.
    fileprivate func removingDuplicates() -> Self {
        var seen = Set<Element.ID>()

        return filter { seen.insert($0.id).inserted }
    }
}
