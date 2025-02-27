import SwiftData
import SwiftUI

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
