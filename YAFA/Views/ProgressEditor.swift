import SwiftData
import SwiftUI

/// The scheduling state and review history of a set of links and cloze blanks studied together.
///
/// There is deliberately no standalone screen listing progresses: this is reachable only from the
/// links and cloze blanks which use it, and so sits less prominently than terms or tags.
struct ProgressEditor: View {
    let progress: Progress

    /// The term whose screen this one was opened from, if any.
    var cameFrom: Term? = nil

    @AppStorage("prefer_relative_date") private var relativeDate = false

    @State private var removing: (any Studiable)?

    /// The term to open, set by a sharer row. Those rows are buttons rather than links, so that a
    /// row inside a `Form` does not draw a disclosure chevron next to its own.
    @State private var openedTerm: TermDestination?

    var body: some View {
        Form {
            Section(header: DueHeader(date: progress.nextReviewDate)) {
                DatePicker(
                    "Date",
                    selection: Binding {
                        progress.nextReviewDate
                    } set: {
                        progress.reschedule(to: $0)
                    }
                )
            }
            .monospacedDigit()

            SharersSection()
            HistorySection()
        }
        // Lifted so the mark joining a mutual pair can be a row of its own without being padded out
        // to a tappable height. It is a property of the list, not of a row, so it has to be set
        // here; every row which needs the usual height asks for it explicitly.
        .environment(\.defaultMinListRowHeight, 0)
        .navigationDestination(item: $openedTerm) { destination in
            TermEditor(
                term: destination.term,
                autoFocus: false,
                cameFrom: destination.cameFrom
            )
        }
        .environment(\.openTerm) { openedTerm = $0 }
        .dismissKeyboardToolbar()
        .navigationTitle("Progress")
        .confirmationDialog(
            "Remove from this progress?",
            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
            titleVisibility: .visible,
            presenting: removing
        ) { studiable in
            Button("Remove", role: .destructive) {
                studiable.leaveSharedProgress()
                removing = nil
            }
        } message: { _ in
            Text(
                "It keeps its due date but starts a review history of its own, and is scheduled separately from now on."
            )
        }
    }

    @ViewBuilder
    private func SharersSection() -> some View {
        let sharers = progress.sortedSharers

        Section(
            header: Text("Links"),
            footer: sharers.count > 1
                ? Text("Reviewing any of these advances the schedule of all of them.")
                : Text("Nothing else shares this schedule.")
        ) {
            // Two rows together mean both directions; a row on its own is studied one way, from
            // its first line to its second. That leaves nothing for a per-row arrow to say, so the
            // only mark is the one joining a pair.
            //
            // Each sharer is its own list row rather than sharing one with its partner: stacking
            // two buttons in a single row makes the whole row one tap target, and hangs the swipe
            // actions on the pair instead of on the link they act upon.
            ForEach(progress.sharerGroups) { group in
                ForEach(Array(group.sharers.enumerated()), id: \.element.persistentModelID) {
                    (i, sharer) in
                    // The mark is a row of its own between the pair's two rows, which only works
                    // because the form's minimum row height is lifted above.
                    if i != 0 {
                        BothDirectionsMark()
                            .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .selectionDisabled()
                    }

                    SharerRow(
                        sharer: sharer,
                        // Inside a pair each row names one end and the mark says the rest;
                        // spelling out the answer too would print the same two terms twice.
                        showsAnswer: !group.isMutual,
                        goesBack: sharer.owningTerm?.persistentModelID
                            == cameFrom?.persistentModelID
                    )
                    .swipeActions(edge: .leading) {
                        DirectionActions(sharer: sharer)
                    }
                    .swipeActions(edge: .trailing) {
                        if sharers.count > 1 {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                removing = sharer
                            }
                            // See the note on the term view's delete action: the ambient tint wins
                            // over the destructive role here.
                            .tint(.red)
                        }
                    }
                    .contextMenu {
                        DirectionActions(sharer: sharer)

                        if sharers.count > 1 {
                            Button(
                                "Remove from progress",
                                systemImage: "minus.circle",
                                role: .destructive
                            ) {
                                removing = sharer
                            }
                        }
                    }
                    // Between a pair, the mark is the separator.
                    .listRowSeparator(i != 0 ? .hidden : .automatic, edges: .top)
                    .listRowSeparator(
                        group.isMutual && i == 0 ? .hidden : .automatic,
                        edges: .bottom
                    )
                }
            }

            NewProgressLinkRow(progress: progress)
        }
    }

    @ViewBuilder
    private func HistorySection() -> some View {
        let reviewsByDate = progress.reviewsByDate
        let shared = progress.sharers.count > 1

        if !reviewsByDate.isEmpty {
            Section(header: Text("Review history")) {
                ForEach(reviewsByDate) { review in
                    let reviewImage =
                        switch review.outcome {
                        case .ok, .easy: "checkmark"
                        case .fail, .hard: "xmark"
                        }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            DateText(date: review.date, relative: $relativeDate)

                            // Once a progress is shared, its reviews can come from different
                            // links or blanks, so each one says what was actually shown.
                            if shared, let studied = review.studied {
                                Text(studied.answerText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                        Image(systemName: reviewImage)
                    }
                }
            }
            .monospacedDigit()
        }
    }
}

/// Drawn between the two rows of a mutual pair, in place of a divider.
///
/// The arrows point at the rows they join, so the pair reads as one thing studied both ways.
private struct BothDirectionsMark: View {
    var body: some View {
        ZStack(alignment: .leading) {
            // The rule sits behind, starting after the icon so the two don't overlap.
            Divider().padding(.leading, 22)

            Image(systemName: "arrow.up.arrow.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Studied in both directions")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Actions offered for a link whose reverse direction isn't in the set.
///
/// A link with no reverse can either be turned around or joined by its reverse; once both
/// directions are present there is nothing left to offer.
private struct DirectionActions: View {
    let sharer: any Studiable

    var body: some View {
        if let link = sharer as? Link, link.reverse == nil {
            Button("Add reverse", systemImage: "arrow.left.arrow.right") {
                link.addReverse()
            }
            .tint(.accentColor)

            Button("Swap direction", systemImage: "arrow.uturn.left") {
                link.swapDirection()
            }
            .tint(.gray)
        }
    }
}

/// One link or cloze blank scheduled against the progress being viewed, as prompt over answer.
///
/// Inside a mutual pair this appears twice, once per direction; the shared arrow beside them says
/// they are the same two terms both ways.
private struct SharerRow: View {
    let sharer: any Studiable
    /// Whether to spell out the answer under the prompt. Off inside a mutual pair, where the two
    /// rows hold the same two terms and the arrow already says so.
    var showsAnswer: Bool = true
    var goesBack: Bool = false

    @Environment(\.openTerm) private var openTerm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if goesBack {
                dismiss()
            } else if let term = sharer.owningTerm {
                openTerm(.init(term))
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sharer.promptText)

                    if showsAnswer {
                        Text(sharer.answerText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: goesBack ? "chevron.left" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

/// When the next review falls due, as a relative phrase.
///
/// A relative phrase reads better than a timestamp here: what matters is how far off the review is,
/// not the wall-clock moment, which the picker below states exactly anyway.
private struct DueHeader: View {
    let date: Date

    var body: some View {
        RelativeDueText(date: date)
    }
}

/// A progress belonging to one link, with a review history.
#Preview("Own progress") {
    let container = previewModelContainer()
    let progress = previewTerm("한국어", in: container).outgoingLinks!.first!.progress!

    NavigationStack {
        ProgressEditor(progress: progress)
    }
    .modelContainer(container)
}

/// A progress shared by two links, so its history spans both.
#Preview("Shared progress") {
    let container = previewModelContainer()
    let progress = previewTerm("big", in: container).outgoingLinks!.first!.progress!

    NavigationStack {
        ProgressEditor(progress: progress)
    }
    .modelContainer(container)
}

/// A progress whose two links are the two directions of one pair of terms.
#Preview("Both directions") {
    let container = previewModelContainer()
    let progress = previewTerm("하나", in: container).outgoingLinks!.first!.progress!

    NavigationStack {
        ProgressEditor(progress: progress)
    }
    .modelContainer(container)
}
