import Combine
import SwiftData
import SwiftUI

struct StudyView: View {
    @Binding var stateColor: Color
    @Binding var lastReviewUndoStates: [ReviewUndo]

    /// The progress to study next, if any.
    let progress: Progress?

    /// A dummy boolean toggled every time an answer is provided to trigger an animation.
    @State private var toggledOnAnswer = false

    var body: some View {
        // When a progress is shared, only one of its sharers is shown: reviewing it schedules them
        // all, so showing them one after the other would be asking the same question twice.
        if let progress, let link = progress.nextSharer {
            // The link handed back is not always the one shown: a sibling answer graded from the
            // prompt is graded against its own progress, which is why the review goes through
            // `graded` rather than through the progress this queue entry came from.
            StudyPrompt(link: link) { graded, outcome in
                withAnimation(.easeInOut) {
                    switch outcome {
                    case .ok: stateColor = RootView.stateColors.ok
                    case .easy: stateColor = RootView.stateColors.easy
                    case .hard: stateColor = RootView.stateColors.hard
                    case .fail: stateColor = RootView.stateColors.notOk
                    }
                    toggledOnAnswer.toggle()
                }
                withAnimation(.spring(duration: 0.15)) {
                    guard let undo = graded.addReview(outcome: outcome) else { return }

                    if lastReviewUndoStates.count == 10 {
                        lastReviewUndoStates.removeFirst()
                    }
                    lastReviewUndoStates.append(undo)
                }
            }
            .padding(.top, 32)
        } else {
            NoTermView()
        }
    }
}

/// Shown when nothing is due.
///
/// Usually only the button: the header directly above already says there is no review due, and
/// saying it twice on an otherwise empty screen reads as an error rather than a state.
///
/// The exception is a database with nothing in it, which is the same screen for a very different
/// reason -- not "you are done" but "you have not started". That one gets a line saying what a term
/// is, since this is the first screen of the app and nothing has introduced it yet.
private struct NoTermView: View {
    /// Only whether any term exists, which is what separates the two readings of this screen.
    ///
    /// Unsorted, and asking for one row: nothing here reads a term, so ordering the whole table to
    /// find out whether it is empty is work with no result.
    @Query(Self.anyTerm) private var terms: [Term]

    /// Unsorted, and asking for one row: nothing here reads a term, so ordering the whole table to
    /// find out whether it is empty is work with no result.
    private static var anyTerm: FetchDescriptor<Term> {
        var descriptor = FetchDescriptor<Term>()

        descriptor.fetchLimit = 1

        return descriptor
    }

    /// Whether there were no terms at all when this view appeared. Sampled once, for the reason
    /// given on `TermEditor.tip`.
    @State private var hadNoTerms = false

    var body: some View {
        Spacer()

        VStack(spacing: 12) {
            if hadNoTerms {
                Tip(
                    "A term is a word, phrase, or sentence you can study. Add one, then link it to what it means to start studying."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            NavigationLink(value: NewTerm()) {
                Label("Add term", systemImage: "plus")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .onAppear { hadNoTerms = terms.isEmpty }

        Spacer()
    }
}
