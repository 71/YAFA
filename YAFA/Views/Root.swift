import SwiftUI

struct RootView: View {
    static let stateColors = determineOkNotOkColors()

    @State private var stateColor = Self.stateColors.ok

    var body: some View {
        NavigationStack {
            // Use a GeometryReader to compute large sizes for the cards.
            GeometryReader { geometry in
                StudyView(height: geometry.size.height, stateColor: $stateColor)
            }
        }
        .tint(stateColor)
    }
}

#Preview {
    RootView().modelContainer(previewModelContainer())
}

/// Determine the OK and NOT OK button colors for the current system / app configuration.
private func determineOkNotOkColors() -> (ok: Color, notOk: Color) {
    // Different cultures have different colors that represent "good" / "bad". Trying to express
    // this as a short function is bound to produce errors, so this function is definitely a "best
    // effort" function more here to say "hey, we should try to be correct", rather than
    // attempting to be perfect. A couple of things to keep in mind:
    //
    // 1. Different _cultures_ use different colors differently; not different _languages_ or
    //    _regions_.
    // 2. The user's app language may be different from their device language, which may not
    //    match where they live, which may not match their culture.
    //
    // For now, we use the _preferred app language_ and map it to this answer:
    // https://graphicdesign.stackexchange.com/a/118989.
    let languageCode =
        if let preferredLocalization = Bundle.main.preferredLocalizations.first
        {
            Locale(identifier: preferredLocalization).language.languageCode
        } else {
            Locale.autoupdatingCurrent.language.languageCode
        }

    // https://www.loc.gov/standards/iso639-2/php/English_list.php
    return switch languageCode {
    // Chinese, Japanese
    case "ja", "zh": (.red, .green)
    // Korean
    case "ko": (.red, .blue)
    default: (.green, .red)
    }
}
