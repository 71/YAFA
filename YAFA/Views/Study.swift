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
        if let progress, let studiable = progress.nextSharer {
            StudyPrompt(studiable: studiable) { outcome in
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
                    if lastReviewUndoStates.count == 10 {
                        lastReviewUndoStates.removeFirst()
                    }
                    lastReviewUndoStates.append(progress.addReview(of: studiable, outcome: outcome))
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
/// Only the button: the header directly above already says there is no review due, and saying it
/// twice on an otherwise empty screen reads as an error rather than a state.
private struct NoTermView: View {
    var body: some View {
        Spacer()

        HStack {
            Spacer()

            NavigationLink(value: NewTerm()) {
                Label("Add term", systemImage: "plus")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(.bordered)

            Spacer()
        }

        Spacer()
    }
}
