import Foundation

public struct SemanticVersion: Sendable, Comparable {
    public let raw: String
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public var stable: Bool { prerelease.isEmpty }

    public init?(_ raw: String) {
        let pattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let majorRange = Range(match.range(at: 1), in: raw), let major = Int(raw[majorRange]),
              let minorRange = Range(match.range(at: 2), in: raw), let minor = Int(raw[minorRange]),
              let patchRange = Range(match.range(at: 3), in: raw), let patch = Int(raw[patchRange]) else { return nil }
        let prerelease = Range(match.range(at: 4), in: raw).map { raw[$0].split(separator: ".").map(String.init) } ?? []
        guard !prerelease.contains(where: { $0.allSatisfy(\.isNumber) && $0.count > 1 && $0.first == "0" }) else { return nil }
        self.raw = raw; self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.stable || rhs.stable { return !lhs.stable && rhs.stable }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = left.allSatisfy(\.isNumber), rightNumeric = right.allSatisfy(\.isNumber)
            if leftNumeric != rightNumeric { return leftNumeric }
            if leftNumeric { return left.count != right.count ? left.count < right.count : left < right }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
