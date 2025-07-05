import SwiftUI

/// The flashcard "prompt": the flashcard text followed by "OK" / "not OK" buttons.
struct StudyPrompt: View {
    let currentFlashcard: Flashcard
    let isLeftHanded: Bool
    let onChange: (FlashcardReview.Outcome) -> Void

    @State private var undoStack: [Bool] = []
    @State private var revealAnswer = false
    @State private var okPressed = false
    @State private var notOkPressed = false
    @State private var swapSides = false
    @State private var lastReviewUndoStates: [FlashcardReviewUndo] = []

    var body: some View {
        DueTimeView(nextReviewDate: currentFlashcard.nextReviewDate)

        VStack {
            NavigationLink {
                FlashcardEditor(flashcard: currentFlashcard, autoFocus: false, resetIfNew: nil)
            } label: {
                FlashcardView(
                    currentFlashcard: currentFlashcard,
                    topText: swapSides
                        ? currentFlashcard.back : currentFlashcard.front,
                    bottomText: swapSides
                        ? currentFlashcard.front : currentFlashcard.back,
                    backgroundColor: okPressed
                        ? RootView.stateColors.ok
                        : notOkPressed ? RootView.stateColors.notOk : nil,
                    reveal: $revealAnswer
                )
            }

            ZStack {
                HStack {
                    if isLeftHanded { Spacer() }

                    if let undoState = lastReviewUndoStates.last {
                        Button {
                            undoState.undo()
                            withAnimation(.spring(duration: 0.15)) {
                                _ = lastReviewUndoStates.popLast()
                            }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.title3)
                        }
                        .labelStyle(.iconOnly)
                        .padding(14)
                        .answerButtonLike(background: Color.accentColor.opacity(0.5))
                        .padding(.horizontal, 22)
                        .transition(.scale)
                    }

                    if !isLeftHanded { Spacer() }
                }

                HStack(spacing: 0) {
                    Spacer()

                    AnswerButton(
                        systemImageName: "checkmark",
                        answerColor: RootView.stateColors.ok,
                        pressed: $okPressed
                    ) {
                        onSubmit(outcome: .ok)
                    }

                    AnswerButton(
                        systemImageName: "xmark",
                        answerColor: RootView.stateColors.notOk,
                        pressed: $notOkPressed
                    ) {
                        onSubmit(outcome: .fail)
                    }

                    Spacer()
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 16)
        .background(Color.accentColor.opacity(0.1))
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .onChange(of: currentFlashcard, initial: true) { updateSwapSides() }
    }

    private func updateSwapSides() {
        swapSides =
            switch currentFlashcard.studyMode {
            case nil, .recallBack:
                false
            case .recallFront:
                true
            case .recallBothSides:
                Bool.random()
            }
    }

    private func onSubmit(outcome: FlashcardReview.Outcome) {
        withAnimation(.spring(duration: 0.35)) {
            revealAnswer = false
        }
        withAnimation(.spring(duration: 0.15)) {
            if lastReviewUndoStates.count == 10 {
                lastReviewUndoStates.removeFirst()
            }
            lastReviewUndoStates.append(currentFlashcard.addReview(outcome: outcome))
        }
        onChange(outcome)
    }
}

private struct DueTimeView: View {
    let nextReviewDate: Date

    @State private var currentDate = Date.now
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if nextReviewDate > currentDate {
                Text("Due \(formatDueString())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .padding(.leading, 4)
            }
        }
        .onReceive(timer) { currentDate = $0 }
    }

    private func formatDueString() -> String {
        let dateFormatter = RelativeDateTimeFormatter()

        dateFormatter.dateTimeStyle = .named

        return dateFormatter.localizedString(for: nextReviewDate, relativeTo: currentDate)
    }
}

private struct FlashcardView: View {
    let currentFlashcard: Flashcard
    let topText: String
    let bottomText: String
    let backgroundColor: Color?
    @Binding var reveal: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(topText)
                .font(.title)
                .bold()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)

            Group {
                // Use a different font size and padding to make sure we always have some visual
                // feedback when revealing the text.
                if reveal {
                    Text(bottomText)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                } else {
                    Text("Tap to reveal")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
            }
            .transition(.push(from: .bottom))
            .fontWeight(.semibold)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        // I can't get this view to take the full width of the container no matter how many
        // views I modify with `.frame(maxWidth: .infinity)`, but Swift is happy to take the
        // full width if there is any non-transparent background, so here we go.
        .background(.white.opacity(0.00001))
        .gesture(
            TapGesture().onEnded {
                withAnimation(.spring(duration: 0.35)) {
                    reveal = true
                }
            }, isEnabled: !reveal)
    }
}

private struct AnswerButton: View {
    let systemImageName: String
    let answerColor: Color
    @Binding var pressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .padding(24)
                .font(.title)
                .bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .answerButtonLike(
            background: pressed ? answerColor.opacity(0.5) : Color.accentColor.opacity(0.3)
        )
        .padding(.vertical, 12)
        .onLongPressGesture(
            minimumDuration: 0.0, maximumDistance: .infinity, perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}

extension View {
    fileprivate func answerButtonLike(background: Color) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(background, in: Circle())
    }
}
