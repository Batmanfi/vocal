import Foundation

/// Converts spelled-out English numbers in dictated text into digits.
/// e.g. "twenty" -> "20", "twenty-five" -> "25", "one hundred twenty three" -> "123".
/// Handles cardinals up to the billions; leaves all other words untouched.
enum NumberWordConverter {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    private static func isNumberWord(_ w: String) -> Bool {
        units[w] != nil || tens[w] != nil || scales[w] != nil
    }

    /// Splits a raw token into (leadingPunct, core, trailingPunct), lowercasing the core.
    private static func split(_ token: String) -> (lead: String, core: String, trail: String) {
        let chars = Array(token)
        var start = 0
        var end = chars.count
        while start < end, !chars[start].isLetter && !chars[start].isNumber { start += 1 }
        while end > start, !chars[end - 1].isLetter && !chars[end - 1].isNumber { end -= 1 }
        let lead = String(chars[0..<start])
        let core = String(chars[start..<end]).lowercased()
        let trail = String(chars[end..<chars.count])
        return (lead, core, trail)
    }

    /// A token is "numeric" if every hyphen-separated part is a number word (twenty-five).
    private static func numberParts(_ core: String) -> [String]? {
        guard !core.isEmpty else { return nil }
        let parts = core.split(separator: "-").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(isNumberWord) else { return nil }
        return parts
    }

    private static func value(of words: [String]) -> Int {
        var total = 0
        var current = 0
        for w in words {
            if let u = units[w] {
                current += u
            } else if let t = tens[w] {
                current += t
            } else if let s = scales[w] {
                if s >= 1000 {
                    total += (current == 0 ? 1 : current) * s
                    current = 0
                } else { // hundred
                    current = (current == 0 ? 1 : current) * s
                }
            }
        }
        return total + current
    }

    static func convert(_ text: String) -> String {
        let tokens = text.components(separatedBy: " ")
        var output: [String] = []
        var i = 0

        while i < tokens.count {
            let token = tokens[i]
            if token.isEmpty { output.append(token); i += 1; continue }

            let (lead, core, trail) = split(token)
            guard let firstParts = numberParts(core) else {
                output.append(token)
                i += 1
                continue
            }

            // Start a run of number words (with "and" allowed only between them).
            var runWords = firstParts
            let runLead = lead
            var runTrail = trail
            var j = i + 1
            var pendingAnd = false

            // If the first token already had trailing punctuation, the run ends here.
            if trail.isEmpty {
                while j < tokens.count {
                    let (l2, c2, t2) = split(tokens[j])
                    if c2 == "and", l2.isEmpty {
                        pendingAnd = true
                        j += 1
                        continue
                    }
                    if !l2.isEmpty { break } // punctuation before this token ends the run
                    if let parts = numberParts(c2) {
                        runWords.append(contentsOf: parts)
                        runTrail = t2
                        pendingAnd = false
                        j += 1
                        if !t2.isEmpty { break } // trailing punctuation ends the run
                    } else {
                        break
                    }
                }
            }

            // A sequence of single digits (e.g. a phone number "five five five …") should
            // be concatenated, preserving leading zeros — not summed like a number phrase.
            let numberString: String
            if runWords.count > 1, runWords.allSatisfy({ (units[$0] ?? 99) <= 9 }) {
                numberString = runWords.map { String(units[$0]!) }.joined()
            } else {
                numberString = String(value(of: runWords))
            }
            output.append("\(runLead)\(numberString)\(runTrail)")
            i = j
            if pendingAnd { output.append("and") }
        }

        return output.joined(separator: " ")
    }
}
