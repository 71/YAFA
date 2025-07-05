import SwiftUI

/// A button made up text followed by a checkmark if checked, and nothing if unchecked.
struct CheckboxButton: View {
    let text: String
    let checked: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button(action: { action(!checked) }) {
            if checked {
                Label(text, systemImage: "checkmark")
            } else {
                Text(text)
            }
        }
        .foregroundStyle(.primary)
    }
}
