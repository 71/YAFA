import SwiftData
import SwiftUI

struct Tags: View {
    @Binding var searchTags: [FlashcardTag]

    let tags: [FlashcardTag]

    var body: some View {
        List {
            ForEach(tags) { tag in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Tag", text: bindToProperty(of: tag, \.name))
                            .font(.headline)

                        Text(caption(of: tag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ToggleButton(
                        label: Text("B")
                            .font(.headline.bold())
                            .frame(width: 32, height: 32),
                        shape: RoundedRectangle(cornerRadius: 4),
                        on: tag.studyMode?.hasRecallBack ?? false
                    ) { _ in
                        tag.studyMode =
                            switch tag.studyMode {
                            case nil: .recallBack
                            case .recallBack: nil
                            case .recallFront: .recallBothSides
                            case .recallBothSides: .recallFront
                            }
                    }
                    .buttonStyle(.plain) // https://stackoverflow.com/a/59402642

                    ToggleButton(
                        label: Text("F")
                            .font(.headline.bold())
                            .frame(width: 32, height: 32),
                        shape: RoundedRectangle(cornerRadius: 4),
                        on: tag.studyMode?.hasRecallFront ?? false
                    ) { _ in
                        tag.studyMode =
                            switch tag.studyMode {
                            case nil: .recallFront
                            case .recallFront: nil
                            case .recallBack: .recallBothSides
                            case .recallBothSides: .recallBack
                            }
                    }
                    .buttonStyle(.plain) // https://stackoverflow.com/a/59402642

                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                }
                .contextMenu {
                    Button("Delete tag", systemImage: "trash", role: .destructive) {
                        tag.modelContext?.delete(tag)
                    }
                    .tint(.red)
                }
                .onTapGesture {
                    searchTags = [tag]
                }
            }
            .onDelete { indices in
                for index in indices.reversed() {
                    let tag = tags[index]

                    tag.modelContext?.delete(tag)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .padding(.top, 16)
    }
}

private func caption(of tag: FlashcardTag) -> String {
    let studyMode = switch tag.studyMode {
    case nil: ""
    case .recallBack: ", studying back"
    case .recallFront: ", studying front"
    case .recallBothSides: ", studying" // "both sides" leads to overflow
    }

    guard let flashcards = tag.flashcards, !flashcards.isEmpty else {
        return "No flashcard\(studyMode)"
    }

    let now = Date.now
    let dueFlashcards = flashcards.count { !$0.isDoneForNow(now: now) }
    let s = flashcards.count == 1 ? "" : "s"

    return if dueFlashcards == 0 {
        "\(flashcards.count) flashcard\(s)\(studyMode)"
    } else {
        "\(dueFlashcards)/\(flashcards.count) due flashcard\(s)\(studyMode)"
    }
}
