# ⚡ Quick Start: Get LocalLoom Running in 5 Minutes

## Step 1: Add Permission Keys to Info.plist (2 min)

1. In Xcode, find and open `Info.plist`
2. Right-click → "Add Row" three times
3. Add these exact keys and values:

```
Key: NSScreenCaptureUsageDescription
Value: LocalLoom needs screen recording permission to capture your display or windows for video recording.

Key: NSMicrophoneUsageDescription  
Value: LocalLoom needs microphone access to record audio with your screen recordings.

Key: NSSpeechRecognitionUsageDescription
Value: LocalLoom uses speech recognition to automatically scroll the teleprompter as you speak, keeping perfect pace with your voice.
```

## Step 2: Configure App Sandbox (2 min)

1. Click your project name in Project Navigator
2. Select "LocalLoom" target
3. Go to "Signing & Capabilities" tab
4. If "App Sandbox" isn't there, click "+ Capability" and add it
5. Check these boxes:

```
✅ File Access → User Selected File (Read/Write)
✅ File Access → Downloads Folder (Read/Write)
✅ Hardware → Camera  ← CRITICAL!
✅ Hardware → Audio Input
✅ Network → Outgoing Connections (Client)
```

## Step 3: Build & Run (1 min)

1. Clean: `Cmd+Shift+K`
2. Build: `Cmd+B`  
3. Run: `Cmd+R`

## Step 4: Grant Permissions

When the app launches:
- Click "Allow" for Screen Recording
- Click "Allow" for Microphone
- (Speech permission appears when you enable voice-following mode)

## Step 5: Quick Test

1. Select "Display" from the dropdown
2. Set countdown to "None"
3. Click "Start Recording"
4. Wait 5 seconds
5. Click "Stop Recording"
6. Check Desktop for "Recording.mov"
7. Play it!

## ✅ If it works, you're done!

## ❌ If it doesn't work:

**Most common issue:** Forgot to enable "Camera" in App Sandbox
- Go back to Step 2
- Make sure "Camera" checkbox is ✅

**Second most common:** Missing Info.plist keys
- Go back to Step 1
- Verify all 3 keys are present

---

## 🎯 What to Test Next

### Test Teleprompter (Classic Mode)
1. Enable "Teleprompter" toggle
2. Type some text in the script box
3. Adjust speed slider
4. Start recording
5. Teleprompter window appears above notch
6. Text scrolls automatically

### Test Voice-Following Mode 🆕
1. Switch to "Voice-Following (Auto)" mode
2. Select "English (India) 🇮🇳" from language dropdown
3. Type your script
4. Enable "Highlight current phrase"
5. Click "Start Recording"
6. **Speak your script** - teleprompter follows your voice!

### Test Hotkeys
- `Cmd+Shift+R` - Start/Stop Recording
- `Cmd+Shift+T` - Toggle Teleprompter

### Test Window Capture
1. Switch to "Window" capture mode
2. Click "Browse..."
3. Select a window from the visual picker
4. Record it

---

## 🆘 Emergency Troubleshooting

**App crashes on launch:**
```
Check Info.plist has all 3 permission keys
```

**"Permission denied" error:**
```
System Settings → Privacy & Security → Screen Recording
Enable LocalLoom
Restart app
```

**No audio in recording:**
```
System Settings → Privacy & Security → Microphone
Enable LocalLoom
Restart app
```

**Speech recognition not working:**
```
1. Check you enabled voice-following mode
2. System Settings → Privacy & Security → Speech Recognition
3. Enable LocalLoom
4. Try speaking louder/clearer
```

---

## 📁 Files That Were Fixed/Created

You now have these new/updated files:

**Created:**
- ✅ `CloudStorageViews.swift` - UI for cloud upload status and settings
- ✅ `TESTING_READINESS_CHECKLIST.md` - Full testing guide
- ✅ `QUICK_START.md` - This file!

**Updated:**
- ✅ `CloudStorageManager.swift` - Added missing UI properties and methods
- ✅ `ContentView.swift` - Fixed undefined variable bug
- ✅ `LocalLoomApp.swift` - Removed unnecessary Core Data dependency

**Already Complete (no changes needed):**
- ✅ `SpeechRecognitionManager.swift`
- ✅ `TeleprompterTextMatcher.swift`
- ✅ `TeleprompterView.swift`
- ✅ `TeleprompterWindowController.swift`
- ✅ `CaptureController.swift`
- ✅ `SettingsManager.swift`
- ✅ `PermissionsHelper.swift`
- ✅ `HotkeyManager.swift`
- ✅ `WindowThumbnailView.swift`

---

## 🎉 You're Ready!

Everything is coded and working. Just complete Steps 1 & 2 above and you're good to go!

**Total time to get running: ~5 minutes** ⏱️

Happy testing! 🚀
