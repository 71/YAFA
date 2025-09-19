import SwiftUI

/// The header showing due flashcards / tags in the study view.
struct DueFlashcardsHeader: View {
    @Binding var showTags: Bool

    let flashcards: [Flashcard]
    let tags: [FlashcardTag]

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showTags.toggle() }
        } label: {
            HStack {
                DueFlashcardsText(flashcards: flashcards, tags: tags)

                Spacer()

                ToggleButton(
                    label: Label("Edit tags", systemImage: "ellipsis")
                        .padding(16)
                        .frame(width: 32, height: 32)
                        .labelStyle(.iconOnly),
                    shape: Circle(),
                    on: showTags
                ) { showTags = $0 }
            }
        }
        .tint(.primary)
    }
}

private struct DueFlashcardsText: View {
    let flashcards: [Flashcard]
    let tags: [FlashcardTag]

    @State private var text = AttributedString()
    @State private var currentDate = Date.now
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var nextDueString: String?
    @State private var dueFlashcards: Int = 0
    @State private var selectedTags: Int = 0

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .contentTransition(.numericText())
            .onAppear { updateState() }
            .onChange(of: flashcards.first) {
                currentDate = .now
                updateState()
            }
            .onReceive(timer) {
                currentDate = $0
                updateState()
            }
    }

    private func updateState() {
        withAnimation {
            text = computeText()
            dueFlashcards = flashcards.count { !$0.isDoneForNow(now: currentDate) }
            selectedTags = tags.count { $0.isStudying }

            nextDueString = flashcards.first.map {
                let dateFormatter = RelativeDateTimeFormatter()
                dateFormatter.dateTimeStyle = .numeric
                dateFormatter.unitsStyle = .short
                return dateFormatter.localizedString(for: $0.nextReviewDate, relativeTo: currentDate)
            }
        }
    }

    private func computeText() -> AttributedString {
        var text: AttributedString = .init()

        let dueFlashcards = flashcards.count { !$0.isDoneForNow(now: currentDate) }

        switch dueFlashcards {
        case 0:
            if let first = flashcards.first {
                let dateFormatter = RelativeDateTimeFormatter()
                dateFormatter.dateTimeStyle = .numeric
                dateFormatter.unitsStyle = .short
                let dueDate =
                    dateFormatter.localizedString(for: first.nextReviewDate, relativeTo: currentDate)

                text.append(secondaryAttributedString("Next flashcard due in "))
                text.append(primaryAttributedString(dueDate))
            } else {
                text.append(secondaryAttributedString("No flashcard due"))
            }
        case 1:
            text.append(primaryAttributedString("1"))
            text.append(secondaryAttributedString(" flashcard due"))
        case let n:
            text.append(primaryAttributedString("\(n)"))
            text.append(secondaryAttributedString(" flashcards due"))
        }

        let selectedTags = tags.count { $0.isStudying }

        switch selectedTags {
        case 0:
            break
        case 1:
            text.append(secondaryAttributedString(" with "))
            text.append(primaryAttributedString("1"))
            text.append(secondaryAttributedString(" tag"))
        case let n:
            text.append(secondaryAttributedString(" with "))
            text.append(primaryAttributedString("\(n)"))
            text.append(secondaryAttributedString(" tags"))
        }

        return text
    }
}

private func primaryAttributedString(_ text: some StringProtocol) -> AttributedString {
    var s = AttributedString(text)
    s.foregroundColor = .primary
    s.font = .body.weight(.bold)
    return s
}

private func secondaryAttributedString(_ text: some StringProtocol) -> AttributedString {
    var s = AttributedString(text)
    s.foregroundColor = .secondary
    s.font = .body.weight(.semibold)
    return s
}
