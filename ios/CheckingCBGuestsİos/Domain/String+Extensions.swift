import Foundation

extension String {

    /// Firestore kırmızı liste anahtarları ile uyumlu misafir adı normalizasyonu.
    /// Android `normalizeGuestName` ile birebir aynı dönüşüm sırası ve kuralları.
    func normalizeGuestName() -> String {
        guard !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        var result = trimmingCharacters(in: .whitespacesAndNewlines)
        let turkishMappings: [(String, String)] = [
            ("İ", "i"), ("I", "i"), ("ı", "i"),
            ("Ğ", "g"), ("ğ", "g"),
            ("Ü", "u"), ("ü", "u"),
            ("Ş", "s"), ("ş", "s"),
            ("Ö", "o"), ("ö", "o"),
            ("Ç", "c"), ("ç", "c"),
        ]
        for (from, to) in turkishMappings {
            result = result.replacingOccurrences(of: from, with: to)
        }

        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
            )
        }

        return result.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
