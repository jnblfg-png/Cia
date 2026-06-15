# ChainMark — iOS App

**Private Investigator Evidence & Reporting Tool**

An iOS application that turns an iPhone into a complete field-evidence capture, sealing, and reporting tool for professional private investigators.

## Project Structure

```
ChainMark/
├── ChainMark/                    # App source code
│   ├── ChainMarkApp.swift        # App entry point (@main)
│   ├── ContentView.swift         # Main camera view with recording controls
│   ├── Info.plist                # App permissions & configuration
│   ├── ChainMark.entitlements    # Keychain entitlements
│   ├── Camera/
│   │   ├── CameraViewModel.swift  # AVFoundation capture session, location, recording
│   │   └── CameraPreviewView.swift # UIViewRepresentable for live camera preview
│   ├── Storage/
│   │   └── SecureStorageManager.swift # Encrypted app-private file storage
│   ├── Models/
│   │   └── (future: evidence models, chain-of-custody)
│   └── Utils/
│       └── (future: crypto helpers, timestamp utilities)
└── README.md
```

## Requirements

- **Xcode 15+** (Swift 5.9+)
- **iOS 17.0+** deployment target
- **Apple Developer Account** (for device testing)
- Physical iPhone with camera, microphone, and GPS
  - Camera works in iOS Simulator (macOS camera), GPS does not

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App** template
3. Configure:
   - **Product Name:** `ChainMark`
   - **Team:** Your Apple Developer team
   - **Organization Identifier:** `com.chainmark`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Minimum Deployment Target:** iOS 17.0
4. Save the project
5. **Replace** the auto-generated files with the files from this directory

### 2. Configure Permissions (Info.plist)

The `Info.plist` includes required usage descriptions:
- `NSCameraUsageDescription` — Camera access for video recording
- `NSMicrophoneUsageDescription` — Microphone for audio recording
- `NSLocationWhenInUseUsageDescription` — GPS for evidence geolocation

### 3. Configure Signing & Capabilities

- **Signing:** Enable automatic signing with your Developer account
- **Capabilities:** Add **Keychain Sharing** (for Secure Enclave in Stage B3)

### 4. Run on Device

1. Connect your iPhone or use a provisioning profile
2. Select your device as the run target
3. Build and run (⌘R)

## Architecture Decisions

### Camera: AVFoundation (NOT system camera/photo library)

- Uses `AVCaptureSession` directly with `AVCaptureMovieFileOutput`
- Camera preview via `AVCaptureVideoPreviewLayer` wrapped in `UIViewRepresentable`
- Never uses `UIImagePickerController`, `PHPickerViewController`, or camera app URLs

### Storage: App-Private, Encrypted

- Videos stored in `Documents/ChainMarkEvidence/Videos/`
- `NSFileProtectionComplete` applied to all evidence directories
- `isExcludedFromBackup = true` — files never synced to iCloud
- Metadata stored as JSON alongside video files
- NOT saved to camera roll, photo library, or shared directories

### GPS: CoreLocation

- `kCLLocationAccuracyBest` for maximum precision
- Horizontal accuracy displayed to user (never fake precision)
- Invalid/simulated locations filtered out (accuracy < 0)

## Build Order Context

This is **Stage B, Step 1** of the build order:

| Step | Status | Description |
|------|--------|-------------|
| B1   | ✅ Done | SwiftUI + AVFoundation video capture to private storage |
| B2   | 🔜 Next | Timestamp + GPS at record start/during/end |
| B3   | 🔜 Next | SHA-256 hashing + Secure Enclave signing on capture |
| B4   | 🔜 Next | Burn visible timestamp into video frame |
| B5   | 🔜 Next | Chronological timeline of local captures |
| B6   | 🔜 Next | Local export: video + metadata/custody sheet |

## Invariants (NEVER violate)

1. Evidence sealed at capture, never altered — originals are write-once
2. Never route through system camera/photo library — use AVFoundation in-app
3. Files in app-private encrypted storage, NOT shared camera roll or iCloud
4. No hand-rolled crypto — only CryptoKit + Secure Enclave
5. Display GPS accuracy radius; never present false precision
6. Capture + seal must work fully offline (upload is transport only)

## License

Proprietary — ChainMark Inc.