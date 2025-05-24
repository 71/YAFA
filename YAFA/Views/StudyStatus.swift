import SwiftUI

struct StudyStatus: View {
    let flashcardsCount: Int
    @Binding var studyMode: StudyMode

    var body: some View {
        HStack {
            Spacer()

            Menu {
                CheckboxButton(
                    text: "Recall back", checked: studyMode.hasRecallBack
                ) { _ in
                    studyMode = studyMode.toggleRecallBack()
                }
                CheckboxButton(
                    text: "Recall front", checked: studyMode.hasRecallFront
                ) { _ in
                    studyMode = studyMode.toggleRecallFront()
                }
            } label: {
                Label("Preferences", systemImage: "slider.vertical.3")
            }
            .menuActionDismissBehavior(.disabled)

            NavigationLink {
                FlashcardsView()
            } label: {
                Label("Flashcards", systemImage: "list.bullet")
            }

            NavigationLink {
                PendingFlashcardEditor()
            } label: {
                Label("Add flashcard", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        }
    }
}

enum StudyMode: String, CaseIterable, Identifiable {
    case recallBack, recallFront, recallBothSides

    var id: Self { self }

    var hasRecallBack: Bool {
        switch self {
        case .recallBack, .recallBothSides: true
        default: false
        }
    }
    var hasRecallFront: Bool {
        switch self {
        case .recallFront, .recallBothSides: true
        default: false
        }
    }

    func toggleRecallBack() -> Self {
        switch self {
        case .recallBack, .recallBothSides: .recallFront
        case .recallFront: .recallBothSides
        }
    }
    func toggleRecallFront() -> Self {
        switch self {
        case .recallFront, .recallBothSides: .recallBack
        case .recallBack: .recallBothSides
        }
    }
}
