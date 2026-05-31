# Technology Stack

**Analysis Date:** 2026-05-31

## Languages

**Primary:**
- Dart 3.10.7 - All application code under `flutter/lib/`

**Secondary:**
- Kotlin / Java - Android platform runner under `flutter/android/`
- Swift / Objective-C - iOS and macOS platform runners under `flutter/ios/`, `flutter/macos/`
- C++ - Linux and Windows platform runners under `flutter/linux/`, `flutter/windows/`
- HTML/CSS/JS - Web platform scaffold under `flutter/web/`

## Runtime

**Environment:**
- Flutter 3.38.7 (stable channel, revision `3b62efc2a3`) — cross-platform UI framework
- Dart SDK 3.10.7 — required minimum `^3.8.0` (declared in `flutter/pubspec.yaml`)
- DevTools 2.51.1 — bundled with Flutter SDK

**Package Manager:**
- pub (bundled with Dart/Flutter SDK)
- Lockfile: `flutter/pubspec.lock` present

## Frameworks

**Core:**
- Flutter 3.38.7 - Cross-platform UI framework (Material Design)
- `uses-material-design: true` declared in `flutter/pubspec.yaml`

**Testing:**
- `flutter_test` (SDK built-in) - Widget testing
- One test file exists: `flutter/test/widget_test.dart` (smoke test only)

**Build/Dev:**
- Flutter toolchain - builds for Android, iOS, Web, macOS, Linux, Windows
- `flutter_lints ^6.0.0` - Lint rules (`flutter/analysis_options.yaml`)

## Key Dependencies

**Critical:**
- `google_fonts ^6.2.1` (resolved 6.3.3) - Runtime font loading; fetches Bricolage Grotesque + Be Vietnam Pro at runtime from Google Fonts CDN
- `cupertino_icons ^1.0.8` (resolved 1.0.9) - iOS-style icon assets

**Infrastructure (transitive, pulled by google_fonts):**
- `path_provider` - Platform file system access (used by google_fonts for font caching); platform implementations: `path_provider_foundation` (iOS/macOS), `path_provider_android`, `path_provider_linux`, `path_provider_windows`
- `http` - HTTP client used internally by google_fonts to download fonts
- `crypto` 3.0.7 - Hashing, used by google_fonts

**Dev:**
- `flutter_lints ^6.0.0` - Extends `package:flutter_lints/flutter.yaml`; extra rules: `prefer_const_constructors`, `avoid_print`

## Configuration

**Environment:**
- No environment variables — app is self-contained with in-memory mock data
- No `.env` files present
- No secrets or API keys required to run

**Build:**
- `flutter/pubspec.yaml` - Package manifest and SDK constraint
- `flutter/pubspec.lock` - Dependency lock file
- `flutter/analysis_options.yaml` - Lint configuration
- `flutter/android/` - Android Gradle build files
- `flutter/ios/Podfile` - iOS CocoaPods config (no extra pods beyond Flutter SDK)
- `flutter/macos/Podfile` - macOS CocoaPods config

## Platform Requirements

**Development:**
- Flutter SDK 3.38.7 (stable) with Dart 3.10.7
- For iOS/macOS: Xcode + CocoaPods
- For Android: Android SDK
- All other platforms (Linux, Windows, Web): standard Flutter toolchain
- Run: `cd flutter && flutter pub get && flutter run`

**Production:**
- Currently a UI prototype only — no deployment target defined
- Supports: Android, iOS, Web, macOS, Linux, Windows
- No backend, no auth, no network calls beyond Google Fonts font downloads

---

*Stack analysis: 2026-05-31*
*Update after major dependency changes*
