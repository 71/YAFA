import Combine
import SwiftData
import SwiftUI

struct StudyView: View {
    let height: CGFloat
    @Binding var stateColor: Color

    @Query(filter: Flashcard.nonEmptyPredicate, sort: \Flashcard.nextReviewDate)
    private var queuedFlashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]

    @AppStorage("left_handed") private var isLeftHanded = false

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false

    /// A stream of answered flashcards.
    @State private var answeredSubject = PassthroughSubject<Flashcard, Never>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StudyTagList(
                allFlashcards: queuedFlashcards, allTags: allTags,
                onAnswered: answeredSubject.eraseToAnyPublisher()
            )
            .padding(.top, 16)

            Spacer()

            if let currentFlashcard = firstSelectedFlashcard() {
                StudyPrompt(
                    currentFlashcard: currentFlashcard, cardHeight: height / 3,
                    isLeftHanded: isLeftHanded
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
    }

    private func firstSelectedFlashcard() -> Flashcard? {
        queuedFlashcards.first { $0.studyMode != nil }
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
                PendingFlashcardEditor(tag: nil)
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
