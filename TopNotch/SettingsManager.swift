import Foundation
import SwiftUI
import Combine

/// Manages persistence of app settings using UserDefaults
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let teleprompterText = "teleprompter.text"
        static let teleprompterSpeed = "teleprompter.speed"
        static let teleprompterEnabled = "teleprompter.enabled"
        static let teleprompterFontSize = "teleprompter.fontSize"
        static let teleprompterTextAlignment = "teleprompter.textAlignment"
        static let lastOutputPath = "capture.outputPath"
        static let countdownDuration = "capture.countdownDuration"
        
        // Cloud Storage
        static let googleDriveEnabled = "cloud.googleDrive.enabled"
        static let iCloudEnabled = "cloud.iCloud.enabled"
        static let deleteAfterUpload = "cloud.deleteAfterUpload"
        static let generateShareLinks = "cloud.generateShareLinks"
        static let autoUploadEnabled = "cloud.autoUpload.enabled"
        
        // Speech Recognition
        static let speechSyncEnabled = "speech.sync.enabled"
        static let speechLocale = "speech.locale"
        static let speechHighlightPhrase = "speech.highlight.enabled"

        // Banners
        static let arrangeTextBannerDismissed = "banner.arrangeTextDismissed"
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

    @Published var teleprompterFontSize: Double {
        didSet {
            defaults.set(teleprompterFontSize, forKey: Keys.teleprompterFontSize)
        }
    }

    /// "leading" or "center"
    @Published var teleprompterTextAlignment: String {
        didSet {
            defaults.set(teleprompterTextAlignment, forKey: Keys.teleprompterTextAlignment)
        }
    }

    // MARK: - Capture Settings
    
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
    
    // MARK: - Cloud Storage Settings
    
    @Published var googleDriveEnabled: Bool {
        didSet {
            defaults.set(googleDriveEnabled, forKey: Keys.googleDriveEnabled)
        }
    }
    
    @Published var iCloudEnabled: Bool {
        didSet {
            defaults.set(iCloudEnabled, forKey: Keys.iCloudEnabled)
        }
    }
    
    @Published var deleteAfterUpload: Bool {
        didSet {
            defaults.set(deleteAfterUpload, forKey: Keys.deleteAfterUpload)
        }
    }
    
    @Published var generateShareLinks: Bool {
        didSet {
            defaults.set(generateShareLinks, forKey: Keys.generateShareLinks)
        }
    }
    
    @Published var autoUploadEnabled: Bool {
        didSet {
            defaults.set(autoUploadEnabled, forKey: Keys.autoUploadEnabled)
        }
    }
    
    // MARK: - Speech Recognition Settings
    
    @Published var speechSyncEnabled: Bool {
        didSet {
            defaults.set(speechSyncEnabled, forKey: Keys.speechSyncEnabled)
        }
    }
    
    @Published var speechLocale: String {
        didSet {
            defaults.set(speechLocale, forKey: Keys.speechLocale)
        }
    }
    
    @Published var speechHighlightPhrase: Bool {
        didSet {
            defaults.set(speechHighlightPhrase, forKey: Keys.speechHighlightPhrase)
        }
    }

    // MARK: - Banner Settings

    @Published var arrangeTextBannerDismissed: Bool {
        didSet {
            defaults.set(arrangeTextBannerDismissed, forKey: Keys.arrangeTextBannerDismissed)
        }
    }

    // MARK: - Initialization
    
    private init() {
        // Load saved values or use defaults
        self.teleprompterText = defaults.string(forKey: Keys.teleprompterText) ?? "Welcome to TopNotch, your notch teleprompter.\nThis short paragraph is here to help you test the scroll speed and speech sync features.\nTry reading it aloud at a comfortable pace and watch the text follow your voice.\nYou can adjust the scroll speed and font size in the settings panel on the right.\nSpeech recognition works best in a quiet environment with clear pronunciation.\nTesting one, two, three — the quick brown fox jumped over the lazy dog."
        let savedSpeed = defaults.double(forKey: Keys.teleprompterSpeed)
        self.teleprompterSpeed = savedSpeed == 0 ? 40 : savedSpeed
        
        self.teleprompterEnabled = defaults.object(forKey: Keys.teleprompterEnabled) as? Bool ?? true

        let savedFontSize = defaults.double(forKey: Keys.teleprompterFontSize)
        self.teleprompterFontSize = savedFontSize == 0 ? 16 : savedFontSize

        self.teleprompterTextAlignment = defaults.string(forKey: Keys.teleprompterTextAlignment) ?? "leading"

        self.lastOutputPath = defaults.string(forKey: Keys.lastOutputPath) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Recording.m4a").path
        
        let savedCountdown = defaults.integer(forKey: Keys.countdownDuration)
        self.countdownDuration = savedCountdown == 0 ? 3 : savedCountdown
        
        // Cloud storage settings
        self.googleDriveEnabled = defaults.bool(forKey: Keys.googleDriveEnabled)
        self.iCloudEnabled = defaults.bool(forKey: Keys.iCloudEnabled)
        self.deleteAfterUpload = defaults.bool(forKey: Keys.deleteAfterUpload)
        self.generateShareLinks = defaults.object(forKey: Keys.generateShareLinks) as? Bool ?? true
        self.autoUploadEnabled = defaults.bool(forKey: Keys.autoUploadEnabled)
        
        // Speech recognition settings
        self.speechSyncEnabled = defaults.bool(forKey: Keys.speechSyncEnabled)
        self.speechLocale = defaults.string(forKey: Keys.speechLocale) ?? "en-IN" // Default to Indian English
        self.speechHighlightPhrase = defaults.object(forKey: Keys.speechHighlightPhrase) as? Bool ?? true

        // Banner settings
        self.arrangeTextBannerDismissed = defaults.bool(forKey: Keys.arrangeTextBannerDismissed)
    }
    
    // MARK: - Reset Methods
    
    /// Reset all teleprompter settings to defaults
    func resetTeleprompterSettings() {
        teleprompterText = "Welcome to TopNotch! This is your notch teleprompter."
        teleprompterSpeed = 40
        teleprompterEnabled = true
        teleprompterFontSize = 16
        teleprompterTextAlignment = "leading"
    }
    
    /// Reset all settings to defaults
    func resetAllSettings() {
        resetTeleprompterSettings()
        lastOutputPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Recording.m4a").path
        countdownDuration = 3
        googleDriveEnabled = false
        iCloudEnabled = false
        deleteAfterUpload = false
        generateShareLinks = true
        autoUploadEnabled = false
        speechSyncEnabled = false
        speechLocale = "en-IN"
        speechHighlightPhrase = true
    }
    
    /// Get current upload settings for CloudStorageManager
    var uploadSettings: UploadSettings {
        UploadSettings(
            googleDriveEnabled: googleDriveEnabled,
            iCloudEnabled: iCloudEnabled,
            deleteAfterUpload: deleteAfterUpload,
            generateShareLinks: generateShareLinks
        )
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
