import SwiftUI

struct TeleprompterView: View {
    @ObservedObject var textMatcher: TextMatcher
    @ObservedObject var speechManager: SpeechManager
    @Binding var isScrolling: Bool
    @ObservedObject var settings: Settings
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .padding()
        }
        .onAppear {
            textMatcher.setText(text)
            if settings.speechSyncEnabled {
                Task { _ = await speechManager.requestAuthorization() }
            }
            // Start immediately if isScrolling is already true
            if isScrolling {
                if settings.speechSyncEnabled {
                    startSpeechSync()
                } else {
                    startScrolling()
                }
            }
        }
        .onChange(of: isScrolling) { _, active in
            if active {
                if settings.speechSyncEnabled {
                    startSpeechSync()
                } else {
                    startScrolling()
                }
            } else {
                stopScrolling()
                stopSpeechSync()
            }
        }
        .onChange(of: settings.speechSyncEnabled) { _, enabled in
            if isScrolling {
                if enabled {
                    // Switch to speech sync
                    stopScrolling()
                    startSpeechSync()
                } else {
                    // Switch to manual scrolling
                    stopSpeechSync()
                    startScrolling()
                }
            } else {
                // Ensure both mechanisms are stopped when not scrolling
                stopScrolling()
                stopSpeechSync()
            }
        }
    }

    func startScrolling() {
        // Implementation for starting scrolling
    }

    func stopScrolling() {
        // Implementation for stopping scrolling
    }

    func startSpeechSync() {
        // Implementation for starting speech synchronization
    }

    func stopSpeechSync() {
        // Implementation for stopping speech synchronization
    }
}
