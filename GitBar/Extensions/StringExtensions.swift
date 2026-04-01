import Foundation

extension String {
    func trunc(length: Int, trailing: String = "…") -> String {
        guard count > length else { return self }
        return String(prefix(length)) + trailing
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

