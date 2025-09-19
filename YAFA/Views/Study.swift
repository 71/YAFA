import Combine
import SwiftData
import SwiftUI

struct StudyView: View {
    @Binding var stateColor: Color
    @Binding var lastReviewUndoStates: [FlashcardReviewUndo]

    let flashcard: Flashcard?

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false

    /// A stream of answered flashcards.
    @State private var answeredSubject = PassthroughSubject<Flashcard, Never>()

    var body: some View {
        if let currentFlashcard = flashcard {
            StudyPrompt(
                currentFlashcard: currentFlashcard
            ) { outcome in
                withAnimation(.easeInOut) {
                    switch outcome {
                    case .ok: stateColor = RootView.stateColors.ok
                    case .fail: stateColor = RootView.stateColors.notOk
                    }
                    toggledOnAnswer.toggle()
                }
                withAnimation(.spring(duration: 0.15)) {
                    if lastReviewUndoStates.count == 10 {
                        lastReviewUndoStates.removeFirst()
                    }
                    lastReviewUndoStates.append(currentFlashcard.addReview(outcome: outcome))
                }
                answeredSubject.send(currentFlashcard)
            }
            .padding(.top, 32)
        } else {
            NoFlashcardView()
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
                NewFlashcardEditor(text: "", tags: [])
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
