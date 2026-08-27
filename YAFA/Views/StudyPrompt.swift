import SwiftData
import SwiftUI

/// The study prompt: the text to recall, followed by the answer buttons.
///
/// A prompt shown for one link may have been answered with another's target -- 차 prompts for "car"
/// while the reader recalls "tea" -- so the siblings are offered too, each with buttons of its own.
/// `onChange` therefore reports *which* link was graded, not only how.
struct StudyPrompt: View {
    let link: Link
    let onChange: (Link, Review.Outcome) -> Void

    @State private var revealAnswer = false
    @State private var showSiblings = false
    @State private var okPressed = false
    @State private var notOkPressed = false

    var body: some View {
        VStack {
            PromptView(
                topTerm: link.source,
                bottomTerm: link.target,
                // Revealing fills the blank back in, so the sentence is shown whole alongside
                // the answer rather than still holding a rectangle over the word just given.
                topText: revealAnswer
                    ? AttributedString(link.source?.text ?? "")
                    : blankedPrompt(of: link),
                context: promptContext(of: link),
                hint: link.hint,
                bottomText: link.answerText,
                backgroundColor: okPressed
                    ? RootView.stateColors.ok
                    : notOkPressed ? RootView.stateColors.notOk : nil,
                reveal: $revealAnswer
            )

            if revealAnswer {
                SiblingsList(link: link, revealed: $showSiblings) { sibling, outcome in
                    submit(sibling, outcome: outcome)
                }
            }

            AnswerButtons(okPressed: $okPressed, notOkPressed: $notOkPressed) { outcome in
                submit(link, outcome: outcome)
            }
        }
        .foregroundStyle(.primary)
        // Whatever brings a different link here -- answering, undoing, a tag being toggled --
        // it arrives unrevealed. The view is deliberately *not* given a new identity per link:
        // keeping one lets `contentTransition` animate the text changing, where recreating it would
        // simply swap one prompt for another.
        .onChange(of: link.persistentModelID) {
            revealAnswer = false
            showSiblings = false
        }
    }

    private func submit(_ graded: Link, outcome: Review.Outcome) {
        withAnimation(.spring(duration: 0.35)) {
            revealAnswer = false
            showSiblings = false
        }
        onChange(graded, outcome)
    }
}

/// The other answers this prompt could have wanted, hidden until asked for.
///
/// Called "siblings" here and in the RFC -- they are the source term's other outgoing links -- but
/// never to the reader, who is looking at answers rather than at the graph: on screen they are
/// "other answers".
///
/// Hidden by default, and not opened by revealing the answer either: a sibling read here is a
/// sibling given away, and the next review of it would be scored on having just seen it.
///
/// Revealing swaps the invitation out for the rows rather than unfolding them beneath it, matching
/// the answer above -- which fades one text into another in place rather than growing the screen.
private struct SiblingsList: View {
    let link: Link
    @Binding var revealed: Bool
    let onChange: (Link, Review.Outcome) -> Void

    var body: some View {
        let siblings = link.siblings

        if !siblings.isEmpty {
            ZStack(alignment: .topLeading) {
                if revealed {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(siblings, id: \.persistentModelID) { sibling in
                            SiblingRow(sibling: sibling) { onChange(sibling, $0) }
                        }

                        // Under the rows rather than under the invitation: before the tap this
                        // competes with recalling the answer, and describes buttons which are not
                        // on screen yet. After it, every row has its own pair beside it, and the
                        // tip names what the reader is looking at.
                        Tip("Grade the answer you recalled, in case the answer above is not the one you were thinking of.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity)
                } else {
                    // Plural only when there is more than one to reveal: a homograph with a single
                    // other reading is the common case, and the plural reads as a promise of more.
                    Text(
                        siblings.count == 1
                            ? "Tap to reveal other answer" : "Tap to reveal other answers"
                    )
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35)) { revealed = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }
}

/// One sibling answer on a line of its own: what it is, and the buttons grading *it* rather than the
/// link which was prompted.
///
/// Its own progress is advanced, whether or not it was due: reviewing ahead of schedule has always
/// been possible, and FSRS reads an early review as a smaller step rather than a full interval's
/// worth of evidence.
private struct SiblingRow: View {
    let sibling: Link
    let onChange: (Review.Outcome) -> Void

    @State private var okPressed = false
    @State private var notOkPressed = false

    var body: some View {
        HStack(spacing: 8) {
            PromptLink(term: sibling.target) {
                VStack(alignment: .leading, spacing: 1) {
                    // Full strength: this is an answer, read the same way the revealed one above is, and
                    // the buttons beside it are the quiet half of the row.
                    Text(verbatim: sibling.answerText)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Grading a sibling reviews it early, so how early is worth saying: "Due in 3 days"
                    // is what tells the reader this is a card pulled forward rather than one owed.
                    if let progress = sibling.progress {
                        RelativeDueText(date: progress.nextReviewDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Trailing, on the row's own line: these grade this one answer, and centring them the
            // way the prompt's own buttons are centred would read as a second set of main buttons.
            AnswerButtons(
                layout: .trailing,
                okPressed: $okPressed,
                notOkPressed: $notOkPressed,
                onSubmit: onChange
            )
        }
    }
}

/// The grading buttons: two of them, or four under the advanced preference.
///
/// Shared by the prompt and by each sibling row, so that grading a sibling offers exactly the same
/// choices as grading what was asked -- only smaller, and sitting at the end of its row.
private struct AnswerButtons: View {
    enum Layout {
        /// Filling the width at the bottom of the screen: the buttons the prompt itself is answered
        /// with.
        case main
        /// Small, at the end of a sibling's row. The advanced buttons lose their labels here, since
        /// four of them and an answer do not fit across a line.
        case trailing
    }

    var layout: Layout = .main
    @Binding var okPressed: Bool
    @Binding var notOkPressed: Bool
    let onSubmit: (Review.Outcome) -> Void

    @Environment(\.useSimplePrompt) private var simplePrompt: Bool

    var body: some View {
        let spacing: CGFloat = 6
        let compact = layout == .trailing

        HStack(spacing: simplePrompt && !compact ? 0 : spacing) {
            GlassEffectContainer {
                if simplePrompt {
                    if !compact { Spacer() }

                    AnswerButton(
                        systemImageName: "checkmark",
                        answerColor: RootView.stateColors.ok,
                        compact: compact,
                        pressed: $okPressed
                    ) {
                        onSubmit(.ok)
                    }
                    AnswerButton(
                        systemImageName: "xmark",
                        answerColor: RootView.stateColors.notOk,
                        compact: compact,
                        pressed: $notOkPressed
                    ) {
                        onSubmit(.fail)
                    }

                    if !compact { Spacer() }
                } else if compact {
                    // One run of four, hardest to easiest, rather than the 2x2 the main buttons use:
                    // a row has one line to spend, and the reading order is the same either way.
                    AdvancedAnswerButton(
                        icon: "backward",
                        label: "Again",
                        answerColor: RootView.stateColors.notOk,
                        compact: true,
                        pressed: $notOkPressed
                    ) {
                        onSubmit(.fail)
                    }
                    AdvancedAnswerButton(
                        icon: "arrowtriangle.backward",
                        label: "Hard",
                        answerColor: RootView.stateColors.hard,
                        compact: true,
                        pressed: $okPressed
                    ) {
                        onSubmit(.hard)
                    }
                    AdvancedAnswerButton(
                        icon: "arrowtriangle.forward",
                        label: "Good",
                        answerColor: RootView.stateColors.ok,
                        compact: true,
                        pressed: $okPressed
                    ) {
                        onSubmit(.ok)
                    }
                    AdvancedAnswerButton(
                        icon: "forward",
                        label: "Easy",
                        answerColor: RootView.stateColors.easy,
                        compact: true,
                        pressed: $okPressed
                    ) {
                        onSubmit(.easy)
                    }
                } else {
                    VStack(spacing: spacing) {
                        AdvancedAnswerButton(
                            icon: "arrowtriangle.backward",
                            label: "Hard",
                            answerColor: RootView.stateColors.hard,
                            pressed: $okPressed
                        ) {
                            onSubmit(.hard)
                        }
                        AdvancedAnswerButton(
                            icon: "backward",
                            label: "Again",
                            answerColor: RootView.stateColors.notOk,
                            pressed: $notOkPressed
                        ) {
                            onSubmit(.fail)
                        }
                    }
                    VStack(spacing: spacing) {
                        AdvancedAnswerButton(
                            icon: "arrowtriangle.forward",
                            label: "Good",
                            answerColor: RootView.stateColors.ok,
                            pressed: $okPressed
                        ) {
                            onSubmit(.ok)
                        }
                        AdvancedAnswerButton(
                            icon: "forward",
                            label: "Easy",
                            answerColor: RootView.stateColors.easy,
                            pressed: $okPressed
                        ) {
                            onSubmit(.easy)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: compact, vertical: false)
    }
}

/// Wraps the prompt in a link to the term it is studied from, so that tapping the prompt (once the
/// answer is revealed) opens that term.
private struct PromptLink<Content: View>: View {
    let term: Term?
    @ViewBuilder let content: () -> Content

    var body: some View {
        // `TermDestination` rather than the bare term: it is `Hashable` in its own right, where
        // `Term` gets its conformance from the `@Model` macro, which the type checker does not
        // always have expanded by the time it checks this generic call.
        if let term {
            NavigationLink(value: TermDestination(term)) { content() }
        } else {
            content()
        }
    }
}

private struct PromptView: View {
    let topTerm: Term?
    let bottomTerm: Term?

    let topText: AttributedString
    /// What the prompt's term is otherwise studied against, shown under a blanked prompt so the
    /// blank is a
    /// question rather than something the sentence gives away. Empty for an ordinary prompt.
    var context: [String] = []
    /// The link's own hint, written to narrow a guess the prompt cannot narrow on its own. Empty
    /// when none was written.
    var hint: String = ""
    let bottomText: String
    let backgroundColor: Color?
    @Binding var reveal: Bool

    /// Everything narrowing the guess, on one line.
    ///
    /// For an ordinary prompt that is the hint, and nothing else: there is no sentence to translate.
    /// For a blanked one the hint has already been spent -- it is what the blank was filled with --
    /// so this is the sentence's own translation, which every blank in it shares.
    ///
    /// The two never both appear, which is why they can share a line rather than stacking into two
    /// that read as one element repeated.
    private var asked: String {
        context.isEmpty ? hint : context.joined(separator: ", ")
    }

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                NavigationLink(value: reveal && topTerm != nil ? TermDestination(topTerm!) : nil) {
                    Text(topText)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                        .multilineTextAlignment(.leading)
                }

                // Shown before the answer, not with it: it is part of the question. A hint is
                // written to be read before guessing rather than as a consolation afterwards, and a
                // sentence's translation is the point of a blank you cannot simply read around.
                //
                // The sentence's translation is the quieter of the two: the blank now carries the
                // meaning being asked for, so the translation is there to place it in the sentence
                // rather than to be read first.
                if !asked.isEmpty {
                    Text(verbatim: asked)
                        .font(context.isEmpty ? .title3 : .subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                // Use a different font size and padding to make sure we always have some visual
                // feedback when revealing the text.
                NavigationLink(value: reveal && bottomTerm != nil ? TermDestination(bottomTerm!) : nil) {
                    (reveal ? Text(verbatim: bottomText) : Text("Tap to reveal"))
                        .font(reveal ? .title : .title2)
                        .foregroundStyle(reveal ? .secondary : .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, reveal ? 16 : 12)
                        .padding(.bottom, reveal ? 12 : 8)
                        .contentTransition(.numericText())
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                }
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
    var compact: Bool = false
    @Binding var pressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                // Grey on a sibling's row: colour is what the main buttons are recognised by, and
                // spending it again here on a second, optional way to answer splits the screen
                // between two sets of green-and-red. The icon still says which is which.
                .foregroundStyle(compact ? AnyShapeStyle(.primary) : AnyShapeStyle(answerColor))
                .padding(compact ? 9 : 32)
                .font(.title.pointSize(compact ? 15 : 32))
                .bold()
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.vertical, compact ? 0 : 8)
        // A rounded rectangle on a row, where a circle reads as a badge stuck onto the line rather
        // than as a control belonging to it; the main buttons stay circular.
        .glassEffect(
            .regular.tint(compact ? .gray.opacity(0.1) : answerColor.opacity(0.25)).interactive(),
            in: compact ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle())
        )
        .padding(.vertical, compact ? 0 : 12)
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}

/// Drops a label's title when asked, and leaves it alone otherwise.
private struct IconOnlyIf: LabelStyle {
    let iconOnly: Bool

    init(_ iconOnly: Bool) {
        self.iconOnly = iconOnly
    }

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}

private struct AdvancedAnswerButton: View {
    let icon: String
    let label: LocalizedStringKey
    let answerColor: Color
    var compact: Bool = false
    @Binding var pressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Icon-only on a sibling's row: the label is what makes the main buttons readable at a
            // glance, and it is also what makes four of them too wide to sit beside an answer. The
            // accessibility label keeps the wording for anyone not reading the icon.
            Label(label, systemImage: icon)
                // The two styles are different types, so this cannot be a ternary in one modifier.
                .labelStyle(IconOnlyIf(compact))
                .font(.title.pointSize(compact ? 15 : 18))
                .fontWeight(.semibold)
                // Equal width for all buttons, except on a row, where they take only what they need.
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 9 : 0)
                .padding(.vertical, compact ? 9 : 24)  // Make every button tall, for ease of use.
                // Grey on a row, for the same reason the simple pair is: four saturated buttons
                // beside an answer outshout the ones the prompt itself is answered with, and the
                // four icons already run hardest to easiest.
                .foregroundStyle(compact ? AnyShapeStyle(.secondary) : AnyShapeStyle(answerColor))
                .glassEffect(
                    .regular
                        .tint(compact ? .gray.opacity(0.1) : answerColor.opacity(0.25))
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: compact ? 10 : 16)
                )
        }
        .accessibilityLabel(label)
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: {}
        ) { pressed in
            withAnimation { self.pressed = pressed }
        }
    }
}
