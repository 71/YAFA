import SwiftUI

struct StudyPrompt: View {
    let currentFlashcard: Flashcard
    let cardHeight: CGFloat
    let isLeftHanded: Bool
    let studyMode: StudyMode
    let onChange: (FlashcardReview.Outcome) -> Void

    @State private var undoStack: [Bool] = []
    @State private var revealAnswer = false
    @State private var okPressed = false
    @State private var notOkPressed = false
    @State private var swapSides = false
    @State private var lastReviewUndoState: FlashcardReviewUndo?
    @State private var everySecond = Timer.publish(every: 1, on: .current, in: .common)

    var body: some View {
        if currentFlashcard.nextReviewDate.timeIntervalSinceNow > 0 {
            DueTimeView(nextReviewDate: currentFlashcard.nextReviewDate)
        }

        NavigationLink {
            FlashcardEditor(flashcard: currentFlashcard, resetIfNew: nil)
        } label: {
            FlashcardView(
                height: cardHeight,
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
        .foregroundStyle(.primary)
        .onChange(of: currentFlashcard, initial: true) { updateSwapSides() }
        .onChange(of: studyMode) { updateSwapSides() }

        ZStack {
            HStack {
                if isLeftHanded { Spacer() }

                if let undoState = lastReviewUndoState {
                    Button {
                        undoState.undo()
                        withAnimation(.spring(duration: 0.15)) { lastReviewUndoState = nil }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.title3)
                    }
                    .labelStyle(.iconOnly)
                    .padding(14)
                    .background(.thinMaterial, in: Circle())
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
        .foregroundStyle(.primary)
        .padding(.vertical, 16)
        .background(Color.accentColor.opacity(0.1))
        .background(.regularMaterial)
        .ignoresSafeArea()
    }

    private func updateSwapSides() {
        swapSides =
            switch studyMode {
            case .recallBack:
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
            lastReviewUndoState = currentFlashcard.addReview(outcome: outcome)
        }
        onChange(outcome)
    }
}

private struct DueTimeView: View {
    let nextReviewDate: Date

    @State private var currentDate = Date.now
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("Due \(formatDueString())")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
            .padding(.leading, 4)
            .onReceive(timer) { currentDate = $0 }
    }

    private func formatDueString() -> String {
        let dateFormatter = RelativeDateTimeFormatter()

        dateFormatter.dateTimeStyle = .named

        return dateFormatter.localizedString(for: nextReviewDate, relativeTo: currentDate)
    }
}

private struct FlashcardView: View {
    let height: CGFloat
    let topText: String
    let bottomText: String
    let backgroundColor: Color?
    @Binding var reveal: Bool

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                Text(topText)
                    .font(.title2)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .cornerRadius(12)

            VStack {
                if reveal {
                    Text(bottomText)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap to reveal")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: reveal ? 150 : 0)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom))
            .padding(
                EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12)
            )
            .gesture(
                TapGesture().onEnded {
                    withAnimation(.spring(duration: 0.35)) {
                        reveal = true
                    }
                }, isEnabled: !reveal)

            Spacer().frame(height: max(0, -dragOffset))
        }
        .background(Color.accentColor.opacity(0.1))
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadii: .init(topLeading: 12, topTrailing: 12)))
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local).onChanged
            {
                gesture in
                dragOffset += gesture.translation.height
            }.onEnded { gesture in
                if reveal && gesture.translation.height > 10 {
                    reveal = false
                } else if !reveal && gesture.translation.height < 100 {
                    reveal = true
                }
                withAnimation { dragOffset = 0 }
            }
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
                .padding(20)
                .font(.title2)
                .bold()
        }
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: Circle())
        .colorMultiply(pressed ? answerColor : .white)
        .onLongPressGesture(
            minimumDuration: 0.0, maximumDistance: .infinity, perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}
