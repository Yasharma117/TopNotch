import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - TeleprompterSection

struct TeleprompterSection {
    let text: String
    let pauseAfter: TimeInterval
    let wordCount: Int
}

// MARK: - ParsedScript

struct ParsedScript {
    let title: String?
    let sections: [TeleprompterSection]
    let totalWords: Int
    let totalPauseDuration: TimeInterval

    /// Estimated speaking duration at the given words-per-minute rate, plus pauses.
    func estimatedDuration(wpm: Double = 150) -> TimeInterval {
        guard totalWords > 0 else { return totalPauseDuration }
        return (Double(totalWords) / wpm) * 60.0 + totalPauseDuration
    }

    static let empty = ParsedScript(title: nil, sections: [], totalWords: 0, totalPauseDuration: 0)
}

// MARK: - SectionParser

enum SectionParser {
    /// Regex matching a section break line: `---` optionally followed by `Ns`
    private static let breakPattern = try! NSRegularExpression(
        pattern: #"^\s*---(?:\s+(\d+)s)?\s*$"#,
        options: []
    )

    static let defaultPauseDuration: TimeInterval = 2.0

    /// Extracts the optional title and body from pre-normalized (LF only) text.
    /// The first non-empty line is treated as a title if it is ≤48 chars and
    /// body text follows; otherwise the entire text is returned as body.
    static func extractTitleAndBody(from text: String) -> (title: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard let firstContentIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return (nil, text)
        }
        let firstLine = lines[firstContentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = Array(lines.dropFirst(firstContentIndex + 1))
        let hasBody = remaining.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if firstLine.count <= 48 && hasBody {
            let bodyText = remaining
                .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                .joined(separator: "\n")
            return (firstLine, bodyText)
        }
        return (nil, text)
    }

    /// Parse raw teleprompter text into a structured ParsedScript.
    static func parse(_ text: String) -> ParsedScript {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }

        let (title, bodyText) = extractTitleAndBody(from: normalized)
        let bodyLines = bodyText.components(separatedBy: "\n")

        // Split body into sections on `---` lines
        var sections: [TeleprompterSection] = []
        var currentLines: [String] = []

        for line in bodyLines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = breakPattern.firstMatch(in: line, range: range) {
                // Found a section break — finalize current section
                let sectionText = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let pauseDuration: TimeInterval
                if let durationRange = Range(match.range(at: 1), in: line) {
                    pauseDuration = TimeInterval(line[durationRange]) ?? defaultPauseDuration
                } else {
                    pauseDuration = defaultPauseDuration
                }

                if !sectionText.isEmpty {
                    sections.append(TeleprompterSection(
                        text: sectionText,
                        pauseAfter: pauseDuration,
                        wordCount: countWords(in: sectionText)
                    ))
                }
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        // Final section (no pause after)
        let finalText = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            sections.append(TeleprompterSection(
                text: finalText,
                pauseAfter: 0,
                wordCount: countWords(in: finalText)
            ))
        }

        let totalWords = sections.reduce(0) { $0 + $1.wordCount }
        let totalPause = sections.reduce(0.0) { $0 + $1.pauseAfter }

        return ParsedScript(
            title: title,
            sections: sections,
            totalWords: totalWords,
            totalPauseDuration: totalPause
        )
    }

    /// Count speakable words in text (matches TeleprompterTextMatcher normalization).
    static func countWords(in text: String) -> Int {
        let lowered = text.lowercased()
        let stripped = lowered.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: "",
            options: .regularExpression
        )
        return stripped.split(separator: " ").filter { !$0.isEmpty }.count
    }

    /// Check if raw text contains any section break markers.
    static func containsSectionBreaks(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        return lines.contains { line in
            let range = NSRange(line.startIndex..., in: line)
            return breakPattern.firstMatch(in: line, range: range) != nil
        }
    }

}

// MARK: - Time Formatting

extension ParsedScript {
    /// Format a duration as "~Xm Ys" for display.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 {
            return "~\(total)s"
        }
        let mins = total / 60
        let secs = total % 60
        if secs == 0 {
            return "~\(mins)m"
        }
        return "~\(mins)m \(secs)s"
    }

    /// Format remaining time as "Xm Ys" (no tilde, used during countdown).
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        let mins = total / 60
        let secs = total % 60
        if secs == 0 {
            return "\(mins)m"
        }
        return "\(mins)m \(secs)s"
    }
}
