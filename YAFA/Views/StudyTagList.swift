import Combine
import SwiftData
import SwiftUI
import WrappingHStack

// Collpased height of the tag sheet. Chosen to display "New card" fully without any card
// below it (to avoid giving answers away).
private let tagSheetHeight = PresentationDetent.height(240)

struct StudyTagList: View {
    let allFlashcards: [Flashcard]
    let allTags: [FlashcardTag]
    let selectedTags: FlashcardTagsSelection
    let selectionChanged: () -> Void
    let onAnswered: AnyPublisher<Flashcard, Never>

    @State private var displayedTags: [FlashcardTag] = []
    @State public var sheetTag: FlashcardTag?
    @State private var explicitlyExpandTags = false
    @State private var tagSheetDedent = tagSheetHeight

    var body: some View {
        VStack(alignment: .leading) {
            WrappingHStack(alignment: .topLeading) {
                NavigationLink {
                    FlashcardsView()
                } label: {
                    ProgressCapsule(text: "All", flashcards: allFlashcards, tag: nil, onAnswered: onAnswered, expand: expandTags)
                }
                .foregroundStyle(.primary)

                ForEach(displayedTags) { tag in
                    ProgressCapsule(
                        text: tag.name, flashcards: tag.committedFlashcards, tag: tag, onAnswered: onAnswered, expand: expandTags)
                    .onTapGesture {
                        sheetTag = tag
                    }
                }

                if !implicitlyExpandTags {
                    Button("Expand", systemImage: "chevron.down") {
                        withAnimation {
                            explicitlyExpandTags.toggle()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .rotationEffect(expandTags ? .degrees(180) : .zero)
                    .tagLike()
                }

                NavigationLink {
                    PendingFlashcardEditor()
                } label: {
                    Label("Add flashcard", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .tagLike()
                }
                .foregroundStyle(.primary)
            }
            .sheet(item: $sheetTag) { tag in
                NavigationView {
                    TagSheet(tag: tag, close: { sheetTag = nil })
                }
                .presentationDetents([tagSheetHeight, .large], selection: $tagSheetDedent)
                .presentationBackgroundInteraction(.enabled)
                .presentationCompactAdaptation(.none)
                .presentationBackground(.thickMaterial)
            }

            Spacer()
        }
        .onChange(of: selectedTags, initial: true) {
            if selectedTags.all.isEmpty && selectedTags.any.isEmpty {
                // If we don't include only specific tags, then we display all tags (except
                // explicitly excluded ones).
                if selectedTags.exclude.isEmpty {
                    displayedTags = allTags
                } else {
                    let excludedTags = Set(selectedTags.exclude)

                    displayedTags = allTags.filter {
                        !excludedTags.contains($0)
                    }
                }
            } else {
                // If we include specific tags, we display all of them. Note that include
                // sets cannot overlap with the exclude set, so we don't need to filter out
                // tags in `exclude` here.
                displayedTags = [selectedTags.all, selectedTags.any].joined()
                    .sorted(by: { $0.name < $1.name })
            }
        }
    }

    private var implicitlyExpandTags: Bool {
        displayedTags.count <= 1
    }

    private var expandTags: Bool {
        explicitlyExpandTags || implicitlyExpandTags
    }
}

private struct ProgressCapsule: View {
    let text: String
    let flashcards: [Flashcard]
    let tag: FlashcardTag?
    let onAnswered: AnyPublisher<Flashcard, Never>
    let expand: Bool

    @State private var done: Int = 4
    @State private var total: Int = 10
    @State private var leftCardsText: String?

    var body: some View {
        HStack {
            Text(text)

            if expand {
                Group {
                    if let leftCards = leftCardsText {
                        Text("•")
                        Text(leftCards)
                            .transition(.push(from: .bottom))
                            .id("left-cards-\(text)")
                    } else {
                        Text("✓")
                    }
                }
                .transition(.push(from: .bottom))
            }
        }
        .bold(tag == nil)
        .tagLike()
        .onChange(of: flashcards, initial: true) {
            let now = Date.now

            total = flashcards.count
            done = flashcards.count { $0.isDoneForNow(now: now) }
            updateLeftCardsText()
        }
        .onReceive(onAnswered) { flashcard in
            guard let tag, flashcard.has(tag: tag) else { return }
            let now = Date.now

            done = flashcards.count { $0.isDoneForNow(now: now) }
            updateLeftCardsText()
        }
    }

    private func updateLeftCardsText() {
        let left = total - done
        let leftText: String? =
            if left == 0 { nil }
            else if left > 99 { "99+" }
            else { "\(left)" }

        withAnimation {
            leftCardsText = leftText
        }
    }
}

private struct TagSheet: View {
    let tag: FlashcardTag
    let close: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(tag.name)
                        .font(.title)
                        .bold()

                    Text(progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close", systemImage: "xmark") {
                    close()
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: Circle())
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            HStack {
                HStack(spacing: 0) {
                    Button("Study back") {
                        tag.studyMode = switch tag.studyMode {
                        case nil: .recallBack
                        case .recallBack: nil
                        case .recallFront: .recallBothSides
                        case .recallBothSides: .recallFront
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(studyModeButtonBackground(selectIf: .recallBack))
                    .foregroundStyle(studyModeButtonForeground(selectIf: .recallBack))

                    Button("Study front") {
                        tag.studyMode = switch tag.studyMode {
                        case nil: .recallFront
                        case .recallFront: nil
                        case .recallBack: .recallBothSides
                        case .recallBothSides: .recallBack
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(studyModeButtonBackground(selectIf: .recallFront))
                    .foregroundStyle(studyModeButtonForeground(selectIf: .recallFront))
                }
                .clipShape(.rect(cornerRadius: 8))

                Spacer()

                Button("Delete", systemImage: "trash") {
                    modelContext.delete(tag)
                    close()
                }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 8))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)

            TagFlashcardsView(tag: tag)

            Spacer()
        }
        .ignoresSafeArea()
    }

    private var progressText: String {
        let flashcards = tag.committedFlashcards

        guard !flashcards.isEmpty else { return "No flashcards" }

        let now = Date.now
        let doneFlashcards = flashcards.count { $0.isDoneForNow(now: now) }
        let dueFlashcards = flashcards.count - doneFlashcards
        let s = { (v: Int) in v == 1 ? "" : "s" }

        guard dueFlashcards > 0 else {
            return "\(flashcards.count) flashcard\(s(flashcards.count))"
        }

        return "\(dueFlashcards)/\(flashcards.count) flashcard\(s(dueFlashcards)) due"
    }

    private func studyModeButtonForeground(selectIf mode: StudyMode) -> Color {
        if tag.studyMode == mode || tag.studyMode == .recallBothSides {
            Color(.systemBackground)
        } else {
            Color(.label)
        }
    }

    private func studyModeButtonBackground(selectIf mode: StudyMode) -> Color {
        if tag.studyMode == mode || tag.studyMode == .recallBothSides {
            Color(.label)
        } else {
            Color(.tertiarySystemBackground)
        }
    }
}

private extension View {
    func tagLike() -> some View {
        self
            .frame(height: 44)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Tag sheet") {
    let modelContainer = previewModelContainer()
    let allFlashcards = try! modelContainer.mainContext.fetch(FetchDescriptor<Flashcard>())
    let allTags = try! modelContainer.mainContext.fetch(FetchDescriptor<FlashcardTag>())
    let onAnswered = PassthroughSubject<Flashcard, Never>()

    StudyTagList(allFlashcards: allFlashcards, allTags: allTags, selectedTags: .init(), selectionChanged: {}, onAnswered: onAnswered.eraseToAnyPublisher(), sheetTag: allTags[0])
        .modelContainer(modelContainer)
}
