import Combine
import SwiftData
import SwiftUI

/// The main view shown at the root.
struct Main: View {
    @Binding var stateColor: Color
    @Bindable var navigationModel: NavigationModel

    @State private var searchText: String = ""
    @State private var searchTags: [Tag] = []
    @State private var searchUntagged: Bool = false

    @State private var searching: Bool = false
    @State private var showTags: Bool = false

    @State private var lastReviewUndoStates: [ReviewUndo] = []

    @State private var focusedTerm: Term? = nil

    @Query(sort: \Progress.nextReviewDate)
    private var allProgresses: [Progress]
    @Query(sort: \Tag.name)
    private var tags: [Tag]

    /// Enqueued progresses. As of 2025-10-18, it appears to be impossible to express a predicate
    /// like `term.tags.contains { set.contains($0) }` (this somehow always evaluates to "true"),
    /// despite trying a few workarounds. Instead we must manually filter `allProgresses`.
    @State private var queuedProgresses: [Progress] = []

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false

    var body: some View {
        ZStack {
            if searching {
                TermsView(
                    focusedTerm: $focusedTerm,
                    searchText: searchText,
                    searchTags: searchTags,
                    searchUntagged: searchUntagged,
                    close: stopSearching
                )
                .safeAreaPadding(.bottom, 100)  // Make some room for the search bar.
            } else {
                VStack {
                    DueReviewsHeader(
                        showTags: $showTags,
                        progresses: queuedProgresses,
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
                            progress: queuedProgresses.first
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
                                    .accentColor.opacity(0.45),
                                    .accentColor.opacity(0.25 * phase),
                                    .init(uiColor: .systemBackground),
                                ],
                                startPoint: .init(x: 0.8, y: 0),
                                endPoint: .init(x: 0.2, y: 0.75 * phase)
                            )
                            .ignoresSafeArea()
                        }
                }
                .onChange(of: allProgresses, initial: true) { updateQueue() }
                .onChange(of: tags) { updateQueue() }

                ForEach(tags) { tag in
                    EmptyView().onChange(of: tag.isStudying) { updateQueue() }
                }
            }

            VStack {
                Spacer()

                SearchBar(
                    searchText: $searchText,
                    searchTags: $searchTags,
                    searchUntagged: $searchUntagged,
                    searching: $searching,
                    focusedTerm: focusedTerm,
                    tags: tags,
                    undo: undo
                )
            }
        }
        .navigationDestination(for: NewTerm.self) { _ in
            NewTermEditor(text: "", tags: [])
        }
        .onChange(of: navigationModel.searchParameters, initial: true) { (_, params) in
            guard let params else { return }

            searching = true
            searchText = params.search
            searchTags = params.tags

            navigationModel.searchParameters = nil
        }
    }

    /// Leaves the search, clearing what was being searched for.
    ///
    /// Shared by the term list's toolbar and the search bar so that closing from either does the
    /// same thing.
    private func stopSearching() {
        // The search field or a focused term row may still hold the keyboard, and leaving it up
        // over a screen which is no longer being searched reads as though the tap did nothing.
        dismissKeyboard()

        searching = false
        searchText = ""
        searchTags = []
        searchUntagged = false
    }

    private func updateQueue() {
        let studyingTags = Set(tags.filter(\.isStudying))

        withAnimation {
            queuedProgresses = allProgresses.filter { progress in
                let sharers = progress.sharers

                // A progress whose link and blanks were all deleted is not studiable at all.
                guard !sharers.isEmpty else { return false }
                guard !studyingTags.isEmpty else { return true }

                return sharers.contains { $0.owningTerm?.has(tagIn: studyingTags) == true }
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

#Preview("Simple buttons") {
    Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(previewModelContainer())
        .environment(\.useSimplePrompt, true)
}

#Preview("Advanced buttons") {
    Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(previewModelContainer())
        .environment(\.useSimplePrompt, false)
}
