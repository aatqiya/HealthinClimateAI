import Foundation

enum ProfileTags {
    static let maximumCount = 25
    static func adding(_ raw: String, to values: [String]) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, values.count < maximumCount, !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return values }
        return values + [value]
    }
}
