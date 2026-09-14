# SmartDukan Flutter APK — Build Instructions

## Prerequisites

1. Install **Flutter SDK** (stable channel):
   - Download from https://docs.flutter.dev/get-started/install/windows
   - Extract to `C:\flutter` (or any path without spaces)
   - Add `C:\flutter\bin` to your `PATH` environment variable
   - Run `flutter doctor` to verify setup

2. Install **Android Studio** (for Android SDK):
   - Download from https://developer.android.com/studio
   - In Android Studio → SDK Manager, install:
     - Android SDK Platform 34
     - Android SDK Build-Tools 34.0.0
     - NDK (Side by side)

3. Accept Android licenses:
   ```
   flutter doctor --android-licenses
   ```

## Build Steps

1. Open a terminal and `cd` into this folder:
   ```
   cd path\to\m2i-seeds\flutter_app
   ```

2. Get dependencies:
   ```
   flutter pub get
   ```

3. Build the APK:
   ```
   flutter build apk --release
   ```
   The APK will be at: `build\app\outputs\flutter-apk\app-release.apk`

   Or for a debug build (easier, no signing needed):
   ```
   flutter build apk --debug
   ```

4. Install directly on a connected Android phone:
   ```
   flutter install
   ```

## Project Structure

```
flutter_app/
├── lib/
│   ├── main.dart              — Entry point
│   ├── app.dart               — Bottom nav shell (4 tabs)
│   ├── theme.dart             — Colors matching web app
│   ├── supabase_config.dart   — Supabase URL + Railway API URL
│   ├── models/
│   │   └── models.dart        — StockItem, BillItem, Bill, MasterItem
│   ├── services/
│   │   ├── supabase_service.dart  — All DB + API calls
│   │   └── voice_service.dart     — Mic recording + Railway voice API
│   └── screens/
│       ├── home_screen.dart        — Dashboard (stats, recent bills)
│       ├── voice_billing_screen.dart — Voice billing (mic → bill → settle)
│       ├── inventory_screen.dart   — Stock management (inline edit)
│       ├── reports_screen.dart     — Ledger + sales reports
│       └── past_bills_screen.dart  — Bill history + PDF download
├── android/
│   ├── app/
│   │   ├── build.gradle
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/smartdukan/app/MainActivity.kt
│   ├── build.gradle
│   ├── settings.gradle
│   └── gradle.properties
└── pubspec.yaml
```

## Before Building

Update `lib/supabase_config.dart` with your actual credentials:
```dart
static const String supabaseUrl = 'YOUR_SUPABASE_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
static const String railwayBaseUrl = 'YOUR_RAILWAY_API_URL';
```

## Release Signing

`flutter build apk --release` will currently succeed but fall back to
signing with the **debug keystore** (with a warning printed during the
Gradle build) unless `android/key.properties` exists. **A debug-signed
APK must never be distributed** — not via Play Store (won't be accepted
past internal testing without a real key), nor as a side-loaded APK where
users are expected to receive future updates (Android treats
differently-signed APKs as different apps for update purposes).

To produce a real, distributable release build, one-time setup (do this
yourself — an agent should not generate or handle your real signing key):

1. Generate an upload/release keystore:
   ```
   keytool -genkey -v -keystore /path/outside/this/repo/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Store this `.jks` file **outside the repo**, and back it up somewhere
   durable (e.g. a password manager or secure cloud storage) — if it's
   lost, you permanently lose the ability to publish updates to the same
   app under the same identity on the Play Store.

2. Create `android/key.properties` (already gitignored — never commit it):
   ```
   storePassword=<your store password>
   keyPassword=<your key password>
   keyAlias=upload
   storeFile=/path/outside/this/repo/upload-keystore.jks
   ```

3. Run `flutter build apk --release` (or `--release` app bundle) again —
   `android/app/build.gradle` will pick up `key.properties` automatically
   and sign with the real key instead of debug, with no further changes
   needed.

## Permissions Required

The app requests these permissions at runtime:
- **Microphone** — for voice billing
- **Internet** — for Supabase + Railway API
- **Storage** (Android ≤ 9) — for PDF export

## Features

| Feature | Description |
|---------|-------------|
| Voice Billing | Tap mic, speak items in Hindi/English, AI builds the bill |
| Auto-match | Closest item match is auto-added (no "not found" errors) |
| Inline edit | Tap any item/price/qty to edit directly in the bill |
| Unit badge | Shows ₹/kg, ₹/pcs etc. under each item name |
| Inventory | View/edit stock, price, low-stock limit per item |
| Customer Ledger | Track उधार (credit) and record payments |
| Reports | Monthly cash vs credit summary |
| PDF | Download/print bill receipt from any bill |
