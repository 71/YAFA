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
}
