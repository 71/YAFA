import Combine
import SwiftData
import SwiftUI

struct StudyView: View {
    let height: CGFloat
    @Binding var stateColor: Color

    @Query(sort: \Flashcard.nextReviewDate) private var queuedFlashcards:
        [Flashcard]
    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var selectedTags: FlashcardTagsSelection = .init()

    @AppStorage("left_handed") private var isLeftHanded = false
    @AppStorage("study_mode") private var studyModeStr: String = ""

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false

    /// A stream of answered flashcards.
    @State private var answeredSubject = PassthroughSubject<Flashcard, Never>()

    private var studyMode: Binding<StudyMode> {
        Binding {
            .init(rawValue: studyModeStr) ?? .recallFront
        } set: {
            studyModeStr = $0.rawValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StudyTagList(
                allFlashcards: queuedFlashcards, allTags: allTags,
                selectedTags: selectedTags,
                selectionChanged: { selectedTags = .init(allTags: allTags) },
                onAnswered: answeredSubject.eraseToAnyPublisher()
            )
            .padding(.top, 16)

            Spacer()

            if let currentFlashcard = firstSelectedFlashcard() {
                StudyPrompt(
                    currentFlashcard: currentFlashcard, cardHeight: height / 3,
                    isLeftHanded: isLeftHanded,
                    studyMode: studyMode.wrappedValue
                ) { outcome in
                    withAnimation(.easeInOut) {
                        switch outcome {
                        case .ok: stateColor = RootView.stateColors.ok
                        case .fail: stateColor = RootView.stateColors.notOk
                        }
                        toggledOnAnswer.toggle()
                    }
                    answeredSubject.send(currentFlashcard)
                }
            } else {
                NoFlashcardView()
            }
        }
        .navigationTitle("Study")
        .toolbar {
            StudyStatus(
                flashcardsCount: queuedFlashcards.count, studyMode: studyMode)
        }
        .padding(.horizontal, 16)
        .phaseAnimator([1, 1.5, 1], trigger: toggledOnAnswer) { view, phase in
            view
                .background {
                    LinearGradient(
                        colors: [
                            .accentColor.opacity(0.25 * phase),
                            .init(uiColor: .systemBackground),
                        ],
                        startPoint: .init(x: 0, y: 0),
                        endPoint: .init(x: 0, y: 0.6 * phase)
                    )
                    .ignoresSafeArea()
                }
        }
        .onChange(of: allTags, initial: true) {
            selectedTags = .init(allTags: allTags)
        }
    }

    private func firstSelectedFlashcard() -> Flashcard? {
        return queuedFlashcards.first { flashcard in
            selectedTags.contains(flashcard)
        }
    }
}

private struct NoFlashcardView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("No flashcard due.")
            Spacer()
        }

        Spacer()

        HStack {
            Spacer()

            NavigationLink {
                PendingFlashcardEditor()
            } label: {
                Label("Add flashcard", systemImage: "plus")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(.bordered)

            Spacer()
        }

        Spacer()
    }
}
