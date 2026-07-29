# Smart Teleprompter: Speech-Synchronized Scrolling

## 🎯 Feature Overview

**Goal:** Automatically scroll the teleprompter in sync with the user's speech, eliminating manual scrolling and creating a seamless recording experience.

**User Benefit:** 
- Hands-free teleprompter control
- Perfect pacing (matches actual speech speed)
- No more "catching up" or "waiting" for scroll
- Professional delivery without looking away
- Reduces cognitive load during recording

---

## ✅ Feasibility Analysis

### Is This Possible?
**YES! Absolutely feasible.** ✅

Apple provides excellent on-device speech recognition APIs that make this very achievable:

1. **Speech Framework** - Real-time speech recognition
2. **Natural Language Framework** - Word matching & text processing
3. **AVFoundation** - Audio capture from microphone
4. **On-device processing** - Fast, private, no internet required

### Technical Complexity
- **Difficulty:** Medium
- **Implementation Time:** 4-6 hours
- **External Dependencies:** None (all Apple frameworks)
- **Privacy:** Excellent (100% on-device)

### Platform Requirements
- **macOS 10.15+** (Speech framework)
- **Microphone permission** (already handled)
- **No internet required** (on-device recognition)

---

## 🏗️ Architecture Design

### High-Level Flow

```
User Speaks
    ↓
Microphone Captures Audio
    ↓
Speech Framework → Real-time transcription
    ↓
Word Matching Algorithm
    ├→ Find current position in teleprompter text
    ├→ Calculate scroll position
    └→ Smooth scroll to position
    ↓
Teleprompter Updates (smooth animation)
```

### Components Needed

#### 1. SpeechRecognitionManager
```swift
class SpeechRecognitionManager: ObservableObject {
    @Published var recognizedText: String = ""
    @Published var currentWord: String = ""
    @Published var isListening: Bool = false
    
    func startListening()
    func stopListening()
    func getCurrentWordPosition() -> Int
}
```

#### 2. TeleprompterTextMatcher
```swift
class TeleprompterTextMatcher {
    func findWordPosition(spokenText: String, in fullText: String) -> Int
    func calculateScrollOffset(for position: Int) -> CGFloat
    func fuzzyMatch(spoken: String, written: String) -> Double
}
```

#### 3. Enhanced TeleprompterView
```swift
struct TeleprompterView: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @State private var scrollOffset: CGFloat = 0
    
    // Auto-scroll based on speech
    // Highlight current word/phrase
    // Smooth animations
}
```

---

## 🎯 Implementation Plan

### Phase 1: Speech Recognition Core (2 hours)

#### Step 1: Create SpeechRecognitionManager

**File:** `SpeechRecognitionManager.swift`

```swift
import Speech
import AVFoundation

final class SpeechRecognitionManager: NSObject, ObservableObject {
    // Published properties
    @Published var recognizedText: String = ""
    @Published var currentPhrase: String = ""
    @Published var isListening: Bool = false
    @Published var isAuthorized: Bool = false
    
    // Speech components
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Configuration
    private let locale = Locale(identifier: "en-US") // User configurable
    
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.delegate = self
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authorized = status == .authorized
                Task { @MainActor in
                    self.isAuthorized = authorized
                }
                continuation.resume(returning: authorized)
            }
        }
    }
    
    // MARK: - Listening Control
    
    func startListening() throws {
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.recognitionRequestFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // Privacy!
        
        // Configure audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw SpeechError.audioEngineFailed
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                Task { @MainActor in
                    self.recognizedText = result.bestTranscription.formattedString
                    // Get last spoken phrase (for matching)
                    self.currentPhrase = self.getRecentPhrase(from: result)
                }
            }
            
            if error != nil || result?.isFinal == true {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        Task { @MainActor in
            isListening = true
        }
    }
    
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        
        Task { @MainActor in
            isListening = false
        }
    }
    
    // MARK: - Text Processing
    
    private func getRecentPhrase(from result: SFSpeechRecognitionResult) -> String {
        let words = result.bestTranscription.segments.suffix(5) // Last 5 words
        return words.map { $0.substring }.joined(separator: " ")
    }
    
    func reset() {
        recognizedText = ""
        currentPhrase = ""
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            isAuthorized = available
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case recognitionRequestFailed
    case audioEngineFailed
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .recognitionRequestFailed:
            return "Failed to create speech recognition request"
        case .audioEngineFailed:
            return "Failed to initialize audio engine"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}
```

**Key Features:**
- ✅ Real-time speech recognition
- ✅ On-device processing (privacy!)
- ✅ Partial results (live updates)
- ✅ Recent phrase tracking (last 5 words)
- ✅ Clean start/stop control

---

### Phase 2: Text Matching Algorithm (1.5 hours)

#### Step 2: Create TeleprompterTextMatcher

**File:** `TeleprompterTextMatcher.swift`

```swift
import Foundation

final class TeleprompterTextMatcher {
    private var fullText: String = ""
    private var words: [String] = []
    private var lastMatchedIndex: Int = 0
    
    // Configuration
    private let fuzzyThreshold: Double = 0.7 // 70% similarity required
    private let searchWindow: Int = 50 // Search ±50 words from last position
    
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
        
        // Update last matched position
        if bestMatch.score >= fuzzyThreshold {
            lastMatchedIndex = bestMatch.index
            
            return TextPosition(
                wordIndex: bestMatch.index,
                characterOffset: calculateCharacterOffset(for: bestMatch.index),
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
        
        // Levenshtein distance
        let distance = levenshteinDistance(word1, word2)
        let maxLength = max(word1.count, word2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        
        return similarity >= 0.8 // 80% character similarity
    }
    
    // MARK: - Helper Functions
    
    private func normalizeText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
    }
    
    private func calculateCharacterOffset(for wordIndex: Int) -> Int {
        words.prefix(wordIndex).reduce(0) { $0 + $1.count + 1 } // +1 for spaces
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
    }
}

// MARK: - Models

struct TextPosition {
    let wordIndex: Int
    let characterOffset: Int
    let confidence: Double
}
```

**Key Features:**
- ✅ Fuzzy matching (handles mispronunciations)
- ✅ Windowed search (performance optimization)
- ✅ Levenshtein distance (character similarity)
- ✅ Confidence scoring
- ✅ Progressive tracking (remembers position)

---

### Phase 3: Enhanced Teleprompter View (1.5 hours)

#### Step 3: Update TeleprompterView with Speech Sync

```swift
// Add to TeleprompterView.swift

@ObservedObject var speechManager: SpeechRecognitionManager
@StateObject private var textMatcher = TeleprompterTextMatcher()

@State private var autoScrollEnabled: Bool = false
@State private var highlightedRange: Range<String.Index>?

var body: some View {
    ZStack {
        // ... existing visual effect
        
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    AttributedTextView(
                        text: text,
                        highlightedRange: highlightedRange,
                        onTextLayout: { textHeight in
                            contentHeight = textHeight
                            containerHeight = geo.size.height
                        }
                    )
                    .id("teleprompterText")
                }
                .onChange(of: speechManager.currentPhrase) { _, phrase in
                    if autoScrollEnabled && !phrase.isEmpty {
                        updateScrollPosition(phrase: phrase, proxy: proxy)
                    }
                }
            }
        }
    }
    .onAppear {
        textMatcher.setText(text)
    }
    .onChange(of: text) { _, newText in
        textMatcher.setText(newText)
    }
}

private func updateScrollPosition(phrase: String, proxy: ScrollViewProxy) {
    guard let position = textMatcher.findPosition(for: phrase) else { return }
    
    // Calculate scroll offset
    let percentage = Double(position.characterOffset) / Double(text.count)
    let targetOffset = contentHeight * percentage
    
    // Smooth scroll
    withAnimation(.easeOut(duration: 0.3)) {
        offset = targetOffset
    }
    
    // Highlight current phrase
    highlightCurrentPhrase(at: position)
}

private func highlightCurrentPhrase(at position: TextPosition) {
    // Calculate text range for highlighting
    let startIndex = text.index(text.startIndex, offsetBy: position.characterOffset)
    let endIndex = text.index(startIndex, offsetBy: min(50, text.count - position.characterOffset))
    
    highlightedRange = startIndex..<endIndex
}
```

---

### Phase 4: UI Integration (1 hour)

#### Step 4: Add Speech Controls to TeleprompterView

```swift
// Speech control overlay
VStack {
    Spacer()
    
    HStack(spacing: 12) {
        // Auto-scroll toggle
        Toggle("Auto-scroll", isOn: $autoScrollEnabled)
            .toggleStyle(.button)
            .tint(autoScrollEnabled ? .green : .gray)
        
        // Listening indicator
        if speechManager.isListening {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Listening...")
                    .font(.caption)
            }
        }
        
        // Reset button
        Button {
            textMatcher.reset()
            speechManager.reset()
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
    }
    .padding()
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
.padding()
```

---

## 🎯 Features & Capabilities

### Core Features

#### 1. Real-time Speech Recognition
- ✅ On-device processing (privacy)
- ✅ Partial results (live updates)
- ✅ Multiple language support
- ✅ No internet required

#### 2. Intelligent Text Matching
- ✅ Fuzzy matching (handles mispronunciations)
- ✅ Context-aware (windowed search)
- ✅ Confidence scoring
- ✅ Progressive tracking

#### 3. Smooth Auto-Scrolling
- ✅ Animated transitions
- ✅ Natural pacing
- ✅ Current phrase highlighting
- ✅ Manual override available

#### 4. User Controls
- ✅ Toggle auto-scroll on/off
- ✅ Reset position
- ✅ Listening indicator
- ✅ Confidence feedback

---

## 🎨 User Experience

### Recording Workflow

```
1. User opens teleprompter
2. Toggles "Auto-scroll" ON
3. System requests speech permission (if needed)
4. User starts recording
5. Teleprompter automatically:
   - Listens to speech
   - Matches words to script
   - Scrolls smoothly
   - Highlights current position
6. User speaks naturally
7. Teleprompter keeps perfect pace
8. User stops recording
9. Auto-scroll stops
```

### Visual Feedback

```
┌─────────────────────────────────────┐
│  Welcome to LocalLoom! This is     │
│  your notch teleprompter with      │
│  ▶ speech-synchronized scrolling ◀  │ ← Highlighted
│  that automatically follows your    │
│  voice as you speak.                │
│                                     │
│  Simply enable auto-scroll and      │
│  start talking...                   │
└─────────────────────────────────────┘
     [Auto-scroll: ON] [🟢 Listening...]
```

---

## ⚙️ Configuration Options

### Settings to Add

```swift
// In SettingsManager
@Published var speechSyncEnabled: Bool
@Published var speechLanguage: String = "en-US"
@Published var highlightCurrentPhrase: Bool = true
@Published var scrollSensitivity: Double = 1.0
@Published var fuzzyMatchThreshold: Double = 0.7
```

### User-Configurable

- **Enable/Disable** - Toggle feature on/off
- **Language** - Select speech recognition language
- **Sensitivity** - How aggressively to scroll
- **Highlighting** - Show/hide current phrase highlight
- **Match Strictness** - How exact pronunciation must be

---

## 🚨 Edge Cases & Solutions

### Problem 1: User Goes Off-Script
**Solution:** Windowed search continues from last known position

### Problem 2: Long Pauses
**Solution:** Don't scroll during silence (voice activity detection)

### Problem 3: Mispronunciation
**Solution:** Fuzzy matching with 70-80% threshold

### Problem 4: Background Noise
**Solution:** Confidence scoring + manual override always available

### Problem 5: Multiple Languages
**Solution:** Configurable locale setting

---

## 📊 Performance Considerations

### CPU Usage
- Speech recognition: ~5-10% (on-device)
- Text matching: <1% (optimized search)
- UI updates: Minimal (throttled)

### Memory
- ~10-20MB for speech engine
- Negligible for text matching

### Battery Impact
- Low (same as existing microphone capture)
- On-device = no network overhead

---

## 🔐 Privacy & Permissions

### Required Permission
- **Speech Recognition** - One-time authorization
- **Microphone** - Already have this!

### Privacy Features
- ✅ 100% on-device processing
- ✅ No data sent to servers
- ✅ No recording stored (live only)
- ✅ User can disable anytime
- ✅ Clear "listening" indicator

---

## 🧪 Testing Strategy

### Unit Tests
- [ ] Speech recognition initialization
- [ ] Text matching accuracy
- [ ] Fuzzy matching algorithm
- [ ] Scroll position calculation

### Integration Tests
- [ ] End-to-end speech → scroll
- [ ] Permission handling
- [ ] Error recovery
- [ ] Performance under load

### User Testing
- [ ] Different accents
- [ ] Various speech speeds
- [ ] Different script lengths
- [ ] Background noise tolerance

---

## 📈 Implementation Timeline

### Phase 1: Core (2 hours)
- SpeechRecognitionManager
- Basic speech-to-text
- Permission handling

### Phase 2: Matching (1.5 hours)
- TeleprompterTextMatcher
- Fuzzy matching algorithm
- Position tracking

### Phase 3: UI (1.5 hours)
- Enhanced TeleprompterView
- Auto-scroll logic
- Phrase highlighting

### Phase 4: Polish (1 hour)
- Settings integration
- Error handling
- Performance optimization

**Total: 6 hours**

---

## 🎯 Success Metrics

### Technical
- ✅ <100ms latency (speech → scroll)
- ✅ >85% matching accuracy
- ✅ <10% CPU usage
- ✅ Smooth 60fps scrolling

### User Experience
- ✅ Natural pacing
- ✅ Reduced cognitive load
- ✅ Increased recording quality
- ✅ Fewer retakes needed

---

## 🚀 Future Enhancements

### Phase 2 Features (Future)
- **Learning Mode** - Adapt to user's speech patterns
- **Multi-language** - Switch languages mid-recording
- **Voice Commands** - "Scroll up", "Pause", "Reset"
- **Offline Training** - Improve accuracy over time
- **Speed Adjustment** - Auto-adjust based on detected pace

---

## 💡 Alternative Approaches

### Approach 1: Word-by-Word (Current Plan)
**Pros:** Accurate, smooth, natural
**Cons:** Requires fuzzy matching
**Verdict:** ✅ Recommended

### Approach 2: Time-Based
**Pros:** Simple, predictable
**Cons:** Doesn't adapt to actual speech
**Verdict:** ❌ Not as good

### Approach 3: Phrase-Based
**Pros:** Less sensitive to errors
**Cons:** Jumpy scrolling
**Verdict:** ⚠️ Could be fallback

---

## 📝 Code Files Needed

### New Files (3)
1. `SpeechRecognitionManager.swift` - Speech-to-text engine
2. `TeleprompterTextMatcher.swift` - Matching algorithm
3. `SmartTeleprompter_GUIDE.md` - Documentation

### Modified Files (3)
4. `TeleprompterView.swift` - Add auto-scroll
5. `TeleprompterWindowController.swift` - Pass speech manager
6. `SettingsManager.swift` - Add speech settings
7. `ContentView.swift` - Initialize speech manager

**Total: ~700 lines of code**

---

## 🎉 Conclusion

### Feasibility: ✅ YES
This feature is **absolutely feasible** and can be implemented in ~6 hours.

### Value: ✅ HIGH
This is a **game-changing feature** that:
- Differentiates LocalLoom from competitors
- Solves a real pain point
- Uses cutting-edge technology
- Enhances professional use cases

### Recommendation: ✅ IMPLEMENT
**I strongly recommend implementing this feature.**

It's:
- Technically feasible
- Relatively quick to implement
- High user value
- Great marketing angle ("AI-powered teleprompter")
- Privacy-friendly (on-device)

---

## 🤔 Decision Points

### Do you want to:

**Option 1:** Implement this feature now? (6 hours)
- I can start building it immediately

**Option 2:** Implement later?
- Save it for v2.0

**Option 3:** Simplified version first?
- Basic speech sync without fuzzy matching (3 hours)

**Option 4:** Explore more?
- Discuss specific aspects in detail

---

**What would you like to do?** This feature would make LocalLoom stand out significantly in the market! 🚀
