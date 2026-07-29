# 🚨 IMMEDIATE BUILD FIX CHECKLIST

## Most Common Cause: Files Not Added to Target

This is the #1 reason for "Cannot find X in scope" errors.

### **Quick Fix (30 seconds):**

1. **In Xcode, select EACH of these files one by one:**
   - CloudStorageViews.swift ⚠️ (I just created this)
   - SettingsManager.swift
   - SpeechRecognitionManager.swift
   - CloudStorageManager.swift
   - TeleprompterTextMatcher.swift
   - TeleprompterView.swift
   - TeleprompterWindowController.swift
   - CaptureController.swift
   - PermissionsHelper.swift
   - HotkeyManager.swift
   - WindowThumbnailView.swift
   - ContentView.swift
   - LocalLoomApp.swift

2. **For each file, check the right panel (File Inspector):**
   - Look for "Target Membership" section
   - Make sure "LocalLoom" has a ✅ checkmark
   - If no checkmark, CLICK IT!

**This single step fixes 90% of build errors!**

---

## Step-by-Step: Add CloudStorageViews.swift to Target

Since I just created this file, it might not be in your target:

1. **Click on `CloudStorageViews.swift`** in Project Navigator (left panel)
2. **Look at right panel** (press Cmd+Opt+1 if not visible)
3. **Find "Target Membership"** section
4. **Check the box** next to "LocalLoom"

---

## Alternative: Check All Files At Once

1. **Select your project** (top item in Project Navigator)
2. **Select "LocalLoom" target**
3. **Go to "Build Phases" tab**
4. **Expand "Compile Sources"**
5. **You should see ALL .swift files listed**

**Expected files in "Compile Sources":**
```
LocalLoomApp.swift
ContentView.swift
SettingsManager.swift
SpeechRecognitionManager.swift
TeleprompterTextMatcher.swift
TeleprompterView.swift
TeleprompterWindowController.swift
CaptureController.swift
PermissionsHelper.swift
HotkeyManager.swift
WindowThumbnailView.swift
CloudStorageManager.swift
CloudStorageViews.swift ← Make sure this is here!
```

**If any are missing:**
1. Click the "+" button under Compile Sources
2. Find the missing .swift file
3. Click "Add"

---

## Common Error Messages & Their Meaning

### Error: "Cannot find 'CloudUploadStatusView' in scope"
**Cause:** CloudStorageViews.swift not in target  
**Fix:** Add CloudStorageViews.swift to target (see above)

### Error: "Cannot find 'WindowPickerRow' in scope"
**Cause:** WindowThumbnailView.swift not in target  
**Fix:** Add WindowThumbnailView.swift to target

### Error: "Use of undeclared type 'SettingsManager'"
**Cause:** SettingsManager.swift not in target  
**Fix:** Add SettingsManager.swift to target

### Error: "Value of type 'CloudStorageManager' has no member 'isUploading'"
**Cause:** Using old version of CloudStorageManager.swift  
**Fix:** Make sure you have the updated version I provided

---

## Nuclear Option: Force Rebuild Everything

If nothing else works:

1. **Close Xcode** (Cmd+Q)
2. **Delete Derived Data:**
   - Open Finder
   - Press Cmd+Shift+G
   - Paste: `~/Library/Developer/Xcode/DerivedData`
   - Find folder with "LocalLoom" in name
   - Delete it
3. **Reopen Xcode**
4. **Clean:** Cmd+Shift+K
5. **Build:** Cmd+B

---

## What to Share If Still Failing

Please share a screenshot or copy/paste of:

**1. The Issue Navigator (left panel showing errors):**
- Press Cmd+5 to open it
- Screenshot or copy first 3-5 errors

**2. The specific error details:**
```
Example:
/path/to/ContentView.swift:123: error: Cannot find 'CloudUploadStatusView' in scope
```

**3. Build Phases → Compile Sources list:**
- Does it include CloudStorageViews.swift?
- Screenshot this section

---

## Quick Diagnostic Questions

Answer these to help me help you:

1. **Is CloudStorageViews.swift in Project Navigator?** 
   - [ ] Yes, I can see it
   - [ ] No, I don't see it

2. **When you click CloudStorageViews.swift, do you see "Target Membership" in right panel?**
   - [ ] Yes, LocalLoom is checked ✅
   - [ ] Yes, but LocalLoom is NOT checked ❌
   - [ ] I don't see Target Membership section

3. **What's the FIRST error message (exact text)?**
   - Write it here: _________________

4. **Which file does the error point to?**
   - File name: _________________
   - Line number: _________________

---

## Try This RIGHT NOW:

```
Step 1: Click CloudStorageViews.swift in Project Navigator
Step 2: Press Cmd+Opt+1 (show File Inspector)
Step 3: Look for "Target Membership"
Step 4: Check ✅ the "LocalLoom" checkbox
Step 5: Cmd+B (build)
```

**Did that fix it?**

If yes → Great! Move on to testing
If no → Share the error message and I'll help immediately

---

## Last Resort: Verify File Exists

If CloudStorageViews.swift isn't showing in Project Navigator:

1. **Right-click on project folder** (where other .swift files are)
2. **Select "Add Files to LocalLoom..."**
3. **Navigate to where CloudStorageViews.swift is saved**
4. **Select it**
5. **Make sure "Copy items if needed" is checked**
6. **Make sure "LocalLoom" target is checked**
7. **Click "Add"**

---

**Do the "Try This RIGHT NOW" steps above and let me know what happens!**

The build should work - we just need to make sure all files are properly added to the target. This is a configuration issue, not a code issue.
