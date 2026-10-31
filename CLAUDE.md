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
```
Without `android/key.properties` a local release build is signed with the
debug key (only CI signs releases).

## CI and releases
- `.github/workflows/android-release.yml`: every push to `main` runs tests and
  a signed arm64 build, then publishes `v<version>-build.<N>`
  (versionCode 2000 + N). `[skip ci]` skips it.
- Signing: package `dev.arne5.lightlib`, certificate `CN=LightLib, O=4rNe5`;
  CI refuses any other key (`EXPECTED_CERT_SHA256`). Keystore and passwords
  live only in GitHub Secrets and with the owner.
- `gh` works through REST only (no GraphQL, no Actions secrets).

## Map
| Area | Where |
|---|---|
| App start, tabs, home widgets update | `lib/main.dart` |
| Settings / prefs DB (sqflite) | `lib/services/database.dart` (`MyLibraryDb`, `savePreference`) |
| Home: BOOK☆WALKER (Japan, default) / English lists | `lib/services/bookwalker.dart`, `lib/ui/japan_discover.dart`; 202 WAF → `browser_page_reader.dart` |
| Reader (foliate-js in a WebView) | `lib/ui/book_reader_page.dart`, `reader_web/` (built with `build.mjs`) |
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
- Tests: no network, no platform channels — inject `Dio` adapters, use
  `debugSet`/`debugShow` hooks, and do not `await` database writes inside
  `testWidgets`.

## Open plans (owner's order)
1. Translation on the owner's MacBook: largest Gemma 4 the Mac's memory
   allows (MLX or llama-server, OpenAI-compatible), reachable only by the
   owner (Tailscale preferred, or a tunnel with an API key); an app engine
   "내 서버" (URL + key) reusing `CloudTranslator`'s structure.
2. Flutter Web (static hosting, IndexedDB, Gemini with the user's own key):
   no public relay for shadow-library search/downloads; books reach the web
   through the owner's own Google Drive app folder sync, upload, or
   public-domain sources.
3. Smaller: `[n]`→`n.` numbering, token-budget batches, translator-note
   stripping, tok/s + heat logs, per-book genre detection, bilingual EPUB,
   two-page spread on unfolded screens.
