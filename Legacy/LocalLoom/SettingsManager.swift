import Foundation
import SwiftUI

/// Manages persistence of app settings using UserDefaults
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let teleprompterText = "teleprompter.text"
        static let teleprompterSpeed = "teleprompter.speed"
        static let teleprompterEnabled = "teleprompter.enabled"
        static let lastCaptureTarget = "capture.target"
        static let lastOutputPath = "capture.outputPath"
        static let countdownDuration = "capture.countdownDuration"
    }
    
    // MARK: - Teleprompter Settings
    
    @Published var teleprompterText: String {
        didSet {
            defaults.set(teleprompterText, forKey: Keys.teleprompterText)
        }
    }
    
    @Published var teleprompterSpeed: Double {
        didSet {
            defaults.set(teleprompterSpeed, forKey: Keys.teleprompterSpeed)
        }
    }
    
    @Published var teleprompterEnabled: Bool {
        didSet {
            defaults.set(teleprompterEnabled, forKey: Keys.teleprompterEnabled)
        }
    }
    
    // MARK: - Capture Settings
    
    @Published var lastCaptureTarget: String {
        didSet {
            defaults.set(lastCaptureTarget, forKey: Keys.lastCaptureTarget)
        }
    }
    
    @Published var lastOutputPath: String {
        didSet {
            defaults.set(lastOutputPath, forKey: Keys.lastOutputPath)
        }
    }
    
    @Published var countdownDuration: Int {
        didSet {
            defaults.set(countdownDuration, forKey: Keys.countdownDuration)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved values or use defaults
        self.teleprompterText = defaults.string(forKey: Keys.teleprompterText) ?? "Welcome to LocalLoom! This is your notch teleprompter."
        self.teleprompterSpeed = defaults.double(forKey: Keys.teleprompterSpeed)
        if self.teleprompterSpeed == 0 { self.teleprompterSpeed = 40 }
        
        self.teleprompterEnabled = defaults.object(forKey: Keys.teleprompterEnabled) as? Bool ?? true
        
        self.lastCaptureTarget = defaults.string(forKey: Keys.lastCaptureTarget) ?? "display"
        
        self.lastOutputPath = defaults.string(forKey: Keys.lastOutputPath) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Recording.mov").path
        
        self.countdownDuration = defaults.integer(forKey: Keys.countdownDuration)
        if self.countdownDuration == 0 { self.countdownDuration = 3 }
    }
    
    // MARK: - Reset Methods
    
    /// Reset all teleprompter settings to defaults
    func resetTeleprompterSettings() {
        teleprompterText = "Welcome to LocalLoom! This is your notch teleprompter."
        teleprompterSpeed = 40
        teleprompterEnabled = true
    }
    
    /// Reset all settings to defaults
    func resetAllSettings() {
        resetTeleprompterSettings()
        lastCaptureTarget = "display"
        lastOutputPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Recording.mov").path
        countdownDuration = 3
    }
}

// MARK: - SwiftUI Property Wrapper Alternative

/// For easier SwiftUI integration, here's an @AppStorage-style approach for individual settings
extension SettingsManager {
    /// Creates a binding for a specific setting
    func binding<T>(
        get: @escaping (SettingsManager) -> T,
        set: @escaping (SettingsManager, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { get(self) },
            set: { set(self, $0) }
        )
    }
    
    var teleprompterTextBinding: Binding<String> {
        binding(get: \.teleprompterText, set: { $0.teleprompterText = $1 })
    }
    
    var teleprompterSpeedBinding: Binding<Double> {
        binding(get: \.teleprompterSpeed, set: { $0.teleprompterSpeed = $1 })
    }
    
    var teleprompterEnabledBinding: Binding<Bool> {
        binding(get: \.teleprompterEnabled, set: { $0.teleprompterEnabled = $1 })
    }
    
    var countdownDurationBinding: Binding<Int> {
        binding(get: \.countdownDuration, set: { $0.countdownDuration = $1 })
    }
}
