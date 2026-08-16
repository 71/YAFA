import SwiftUI

extension EnvironmentValues {
    @Entry var useSimplePrompt: Bool = true

    /// Opens a term from a row which cannot itself be a `NavigationLink` -- because it holds a text
    /// field, or because a nested link would draw a second disclosure chevron.
    @Entry var openTerm: (TermDestination) -> Void = { _ in }
}
