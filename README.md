# SmartSort VERSION 1.0

SmartSort is a Flutter dashboard for connected waste-sorting hardware. It combines live bin telemetry, maintenance alerts, motor controls, voice commands, wallet linking, and Solana-based reward tracking in one workspace.

![SmartSort logo](assets/logo.png)

## Features

- Live bin capacity and system status from Firebase Realtime Database
- Automatic maintenance lockout when bin capacity reaches 90 percent
- Telegram notifications for full-bin and recovery events
- Manual motor controls for forward, reverse, left, right, and stop
- Voice commands for hands-free motor control
- Solana Devnet wallet display and reward transfer workflow
- Local wallet persistence with `shared_preferences`
- Public user dashboard and internal admin panel
- Flutter support for Android, iOS, web, Windows, macOS, and Linux

## Tech Stack

- Flutter and Dart
- Firebase Core
- Firebase Realtime Database
- Solana Devnet
- `speech_to_text`
- Telegram Bot API

## Requirements

- Flutter SDK with Dart 3.4.3 or newer
- A configured Firebase project with Realtime Database enabled
- A Solana Devnet RPC endpoint or access to the public Devnet endpoint
- A Telegram bot and destination chat ID if alert notifications are enabled

## Getting Started

Clone the repository and install dependencies:

```bash
git clone <repository-url>
cd smartsort-app
flutter pub get
```

Run the application on a connected device or supported desktop target:

```bash
flutter run
```

Run the test suite:

```bash
flutter test
```

Check the project for analyzer issues:

```bash
flutter analyze
```

## Firebase Setup

1. Create or select a Firebase project.
2. Enable Realtime Database.
3. Register each platform you intend to build for.
4. Add the generated Firebase configuration files for Android, iOS, macOS, and web as required by FlutterFire.
5. Update the Firebase initialization in `lib/main.dart` with your project configuration.

The dashboard listens for SmartSort telemetry under the `SmartSort` path. The expected fields include:

```json
{
	"waste_level": 42,
	"system_state": "Operational",
	"last_sorted": "dry"
}
```

Motor commands are written under `completed_cycles/motor_control`.

## Security

Before publishing or deploying this project, move all credentials out of source control and load them through platform configuration or environment-specific secrets. This includes:

- Firebase configuration values where project policy requires private handling
- Telegram bot tokens and chat IDs
- Solana seed phrases or private keys

Never use a real wallet seed phrase in a client application. Use a dedicated Devnet wallet while testing, rotate any credentials that have been exposed, and apply Firebase Realtime Database security rules before connecting production hardware.

## Project Structure

```text
lib/main.dart       Application entry point and dashboard UI
assets/logo.png     SmartSort branding asset
test/               Flutter widget tests
android/            Android runner project
ios/                iOS runner project
web/                Web runner project
windows/            Windows runner project
macos/              macOS runner project
linux/              Linux runner project
```

## Development Notes

- The app uses Solana Devnet by default.
- The widget test disables external integrations so it can run without Firebase platform channels.
- The Firebase listener and Solana initialization run only when `DashboardScreen.enableIntegrations` is enabled.

## License

This project is currently marked as private in `pubspec.yaml` and does not declare an open-source license.
