# ArticrenWave-iOS
**Augmented Reality Classical Music Score Writing Application**
by DART Meadow LLC & Radical Deepscale LLC

![Articren Wave Logo](ArticrenWave/Assets.xcassets/AppIcon.appiconset/logo.png)

---

## Overview
Articren Wave is a professional-grade iOS app for **writing, performing, and exporting classical music scores** with:
- Full **Grand Staff** score writing (treble + bass, expandable to full symphony)
- **88-key virtual piano** with octave jump, instrument switching (10 instruments)
- Note entry: whole, half, quarter, eighth, sixteenth notes + rests
- **Ties, slurs, accidentals** (sharp, flat, natural), accent markers
- **Live recording mode** — play the piano and notes drop straight to the staff
- Export: **MP3 / WAV / M4A / MIDI / PDF**
- **Sign In with Apple** + **iCloud sync**
- Dark mode UI with 5 color themes
- Powered by the **LEATR Neural Architecture** (Lead Edge Ash Tree Reflex)

---

## Bundle ID
`ArticrenWaveAppStore`

---

## Xcode Setup

### Requirements
- Xcode 15.0+
- iOS 16.0+ deployment target
- Swift 5.9

### 1. Open the project
```bash
open ArticrenWave.xcodeproj
```

### 2. Sign the app
1. Select the `ArticrenWave` target
2. Under **Signing & Capabilities**, set your **Team** (Dart Solar Punk / DART Meadow)
3. Ensure **Bundle Identifier** = `ArticrenWaveAppStore`

### 3. Entitlements
The following capabilities are pre-configured in `ArticrenWave.entitlements`:
- ✅ Sign In with Apple
- ✅ iCloud Documents (`iCloud.ArticrenWaveAppStore`)
- ✅ Push Notifications

These should already be enabled under your App ID in App Store Connect.

### 4. SoundFont
Place a `GrandPiano.sf2` (and other instrument `.sf2` files) inside:
```
ArticrenWave/Resources/Sounds/
```
Recommended free source: **GeneralUser GS** (http://schristiancollins.com/generaluser.php)
Or any commercial high-quality orchestral SoundFont.

---

## GitHub Actions CI/CD

### Required Secrets (set in repo Settings → Secrets → Actions)

| Secret | Value |
|--------|-------|
| `BUILD_CERTIFICATE_BASE64` | Base64 of your `.p12` distribution certificate |
| `P12_PASSWORD` | Password for the `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 of your `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Any secure string for the CI keychain |
| `ASC_PRIVATE_KEY` | Contents of `AuthKey_NQXQ595W59.p8` |
| `ASC_ISSUER_ID` | Found in App Store Connect → Keys |
| `DEVELOPMENT_TEAM` | Your 10-character Apple Team ID |

### Deploy
Push to `main` or trigger manually via **Actions → Run workflow**.

---

## App Store Connect

### App ID
- **Name:** Articren Wave
- **Bundle ID:** ArticrenWaveAppStore

### Capabilities to enable in App Store Connect:
- ✅ Sign In with Apple
- ✅ iCloud
- ✅ In-App Purchases (for future premium features)
- ✅ Push Notifications

### App Description (use in App Store submission)
```
Articren Wave — the AR classical music score writing app built for composers 
who think in sound. Write for Grand Piano, Chamber Orchestra, or Full Symphony 
directly on your iPhone or iPad.

• 88-key virtual piano with 10 orchestral instruments
• Full staff score writing: treble, bass, all grand orchestra parts
• Note entry: whole through sixteenth notes, all rests, ties, slurs
• Live recording: play the keys and watch notation appear on the staff
• Export: MP3, WAV, MIDI, PDF — SoundCloud-ready audio quality
• Sign In with Apple — syncs across devices with iCloud
• Dark mode with 5 custom color themes

Powered by LEATR (Lead Edge Ash Tree Reflex) neural architecture.
© 2026 DART Meadow LLC & Radical Deepscale LLC
```

### Keywords (100 chars max)
`sheet music,score writing,piano,classical,notation,composer,orchestra,MIDI,music,AR`

---

## Architecture

```
ArticrenWave/
├── ArticrenWaveApp.swift        # @main entry point
├── Models/
│   ├── AppState.swift           # Theme, orientation, UI state
│   └── MusicModels.swift        # Score, Measure, Chord, Pitch, Note data models
├── Services/
│   ├── ScoreEngine.swift        # Score editing state machine
│   ├── AudioEngine.swift        # AVAudioEngine, SoundFont, MIDI render, export
│   ├── AuthManager.swift        # Sign In with Apple + iCloud
│   └── ProjectManager.swift     # Save/load/export .awscore / PDF / MIDI
├── Views/
│   ├── ContentView.swift        # Root navigation shell
│   ├── OnboardingView.swift     # Welcome + storage + Sign In with Apple
│   ├── MainComposerView.swift   # Score area + piano drawer shell
│   ├── ScoreEditorView.swift    # Staff canvas, note rendering, tap entry
│   ├── NotePalette.swift        # Note/rest/accidental/tie toolbar
│   ├── PianoDrawerView.swift    # 88-key piano + octave jump + instrument picker
│   ├── MainMenuOverlay.swift    # Slide-out main menu (profile, projects, themes)
│   └── SheetsViews.swift        # Export, Layout, Tempo sheets
├── Extensions/
│   └── Extensions.swift         # Color(hex:), utility helpers
├── Assets.xcassets/             # App icon, colors
├── Info.plist                   # App configuration
└── ArticrenWave.entitlements    # Sign In with Apple, iCloud, network
```

---

## Music Theory Reference

### Middle C Locations
- **Middle C (C4)**: middle white key of the 88-key piano
  - **Treble clef**: first ledger line below the staff
  - **Bass clef**: first ledger line above the staff
- **C3 (Bass Middle C marker)**: one octave below middle C, marked on piano
- **Octaves**: labeled 1–7 on piano keys; Σ button jumps to flats/sharps overview

### Note Rules
- Max **4 notes per chord**, all within **4 staff positions** of the root
- Max **4 beats per measure** (4/4 time fixed for v1.0)
- Shortest note: **sixteenth** (0.25 beats)
- Tempo: 40–208 BPM, default **80 BPM**

---

## License
Proprietary — © 2026 DART Meadow LLC & Radical Deepscale LLC. All rights reserved.
