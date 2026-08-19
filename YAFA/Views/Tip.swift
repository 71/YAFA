import SwiftUI

/// A short explanation of a concept, shown in a section's footer where that concept first appears.
///
/// Tips retire themselves: each one is shown only while the screen it sits on says the thing it
/// describes has not been used yet -- "what a link is" while a term has no links, "what a blank is"
/// while none of them is anchored. Nothing counts how much of the app has been seen, so a tip comes
/// back on the next term which needs it, which is where someone learning is most likely to want it
/// again.
///
/// The `showTips` preference turns them all off for the reader who would rather not be told.
///
/// The text is a `LocalizedStringResource` rather than a `LocalizedStringKey`: a key handed to a
/// view of our own is only a key once it reaches `Text`, and string extraction does not follow it
/// that far, so the tips would ship as English literals in every language.
struct Tip: View {
    private let text: Content

    @Environment(\.showTips) private var showTips

    private enum Content {
        case plain(LocalizedStringResource)
        case attributed(AttributedString)
    }

    init(_ text: LocalizedStringResource) {
        self.text = .plain(text)
    }

    /// A tip whose sentence quotes something from the screen, with the quoted part emphasised so
    /// the two can be told apart. Build it with ``Tip/init(_:quoting:)`` rather than assembling an
    /// `AttributedString` at the call site.
    ///
    /// Labelled rather than overloading `init(_:)`: `LocalizedStringResource` and
    /// `AttributedString` are both expressible by a string literal, so the two would be ambiguous
    /// at every call site which passes one.
    init(attributed text: AttributedString) {
        self.text = .attributed(text)
    }

    /// A tip which names something on screen, set apart from the sentence around it.
    ///
    /// The quotes belong in the sentence, not here: French sets off a quotation with guillemets and
    /// Korean often with corner brackets or nothing at all, so which marks to use -- and whether to
    /// use any -- is the translator's call, the same as the words are.
    ///
    /// `text` holds `$1` where the name goes, written into the literal itself rather than
    /// interpolated -- interpolating makes the resource a format string, so extraction would record
    /// `%@` while the lookup at runtime asks for the token, and the two would never meet. `value`
    /// is dropped in at that spot. Substituting a token rather than interpolating and searching afterwards: a sentence
    /// which quotes a term may contain that term's own words elsewhere in it, and a translator may
    /// move or reword around the value, neither of which a search can tell apart. The token is
    /// exactly one thing in exactly one place.
    ///
    /// Built by hand rather than by writing `*\(value)*` and letting `AttributedString(localized:)`
    /// parse it, which runs a markdown parser on every use to produce the one attribute set here.
    /// - Parameter font: The text style the tip is drawn in, which the emphasised value has to be
    ///   given too. Emphasis can only be asked for as a whole font -- no attribute carries weight
    ///   or slant on its own -- so a run which does not name the surrounding style would come out
    ///   at a size of its own.
    init(_ text: LocalizedStringResource, value: String, font: Font = .body) {
        self.init(text, values: [value], font: font)
    }

    /// A tip which names more than one thing, `$1` and `$2` standing for them in order.
    ///
    /// Numbered rather than positional so a translation can put them in whichever order its
    /// grammar wants -- the sentence about a link's direction names both ends, and which comes
    /// first is not the same question in every language.
    init(_ text: LocalizedStringResource, values: [String], font: Font = .body) {
        var string = AttributedString(localized: text)

        for (index, value) in values.enumerated() {
            let placeholder = Self.valuePlaceholder(index)

            // Every occurrence, not just the first: a sentence describing a pair may well name both
            // ends twice, once in each order. Searching only what is left after each replacement,
            // so a value which itself contains the token -- a term someone named "$1" -- is not
            // found again in the text just written.
            var searched = string.startIndex..<string.endIndex

            while let range = string[searched].range(of: placeholder) {
                var replacement = AttributedString(value)

                // Weight rather than slant: most Korean faces have no italic, and CoreText does
                // not synthesise an oblique for Hangul, so an italicised term simply came out
                // looking unstyled -- in the language this app is most likely to be holding terms
                // in. Bold exists in every face the app can be asked to draw.
                //
                // `font` rather than `inlinePresentationIntent`: the latter is what Foundation's
                // markdown parser records for a converter to act on later, and `Text` draws
                // straight past it. Emphasis has to be asked for in SwiftUI's own attribute scope.
                //
                // It renders in a preview but not in a menu item, whose label is drawn with a font
                // of its own -- which is why the sentences quote their values as well as
                // emphasising them, so they read as quotations wherever the styling is dropped.
                replacement.font = font.bold()
                string.replaceSubrange(range, with: replacement)

                // `replaceSubrange` invalidates indices past the edit, so the remaining span is
                // measured from the start rather than carried over.
                let consumed = string.characters.distance(
                    from: string.startIndex,
                    to: range.lowerBound
                ) + value.count

                let resumeAt = string.index(string.startIndex, offsetByCharacters: consumed)

                searched = resumeAt..<string.endIndex
            }
        }

        self.text = .attributed(string)
    }

    /// What ``Tip/init(_:values:font:)`` replaces with the value at `index`.
    ///
    /// Visible and typeable, so a translator can see what has to survive into their sentence and
    /// put it back if they move it. Not `%1`, which lives in the same space as the format
    /// specifiers a strings file already gives meaning to; `$` has no such role here.
    ///
    /// Not for interpolating into a tip's text -- see ``Tip/init(_:value:)`` -- only for finding it
    /// again once the string has been loaded.
    private static func valuePlaceholder(_ index: Int) -> String { "$\(index + 1)" }

    var body: some View {
        if showTips {
            switch text {
            case .plain(let resource): Text(resource)
            case .attributed(let string): Text(string)
            }
        }
    }
}
