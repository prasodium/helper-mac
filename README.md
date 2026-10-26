# Helper for Mac

A native, lightweight AI assistant for macOS, written in Swift with SwiftUI and AppKit.
It is the Mac-only sibling of [Helper](https://github.com/prasodium/helper) (Electron), rebuilt to feel
like a first-party Apple app: a real translucent window, a menu-bar item, standard Settings (⌘,),
the system Keychain, and a **~2.6 MB** download (the Electron app is ~200 MB).

> Helper is a normal, visible app. It shows up in screen shares and recordings like any other window,
> has a Dock icon, and never hides itself from other people or from proctoring software.

## Features

| | Free | Pro |
|---|:--:|:--:|
| Ask questions, solve MCQs, summarize, debug (typed or pasted) | ✓ | ✓ |
| Window transparency, always-on-top | ✓ | ✓ |
| Streaming answers with Markdown and copyable code blocks | ✓ | ✓ |
| Capture a screen region, analyze the whole screen (ScreenCaptureKit) | | ✓ |
| Scrolled capture: stitch a long page into one image | | ✓ |
| Voice input (Quick Answer + Detailed Explanation) and read-aloud replies | | ✓ |
| Live translation of meeting audio (system audio or microphone) | | ✓ |
| Resume, document library (PDF/DOCX/TXT/MD) and GitHub projects as context | | ✓ |
| Mock-interview practice with feedback | | ✓ |
| Solve / Explain code quick actions | | ✓ |

Pro is unlocked by the same `HLP-XXXX-XXXX-XXXX` activation key as the Electron app
(sold through [Helper Store](https://github.com/prasodium/helper-store); 1 payment = 1 device,
7-day offline grace, device ID derived the same way so a Mac counts once).

**Mock interview practice** replaces the live "answer the interviewer for me" mode of the Electron
app: Helper plays the interviewer, asks one question at a time (tailored to your resume and projects),
and gives feedback on your answers.

### Keyboard shortcuts (global)

| Shortcut | Action |
|---|---|
| ⌃⌥Space | Show / hide Helper |
| ⌃⌥S | Capture a screen region |
| ⌃⌥V | Start / stop voice input |
| ⌃⌥A | Analyze the whole screen |

## Install

Download `Helper-x.y.z.dmg` from [Releases](../../releases), drag Helper to Applications.
Builds are ad-hoc signed, not notarized. If macOS says the app is damaged or from an unidentified
developer, right-click → Open, or run `scripts/fix-gatekeeper.sh`.

On first use macOS asks for **Screen Recording** (capture, system-audio translation) and **Microphone**
(voice, mic translation). Then open Settings → OpenAI and paste your own API key; it is stored in the
Keychain and only ever sent to OpenAI.

Requires macOS 14 (Sonoma) or later. Apple silicon and Intel.

## Develop

Only the Command Line Tools are needed (Xcode is optional).

```bash
swift run Helper            # run from the terminal
swift run HelperChecks      # core logic checks (licensing, RAG, stitching, parsing…)
scripts/build-app.sh        # dist/Helper.app (universal, ad-hoc signed)
scripts/make-dmg.sh         # dist/Helper-<version>.dmg
```

Open `Package.swift` in Xcode to use the debugger and previews.

```
Sources/
  HelperCore/    UI-free logic: OpenAI client, RAG, license, image stitching, translation
  HelperMac/     SwiftUI + AppKit app: windows, capture, audio, hotkeys, settings
  HelperChecks/  dependency-free test runner (XCTest needs full Xcode)
scripts/         app bundle, DMG, icon, Gatekeeper helper
```

`Local.swift` is a tiny stand-in for `@State` so the project builds without Xcode's SwiftUI macro plugin.

## Releasing

Tag and push: `git tag v1.0.0 && git push --tags`. The Release workflow builds the universal app and
attaches the DMG to a GitHub release.

## Differences from the Electron app

- Native UI, Keychain storage, ScreenCaptureKit capture, `SMAppService` launch-at-login (off by default).
- Visible, normal Mac window instead of a hidden overlay; no auto-hide in meetings.
- No test-taking mode and no live "feed me the interviewer's answer" mode.
- Documents and resume indexes persist across launches (no re-embedding).
- Default model is `gpt-4o` and is editable in Settings.
