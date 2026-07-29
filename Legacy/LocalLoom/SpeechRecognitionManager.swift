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
    private var currentLocale: Locale
    
    init(locale: String = "en-IN") {
        self.currentLocale = Locale(identifier: locale)
        super.init()
        setupRecognizer()
    }
    
    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        speechRecognizer?.delegate = self
        checkAuthorization()
    }
    
    // MARK: - Locale Management
    
    func setLocale(_ locale: String) {
        currentLocale = Locale(identifier: locale)
        setupRecognizer()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorization() {
        let status = SFSpeechRecognizer.authorizationStatus()
        Task { @MainActor in
            isAuthorized = status == .authorized
        }
    }
    
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
        
        // Use on-device recognition if available (privacy + speed)
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        
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
                self.stopListeningInternal()
            }
        }
        
        Task { @MainActor in
            isListening = true
        }
    }
    
    func stopListening() {
        stopListeningInternal()
        Task { @MainActor in
            isListening = false
        }
    }
    
    private func stopListeningInternal() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
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

// MARK: - Speech Locale Options

enum SpeechLocale: String, CaseIterable, Identifiable {
    case indianEnglish = "en-IN"
    case usEnglish = "en-US"
    case ukEnglish = "en-GB"
    case hindi = "hi-IN"
    case tamil = "ta-IN"
    case telugu = "te-IN"
    case malayalam = "ml-IN"
    case marathi = "mr-IN"
    case gujarati = "gu-IN"
    case kannada = "kn-IN"
    case punjabi = "pa-IN"
    case bengali = "bn-IN"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .indianEnglish: return "English (India) 🇮🇳"
        case .usEnglish: return "English (US)"
        case .ukEnglish: return "English (UK)"
        case .hindi: return "हिन्दी (Hindi)"
        case .tamil: return "தமிழ் (Tamil)"
        case .telugu: return "తెలుగు (Telugu)"
        case .malayalam: return "മലയാളം (Malayalam)"
        case .marathi: return "मराठी (Marathi)"
        case .gujarati: return "ગુજરાતી (Gujarati)"
        case .kannada: return "ಕನ್ನಡ (Kannada)"
        case .punjabi: return "ਪੰਜਾਬੀ (Punjabi)"
        case .bengali: return "বাংলা (Bengali)"
        }
    }
    
    var isAvailable: Bool {
        SFSpeechRecognizer(locale: Locale(identifier: rawValue))?.isAvailable ?? false
    }
}
