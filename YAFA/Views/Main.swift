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

                    StudyView(
                        stateColor: $stateColor,
                        lastReviewUndoStates: $lastReviewUndoStates,
                        progress: queuedProgresses.first
                    )
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
        // A sheet rather than a screen swapped in below the header: tapping a tag opens the terms
        // it holds, and dismissing that search used to land on the study view, leaving no way back
        // to the list except the header button again.
        .sheet(isPresented: $showTags) {
            Tags(searchTags: $searchTags, tags: tags)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .onChange(of: searchTags) {
                    guard !searchTags.isEmpty else { return }

                    showTags = false
                    searching = true
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

                // A progress whose links were all deleted has nothing left to study.
                guard !sharers.isEmpty else { return false }
                guard !studyingTags.isEmpty else { return true }

                return sharers.contains { $0.joins(tagIn: studyingTags) }
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

/// An anchored link: the sentence with one word blanked, answered by the term that word stands for.
///
/// The anchored span is 갔다 and the answer is 가다, so this is also the case where the two disagree
/// -- what the sentence says is a conjugation of what is being recalled.
#Preview("Anchored prompt") {
    let container = previewModelContainer()

    studyFirst(previewLink(from: "고양이가 학교에 갔다", to: "가다", in: container))

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, true)
}

/// The same sentence studied against its other blank, so the two prompts can be compared: each
/// hides only its own word and leaves the other one filled in.
#Preview("Anchored prompt (other blank)") {
    let container = previewModelContainer()

    studyFirst(previewLink(from: "고양이가 학교에 갔다", to: "학교", in: container))

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, true)
}

/// The same sentence as an ordinary link: nothing is blanked, and the whole thing is the prompt.
#Preview("Unanchored prompt") {
    let container = previewModelContainer()

    studyFirst(
        previewLink(from: "고양이가 학교에 갔다", to: "the cat went to school", in: container)
    )

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, true)
}

/// A homograph: 차 prompts for one of its two answers, and the other is a tap away under "Tap to
/// reveal other answers", gradable on its own.
#Preview("Other answers") {
    let container = previewModelContainer()

    studyFirst(previewLink(from: "차", to: "car", in: container))

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, true)
}

/// The same prompt under the four-button preference, where each other answer carries four of its
/// own.
#Preview("Other answers (advanced buttons)") {
    let container = previewModelContainer()

    studyFirst(previewLink(from: "차", to: "car", in: container))

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, false)
}

/// A link with a hint, which is shown with the prompt and ahead of the answer: 차 → tea says "Drunk,
/// not driven" before anything is revealed.
#Preview("Hint") {
    let container = previewModelContainer()

    studyFirst(previewLink(from: "차", to: "tea", in: container))

    return Main(stateColor: .constant(.red), navigationModel: .init())
        .modelContainer(container)
        .environment(\.useSimplePrompt, true)
}

/// Brings `link` to the front of the study queue, so that a preview showing the prompt shows this
/// one rather than whichever happens to be due first.
///
/// Everything else is pushed a day out rather than this one pulled forward: the queue is ordered by
/// due date, and several links in the preview container are already due now.
@MainActor
private func studyFirst(_ link: Link) {
    guard let context = link.modelContext else { return }

    let tomorrow = Date.now.addingTimeInterval(24 * 60 * 60)

    for progress in (try? context.fetch(FetchDescriptor<Progress>())) ?? [] {
        progress.reschedule(to: tomorrow)
    }

    link.progress?.reschedule(to: .now.addingTimeInterval(-60))
}
