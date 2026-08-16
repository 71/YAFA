import SwiftUI

/// When something is next due, as a relative phrase: "Due in 3 days", "Due 2 hours ago".
///
/// A relative phrase reads better than a timestamp wherever the exact moment isn't the point: what
/// matters when scanning a list is how far off a review is, not the wall-clock time it lands on.
struct RelativeDueText: View {
    let date: Date

    /// How often the phrase is recomputed. A minute is enough: the phrasing is never finer than
    /// that, since anything closer reads as "Due now".
    private static let tick: TimeInterval = 60

    @State private var now = Date.now
    @State private var timer = Timer.publish(every: tick, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Self.text(for: date, now: now))
            .contentTransition(.numericText())
            .onReceive(timer) { now = $0 }
    }

    static func text(for date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()

        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full

        // Within a minute either way the relative phrasing turns into "in 0 seconds", so treat
        // that as simply due.
        guard abs(date.timeIntervalSince(now)) >= tick else {
            return String(localized: "Due now")
        }

        // "Due" in both directions: the relative phrase already says which way it points ("in 3
        // days" against "3 days ago"), so "overdue ... ago" would say it twice.
        return String(localized: "Due \(formatter.localizedString(for: date, relativeTo: now))")
    }
}
