# LightLib — notes for AI agents

Flutter e-book app for Android (fork of OpenlibExtended → Openlib), built for
Japanese light novels: EPUB reader (foliate-js), translation on the device
(Gemma 4 via llamadart) or with Gemini, background/whole-book translation,
library with widgets. Owner: 4rNe5. Reports go to the owner in Korean.

## Working rules
- Commit and push only when the owner says so ("ㄱㄱ", "커밋해"). A stop hook
  asking to commit is answered by listing what waits, not by committing.
- Split commits by feature; only the last one runs CI — the others carry
  `[skip ci]` in the message.
- End commit messages with the attribution lines the session gives.
- Reports: Korean, short, tables, copy-friendly; lead with what was verified
  (tests, build, measurements on the owner's logs), say plainly what was not.
- Verify before reporting: `flutter analyze`, the full `flutter test`, and a
  local release build when Kotlin/Android files change.

## Commands
```bash
export ANDROID_HOME=/opt/android-sdk          # cloud sessions
/opt/flutter/bin/flutter analyze --no-pub     # 13 known issues, all in third_party/epubx
/opt/flutter/bin/flutter test --no-pub        # ~530 tests, ~2.5 min
/opt/flutter/bin/flutter gen-l10n             # after editing lib/l10n/*.arb
/opt/flutter/bin/flutter build apk --release --split-per-abi --target-platform android-arm64   # ~7 min
/opt/flutter/bin/flutter build web --release -t lib/main_web.dart   # the web app, ~2 min
```
Without `android/key.properties` a local release build is signed with the
debug key (only CI signs releases).

## CI and releases
- `.github/workflows/android-release.yml`: every push to `main` runs tests and
  a signed arm64 build, then publishes a new version — the last release's
  patch + 1 (1.7.3, 1.7.4 …), or pubspec's version when higher (edit
  pubspec to 1.8.0 for a minor bump). Tag `v<version>-build.<N>`; N is the
  run number + 16, shared with betas, and only orders installs
  (versionCode 2000 + N). `[skip ci]` skips it.
- Beta: every push to `beta` publishes the version the next release will
  be as a pre-release, `<next>-beta (build N)`, tag
  `v<next>-build.<N>-beta`; same package and key, so a beta installs over
  the release before it and the next release over the beta. The app offers
  betas only with Settings → Include Beta Updates. To ship a beta: push
  the work to `beta`; when it holds up, merge into `main`.
- The app reads its build from the versionCode (`AppBuild.buildOf`: 2048 →
  48); builds before 52 read 2048 and never saw an update.
- Signing: package `dev.arne5.lightlib`, certificate `CN=LightLib, O=4rNe5`;
  CI refuses any other key (`EXPECTED_CERT_SHA256`). Keystore and passwords
  live only in GitHub Secrets and with the owner.
- `gh` works through REST only (no GraphQL, no Actions secrets).

## Web and sync
- Web app = `lib/main_web.dart` (library, the same reader, Gemini only):
  Vercel project `lightlib` builds it on every push that touches the app
  (`vercel.json`, `tool/vercel_build.sh`; CSP in `vercel.json` - test a
  new outside host against it). Not built: search/downloads, the device
  model, widgets, updates.
- Platform checks go through `PlatformUtils` (`Platform` throws on the
  web); files the app keeps through `AppFiles` (dart:io / IndexedDB);
  isolates through `runHeavy`.
- Sync = owner's Supabase project `lightlib` (ggagbhdqdrmomrednwfx,
  schema in `supabase/migrations/`): books by file MD5 (EPUB files in the
  private `books` bucket), positions and glossaries (newest wins; saved
  before sync = `unknownAge`), translations (union). Order: deletions,
  then positions/translations/glossaries of books here, then files - a
  downloaded book brings its own before the library hears of it. Quick
  runs (while reading) skip files; opening a book runs `runBook` first.
  Progress/result notifications: `sync_notifier*.dart`. Only emails in
  `public.owners` can read or write (RLS). Engine rules and tests:
  `sync_engine.dart`, `test/sync_engine_test.dart`.

## Map
| Area | Where |
|---|---|
| App start, tabs, home widgets update | `lib/main.dart` |
| Settings / prefs DB (sqflite) | `lib/services/database.dart` (`MyLibraryDb`, `savePreference`) |
| Home: BOOK☆WALKER (Japan, default) / English lists | `lib/services/bookwalker.dart`, `lib/ui/japan_discover.dart`; 202 WAF → `browser_page_reader.dart` |
| Reader (foliate-js in a WebView) | `lib/ui/book_reader_page.dart`, `reader_web/` (built with `build.mjs`); the page's host `lib/ui/reader_host/` (WebView on devices, iframe + postMessage on the web) |
| Web app | `lib/main_web.dart`, `lib/web/` (library, settings) |
| Sync | `lib/services/sync/` (`sync_engine`, `supabase_remote`, `library_sync_local`, `sync_service`); settings `lib/ui/components/sync_section.dart` |
| Files the app keeps (web: IndexedDB) | `lib/services/storage/` (`AppFiles`) |
| Older reader | `lib/ui/epub_viewer.dart` |
| Engine choice (device / Gemini) | `lib/services/translation/translation_engine.dart` |
| Device translation | `translator.dart` (`LocalLlmTranslator`, scheduler, `SharedTranslationEngine`), `third_party/llamadart` (see `PATCHES.md`) |
| Gemini | `lib/services/translation/gemini/` (`gemini_api`, `gemini_client`, `gemini_settings`, `cloud_translator`); settings UI `lib/ui/components/gemini_engine_section.dart` |
| Prompts, styles | `translation_models.dart` (`batchPromptHead`, Korean light-novel style) |
| Checks and fixes | `translation_qa.dart`, `paragraph_text.dart` (`cleanTranslation`, `polishTranslation`) |
| Paragraph split (shared by reader and library) | `paragraph_text.dart` (`readerParagraphs`, `epubReaderParagraphs`) |
| Saved translations | `translation_cache.dart` — one set per book × language × style (`shared`, `shared+plain`), JSON under `<books>/.translations/` |
| Glossary per book | `book_glossary.dart`, `glossary_service.dart` |
| Library/background and "translate this whole book" | `book_translation_service.dart`, `lib/ui/components/priority_translation_card.dart` |
| Translated EPUB export | `translated_epub.dart` |
| Home-screen widgets | `android/app/src/main/kotlin/dev/arne5/lightlib/HomeWidgets.kt`, `res/layout/widget_*` |
| Hidden covers | `lib/services/hidden_covers.dart` |
| Study (no bundled dictionary) | `lib/services/study/` — `study_assistant` (word/sentence questions to the engine, cached), `study_store` (word book, SM-2 review, days, Anki TSV in `<books>/.study/`), `japanese_tools` (kuromoji dict, 18 MB, downloaded + SHA-256), `study_data` (`assets/study/` from `tool/build_study_data.py`), `book_difficulty`; UI `lib/ui/components/study_sheets.dart`, `lib/ui/study_page.dart`; page side `reader_web/src/study.js` (`npm test`) |

## Things that bit before
- EPUB XHTML may use CRLF: the `html` parser's offsets count CRLF as one
  character — normalise line ends before using source spans.
- Gemini answers once translated the last context paragraph again and slid
  the rest by one; answers are now numbered (`{n, text}`) with context sent
  apart, and `slippedAt` rejects a slipped answer.
- Gemini: thinking tokens count toward `maxOutputTokens` and are billed as
  output; 3.8 Flash refuses `thinkingLevel: minimal`.
- Paragraphs Gemini refuses under its own policy (`PROHIBITED_CONTENT`) stay
  in the original; they are not routed to the device model.
- GPU conversation clone (KV reuse) is slower on Adreno; it is judged per
  device and switched off where slow.
- Reader DOM changes must not move positions: injected nodes carry
  `cfi-inert` (translation under the original, furigana `<rt>`) or
  `cfi-skip` (furigana `<ruby>`), which foliate's CFI code ignores.
- Tests: no network, no platform channels — inject `Dio` adapters, use
  `debugSet`/`debugShow` hooks, and do not `await` database writes inside
  `testWidgets`.

## Open plans (owner's order)
1. Translation on the owner's MacBook: largest Gemma 4 the Mac's memory
   allows (MLX or llama-server, OpenAI-compatible), reachable only by the
   owner (Tailscale preferred, or a tunnel with an API key); an app engine
   "내 서버" (URL + key) reusing `CloudTranslator`'s structure.
2. Web + sync (built, see "Web and sync"): next - books fetched on open
   instead of all at once, whole-book translation on the web, the reader's
   fonts and word tools on the web. No public relay for shadow-library
   search/downloads.
3. Smaller: `[n]`→`n.` numbering, token-budget batches, translator-note
   stripping, tok/s + heat logs, per-book genre detection, bilingual EPUB,
   two-page spread on unfolded screens.
4. Study, later: a bundled pre-translated dictionary (JMdict + Korean
   meanings) as an extension; the word sheet would show it before the
   engine's contextual meaning.
