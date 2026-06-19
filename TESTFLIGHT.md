# Evidia (ChainMark) — TestFlight Readiness & Setup Checklist

**Purpose:** Make the "day-the-Mac-arrives" handoff near one-click. When the owner
has a Mac + Apple Developer account, getting a build into pilot PIs' hands should
take **hours, not weeks**. This doc is the precise runbook plus a pre-submission
**punch list** of blockers found in a self-audit of the repo (commit on `main`).

> ⚠️ **Cannot be done from this Linux sandbox.** Xcode, code signing, and Fastlane
> are macOS-only. Everything below is prepped and verified as far as possible
> without a Mac; the punch list flags what still needs a human on macOS.

---

## TL;DR — the critical path

1. **Generate a real Xcode project** (the repo's `.xcodeproj` is an empty stub). ← biggest blocker
2. **Enroll in the Apple Developer Program** ($99/yr).
3. **Wire the live Supabase URL + anon key** into the build (currently placeholders, and the app still uses Mock providers).
4. **Fix the punch-list items** below (remove bogus `arkit` requirement, set version/build, signing).
5. **Create the app record** in App Store Connect + a TestFlight internal group.
6. **`bundle exec fastlane beta`** → upload → invite pilot PIs.

---

## Pre-submission PUNCH LIST (must-fix blockers found in audit)

| # | Severity | Item | Where | Fix |
|---|----------|------|-------|-----|
| P1 | 🔴 Blocker | **No real Xcode project.** `ChainMark.xcodeproj/project.pbxproj` is a 9-line empty stub with no targets, build settings, or signing. Nothing can build until a real project exists. | `ChainMark.xcodeproj/` | Generate the project on the Mac — see *Generate the Xcode project* below. Recommended: **XcodeGen** with the provided `project.yml`, or create manually per the repo README. |
| P2 | 🔴 Blocker | **Backend is on Mock providers.** `SupabaseClient` hard-codes `MockAuthProvider()` + `MockAPIClient()`; the real `SupabaseAuthProvider`/`APIClient` are commented out. Pilot uploads/report generation won't hit the live backend. | `ChainMark/Services/SupabaseClient.swift` | Implement & switch in real providers, OR confirm the pilot is **local-capture-only** (capture+seal+export work fully offline without the backend — that's a valid first pilot). Decide with the lead. |
| P3 | 🔴 Blocker | **Supabase creds are placeholders.** `Configuration.swift` falls back to `https://placeholder.supabase.co` / `placeholder-anon-key`. | `ChainMark/Services/Configuration.swift` | Inject the live `SUPABASE_URL` + `SUPABASE_ANON_KEY` via an xcconfig/Info.plist build setting. See *Wire the live Supabase backend*. |
| P4 | 🟠 High | **Bogus `arkit` device requirement.** `Info.plist` lists `arkit` in `UIRequiredDeviceCapabilities`, but **no code uses ARKit** (grep confirms zero references). This needlessly blocks otherwise-eligible iPhones and can confuse review. | `ChainMark/Info.plist` | Remove `<string>arkit</string>` from `UIRequiredDeviceCapabilities`. (Fixed in this PR — see below.) |
| P5 | 🟠 High | **Brand mismatch: app is "ChainMark", business is "Evidia".** Display name, bundle ID (`com.chainmark.app`), README, and license all say ChainMark. | repo-wide | Decide the shipping brand with the owner **before** registering the bundle ID in App Store Connect (the bundle ID can't be reused/renamed after a build is uploaded). If shipping as Evidia, rename now. |
| P6 | 🟡 Medium | **`print()` debug logging** in 6 files (CameraViewModel, TombstoneStore, UploadQueue, SupabaseClient, SecureStorageManager, CryptoManager). Not a review blocker, but leaks internal detail to device logs. | various | Gate behind `#if DEBUG` or replace with `os.Logger` with appropriate privacy levels before the paid launch. Acceptable for an internal pilot. |
| P7 | 🟡 Medium | **No app icon / launch screen asset catalog.** `UILaunchScreen` is empty and there's no `Assets.xcassets`. TestFlight builds **require** an app icon. | project | Add an `AppIcon` set (1024×1024 + required sizes) when generating the project. Builds without an icon are rejected at upload. |
| P8 | 🟢 Low | **Background modes `audio` + `location`** declared. Apple may ask why during review. We do use background location for capture continuity; `audio` is only justified if recording continues in background. | `Info.plist` | Keep `location`; drop `audio` from `UIBackgroundModes` unless background audio recording is actually required. |

> P1–P3 are the true gating items. P4 and P7 are quick and have to be right for a
> clean upload. P5 is a **business decision that's cheapest to make before the first
> upload**. P6/P8 are polish.

---

## 1. Apple Developer Program enrollment ($99/yr)

- Enroll at <https://developer.apple.com/programs/enroll/>. **Individual** is fine to
  start; **Organization** (requires a D-U-N-S number) is better if Evidia is an LLC and
  you want the seller name to be the company. Org enrollment can take days — start early.
- Info you'll need: Apple ID (with 2FA), legal name/entity, payment method.
- After enrollment you get a **Team ID** (10 chars) at Account → Membership — you'll put
  this in `fastlane/Appfile`.

## 2. Bundle ID, capabilities & entitlements

- **Bundle identifier:** currently `com.chainmark.app` (from `Info.plist`). Confirm or
  change per punch item **P5** before registering it. Once a build with a bundle ID is
  uploaded, that ID is effectively permanent for the app.
- **Capabilities the app actually uses** (verified against source):
  - **Camera** — `AVCaptureSession` (AVFoundation). ✅ usage string present.
  - **Microphone** — audio track on video. ✅ usage string present.
  - **Location (When In Use)** — `CoreLocation`, GPS waypoints. ✅ usage string present.
  - **Keychain / Secure Enclave** — `EnclaveManager` (P-256 signing). ✅ entitlement present
    (`keychain-access-groups` in `ChainMark.entitlements`).
  - **Background Modes** — `location` (justified), `audio` (review per **P8**).
- **No special entitlement** is needed for Secure Enclave itself; keychain access group is
  sufficient. No push, no associated domains, no app groups in use.

## 3. Info.plist usage strings — VERIFIED PRESENT

All three required strings exist and are descriptive (good for review):
- `NSCameraUsageDescription` ✅
- `NSMicrophoneUsageDescription` ✅
- `NSLocationWhenInUseUsageDescription` ✅

Nothing missing here. (If you later add Speech transcription — Stage C4 — you'll need
`NSSpeechRecognitionUsageDescription`; it is **not** present yet but isn't needed until
that feature ships.)

## 4. Generate the Xcode project (resolves P1)

The repo intentionally ships source files without a real `.xcodeproj`. Two paths:

**Option A — XcodeGen (recommended, near one-click).** Install once: `brew install xcodegen`.
A starter `project.yml` is committed at the repo root. From the repo root:
```bash
xcodegen generate      # produces ChainMark.xcodeproj from project.yml
open ChainMark.xcodeproj
```
Then in Xcode: select the target → Signing & Capabilities → check **Automatically manage
signing** → pick your Team. Add the **AppIcon** asset (P7).

**Option B — Manual (per repo README).** File → New → Project → iOS App (SwiftUI, Swift,
iOS 17), product name `ChainMark`, org id `com.chainmark`, then drag in the existing
`ChainMark/` source files and set the Info.plist + entitlements. Slower and error-prone;
prefer Option A.

## 5. Wire the live Supabase backend (resolves P3)

Recommended: a build-setting / xcconfig approach so no secrets are in source.
1. In Xcode, add a `Config.xcconfig` (gitignored) or set User-Defined build settings:
   `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
2. Reference them from `Info.plist` as `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` keys —
   `Configuration.swift` already reads these via `Bundle.main.object(forInfoDictionaryKey:)`.
3. Get the live values from the backend engineer / Supabase dashboard (Project Settings →
   API). The **anon** key is safe to ship (RLS-protected); never ship the service-role key.
4. For real auth/upload, also resolve **P2** (swap in real providers).

## 6. Signing & provisioning (pilot)

- **Use automatic signing** for the pilot — simplest, no `match`/manual profiles to manage.
  The Fastfile passes `-allowProvisioningUpdates` so Xcode creates profiles as needed.
- If/when you have multiple developers or CI, graduate to `fastlane match` (a shared,
  encrypted cert/profile repo). Out of scope for the first pilot.

## 7. App Store Connect: create the app record + TestFlight group

1. <https://appstoreconnect.apple.com> → **Apps → +** → New App.
   - Platform iOS, name (ChainMark/Evidia per P5), primary language, bundle ID (must
     already be registered under Certificates, IDs & Profiles — Xcode does this on first
     run, or register manually), and an SKU (any unique string, e.g. `evidia-ios-001`).
2. **TestFlight tab → Internal Testing → create a group** (e.g. "Pilot PIs").
   Internal testers (up to 100, must be App Store Connect users on your team) get builds
   **immediately, no Beta App Review**.
3. For PIs **outside** your org, use **External Testing** (up to 10,000). The **first**
   external build needs a short **Beta App Review** (usually < 24h); subsequent builds
   from the same version are auto-approved. Provide: a beta description, what to test, and
   a contact email. Privacy: declare camera/mic/location usage truthfully.

## 8. Invite the first pilot PIs as testers

- **Internal:** add them as Users (Account Holder/Admin invites via App Store Connect →
  Users and Access), assign to the internal group → they get a TestFlight email instantly.
- **External (recommended for real PIs):** TestFlight tab → External group → add testers by
  **email**, or share the **public TestFlight link**. They install the **TestFlight app**
  from the App Store, tap the invite, and install the beta.
- Tie this to the validation channel: the owner's father's PI network is the target tester
  pool. Send a one-paragraph "what to test" focused on the **capture → seal → report** loop
  and **capture-to-report time** (the north-star KPI).

## 9. Ship a build

```bash
cd <repo root>
cp .env.example fastlane/.env     # fill in ASC_* and SUPABASE_* values
bundle install                    # installs fastlane (see Gemfile)
bundle exec fastlane beta         # builds + uploads to TestFlight
```
The `beta` lane bumps the build number, signs (automatic), archives, and uploads. It
fails fast with a clear message if the Xcode project doesn't exist yet (P1).

---

## Files added in this PR

- `fastlane/Fastfile` — `beta` (build+upload to TestFlight) and `build_only` lanes, with
  App Store Connect API-key auth via env vars and a pre-flight project-exists check.
- `fastlane/Appfile` — identity config with `team_id` / `apple_id` / `app_identifier`
  placeholders and inline guidance.
- `Gemfile` — pins Fastlane for reproducible installs.
- `.env.example` — template for ASC API key + Supabase live creds (real `.env` is gitignored).
- `project.yml` — XcodeGen spec so the real Xcode project is generated in one command (P1).
- `Info.plist` — removed bogus `arkit` device requirement (P4).

## Troubleshooting

- **"No ChainMark.xcodeproj" on `fastlane beta`** → you skipped step 4 (generate project).
- **Upload rejected: missing app icon** → add the `AppIcon` asset (P7).
- **2FA prompt hangs CI** → set `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT` to use
  the App Store Connect API key instead of interactive Apple ID login.
- **"Invalid bundle ID"** → register the bundle ID under Certificates, IDs & Profiles first
  (or let Xcode auto-create it on first automatic-signing build).
- **External testers can't install** → the first external build is in Beta App Review; wait
  for approval or use internal testing for the very first round.
