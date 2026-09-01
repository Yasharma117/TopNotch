<div align="center">

<img src="TopNotch/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="TopNotch app icon" width="128">

# TopNotch

**A macOS teleprompter that lives in your Mac's notch, follows your voice, and records your microphone audio locally.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

[Live website](https://topnotch-website-tau.vercel.app/) ·
[Run locally](#run-locally) ·
[How it works](#how-it-works) ·
[Keyboard shortcuts](#keyboard-shortcuts) ·
[Limitations](#known-limitations)

</div>

---

TopNotch keeps a script available while you read, scrolls it automatically or
follows your voice, and can record microphone audio to a local `.m4a` file.

**Live website:** [topnotch-website-tau.vercel.app](https://topnotch-website-tau.vercel.app/)

**Companion website source:** [Yasharma117/topnotch-website](https://github.com/Yasharma117/topnotch-website)

## What it does

- Displays a compact, expandable teleprompter panel anchored to the macOS notch.
- Accepts typed scripts and text files dropped onto the panel.
- Parses optional titles and section breaks from script text.
- Arranges long scripts into readable sections and estimates speaking time.
- Scrolls at a configurable speed in classic mode.
- Uses Apple's speech recognition APIs in on-device mode to follow spoken text.
- Matches speech with normalization and fuzzy, accent-tolerant text matching.
- Highlights the matched phrase while voice sync is active.
- Records microphone audio locally as an MPEG-4 AAC `.m4a` file.
- Provides a configurable countdown, font size, alignment, visible line count,
  and speech locale.
- Saves teleprompter and capture settings with `UserDefaults`.

TopNotch is a menu-bar/accessory app. The notch panel is its primary interface;
it does not rely on a conventional Dock window.

## How it works

1. Enter a script in the panel or drop a text file onto it.
2. `SectionParser` normalizes the text, detects a short first-line title, and
   splits sections on `---` markers. A marker can include a pause, such as
   `--- 3s`.
3. `TextArrangementEngine` can insert section breaks based on sentence and
   topic changes. The original text can be restored with the in-app undo action.
4. When recording starts, TopNotch runs an optional countdown, starts microphone
   capture, and begins the selected teleprompter mode.
5. Classic mode advances the script at the configured speed. Speech-sync mode
   sends audio to Apple's on-device recognizer, matches recent phrases against
   the script, and smoothly moves the display forward.

## Requirements

- macOS 13.0 or later.
- Xcode with Swift 5 support.
- A Mac with a compatible notch/display setup for the intended presentation.
- Microphone permission to record audio and run speech-sync input.
- Speech Recognition permission when speech sync is enabled.
- An installed on-device speech model for the selected locale. TopNotch
  requests on-device recognition and reports an error when the locale cannot
  run locally.

## Run locally

1. Clone the repository and open `TopNotch.xcodeproj` in Xcode.
2. Select the `TopNotch` scheme and a macOS destination.
3. Build and run the app.
4. Grant microphone and speech-recognition permissions when prompted, then
   hover over the notch to expand the panel.

The default script uses Indian English (`en-IN`). You can change the locale and
other teleprompter settings from the settings popover.

### Script format

Plain text is supported. The first short non-empty line is treated as a title
when body text follows. Add section breaks on their own lines:

```text
Product demo

Introduce the product and the problem it solves.
--- 2s
Explain the workflow and show the main screen.
---
Close with the next step.
```

## Keyboard shortcuts

These global shortcuts are registered by the app:

| Shortcut | Action |
| --- | --- |
| `Cmd+Shift+R` | Start or stop recording |
| `Cmd+Shift+T` | Toggle the teleprompter |
| `Shift+Left` | Decrease scroll speed |
| `Shift+Right` | Increase scroll speed |
| `Shift+Up` | Move the script up |
| `Shift+Down` | Move the script down |

Move and speed shortcuts are intended for use while the teleprompter is
running.

## Repository structure

```text
TopNotch/
  *.swift                 App, notch UI, parsing, scrolling, speech, and capture
  Info.plist              macOS app metadata and privacy descriptions
  TopNotch.entitlements   Sandbox, file access, and microphone entitlements
TopNotchTests/             Swift Testing and geometry tests
TopNotchUITests/           Launch and accessory-app smoke tests
Docs/                      Implementation notes and troubleshooting material
scripts/                   Archive/export helpers and release notes
TopNotch.xcodeproj/        Xcode project and schemes
LICENSE                    MIT license
```

## Verification status

The repository contains a macOS application target, a unit-test target, and a
UI-test target. The project configuration can be inspected with:

```bash
xcodebuild -list -project TopNotch.xcodeproj
```

The current tests cover notch geometry invariants and basic app launch behavior.
The UI test suite does not yet exercise the complete script, permission,
speech-sync, or audio-recording workflow. Hardware, OS permissions, and
on-device speech model availability can affect local verification.

## Known limitations

- The current capture implementation records microphone audio only. It does not
  produce a screen recording or a combined audio/video movie.
- Speech sync depends on Apple's recognizer being available for the selected
  locale and can behave differently across microphones, accents, noise levels,
  and macOS speech-model installations.
- The app is designed around a notch-style presentation and has not been
  documented as a general-purpose windowed teleprompter.
- Permission prompts and global hotkeys require macOS user approval and can be
  affected by system privacy settings.
- The repository's older `Docs/` files include historical material that still
  refers to the former `LocalLoom` name or describes features not confirmed in
  the current source. Treat the Swift implementation and Xcode project as the
  source of truth until those documents are refreshed.

## Documentation and release files

Useful repository notes include:

- [`Docs/BUILD_TROUBLESHOOTING.md`](Docs/BUILD_TROUBLESHOOTING.md)
- [`Docs/INFO_PLIST_VERIFICATION.md`](Docs/INFO_PLIST_VERIFICATION.md)
- [`Docs/SMART_TELEPROMPTER_COMPLETE.md`](Docs/SMART_TELEPROMPTER_COMPLETE.md)
- [`Docs/TELEPROMPTER_MODE_TOGGLE.md`](Docs/TELEPROMPTER_MODE_TOGGLE.md)
- [`Docs/TESTING_READINESS_CHECKLIST.md`](Docs/TESTING_READINESS_CHECKLIST.md)
- [`scripts/README-release.md`](scripts/README-release.md)

These notes are supplementary and may contain historical status statements; the
known limitations above are the current README-level qualification.

## Website

The companion website is a separate Next.js project that demonstrates the
product and documents its interaction model. Visit the deployed site at
[topnotch-website-tau.vercel.app](https://topnotch-website-tau.vercel.app/) or
view its source at [Yasharma117/topnotch-website](https://github.com/Yasharma117/topnotch-website).

## License

TopNotch is available under the [MIT License](LICENSE) for the original source
code in this repository. Third-party dependencies, Apple frameworks, fonts,
icons, and any brand or externally supplied assets remain subject to their own
licenses and terms. TopNotch is not affiliated with Apple.
