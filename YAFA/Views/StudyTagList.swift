import Combine
import SwiftData
import SwiftUI
import WrappingHStack

struct StudyTagList: View {
    let allFlashcards: [Flashcard]
    let allTags: [FlashcardTag]
    let selectedTags: FlashcardTagsSelection
    let selectionChanged: () -> Void
    let onAnswered: AnyPublisher<Flashcard, Never>

    @State private var displayedTags: [FlashcardTag] = []
    @State private var displaySheet = false

    var body: some View {
        VStack(alignment: .leading) {
            WrappingHStack(alignment: .topLeading) {
                ProgressCapsule(text: "All", flashcards: allFlashcards, tag: nil, onAnswered: onAnswered)
                    .font(.headline)

                ForEach(displayedTags) { tag in
                    ProgressCapsule(
                        text: tag.name, flashcards: tag.flashcards ?? [], tag: tag, onAnswered: onAnswered)
                }
            }
            .onTapGesture {
                if !allTags.isEmpty {
                    displaySheet.toggle()
                }
            }
            .sheet(isPresented: $displaySheet) {
                StudyTagSelector(allTags: allTags, selectionChanged: selectionChanged)
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
}

private struct ProgressCapsule: View {
    let text: String
    let flashcards: [Flashcard]
    let tag: FlashcardTag?
    let onAnswered: AnyPublisher<Flashcard, Never>

    @State private var done: Int = 4
    @State private var total: Int = 10

    var body: some View {
        Text(text)
            .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            .background(progressGradient)
            .background(.thickMaterial)
            .background(Color.accentColor, in: Capsule())
            .onChange(of: flashcards, initial: true) {
                let now = Date.now

                total = flashcards.count
                done = flashcards.count { $0.isDoneForNow(now: now) }
            }
            .onReceive(onAnswered) { flashcard in
                guard let tag, flashcard.has(tag: tag) else { return }
                let now = Date.now

                done = flashcards.count { $0.isDoneForNow(now: now) }
            }
    }

    private var progressGradient: LinearGradient {
        let ratio = Double(done) / Double(total)

        return .init(
            stops: [
                .init(color: .accentColor, location: 0),
                .init(color: .accentColor, location: ratio),
                .init(color: .clear, location: ratio),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
    }
}

private struct StudyTagSelector: View {
    let allTags: [FlashcardTag]
    let selectionChanged: () -> Void

    @State private var currentSelection = FlashcardTag.Selection.all
    @Environment(\.modelContext) private var modelContext

    private var currentSelectionText: String {
        switch currentSelection {
        case .all:
            "all"
        case .any:
            "any"
        case .exclude:
            "none"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WrappingHStack(alignment: .leading, verticalSpacing: 2) {
                Text("Study flashcards with")

                Menu {
                    CheckboxButton(
                        text: "all", checked: currentSelection == .all
                    ) { _ in
                        currentSelection = .all
                    }
                    CheckboxButton(
                        text: "any", checked: currentSelection == .any
                    ) { _ in
                        currentSelection = .any
                    }
                    CheckboxButton(
                        text: "none", checked: currentSelection == .exclude
                    ) { _ in
                        currentSelection = .exclude
                    }
                } label: {
                    Text(currentSelectionText)
                        .padding(
                            EdgeInsets(
                                top: 4, leading: 8, bottom: 4, trailing: 8)
                        )
                        .background(
                            Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .foregroundStyle(.primary)

                Text("of the selected tags")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .font(.title2)
            .background(Color(UIColor.systemGroupedBackground))

            List {
                ForEach(allTags) { tag in
                    LabeledContent {
                        if let label = Self.selectionLabel(tag.selection) {
                            Text(label)
                                .padding(
                                    EdgeInsets(
                                        top: 6, leading: 10, bottom: 6,
                                        trailing: 10)
                                )
                                .background(
                                    .thinMaterial,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(.primary)
                        }
                    } label: {
                        Text(tag.name)
                    }
                    // Use a Rectangle to make the whole row tappable even when no trailing
                    // label is shown.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            tag.selection =
                                if tag.selection == currentSelection {
                                    nil
                                } else {
                                    currentSelection
                                }
                        }
                        selectionChanged()
                    }
                }
                .onDelete { tagIndices in
                    for tagIndex in tagIndices {
                        modelContext.delete(allTags[tagIndex])
                    }
                }
            }
        }
    }

    private static func selectionLabel(_ selection: FlashcardTag.Selection?)
        -> String?
    {
        switch selection {
        case .all:
            "All"
        case .any:
            "Any"
        case .exclude:
            "None"
        case nil:
            nil
        }
    }
}

#Preview {
    let modelContainer = previewModelContainer()
    let allTags = try! modelContainer.mainContext.fetch(FetchDescriptor<FlashcardTag>())

    StudyTagSelector(
        allTags: allTags, selectionChanged: {})
    .modelContainer(modelContainer)
}
