import SwiftUI

/// The study prompt: the text to recall, followed by the answer buttons.
struct StudyPrompt: View {
    let studiable: any Studiable
    let onChange: (Review.Outcome) -> Void

    @Environment(\.useSimplePrompt) var simplePrompt: Bool

    @State private var revealAnswer = false
    @State private var okPressed = false
    @State private var notOkPressed = false

    var body: some View {
        VStack {
            PromptLink(studiable: studiable) {
                PromptView(
                    topText: studiable.promptText,
                    bottomText: studiable.answerText,
                    backgroundColor: okPressed
                        ? RootView.stateColors.ok
                        : notOkPressed ? RootView.stateColors.notOk : nil,
                    reveal: $revealAnswer
                )
            }

            let advButtonSpacing: CGFloat = 6

            HStack(spacing: simplePrompt ? 0 : advButtonSpacing) {
                GlassEffectContainer {
                    if simplePrompt {
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
                    } else {
                        VStack(spacing: advButtonSpacing) {
                            AdvancedAnswerButton(
                                icon: "arrowtriangle.backward",
                                label: "Hard",
                                answerColor: RootView.stateColors.hard,
                                pressed: $okPressed
                            ) {
                                onSubmit(outcome: .hard)
                            }
                            AdvancedAnswerButton(
                                icon: "backward",
                                label: "Again",
                                answerColor: RootView.stateColors.notOk,
                                pressed: $notOkPressed
                            ) {
                                onSubmit(outcome: .fail)
                            }
                        }
                        VStack(spacing: advButtonSpacing) {
                            AdvancedAnswerButton(
                                icon: "arrowtriangle.forward",
                                label: "Good",
                                answerColor: RootView.stateColors.ok,
                                pressed: $okPressed
                            ) {
                                onSubmit(outcome: .ok)
                            }
                            AdvancedAnswerButton(
                                icon: "forward",
                                label: "Easy",
                                answerColor: RootView.stateColors.easy,
                                pressed: $okPressed
                            ) {
                                onSubmit(outcome: .easy)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        // Whatever brings a different studiable here -- answering, undoing, a tag being toggled --
        // it arrives unrevealed. The view is deliberately *not* given a new identity per studiable:
        // keeping one lets `contentTransition` animate the text changing, where recreating it would
        // simply swap one prompt for another.
        .onChange(of: studiable.persistentModelID) { revealAnswer = false }
    }

    private func onSubmit(outcome: Review.Outcome) {
        withAnimation(.spring(duration: 0.35)) {
            revealAnswer = false
        }
        onChange(outcome)
    }
}

/// Wraps the prompt in a link to the term it is studied from, so that tapping the prompt (once the
/// answer is revealed) opens that term.
private struct PromptLink<Content: View>: View {
    let studiable: any Studiable
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let term = studiable.owningTerm {
            NavigationLink(value: term) { content() }
        } else {
            content()
        }
    }
}

private struct PromptView: View {
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
                (reveal ? Text(verbatim: bottomText) : Text("Tap to reveal"))
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

        // The above view is in charge of opening the term view if we click on this view, but
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
                .foregroundStyle(answerColor)
                .padding(32)
                .font(.title.pointSize(32))
                .bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(answerColor.opacity(0.25)).interactive(), in: Circle())
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

private struct AdvancedAnswerButton: View {
    let icon: String
    let label: LocalizedStringKey
    let answerColor: Color
    @Binding var pressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.title.pointSize(18))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)  // Give equal width to all buttons.
                .padding(.vertical, 24)  // Make every button tall, for ease of use.
                .foregroundStyle(answerColor)
                .glassEffect(
                    .regular.tint(answerColor.opacity(0.25)).interactive(),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}
