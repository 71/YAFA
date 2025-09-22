import SwiftUI

/// The flashcard "prompt": the flashcard text followed by "OK" / "not OK" buttons.
struct StudyPrompt: View {
    let currentFlashcard: Flashcard
    let onChange: (FlashcardReview.Outcome) -> Void

    @State private var revealAnswer = false
    @State private var okPressed = false
    @State private var notOkPressed = false
    @State private var swapSides = false

    var body: some View {
        VStack {
            NavigationLink {
                FlashcardEditor(flashcard: currentFlashcard, autoFocus: false)
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

            HStack(spacing: 0) {
                Spacer()

                GlassEffectContainer {
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
                }

                Spacer()
            }
        }
        .foregroundStyle(.primary)
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
        onChange(outcome)
    }
}

private struct FlashcardView: View {
    let currentFlashcard: Flashcard
    let topText: String
    let bottomText: String
    let backgroundColor: Color?
    @Binding var reveal: Bool

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                Text(topText)
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.numericText())

                // Use a different font size and padding to make sure we always have some visual
                // feedback when revealing the text.
                Text(reveal ? bottomText : "Tap to reveal")
                    .font(reveal ? .title : .title2)
                    .foregroundStyle(reveal ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, reveal ? 16 : 12)
                    .padding(.bottom, reveal ? 12 : 8)
                    .contentTransition(.numericText())
                    .fontWeight(.semibold)
            }
            .contextMenu {
                Button(
                    reveal ? "Hide answer" : "Reveal answer",
                    systemImage: reveal ? "eye.slash" : "eye"
                ) {
                    withAnimation { reveal.toggle() }
                }
            }

            Spacer()
        }
        .multilineTextAlignment(.leading)
        // I can't get this view to take the full width of the container no matter how many
        // views I modify with `.frame(maxWidth: .infinity)`, but Swift is happy to take the
        // full width if there is any non-transparent background, so here we go.
        .background(.white.opacity(0.00001))

        // The above view is in charge of opening the flashcard view if we click on this view, but
        // _only_ if `reveal` is false. To enable this, we must add a `TagGesture()` which we
        // disable.
        .gesture(
            TapGesture().onEnded {
                withAnimation(.spring(duration: 0.35)) {
                    reveal = true
                }
            },
            isEnabled: !reveal
        )
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
                .padding(32)
                .font(.title.pointSize(32))
                .bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(answerColor.opacity(0.5)).interactive(), in: Circle())
        .padding(.vertical, 12)
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}
