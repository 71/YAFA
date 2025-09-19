import SwiftUI

/// A button whose foreground/background colors are negated when toggled on.
struct ToggleButton<Label: View, Shape: InsettableShape>: View {
    let label: () -> Label
    let shape: Shape

    let on: Bool
    let toggled: (Bool) -> Void

    init(
        label: @autoclosure @escaping () -> Label,
        shape: Shape,
        on: Bool,
        toggled: @escaping (Bool) -> Void
    ) {
        self.label = label
        self.shape = shape
        self.on = on
        self.toggled = toggled
    }

    var body: some View {
        Button {
            toggled(!on)
        } label: {
            if on {
                label()
                    .foregroundStyle(.background)
                    .background(.primary, in: shape)
                    .background(.ultraThinMaterial, in: shape)
            } else {
                label()
                    .foregroundStyle(.primary)
                    .background(.thinMaterial, in: shape)
            }
        }
        .padding(0)
    }
}
