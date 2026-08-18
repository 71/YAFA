import SwiftUI

/// The header showing due reviews / tags in the study view.
///
/// The whole line opens the tag list, and closes it again. It carried an "..." button beside it
/// while that list was a screen swapped in below, whose state the button reflected; a second target
/// inside a row which was already a button was only ever redundant.
///
/// Tapping to close works because the sheet leaves the view behind it interactive up to its medium
/// detent, so the header stays reachable while the list is open -- and a control which opened
/// something ought to shut it too, rather than making the only way out a swipe.
struct DueReviewsHeader: View {
    @Binding var showTags: Bool

    let progresses: [Progress]
    let tags: [Tag]

    var body: some View {
        Button {
            showTags.toggle()
        } label: {
            HStack {
                DueReviewsText(progresses: progresses, tags: tags)

                Spacer()
            }
        }
        .tint(.primary)
        .accessibilityLabel(showTags ? "Hide tags" : "Edit tags")
    }
}

private struct DueReviewsText: View {
    let progresses: [Progress]
    let tags: [Tag]

    @State private var text = AttributedString()
    @State private var currentDate = Date.now
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .contentTransition(.numericText())
            .onAppear { updateState() }
            .onChange(of: progresses.first) {
                currentDate = .now
                updateState()
            }
            .onChange(of: progresses.count) {
                currentDate = .now
                updateState()
            }
            .onReceive(timer) {
                currentDate = $0
                updateState()
            }
    }

    private func updateState() {
        withAnimation {
            text = computeText()
        }
    }

    private func computeText() -> AttributedString {
        var text: String = .init()

        // A shared progress counts once, not once per sharer: reviewing it schedules them all.
        let dueReviews = progresses.count { !$0.isDoneForNow(now: currentDate) }

        if dueReviews == 0 {
            if let first = progresses.first {
                let dateFormatter = RelativeDateTimeFormatter()
                dateFormatter.dateTimeStyle = .numeric
                dateFormatter.unitsStyle = .short
                let dueDate =
                    dateFormatter.localizedString(
                        for: first.nextReviewDate,
                        relativeTo: currentDate
                    )

                text.append(String(localized: "Review due") + " ")
                text.append(dueDate)
            } else {
                text.append(String(localized: "No review due"))
            }
        } else {
            text.append(String(localized: "\(dueReviews) reviews due"))
        }

        let selectedTags = tags.count { $0.isStudying }

        if selectedTags > 0 {
            // "Active" rather than a bare count: the tag list below shows every tag, so "1 tag"
            // over a list of two reads as a miscount rather than as the filter it is.
            text.append(", " + String(localized: "\(selectedTags) active tags"))
        }

        // Style text.
        var styledText = AttributedString(text)

        styledText.foregroundColor = .secondary
        styledText.font = .body.weight(.semibold)

        for range in text.ranges(of: /\d+/) {
            let lower = AttributedString.Index(range.lowerBound, within: styledText)!
            let upper = AttributedString.Index(range.upperBound, within: styledText)!

            styledText[lower..<upper].foregroundColor = .primary
            styledText[lower..<upper].font = .body.weight(.bold)
        }

        return styledText
    }
}
