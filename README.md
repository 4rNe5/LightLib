<div align="center">

<img src="assets/icons/appIcon.png" width="150">

# LightLib

**An e-book library and reader for Android, built for Japanese light novels: <br/> faithful EPUB rendering, on-device translation, and a library that keeps track of your reading.**

> A fork of [OpenlibExtended](https://github.com/warreth/OpenlibExtended), itself a fork of [Openlib](https://github.com/dstark5/Openlib).

[![made-with-flutter](https://img.shields.io/badge/Made%20with-Flutter-FF6B9D.svg?style=for-the-badge)](https://flutter.dev/)
[![AGPLv3 License](https://img.shields.io/badge/License-AGPL%20v3-e63946.svg?style=for-the-badge)](https://www.gnu.org/licenses/agpl-3.0.html)
[![Latest release](https://img.shields.io/github/release/4rNe5/LightLib.svg?style=for-the-badge)](https://github.com/4rNe5/LightLib/releases/latest)

[<img src="github_releases.png"
     alt="Get it on GitHub"
     height="110">](https://github.com/4rNe5/LightLib/releases/latest)

**[📖 Frequently Asked Questions (FAQ)](./FAQ.md)**
</div>

## Features ✨

- **EPUB reader built on [foliate-js](https://github.com/johnfactotum/foliate-js)**
  The book's own layout, images and covers, vertical (縦書き) or horizontal writing, ruby (furigana), paged or scrolled. Fonts, sizes, spacing and themes per script (Korean, Japanese, Latin), applied to books only. Reader styling follows [Readest](https://github.com/readest/readest).

- **On-device translation**
  Translate books as you read with a local model: Gemma 4 through [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (GPU or CPU) or GGUF models through llama.cpp, via [llamadart](https://pub.dev/packages/llamadart). Several paragraphs per request, a light-novel style option tuned for Korean, character names read from the book's furigana. Nothing leaves the phone.

- **Background translation**
  Optional: library books are translated slowly in the background, pausing while you read, when the phone is warm or the battery is low, with progress in the notification shade.

- **Library**
  Full-quality covers read from the books themselves, reading status, tags and genres, search and filters. A bento overview of what you are reading, and a reading record: checkpoints, streaks, four weeks of activity, the month and your genre mix.

- **Home-screen widgets**
  *Continue reading* (the current book and the next, one tap away) and *Reading record* (checkpoints, streak, activity), in light and dark.

- **Updates from this repository**
  Every build on `main` is released here. The app checks the latest release, downloads a new build over Wi-Fi in the background (verified against its SHA-256), shows what changed since your build, and installs with one tap. The full history is in *Settings → Update history*.

- **Six languages**
  English, 한국어, 日本語, Deutsch, Español, Français.

## Screenshots 🖼️

[<img src="screenshots/Screenshot_1.png" width=160>](screenshots/Screenshot_1.png)
[<img src="screenshots/Screenshot_2.png" width=160>](screenshots/Screenshot_2.png)
[<img src="screenshots/Screenshot_3.png" width=160>](screenshots/Screenshot_3.png)
[<img src="screenshots/Screenshot_4.png" width=160>](screenshots/Screenshot_4.png)
[<img src="screenshots/Screenshot_5.png" width=160>](screenshots/Screenshot_5.png)

## Installation 📦

Download `LightLib-<version>-build.<n>-arm64.apk` from the [latest release](https://github.com/4rNe5/LightLib/releases/latest) and install it. Each release lists its changes and the APK's SHA-256.

- **Android only, arm64** (64-bit phones from the last several years).
- Every release is signed with the same key, so a new build installs over the old one and keeps your library. After the first install, updates come through the app.
- Translation needs a model, downloaded in *Settings → Translation*. Gemma 4 E2B and E4B (`.litertlm`) run on recent phones.

**Note:** Publishing this app to the Play Store violates their terms.

## Development 🛠️

Flutter 3.47 (Dart 3.13).

```bash
git clone https://github.com/4rNe5/LightLib.git
cd LightLib
flutter pub get
flutter run
```

- The EPUB reader's web part lives in `reader_web/` and is bundled into `assets/reader/` (see `reader_web/README.md`).
- Every push to `main` that changes more than Markdown runs `.github/workflows/android-release.yml`: tests, a signed arm64 build, and a release tagged `v<version>-build.<n>`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Credits 🙏

- [Openlib](https://github.com/dstark5/Openlib) by dstark5 and [OpenlibExtended](https://github.com/warreth/OpenlibExtended) by warreth, the apps this one is built on.
- [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT) and [Readest](https://github.com/readest/readest) (AGPL-3.0) for the reader.
- [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM), [llamadart](https://pub.dev/packages/llamadart) and the [Gemma](https://ai.google.dev/gemma) models for translation.

## License 📜

Licensed under [AGPL v3.0](https://www.gnu.org/licenses/agpl-3.0.html), like the projects it comes from.

## Disclaimer ⚠️

LightLib does not own or have any affiliation with the books available through the app. All books are the property of their respective owners and are protected by copyright law. LightLib is not responsible for any infringement of copyright or other intellectual property rights that may result from the use of the books available through the app. By using the app, you agree to use the books only for personal, non-commercial purposes and in compliance with all applicable laws and regulations.
