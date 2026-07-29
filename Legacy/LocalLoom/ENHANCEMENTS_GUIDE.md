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

## Implementation Priority

Recommended order:

1. ✅ **Pulsing Recording Indicator** - Quick win, high visual impact
2. ✅ **Error Type Icons** - Better UX, minimal code
3. ✅ **Screen Capture Permission** - Important for functionality
4. ⚠️ **Countdown Sounds** - Nice to have, user preference dependent
5. 🔧 **Advanced Settings** - Larger feature, plan carefully
6. 🔧 **Recording History** - Future enhancement

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
