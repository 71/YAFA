import Combine
import SwiftData
import SwiftUI

/// The main view shown at the root.
struct Main: View {
    @Binding var stateColor: Color

    @State private var searchText: String = ""
    @State private var searchTags: [FlashcardTag] = []

    @State private var searching: Bool = false
    @State private var showTags: Bool = false

    @State private var lastReviewUndoStates: [FlashcardReviewUndo] = []

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false
    @State private var focusedFlashcard: Flashcard? = nil

    @Query(filter: Flashcard.nonEmptyPredicate, sort: \Flashcard.nextReviewDate)
    private var queuedFlashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name)
    private var tags: [FlashcardTag]

    var body: some View {
        ZStack {
            if searching {
                FlashcardsView(
                    focusedFlashcard: $focusedFlashcard,
                    searchText: searchText,
                    searchTags: searchTags
                )
                .safeAreaPadding(.bottom, 44)
            } else {
                VStack {
                    DueFlashcardsHeader(
                        showTags: $showTags,
                        flashcards: queuedFlashcards,
                        tags: tags
                    )

                    if showTags {
                        Tags(searchTags: $searchTags, tags: tags)
                            .onChange(of: searchTags) {
                                if !searchTags.isEmpty {
                                    searching = true
                                }
                            }
                    } else {
                        StudyView(
                            stateColor: $stateColor,
                            lastReviewUndoStates: $lastReviewUndoStates,
                            flashcard: queuedFlashcards.first
                        )
                    }
                }
                .padding(.bottom, 68)
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

            VStack {
                Spacer()

                SearchBar(
                    searchText: $searchText,
                    searchTags: $searchTags,
                    searching: $searching,
                    outsideFocus: focusedFlashcard != nil,
                    flashcards: queuedFlashcards,
                    tags: tags,
                    undo: undo
                )
            }
        }
    }

    private var undo: (() -> Void)? {
        guard let undoState = lastReviewUndoStates.last else { return nil }

        return {
            undoState.undo()

            withAnimation(.spring(duration: 0.15)) {
                _ = lastReviewUndoStates.popLast()
            }
        }
    }
}
