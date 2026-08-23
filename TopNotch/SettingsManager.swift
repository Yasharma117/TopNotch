import Foundation
import SwiftUI
import Combine

/// Manages persistence of app settings using UserDefaults
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    /// Default script shown on first launch and after a teleprompter reset.
    static let defaultTeleprompterText = "Welcome to TopNotch, your notch teleprompter.\nThis short paragraph is here to help you test the scroll speed and speech sync features.\nTry reading it aloud at a comfortable pace and watch the text follow your voice.\nYou can adjust the scroll speed and font size in the settings panel on the right.\nSpeech recognition works best in a quiet environment with clear pronunciation.\nTesting one, two, three — the quick brown fox jumped over the lazy dog."

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
        self.teleprompterText = defaults.string(forKey: Keys.teleprompterText) ?? Self.defaultTeleprompterText
        let savedSpeed = defaults.double(forKey: Keys.teleprompterSpeed)
        self.teleprompterSpeed = savedSpeed == 0 ? 40 : savedSpeed
        
        self.teleprompterEnabled = defaults.object(forKey: Keys.teleprompterEnabled) as? Bool ?? true

        let savedFontSize = defaults.double(forKey: Keys.teleprompterFontSize)
        self.teleprompterFontSize = savedFontSize == 0 ? 16 : savedFontSize

        self.teleprompterTextAlignment = defaults.string(forKey: Keys.teleprompterTextAlignment) ?? "leading"

        // Migrate anyone still carrying the old Desktop default, which the sandbox
        // always refused — otherwise their recordings keep failing silently.
        let storedOutput = defaults.string(forKey: Keys.lastOutputPath)
        if let storedOutput, storedOutput != Self.unwritableLegacyPath {
            self.lastOutputPath = storedOutput
        } else {
            self.lastOutputPath = Self.defaultOutputURL().path
        }
        
        let savedCountdown = defaults.integer(forKey: Keys.countdownDuration)
        self.countdownDuration = savedCountdown == 0 ? 3 : savedCountdown

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
        teleprompterText = Self.defaultTeleprompterText
        teleprompterSpeed = 40
        teleprompterEnabled = true
        teleprompterFontSize = 16
        teleprompterTextAlignment = "leading"
    }


    /// Where recordings go by default.
    ///
    /// The app is sandboxed, and the sandbox grants Downloads
    /// (`com.apple.security.files.downloads.read-write`) but has no Desktop
    /// equivalent — Desktop is only reachable through a save panel. Writing there
    /// fails with NSFileWriteNoPermissionError (513), so Downloads is the only
    /// location the app can use without prompting.
    static func defaultOutputURL() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return downloads.appendingPathComponent("TopNotch Recording.m4a")
    }

    /// The pre-sandbox default, which could never be written to.
    private static let unwritableLegacyPath =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Recording.m4a").path

    /// Reset all settings to defaults
    func resetAllSettings() {
        resetTeleprompterSettings()
        lastOutputPath = Self.defaultOutputURL().path
        countdownDuration = 3
        speechSyncEnabled = false
        speechLocale = "en-IN"
        speechHighlightPhrase = true
    }
}
