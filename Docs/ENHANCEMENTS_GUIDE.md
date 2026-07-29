# Enhancement Implementation Guide

This guide provides ready-to-use code for the suggested enhancements discussed.

## Enhancement 1: Pulsing Recording Indicator

### Implementation
Add to `ContentView.swift`:

```swift
// Add state variable
@State private var isPulsing = false

// Update the recording indicator
if isRecording {
    HStack(spacing: 8) {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
        
        Text("Recording…")
            .foregroundStyle(.secondary)
    }
}
```

---

## Enhancement 2: Screen Capture Permission Check

### Create PermissionsHelper Extension

Add to `PermissionsHelper.swift`:

```swift
import ScreenCaptureKit

extension PermissionsHelper {
    public static func screenCapturePermissionState() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    public static func requestScreenCapturePermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
}
```

### Integration in ContentView

```swift
.task {
    await refreshTargets()
    
    // Check screen capture permission
    if !PermissionsHelper.screenCapturePermissionState() {
        await presentError("Screen recording permission required. Please grant access in System Settings > Privacy & Security > Screen Recording.")
        
        // Optionally request permission
        let granted = PermissionsHelper.requestScreenCapturePermission()
        if !granted {
            // User denied, show instructions
        }
    }
    
    // ... rest of task code
}
```

---

## Enhancement 3: Error Type-Specific Icons

### Create Error Type Enum

Add to `ContentView.swift`:

```swift
enum ErrorType {
    case permission
    case capture
    case storage
    case general
    
    var icon: String {
        switch self {
        case .permission: return "lock.shield.fill"
        case .capture: return "video.slash.fill"
        case .storage: return "externaldrive.badge.exclamationmark"
        case .general: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .permission: return .orange
        case .capture: return .red
        case .storage: return .purple
        case .general: return .yellow
        }
    }
}
```

### Update Error Banner

```swift
// Add state variable
@State private var errorType: ErrorType = .general

// Update presentError function
private func presentError(_ message: String, type: ErrorType = .general) {
    Task { @MainActor in
        errorMessage = message
        errorType = type
        withAnimation { showErrorBanner = true }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        withAnimation { showErrorBanner = false }
    }
}

// Update error banner overlay
.overlay(alignment: .top) {
    if showErrorBanner {
        HStack {
            Image(systemName: errorType.icon)
                .foregroundColor(errorType.color)
            Text(errorMessage)
            Spacer()
            Button("Dismiss") { withAnimation { showErrorBanner = false } }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

### Usage Examples

```swift
// Permission error
await presentError("Microphone access required", type: .permission)

// Capture error
await presentError("Failed to start capture", type: .capture)

// Storage error
await presentError("Cannot write to output file", type: .storage)
```

---

## Enhancement 4: Countdown Sound Feedback

### Implementation

```swift
// Add to startCountdownThenRecord function
private func startCountdownThenRecord() async {
    let duration = settings.countdownDuration
    
    if duration == 0 {
        await startRecording()
        return
    }
    
    await MainActor.run {
        countdownValue = duration
        showCountdown = true
    }
    
    for _ in 0..<duration {
        // Play sound on each tick
        NSSound(named: "Tink")?.play()
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run { countdownValue -= 1 }
    }
    
    // Play different sound when starting
    NSSound(named: "Hero")?.play()
    
    await MainActor.run { showCountdown = false }
    await startRecording()
}
```

### Alternative: Haptic Feedback

```swift
private func playHapticFeedback() {
    NSHapticFeedbackManager.defaultPerformer.perform(
        .generic,
        performanceTime: .now
    )
}

// Use in countdown
for _ in 0..<duration {
    playHapticFeedback()
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    await MainActor.run { countdownValue -= 1 }
}
```

---

## Enhancement 5: Advanced Settings Panel

### Create AdvancedSettingsView

Create new file `AdvancedSettingsView.swift`:

```swift
import SwiftUI

struct AdvancedSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Advanced Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                // Video Quality Section
                Section("Video Quality") {
                    Picker("Frame Rate", selection: .constant(60)) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                        Text("120 fps").tag(120)
                    }
                    
                    Picker("Resolution", selection: .constant("native")) {
                        Text("Native").tag("native")
                        Text("1080p").tag("1080p")
                        Text("4K").tag("4k")
                    }
                }
                
                // Audio Section
                Section("Audio") {
                    Toggle("Include Microphone", isOn: .constant(true))
                    Toggle("Include System Audio", isOn: .constant(false))
                    
                    Picker("Microphone", selection: .constant("default")) {
                        Text("Default").tag("default")
                        // Add actual audio devices here
                    }
                }
                
                // Hotkeys Section
                Section("Hotkeys") {
                    HStack {
                        Text("Start/Stop Recording")
                        Spacer()
                        Text("⌘⇧R")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Toggle Teleprompter")
                        Spacer()
                        Text("⌘⇧T")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Data Management Section
                Section("Data Management") {
                    Button("Export Settings...") {
                        exportSettings()
                    }
                    
                    Button("Import Settings...") {
                        importSettings()
                    }
                    
                    Button("Reset to Defaults") {
                        settings.resetAllSettings()
                    }
                    .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 600)
    }
    
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "LocalLoom-Settings.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Export settings as JSON
            // Implementation depends on your settings structure
        }
    }
    
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // Import settings from JSON
        }
    }
}
```

### Integration in ContentView

```swift
// Add state variable
@State private var showAdvancedSettings = false

// Add button in main UI
Button("Advanced Settings...") {
    showAdvancedSettings = true
}
.sheet(isPresented: $showAdvancedSettings) {
    AdvancedSettingsView()
}
```

---

## Bonus Enhancement: Recording History

### Create RecordingHistoryView

```swift
import SwiftUI
import QuickLook

struct RecordingHistoryItem: Identifiable, Codable {
    let id: UUID
    let url: URL
    let date: Date
    let duration: TimeInterval
    let fileSize: Int64
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct RecordingHistoryView: View {
    @State private var recordings: [RecordingHistoryItem] = []
    @State private var selectedRecording: RecordingHistoryItem?
    @State private var showQuickLook = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recording History")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Clear All") {
                    recordings.removeAll()
                    saveHistory()
                }
                .disabled(recordings.isEmpty)
            }
            .padding()
            
            Divider()
            
            // List
            List(recordings) { recording in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recording.url.lastPathComponent)
                            .font(.headline)
                        Text(recording.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(recording.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        selectedRecording = recording
                        showQuickLook = true
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                    } label: {
                        Image(systemName: "folder")
                    }
                }
            }
            .quickLookPreview($selectedRecording, in: recordings) { item in
                item.url
            }
        }
        .frame(width: 600, height: 400)
        .onAppear {
            loadHistory()
        }
    }
    
    private func loadHistory() {
        // Load from UserDefaults or file
    }
    
    private func saveHistory() {
        // Save to UserDefaults or file
    }
}
```

---

---

## Enhancement 6: Cloud Storage Integration (Google Drive)

### Overview
**Value Proposition:** ⭐⭐⭐⭐⭐ (Highly Valuable)
- Automatic upload after recording
- Free up local disk space
- Access recordings from anywhere
- Shareable links generation
- Optional: Auto-delete local copy after upload

### Implementation Strategy

There are two approaches:

#### Option A: Google Drive REST API (Recommended)
**Pros:**
- Full control over upload process
- Progress tracking
- Better error handling
- No external dependencies
- Can implement background uploads

**Cons:**
- Need to handle OAuth 2.0 authentication
- More code to write
- API key management

#### Option B: Native Share Sheet → Google Drive
**Pros:**
- Very simple implementation (5 minutes)
- Uses system share functionality
- No API keys needed
- User controls the upload

**Cons:**
- No automation
- Can't track progress
- User must have Google Drive app installed
- Manual process each time

### Option A: Full Google Drive Integration

#### Step 1: Create GoogleDriveManager

Create new file `GoogleDriveManager.swift`:

```swift
import Foundation
import AuthenticationServices

/// Manages Google Drive authentication and file uploads
final class GoogleDriveManager: NSObject, ObservableObject {
    static let shared = GoogleDriveManager()
    
    @Published var isAuthenticated = false
    @Published var uploadProgress: Double = 0.0
    @Published var isUploading = false
    
    private var accessToken: String?
    private var refreshToken: String?
    
    // Google OAuth Configuration
    // ⚠️ You need to create these in Google Cloud Console
    private let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    private let clientSecret = "YOUR_CLIENT_SECRET"
    private let redirectURI = "com.yourdomain.localloom:/oauth2callback"
    
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files"
    
    private override init() {
        super.init()
        loadStoredTokens()
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        let authURL = buildAuthURL()
        
        // Open authentication in browser
        guard let url = URL(string: authURL) else {
            throw DriveError.invalidURL
        }
        
        // Use ASWebAuthenticationSession for OAuth
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "com.yourdomain.localloom"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Authentication error: \(error)")
                return
            }
            
            guard let callbackURL = callbackURL else { return }
            
            Task {
                try? await self.handleAuthCallback(callbackURL)
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
    
    private func buildAuthURL() -> String {
        let scope = "https://www.googleapis.com/auth/drive.file"
        let params = [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "response_type": "code",
            "scope": scope,
            "access_type": "offline",
            "prompt": "consent"
        ]
        
        let queryString = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        return "https://accounts.google.com/o/oauth2/v2/auth?\(queryString)"
    }
    
    private func handleAuthCallback(_ url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw DriveError.noAuthCode
        }
        
        try await exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) async throws {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        let bodyString = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = response.accessToken
            self.refreshToken = response.refreshToken
            self.isAuthenticated = true
            self.saveTokens()
        }
    }
    
    // MARK: - File Upload
    
    func uploadFile(_ fileURL: URL, deleteAfterUpload: Bool = false) async throws -> String {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = 0.0
            }
        }
        
        let fileName = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        
        // Create metadata
        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "video/quicktime"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        
        // Build multipart request
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // Add metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add file data part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create request
        var request = URLRequest(url: URL(string: "\(uploadEndpoint)?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        // Upload with progress tracking
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DriveError.uploadFailed
        }
        
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        
        // Delete local file if requested
        if deleteAfterUpload {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        await MainActor.run {
            uploadProgress = 1.0
        }
        
        return uploadResponse.id
    }
    
    func generateShareLink(_ fileID: String) async throws -> String {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
        }
        
        // Make file publicly accessible
        let permissionURL = "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions"
        var request = URLRequest(url: URL(string: permissionURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let permission = ["role": "reader", "type": "anyone"]
        request.httpBody = try JSONSerialization.data(withJSONObject: permission)
        
        _ = try await URLSession.shared.data(for: request)
        
        return "https://drive.google.com/file/d/\(fileID)/view"
    }
    
    // MARK: - Token Storage
    
    private func saveTokens() {
        let keychain = KeychainHelper.shared
        if let accessToken = accessToken {
            keychain.save(accessToken, for: "drive.accessToken")
        }
        if let refreshToken = refreshToken {
            keychain.save(refreshToken, for: "drive.refreshToken")
        }
    }
    
    private func loadStoredTokens() {
        let keychain = KeychainHelper.shared
        accessToken = keychain.load(for: "drive.accessToken")
        refreshToken = keychain.load(for: "drive.refreshToken")
        isAuthenticated = accessToken != nil
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        KeychainHelper.shared.delete(for: "drive.accessToken")
        KeychainHelper.shared.delete(for: "drive.refreshToken")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleDriveManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Response Models

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct UploadResponse: Codable {
    let id: String
    let name: String
}

// MARK: - Errors

enum DriveError: LocalizedError {
    case invalidURL
    case noAuthCode
    case notAuthenticated
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noAuthCode: return "No authorization code received"
        case .notAuthenticated: return "Not authenticated with Google Drive"
        case .uploadFailed: return "Upload to Google Drive failed"
        }
    }
}
```

#### Step 2: Create KeychainHelper

Create `KeychainHelper.swift`:

```swift
import Foundation
import Security

/// Secure storage for sensitive data like OAuth tokens
final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    func save(_ value: String, for key: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
```

#### Step 3: Update SettingsManager

Add to `SettingsManager.swift`:

```swift
// Add to SettingsManager
@Published var autoUploadToDrive: Bool {
    didSet {
        defaults.set(autoUploadToDrive, forKey: Keys.autoUploadToDrive)
    }
}

@Published var deleteAfterUpload: Bool {
    didSet {
        defaults.set(deleteAfterUpload, forKey: Keys.deleteAfterUpload)
    }
}

@Published var generateShareLink: Bool {
    didSet {
        defaults.set(generateShareLink, forKey: Keys.generateShareLink)
    }
}

// Add to Keys enum
static let autoUploadToDrive = "drive.autoUpload"
static let deleteAfterUpload = "drive.deleteAfterUpload"
static let generateShareLink = "drive.generateShareLink"

// Initialize in init()
self.autoUploadToDrive = defaults.bool(forKey: Keys.autoUploadToDrive)
self.deleteAfterUpload = defaults.bool(forKey: Keys.deleteAfterUpload)
self.generateShareLink = defaults.bool(forKey: Keys.generateShareLink)
```

#### Step 4: Create Google Drive Settings UI

Add to `ContentView.swift`:

```swift
// Add state variable
@StateObject private var driveManager = GoogleDriveManager.shared

// Add to UI (in GroupBox or Advanced Settings)
GroupBox("Google Drive") {
    if driveManager.isAuthenticated {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Connected to Google Drive")
            Spacer()
            Button("Sign Out") {
                driveManager.signOut()
            }
        }
        
        Toggle("Auto-upload after recording", isOn: settings.$autoUploadToDrive)
        
        if settings.autoUploadToDrive {
            Toggle("Delete local copy after upload", isOn: settings.$deleteAfterUpload)
            Toggle("Generate shareable link", isOn: settings.$generateShareLink)
        }
        
        if driveManager.isUploading {
            ProgressView(value: driveManager.uploadProgress) {
                Text("Uploading to Google Drive...")
            }
        }
    } else {
        Button("Connect to Google Drive") {
            Task {
                try? await driveManager.authenticate()
            }
        }
        .buttonStyle(.borderedProminent)
    }
}
```

#### Step 5: Integrate with Recording

Update `stopRecording()` in ContentView:

```swift
private func stopRecording() async {
    await captureController.stopCapture()
    await MainActor.run {
        isRecording = false
        if !settings.teleprompterEnabled {
            teleWindowController?.closeWindow()
            teleWindowController = nil
        }
    }
    
    // Auto-upload to Google Drive if enabled
    if settings.autoUploadToDrive && driveManager.isAuthenticated {
        do {
            let fileID = try await driveManager.uploadFile(
                outputURL,
                deleteAfterUpload: settings.deleteAfterUpload
            )
            
            var message = "Recording uploaded to Google Drive successfully!"
            
            if settings.generateShareLink {
                let shareLink = try await driveManager.generateShareLink(fileID)
                // Copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shareLink, forType: .string)
                message += "\nShare link copied to clipboard."
            }
            
            await presentError(message, type: .general) // Use as success message
        } catch {
            await presentError("Failed to upload to Google Drive: \(error.localizedDescription)", type: .storage)
        }
    }
}
```

### Option B: Simple Share Sheet Implementation

Much simpler, but less automated:

```swift
// Add to ContentView
private func shareRecording() {
    let picker = NSSharingServicePicker(items: [outputURL])
    
    if let button = /* reference to share button */ {
        picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
    }
}

// Add share button after recording stops
if !isRecording && FileManager.default.fileExists(atPath: outputURL.path) {
    Button {
        shareRecording()
    } label: {
        Label("Share", systemImage: "square.and.arrow.up")
    }
}
```

---

### Google Cloud Console Setup Steps

To use Option A, you need to:

1. **Create Google Cloud Project**
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create new project: "LocalLoom"

2. **Enable Google Drive API**
   - In APIs & Services > Library
   - Search "Google Drive API" → Enable

3. **Create OAuth Credentials**
   - APIs & Services > Credentials
   - Create OAuth Client ID
   - Application type: macOS app
   - Add redirect URI: `com.yourdomain.localloom:/oauth2callback`

4. **Configure App**
   - Update `clientID` and `clientSecret` in GoogleDriveManager
   - Add URL scheme to Info.plist:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.yourdomain.localloom</string>
        </array>
    </dict>
</array>
```

---

### Alternative Cloud Providers

The same architecture can be adapted for:

- **Dropbox** - Similar OAuth flow, simpler API
- **iCloud Drive** - Native, no OAuth needed
- **OneDrive** - Microsoft Graph API
- **Box** - Similar to Google Drive

### iCloud Drive (Easiest Option)

```swift
// Add to SettingsManager
@Published var saveToICloud: Bool {
    didSet {
        defaults.set(saveToICloud, forKey: Keys.saveToICloud)
    }
}

// Update recording output path
private var iCloudDocumentsURL: URL? {
    FileManager.default.url(forUbiquityContainerIdentifier: nil)?
        .appendingPathComponent("Documents")
        .appendingPathComponent("Recordings")
}

// When starting recording
if settings.saveToICloud, let iCloudURL = iCloudDocumentsURL {
    try? FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
    outputURL = iCloudURL.appendingPathComponent("Recording-\(Date().timeIntervalSince1970).mov")
}
```

---

## Implementation Priority

Recommended order:

1. ✅ **Pulsing Recording Indicator** - Quick win, high visual impact
2. ✅ **Error Type Icons** - Better UX, minimal code
3. ✅ **Screen Capture Permission** - Important for functionality
4. ⭐⭐⭐⭐⭐ **Cloud Storage Integration** - HIGH VALUE feature
   - Start with **iCloud Drive** (easiest, 30 min)
   - Or **Share Sheet** (5 min, less automated)
   - Then **Google Drive** if needed (2-3 hours)
5. ⚠️ **Countdown Sounds** - Nice to have, user preference dependent
6. 🔧 **Advanced Settings** - Larger feature, plan carefully
7. 🔧 **Recording History** - Future enhancement

---

## Testing Each Enhancement

### Pulsing Indicator:
- [ ] Animation starts when recording begins
- [ ] Animation stops when recording ends
- [ ] No performance impact on capture

### Permission Check:
- [ ] Detects missing screen recording permission
- [ ] Shows helpful error message
- [ ] Opens System Settings when requested

### Error Icons:
- [ ] Each error type shows correct icon/color
- [ ] Icons are visually distinct
- [ ] Error messages are clear

### Countdown Sounds:
- [ ] Sound plays on each tick
- [ ] Volume is appropriate
- [ ] No sound overlap issues
- [ ] Different sound on start

### Advanced Settings:
- [ ] All settings save correctly
- [ ] Export creates valid JSON
- [ ] Import restores all settings
- [ ] Reset clears everything

---

## Notes

- All enhancements are backward compatible
- Each can be implemented independently
- No breaking changes to existing code
- Performance impact is minimal
- User preferences should be respected (e.g., sound on/off)

Ready to implement any of these! Let me know which one you'd like to start with.
