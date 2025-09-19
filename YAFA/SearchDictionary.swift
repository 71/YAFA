/// A dictionary from string to a value of type `T`.
///
/// The dictionary is intended for search; it ignores case, diacritics, width, and composed characters.
public struct SearchDictionary<T> {
    private var entries = [(String, T)]()

    public init() {}

    public init<S: StringProtocol>(_ values: some Sequence<T>, by key: (T) -> S) {
        entries.reserveCapacity(entries.underestimatedCount)

        for value in values {
            let rawKey = key(value)
            let normalizedKey = rawKey.withDecomposedKoreanSyllables()

            entries.append((normalizedKey, value))
        }
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public var values: some Sequence<T> {
        entries.lazy.map(\.1)
    }

    /// Returns an iterator over the entries in the dictionary whose key contains `substring`.
    public func including(_ substring: some StringProtocol) -> some Sequence<T> {
        includingImpl(.init(substring))
    }

    /// Returns an iterator over the entries in the dictionary whose key starts with `prefix`.
    public func starting(with prefix: some StringProtocol) -> some Sequence<T> {
        startingImpl(with: .init(prefix))
    }

    private func includingImpl(_ substring: Substring) -> some Sequence<T> {
        let normalizedSubstring = substring.withDecomposedKoreanSyllables()
        let options: String.CompareOptions = [
            .caseInsensitive, .diacriticInsensitive, .widthInsensitive
        ]

        return entries.lazy.compactMap { (k, v) in
            guard k.range(of: normalizedSubstring, options: options) != nil else { return nil }

            return v
        }
    }

    private func startingImpl(with prefix: Substring) -> some Sequence<T> {
        let normalizedPrefix = prefix.withDecomposedKoreanSyllables()
        let options: String.CompareOptions = [
            .anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive
        ]

        return entries.lazy.compactMap { (k, v) in
            // We use `.anchored`, so we don't need to check that the range starts at 0.
            guard k.range(of: normalizedPrefix, options: options) != nil else { return nil }

            return v
        }
    }
}
