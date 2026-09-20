# Project Structure: connect_call

## Overview
This is a Flutter-based secure calling application using Firebase for signaling/authentication and Agora RTC for video/audio streaming. The architecture uses Riverpod for state management.

## Directory Structure

```text
lib/
├── core/
│   └── theme/
│       └── app_theme.dart             - Application UI theme definitions
├── models/
│   └── user_model.dart                - Data models for users
├── screens/
│   ├── auth/                          - Authentication flows
│   │   ├── login_screen.dart
│   │   ├── otp_screen.dart
│   │   ├── phone_login_screen.dart
│   │   ├── profile_setup_screen.dart
│   │   └── signup_screen.dart
│   ├── call/                          - Agora Calling UI
│   │   ├── audio_call_screen.dart     - Voice call UI (Reactive with AgoraService)
│   │   └── video_call_screen.dart     - Video call UI (Reactive with AgoraService)
│   └── home/                          - Main app navigation
│       ├── call_logs_tab.dart
│       ├── contacts_tab.dart
│       ├── home_screen.dart
│       └── profile_screen.dart
├── services/                          - Core Business Logic & State (Riverpod)
│   ├── agora_service.dart             - Robust Agora RTC engine manager (AutoDispose)
│   ├── agora_token_service.dart       - Firebase Cloud Function caller for dynamic tokens
│   ├── auth_service.dart              - Firebase Auth manager
│   ├── call_service.dart              - Call signaling via Firestore
│   ├── theme_service.dart             - Theme state manager
│   └── user_service.dart              - Firestore user data manager
├── widgets/
│   └── user_tile.dart                 - Reusable UI component
├── firebase_options.dart              - Auto-generated Firebase config
└── main.dart                          - App entry point (ProviderScope)
```

## Known Issues / Recent Fixes
- **Dynamic Agora Tokens**: Fixed token generation by updating Cloud Functions with the correct App ID and App Certificate. `agora_token_service.dart` correctly fetches tokens dynamically.
- **Agora Engine Refactor**: Moved all RTC initialization and disposal out of the UI and into `agora_service.dart` (a Riverpod `StateNotifier`).
- **End Call / Disconnect Bug**: Fixed a major bug where the Agora engine was not cleanly releasing resources on navigation. Implemented `autoDispose` on the `agoraServiceProvider` and overridden `dispose()` to guarantee `leaveChannel` and `release` execute safely when a call ends.
- **Android `INSTALL_FAILED_USER_RESTRICTED`**: Reminded user to enable "Install via USB" and "USB Debugging (Security settings)" in Xiaomi developer options.

## Pending Tasks
- Ensure Push Notifications are fully integrated for incoming calls when the app is in the background.
