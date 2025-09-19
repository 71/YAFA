// Raw translation of
// https://github.com/71/study-korean/blob/c4f3de22cd433c045458198956031f6edbb54f13/app/src/utils/korean.ts

/// A Korean syllable.
public struct KoreanSyllable: CustomStringConvertible {
    public let initialJamo: UnicodeScalar
    public let medialJamo: UnicodeScalar
    public let finalJamo: UnicodeScalar?

    /// Converts a Korean syllable such as 김 to its jamo ㄱㅣㅁ.
    public init?(_ syllable: Character) {
        guard let scalar = syllable.unicodeScalars.first, syllable.unicodeScalars.count == 1 else {
            return nil
        }

        self.init(scalar)
    }

    /// Converts a Korean syllable such as 김 to its jamo ㄱㅣㅁ.
    public init?(_ syllable: UnicodeScalar) {
        guard syllable.isKoreanSyllable else { return nil }

        let x = Int(syllable.value) - syllableBase
        let initialIndex = x / 28 / 21
        let medialIndex = (x / 28) % 21
        let finalIndex = x % 28

        initialJamo = initial[initialIndex]!
        medialJamo = medial[medialIndex]!
        finalJamo = finalIndex == 0 ? nil : final[finalIndex - 1]
    }

    /// The jamo making up the syllable.
    public var description: String {
        if let finalJamo {
            "\(initialJamo)\(medialJamo)\(finalJamo)"
        } else {
            "\(initialJamo)\(medialJamo)"
        }
    }
}

extension StringProtocol {
    /// Returns `self` with Korean syllables replaced by their Jamo.
    ///
    /// In theory, `self.decomposedStringWithCompatibilityMapping` could do the trick. However, the
    /// point of this function is search, such that "ㄱ" is a prefix of "김". But the typed ㄱ (U+3131
    /// in Hangul Compatibility Jamo) is different from the decomposed ᄀ (U+1100 in Hangul Jamo),
    /// so a prefix search yields nothing. As such, we instead use the custom logic below.
    public func withDecomposedKoreanSyllables() -> String {
        var result = ""

        for scalar in unicodeScalars {
            if let syllable = KoreanSyllable(scalar) {
                result.unicodeScalars.append(syllable.initialJamo)
                result.unicodeScalars.append(syllable.medialJamo)

                if let finalJamo = syllable.finalJamo {
                    result.unicodeScalars.append(finalJamo)
                }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }
}

extension Character {
    /// Whether this character is a Korean syllable such as 김.
    public var isKoreanSyllable: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }

        return scalar.isKoreanSyllable
    }
}

extension UnicodeScalar {
    /// Whether this Unicode scalar is a Korean syllable such as 김.
    public var isKoreanSyllable: Bool {
        value >= 0xac00 && value <= 0xd7a3
    }
}

/// First Unicode scalar representing a Korean syllable.
private let syllableBase = 0xac00

private let initial = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".utf16.map { UnicodeScalar($0) }
private let medial = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".utf16.map { UnicodeScalar($0) }
private let final = "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".utf16.map { UnicodeScalar($0) }
