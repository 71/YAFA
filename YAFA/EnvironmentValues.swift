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
    @Entry var openTerm: (TermDestination) -> Void = { _ in }
}
