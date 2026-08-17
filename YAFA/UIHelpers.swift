import SwiftUI

/// `bindToProperty(of: x, \.prop)` returns a `Binding` which reads from and writes to `x.prop`.
func bindToProperty<T, R>(of value: T, _ keyPath: WritableKeyPath<T, R>)
    -> Binding<R>
{
    Binding {
        value[keyPath: keyPath]
    } set: {
        var value = value
        value[keyPath: keyPath] = $0
    }
}

/// Disable smart quotes: https://stackoverflow.com/a/68432940
extension UITextView {
    open override var frame: CGRect {
        didSet {
            self.smartQuotesType = .no
        }
    }

    /// Whether **Blank** applies to whatever is selected right now, and what it does.
    ///
    /// SwiftUI offers no way to add an item to a text selection's edit menu, and the field which
    /// wants one is a `TextEditor` it does not hand out. So the action is declared on `UITextView`
    /// itself and answered by whichever field last said it could be blanked -- there is one text
    /// selection on screen, so one slot is enough.
    @MainActor static var blankAction: (() -> Void)?

    /// Adds **Blank** to the menu the selection brings up, next to Cut and Copy.
    ///
    /// The menu is built from the responder chain each time it is shown, so this runs with the
    /// selection already in place and can simply leave the item out when there is nothing to blank.
    open override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard let blank = Self.blankAction, isFirstResponder else { return }

        builder.insertSibling(
            UIMenu(
                options: .displayInline,
                children: [
                    UIAction(
                        title: String(
                            localized: "Blank",
                            comment: "Edit menu action which blanks out the selected text."
                        )
                    ) { _ in blank() }
                ]
            ),
            afterMenu: .standardEdit
        )
    }
}

extension View {
    /// Offers **Blank** in the edit menu of whichever selection is live, blanking `range` when it is
    /// chosen. Passing a `nil` range withdraws it.
    func blankEditMenuAction(
        for range: Range<String.Index>?,
        perform: @escaping (Range<String.Index>) -> Void
    ) -> some View {
        modifier(BlankEditMenuAction(range: range, perform: perform))
    }
}

private struct BlankEditMenuAction: ViewModifier {
    let range: Range<String.Index>?
    let perform: (Range<String.Index>) -> Void

    func body(content: Content) -> some View {
        content
            // Keyed on the range rather than on whether there is one: the action closes over what
            // is being blanked, and a stale one would blank the words the selection has left.
            .onChange(of: range, initial: true) {
                UITextView.blankAction = range.map { range in { perform(range) } }
            }
            // The slot is global, so it is given up when this screen goes away -- otherwise the
            // menu would still offer to blank a selection on a screen which is no longer there.
            .onDisappear { UITextView.blankAction = nil }
    }
}
