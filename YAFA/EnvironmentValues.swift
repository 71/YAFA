import SwiftUI

extension EnvironmentValues {
    @Entry var useSimplePrompt: Bool = true

    /// Whether the short explanations of links, blanks, and tags are shown where those concepts
    /// first appear.
    ///
    /// Each tip is written to retire itself -- the one saying what a link is only shows on a term
    /// which has none -- so this exists for the reader who finds them noisy anyway, not as the
    /// mechanism which makes them go away.
    @Entry var showTips: Bool = true

    /// Opens a term from a row which cannot itself be a `NavigationLink` -- because it holds a text
    /// field, or because a nested link would draw a second disclosure chevron.
    @Entry var openTerm: OpenTermAction = .init()
}

/// Action for `openTerm` above, used since storing a closure can lead to unexpected re-renders.
struct OpenTermAction {
    let action: (TermDestination) -> ()

    init(_ action: @escaping (TermDestination) -> () = { _ in }) {
        self.action = action
    }

    func callAsFunction(_ destination: TermDestination) {
        action(destination)
    }
}
