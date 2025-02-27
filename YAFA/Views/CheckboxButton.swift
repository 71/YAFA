import SwiftUI

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
