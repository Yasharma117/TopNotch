import Foundation
import NaturalLanguage

// MARK: - TextArrangementEngine

/// Analyzes teleprompter text using on-device NLP and inserts `---` section
/// break markers at natural pause points. Adapts section length to the user's
/// speaking speed. No network calls or API keys required.
enum TextArrangementEngine {

    // MARK: - Public API

    /// Arrange raw script text into sections with `---` pause markers.
    /// - Parameters:
    ///   - text: The raw teleprompter script.
    ///   - speed: Teleprompter speed (10–120). Higher → longer sections.
    /// - Returns: The text with `---` markers inserted at natural break points.
    static func arrange(_ text: String, speed: Double) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        // Strip any existing section break markers
        let stripped = stripExistingBreaks(normalized)
        guard !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }

        // Extract title (same heuristic as SectionParser)
        let (title, body) = extractTitle(from: stripped)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }

        // Tokenize into sentences
        let sentences = tokenizeSentences(body)
        guard sentences.count > 1 else { return text }

        // Score gaps between sentences and decide where to break
        let targetWords = targetWordsPerSection(speed: speed)
        let breaks = computeBreaks(sentences: sentences, body: body, targetWords: targetWords)

        // Reassemble with markers
        return reassemble(title: title, sentences: sentences, breaks: breaks)
    }

    // MARK: - Preprocessing

    private static let breakPattern = try! NSRegularExpression(
        pattern: #"^\s*---(?:\s+\d+s)?\s*$"#,
        options: .anchorsMatchLines
    )

    private static func stripExistingBreaks(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = breakPattern.stringByReplacingMatches(
            in: text, range: range, withTemplate: ""
        )
        // Clean up runs of 3+ newlines left behind
        return stripped.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression
        )
    }

    private static func extractTitle(from text: String) -> (title: String?, body: String) {
        SectionParser.extractTitleAndBody(from: text)
    }

    // MARK: - Sentence Tokenization

    private static func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sentences.append(trimmed)
            }
            return true
        }
        return sentences
    }

    // MARK: - Break Point Scoring

    private struct BreakDecision {
        let afterSentenceIndex: Int
        let pauseDuration: Int  // seconds
    }

    private static func computeBreaks(
        sentences: [String],
        body: String,
        targetWords: Double
    ) -> [BreakDecision] {
        var breaks: [BreakDecision] = []
        var wordsSinceLastBreak = 0

        // Pre-compute noun sets for topic shift detection
        let nounSets = sentences.map { extractNouns($0) }

        for i in 0..<(sentences.count - 1) {
            let currentWords = SectionParser.countWords(in: sentences[i])
            wordsSinceLastBreak += currentWords

            var score = 0
            var maxPause = 1  // default breathing pause

            // Factor 1: Paragraph boundary
            if hasParagraphBoundary(after: sentences[i], before: sentences[i + 1], in: body) {
                score += 10
                maxPause = max(maxPause, 3)
            }

            // Factor 2: Word count exceeds target
            if Double(wordsSinceLastBreak) > targetWords {
                score += 6
            }
            // Factor 2b: Hard break at 1.5× target
            if Double(wordsSinceLastBreak) > targetWords * 1.5 {
                score += 10
            }

            // Factor 3: Sentence ends with ? or !
            let trimmedCurrent = sentences[i].trimmingCharacters(in: .whitespaces)
            if trimmedCurrent.hasSuffix("?") || trimmedCurrent.hasSuffix("!") {
                score += 3
                maxPause = max(maxPause, 2)
            }

            // Factor 4: Next sentence starts with transition word
            if startsWithTransitionWord(sentences[i + 1]) {
                score += 4
                maxPause = max(maxPause, 2)
            }

            // Factor 5: Topic shift (low noun overlap)
            if i < nounSets.count - 1 {
                let similarity = jaccardSimilarity(nounSets[i], nounSets[i + 1])
                if similarity < 0.15 && !nounSets[i].isEmpty {
                    score += 3
                    maxPause = max(maxPause, 2)
                }
            }

            // Insert break if score meets threshold
            if score >= 6 {
                breaks.append(BreakDecision(
                    afterSentenceIndex: i,
                    pauseDuration: maxPause
                ))
                wordsSinceLastBreak = 0
            }
        }

        return breaks
    }

    // MARK: - Scoring Helpers

    private static func hasParagraphBoundary(after current: String, before next: String, in body: String) -> Bool {
        // Find where the current sentence ends and next begins in the original body
        guard let currentRange = body.range(of: current),
              let nextRange = body.range(of: next, range: currentRange.upperBound..<body.endIndex) else {
            return false
        }
        let gap = String(body[currentRange.upperBound..<nextRange.lowerBound])
        return gap.contains("\n\n")
    }

    private static let transitionWords: Set<String> = [
        "however", "meanwhile", "next", "now", "furthermore", "moreover",
        "additionally", "therefore", "consequently", "finally", "alternatively",
        "nevertheless", "first", "second", "third", "lastly", "but", "yet",
        "another", "also", "then", "instead", "regardless", "nonetheless",
        "so", "moving", "let's", "in", "on", "to", "for"
    ]

    /// Two-word transition phrases (checked as "word1 word2").
    private static let transitionPhrases: Set<String> = [
        "in addition", "in conclusion", "on the other hand", "to summarize",
        "moving on", "for example", "in fact", "as a result"
    ]

    private static func startsWithTransitionWord(_ sentence: String) -> Bool {
        let words = sentence.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard let firstWord = words.first else { return false }

        if transitionWords.contains(firstWord) { return true }

        // Check two-word phrases
        if words.count >= 2 {
            let twoWord = "\(words[0]) \(words[1])"
            if transitionPhrases.contains(twoWord) { return true }
        }

        return false
    }

    // MARK: - Topic Shift Detection (NLTagger)

    private static func extractNouns(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var nouns: Set<String> = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, range in
            if let tag = tag, tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName {
                nouns.insert(String(text[range]).lowercased())
            }
            return true
        }
        return nouns
    }

    private static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Speed Adaptation

    private static func targetWordsPerSection(speed: Double) -> Double {
        let baseWords: Double = 45
        let scaleFactor: Double = 0.5
        return max(20, baseWords + (speed - 40) * scaleFactor)
    }

    // MARK: - Reassembly

    private static func reassemble(
        title: String?,
        sentences: [String],
        breaks: [BreakDecision]
    ) -> String {
        let breakIndices = Set(breaks.map(\.afterSentenceIndex))
        let breakMap = Dictionary(uniqueKeysWithValues: breaks.map { ($0.afterSentenceIndex, $0.pauseDuration) })

        var sections: [String] = []
        var currentSection: [String] = []

        for (i, sentence) in sentences.enumerated() {
            currentSection.append(sentence)

            if breakIndices.contains(i) {
                let sectionText = currentSection.joined(separator: " ")
                let pause = breakMap[i] ?? 2
                sections.append(sectionText)
                sections.append("--- \(pause)s")
                currentSection = []
            }
        }

        // Final section (no break after)
        if !currentSection.isEmpty {
            sections.append(currentSection.joined(separator: " "))
        }

        var result = ""
        if let title = title {
            result = title + "\n\n"
        }
        result += sections.joined(separator: "\n\n")
        return result
    }
}
