import Foundation
import Combine

final class TeleprompterTextMatcher: ObservableObject {
    private var fullText: String = ""
    var words: [String] = []
    private var lastMatchedIndex: Int = 0
    
    // Configuration - optimized for accent tolerance
    private let fuzzyThreshold: Double = 0.65 // 65% similarity (looser for accents)
    private let searchWindow: Int = 30 // Search ±30 words from last position
    private var lastMatchedScore: Double = 0 // Score at current position for hysteresis
    
    // MARK: - Setup
    
    func setText(_ text: String) {
        fullText = text
        words = normalizeText(text).components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        lastMatchedIndex = 0
    }
    
    // MARK: - Matching
    
    func findPosition(for spokenPhrase: String) -> TextPosition? {
        guard !words.isEmpty else { return nil }
        
        let spokenWords = normalizeText(spokenPhrase)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard !spokenWords.isEmpty else { return nil }
        
        // Search window around last known position
        let searchStart = max(0, lastMatchedIndex - searchWindow)
        let searchEnd = min(words.count, lastMatchedIndex + searchWindow)
        
        var bestMatch: (index: Int, score: Double) = (0, 0.0)
        
        // Sliding window search
        for i in searchStart..<searchEnd {
            let endIndex = min(i + spokenWords.count, words.count)
            let windowWords = Array(words[i..<endIndex])
            
            let score = calculateSimilarity(spokenWords, windowWords)
            
            if score > bestMatch.score && score >= fuzzyThreshold {
                bestMatch = (i, score)
            }
        }
        
        // Update last matched position with hysteresis:
        // Only move backward if the score improvement is significant (genuine correction).
        // This prevents oscillation between two close-scoring positions.
        if bestMatch.score >= fuzzyThreshold {
            let isForward = bestMatch.index >= lastMatchedIndex
            let isSignificantCorrection = !isForward && (bestMatch.score - lastMatchedScore) > 0.15
            if isForward || isSignificantCorrection {
                lastMatchedIndex = bestMatch.index
                lastMatchedScore = bestMatch.score
            }

            return TextPosition(
                wordIndex: lastMatchedIndex,
                characterOffset: calculateCharacterOffset(for: lastMatchedIndex),
                matchedWordCount: spokenWords.count,
                confidence: bestMatch.score
            )
        }
        
        return nil
    }
    
    // MARK: - Similarity Calculation
    
    private func calculateSimilarity(_ spoken: [String], _ written: [String]) -> Double {
        guard !spoken.isEmpty && !written.isEmpty else { return 0.0 }
        
        let minCount = min(spoken.count, written.count)
        var matches = 0
        
        for i in 0..<minCount {
            if fuzzyWordMatch(spoken[i], written[i]) {
                matches += 1
            }
        }
        
        return Double(matches) / Double(minCount)
    }
    
    private func fuzzyWordMatch(_ word1: String, _ word2: String) -> Bool {
        // Exact match
        if word1 == word2 { return true }
        
        // Check phonetic similarity (for Indian accent variations)
        if soundsLike(word1, word2) { return true }
        
        // Levenshtein distance
        let distance = levenshteinDistance(word1, word2)
        let maxLength = max(word1.count, word2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        
        return similarity >= 0.75 // 75% character similarity
    }
    
    // MARK: - Phonetic Matching (Indian Accent Support)
    
    private func soundsLike(_ word1: String, _ word2: String) -> Bool {
        // Common Indian English pronunciation variations
        let variations: [(String, String)] = [
            ("v", "w"),   // "very" → "wery"
            ("w", "v"),   // reverse
            ("th", "t"),  // "three" → "tree"
            ("th", "d"),  // "this" → "dis"
            ("z", "j"),   // "zero" → "jero"
            ("s", "sh"),  // "sit" → "shit" (common variation)
            ("sh", "s"),  // reverse
        ]
        
        var normalized1 = word1
        var normalized2 = word2
        
        for (from, to) in variations {
            normalized1 = normalized1.replacingOccurrences(of: from, with: to)
            normalized2 = normalized2.replacingOccurrences(of: from, with: to)
        }
        
        return normalized1 == normalized2
    }
    
    // MARK: - Helper Functions
    
    private func normalizeText(_ text: String) -> String {
        text.lowercased()
            // Handle British/Indian spellings
            .replacingOccurrences(of: "colour", with: "color")
            .replacingOccurrences(of: "favour", with: "favor")
            .replacingOccurrences(of: "honour", with: "honor")
            // Remove punctuation
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            // Handle common contractions
            .replacingOccurrences(of: "won't", with: "will not")
            .replacingOccurrences(of: "can't", with: "cannot")
            .replacingOccurrences(of: "don't", with: "do not")
    }
    
    private func calculateCharacterOffset(for wordIndex: Int) -> Int {
        words.prefix(wordIndex).reduce(0) { $0 + $1.count + 1 } // +1 for spaces
    }
    
    func characterLength(for wordIndex: Int, count: Int) -> Int {
        let endIdx = min(wordIndex + count, words.count)
        return words[wordIndex..<endIdx].reduce(0) { $0 + $1.count + 1 }
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        var distances = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)
        
        for i in 0...s1.count {
            distances[i][0] = i
        }
        for j in 0...s2.count {
            distances[0][j] = j
        }
        
        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                distances[i][j] = min(
                    distances[i - 1][j] + 1,
                    distances[i][j - 1] + 1,
                    distances[i - 1][j - 1] + cost
                )
            }
        }
        
        return distances[s1.count][s2.count]
    }
    
    func reset() {
        lastMatchedIndex = 0
        lastMatchedScore = 0
    }
}

// MARK: - Models

struct TextPosition {
    let wordIndex: Int
    let characterOffset: Int
    let matchedWordCount: Int
    let confidence: Double
}
