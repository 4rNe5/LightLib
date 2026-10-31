# LightLib — Setup

## Prerequisites
- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (Dart 3.13) — check with `flutter doctor`.
- Android SDK (Android Studio, or the command-line tools) and an arm64 phone or emulator.
- Node.js, only to rebuild the reader's web part.

## Build and run
```bash
git clone https://github.com/4rNe5/LightLib.git
cd LightLib
flutter pub get
flutter run                 # debug, on a connected phone
```

A release build:
```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```
Without `android/key.properties` it is signed with the debug key, so it does not install over a release from GitHub (different signature).

## Checks
```bash
flutter analyze             # the known issues are all in third_party/epubx
flutter test
flutter gen-l10n            # after editing lib/l10n/*.arb
```

## Project layout
| Path | What |
|---|---|
| `lib/ui/` | Screens and components |
| `lib/services/translation/` | Translation: device engine (`translator.dart`), Gemini (`gemini/`), saved translations, glossary, checks, export |
| `lib/services/` | Library, downloads, catalogues, updates, widgets |
| `reader_web/` | The reader (foliate-js), built into `assets/reader/` — see `reader_web/README.md` |
| `third_party/llamadart` | The on-device model runtime with this app's patches (`PATCHES.md`) |
| `android/app/src/main/kotlin/` | Widgets, the background-translation service, device readings |

## Releases
Every push to `main` (other than Markdown) runs `.github/workflows/android-release.yml`: tests, a build signed with the release key from the repository's secrets, and a GitHub release `v<version>-build.<n>`. Put `[skip ci]` in a commit message to skip it.

## Linux desktop
The desktop build needs WebKitGTK 4.1 for its browser window:
```bash
sudo apt install libwebkit2gtk-4.1-dev     # Ubuntu / Debian
sudo dnf install webkit2gtk4.1-devel       # Fedora
sudo pacman -S webkit2gtk-4.1              # Arch
```
