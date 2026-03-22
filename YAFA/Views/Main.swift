import Combine
import SwiftData
import SwiftUI

/// The main view shown at the root.
struct Main: View {
    @Binding var stateColor: Color
    @Bindable var navigationModel: NavigationModel

    @State private var searchText: String = ""
    @State private var searchTags: [FlashcardTag] = []

    @State private var searching: Bool = false
    @State private var showTags: Bool = false

    @State private var lastReviewUndoStates: [FlashcardReviewUndo] = []

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false
    @State private var focusedFlashcard: Flashcard? = nil

    @Query(sort: \Flashcard.nextReviewDate)
    private var allFlashcards: [Flashcard]
    @Query(sort: \FlashcardTag.name)
    private var tags: [FlashcardTag]

    /// Enqueued flashcards. As of 2025-10-18, it appears to be impossible to express a predicate like
    /// `flashcard.tags.contains { set.contains($0) }` (this somehow always evaluates to "true"),
    /// despite trying a few workarounds. Instead we must manually filter `allFlashcards`.
    @State private var queuedFlashcards: [Flashcard] = []

    var body: some View {
        ZStack {
            if searching {
                FlashcardsView(
                    focusedFlashcard: $focusedFlashcard,
                    searchText: searchText,
                    searchTags: searchTags
                )
                .safeAreaPadding(.bottom, 100) // Make some room for the search bar.
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
                .onChange(of: allFlashcards, initial: true) { updateFlashcards() }
                .onChange(of: tags) { updateFlashcards() }

                ForEach(tags) { tag in
                    EmptyView().onChange(of: tag.isStudying) { updateFlashcards() }
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
        .navigationDestination(for: Flashcard.self) { flashcard in
            FlashcardEditor(
                flashcard: flashcard,
                autoFocus: false
            )
        }
        .navigationDestination(for: NewFlashcard.self) { _ in
            NewFlashcardEditor(front: "", tags: [])
        }
        .onChange(of: navigationModel.searchParameters, initial: true) { (_, params) in
            guard let params else { return }

            searching = true
            searchText = params.search
            searchTags = params.tags

            navigationModel.searchParameters = nil
        }
    }

    private func updateFlashcards() {
        let studyingTags = Set(tags.filter(\.isStudying))

        withAnimation {
            queuedFlashcards = if studyingTags.isEmpty {
                allFlashcards
            } else {
                allFlashcards.filter { flashcard in flashcard.has(tagIn: studyingTags) }
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
