import Combine
import SwiftUI

extension View {
    /// Adds a checkmark to the navigation bar while a field is being edited, dismissing the
    /// keyboard, and hides `whileIdle` -- the screen's own toolbar items -- for as long as it shows.
    ///
    /// Edits here are saved as they are typed, so there is nothing to confirm and no natural moment
    /// at which the keyboard goes away on its own. Swiping the list down also dismisses it, but that
    /// is easy to miss; this gives the gesture a visible counterpart, the way Reminders does while
    /// a reminder is being edited.
    ///
    /// The screen's own actions are passed in rather than declared separately so that they can be
    /// swapped for the checkmark: a destructive button beside a focused field reads as though it
    /// might apply to the field rather than to the thing being edited.
    /// - Parameter enabled: Whether the button should appear at all. A screen with a field of its
    ///   own which is *not* meant to get one -- a search bar, say -- passes `false` while that one
    ///   holds the keyboard.
    func dismissKeyboardToolbar(
        enabled: Bool = true,
        @ViewBuilder whileIdle: @escaping () -> some View = { EmptyView() }
    ) -> some View {
        modifier(DismissKeyboardToolbar(enabled: enabled, whileIdle: AnyView(whileIdle())))
    }
}

private struct DismissKeyboardToolbar: ViewModifier {
    let enabled: Bool
    let whileIdle: AnyView

    @State private var editing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                // `.primaryAction` rather than `.confirmationAction`, which styles whatever it
                // holds as the screen's affirmative action -- wrong for the destructive button
                // this slot shows the rest of the time.
                ToolbarItem(placement: .primaryAction) {
                    if editing && enabled {
                        // Prominence is put on the button rather than taken from the placement:
                        // `.confirmationAction` would style whatever this slot holds as the
                        // screen's affirmative action, including the destructive button it shows
                        // the rest of the time.
                        Button("Dismiss keyboard", systemImage: "checkmark") { dismissKeyboard() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderedProminent)
                    } else {
                        whileIdle
                    }
                }
            }
            .animation(.default, value: editing && enabled)

            // Tracked from the keyboard itself rather than from a `@FocusState`: the fields which
            // need dismissing are spread across nested views which own their own focus state.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillShowNotification
                )
            ) { _ in
                editing = true
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification
                )
            ) { _ in
                editing = false
            }
    }

}

/// Dismisses the keyboard, whichever field is holding it.
///
/// Resigning first responder rather than clearing a `@FocusState`: the fields which need dismissing
/// are spread across nested views which own their own focus state, and a caller elsewhere in the
/// hierarchy has no way to reach it.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
