import SwiftData
import SwiftUI

struct ImportView: View {
    enum Separator: Hashable {
        case comma, semicolon, tab, text
    }

    struct ParsedRow: Identifiable {
        let row: UInt
        let front: String
        let back: String
        let conflictsWith: Flashcard?

        init(row: UInt, front: String, back: String, flashcards: [String: Flashcard]) {
            self.row = row
            self.front = front
            self.back = back
            self.conflictsWith =
                flashcards[front.localizedLowercase] ?? flashcards[back.localizedLowercase]
        }

        var id: UInt { row }
    }

    struct ErrorRow: Identifiable {
        let row: UInt
        let error: String

        var id: UInt { row }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var allFlashcards: [Flashcard]

    @State private var flashcardsByText: [String: Flashcard] = [:]
    @State private var data = ""

    @State private var separatorStyle = Separator.comma
    @State private var separatorText = ""
    @State private var separatorValidationError: String?
    @State private var detectQuotes = true

    @State private var selectedTags: [FlashcardTag] = []

    @State private var parsedRows: [ParsedRow] = []
    @State private var errorRows: [ErrorRow] = []

    var body: some View {
        Form {
            FormatSection()
            TagsSection()

            Section(header: Text("Data")) {
                TextEditor(text: $data)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 180)
                    .monospaced()
            }

            RowsSections()
        }
        .navigationTitle("Import")
        .toolbar {
            Button {
                for parsedRow in parsedRows {
                    let flashcard = Flashcard(
                        front: parsedRow.front, back: parsedRow.back, tags: selectedTags)

                    modelContext.insert(flashcard)
                }

                data = ""  // Will reset rows.
            } label: {
                Text("Save")
            }
            .disabled(
                separatorValidationError != nil || !errorRows.isEmpty
                    || parsedRows.isEmpty)
        }
        .onChange(of: data) { parseRows() }
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
    }

    private func FormatSection() -> some View {
        Section(header: Text("Format")) {
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

    private func TagsSection() -> some View {
        Section(header: Text("Tags")) {
            TagSelectionList(
                selectedTags: selectedTags,
                addTag: { selectedTags.append($0) },
                removeTags: { selectedTags.remove(atOffsets: $0) })
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
                            Text(row.front)
                            Text(row.back)
                        }
                        .padding(.leading, 12)

                        if let flashcard = row.conflictsWith {
                            Spacer()

                            NavigationLink {
                                FlashcardEditor(flashcard: flashcard, autoFocus: false)
                            } label: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                            .frame(width: 32) // Make sure that we let the `Spacer()` do its job.
                                              // `width: 0` results in a small arrow, so we give it
                                              // more room.
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

        switch separatorStyle {
        case .comma: parseLines(separatedBy: ",")
        case .semicolon: parseLines(separatedBy: ";")
        case .tab: parseLines(separatedBy: "\t")
        case .text:
            if separatorText.count != 1 {
                separatorValidationError =
                    "Separator text must contain exactly one character."
                return
            }

            parseLines(separatedBy: separatorText.first!)
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
                        .init(row: row, error: "Not enough values"))
                } else if fields.count > 2 {
                    errorRows.append(.init(row: row, error: "Too many values"))
                } else {
                    let front = String(fields[0])
                    let back = String(fields[1])

                    parsedRows.append(
                        .init(row: row, front: front, back: back, flashcards: flashcardsByText))
                }
                row += 1
            }
            return
        }

        var firstField: String?
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
            currentField = ""
        }
        let finishRecord = {
            if let firstField {
                parsedRows.append(
                    .init(row: row, front: firstField, back: currentField, flashcards: flashcardsByText))
            } else if currentField.isEmpty {
                // Ignore empty line.
            } else {
                errorRows.append(.init(row: row, error: "Missing definition"))
            }
            row += 1
            firstField = nil
            currentField = ""
        }
        let finishField = {
            if firstField != nil {
                addErrorAndRecover("Two values were expected")
            } else {
                firstField = currentField
                currentField = ""
            }
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
                        "Quote can only appear at start of field")
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
                            "Quote must be followed by separator or end of line"
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
        ImportView()
    }
    .modelContainer(previewModelContainer())
}
