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
  new outside host against it; no inline script, so `web/splash.js`). Not
  built: search/downloads, the device model, widgets, updates.
- The web lists the library from the account's rows (`RemoteLibraryStore`,
  `lib/web/web_library.dart`: title, author, a small cover
  `<md5>.cover.jpg`) and fetches a book's file only when it is opened
  (`SyncEngine(onDemand: true)`, `fetchBook`; `WebBookOpenPage`). A file
  missing in the browser deletes nothing; deleting is `deleteBook`,
  freeing space `dropLocalCopy`. A book no device has put a small cover
  of gets its cover read out of its file on the account by byte ranges
  (`epub_remote_cover.dart`, `SyncService.cardFromFile`; never the whole
  book) and kept for the others. The first frame waits for nothing
  (`main_web.dart`); `web/index.html` shows the app's name until then.
  A window ≥ 900 px wide gets the desktop layout (`webWideLayout`).
- Cloudflare, for a network that does not reach `*.supabase.co` (nor
  Vercel): the Workers project `lightlib`
  (https://lightlib.4rnne5.workers.dev), root `cloudflare`, build
  `bash ../tool/cloudflare_build.sh`, deploy `npx wrangler deploy`
  (`cloudflare/wrangler.jsonc`: the files of `dist`, and `worker.js` for
  what is not a file - without that config wrangler deploys the files
  alone and `/sb` answers 404). The app is built with `SYNC_RELAY=/sb`
  (`SyncConfig.viaRelay`): it asks the project through the site's own
  `/sb/*`, passed on by `cloudflare/relay.js` (that project only,
  auth/rest/storage, the site's own pages; `npm test` there). Files are
  served without the Worker; the Worker's free plan is 100,000 requests
  a day. `functions/` and `_routes.json` are the same relay for a Pages
  project, should one be made. Signing in there is Google's button on the page
  (`lib/web/google_id_sign_in*.dart`, `signInWithIdToken`): the usual way
  sends the browser to the project's address. The site's address must be
  among the Google client's authorised JavaScript origins. Headers:
  `tool/cloudflare_headers.py` writes `_headers` from `vercel.json`.
  Cloudflare skips a build whose commit message has `[skip ci]`.
- A second host, for networks that block Vercel: GitHub Pages,
  `.github/workflows/web-pages.yml` (the same build under `/LightLib/`,
  `BASE_HREF`; no headers there, so `tool/pages_csp.py` puts the policy
  in the page). `[skip ci]` skips it: run the workflow by hand then. The
  sign-in returns to `SyncConfig.webRedirect` (the app's own address); a
  new host's address must be in the project's Auth redirect URLs.
- Web checks: `tool/web_check/` (its README) - the built app in headless
  Chrome with real clicks and touches, against a stand-in for the sync
  project (no live account).
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
  Each device that has a book puts its details and a small cover
  (`CoverThumbs`) once - the cover saved with the book, or the book's own
  out of its file when that is a web address (a book downloaded in the
  app). How far a book was read travels as
  `progress.fraction` (`frac:<file>` here; `put_reading`; the old
  `put_progress` clears it). Shared settings (`settings` table,
  `put_setting`, newest wins): the Gemini key, unless `syncGeminiKey`
  is 0. Progress/result notifications: `sync_notifier*.dart`. Only
  emails in `public.owners` can read or write (RLS). Engine rules and
  tests: `sync_engine.dart`, `test/sync_engine_test.dart`.

## Map
| Area | Where |
|---|---|
| App start, tabs, home widgets update | `lib/main.dart` |
| Settings / prefs DB (sqflite) | `lib/services/database.dart` (`MyLibraryDb`, `savePreference`) |
| Home: BOOK☆WALKER (Japan, default) / English lists | `lib/services/bookwalker.dart`, `lib/ui/japan_discover.dart`; 202 WAF → `browser_page_reader.dart` |
| Reader (foliate-js in a WebView) | `lib/ui/book_reader_page.dart`, `reader_web/` (built with `build.mjs`); the page's host `lib/ui/reader_host/` (WebView on devices, iframe + postMessage on the web) |
| Relay to the sync project (Cloudflare) | `cloudflare/` (`relay.js`, `worker.js` + `wrangler.jsonc`, `functions/sb/[[path]].js` for Pages, `test/`), `tool/cloudflare_build.sh`, `tool/cloudflare_headers.py` |
| Web app | `lib/main_web.dart`, `lib/web/` (`web_library_page` shell and grid, `web_book_dialog` a book's card, `web_book_opening` fetching a book, `web_cover`, `web_settings_page`, `browser` drops and storage), `web/index.html` + `splash.js` |
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
| Z-Library account (its download limit) | `lib/services/zlibrary_account.dart` (session = two cookies, in `zlibrary_session` in the private folder; not in backups or sync), `ZlibraryProvider.signIn` / `accountLimits` (`/eapi/user/login`, `/eapi/user/profile`) and `_AsAccount` (book pages, `/dl/`, `/eapi` only) in `search_manager.dart`; UI `components/zlibrary_account_sheet.dart`, browser sign-in `zlibrary_login_page.dart` |
| Search | `lib/ui/search_page.dart` (field, suggestions: BOOK☆WALKER `suggest`, Google `hl=ja`, history; Korean → Japanese title via `original_title.dart`), filters in `components/search_filter_sheet.dart` (default Japanese + EPUB); results `results_page.dart` grouped by `search_results.dart` (series/volume from titles, best file per volume — only what the libraries returned); catalogs in `search_manager.dart` |
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
- Search candidates come only from the libraries: BOOK☆WALKER lists books
  the libraries do not have, so it only fills the search field.
- Web reader: the iframe takes every tap inside its box, Flutter widgets
  drawn over it included. Bars and buttons over the page go in
  `PointerInterceptor` (`_onPage` in `book_reader_page.dart`); the iframe's
  `pointer-events` is off while another route (sheet, dialog) is on top
  (`reader_host_web.dart`). Browser tests tap real coordinates: clicks on
  semantics nodes passed while real taps did not.
- Web reader: nothing may keep animating over the iframe (a spinner, a
  running progress bar) - each frame of it is drawn on the thread the
  page works on; a running bar made a 3 s opening take 12 s.
- Web frames are dear: each is drawn, then copied to the page, at the
  full pixel size (in headless Chrome `createImageBitmap` is 60% of a
  scroll). So `web/splash.js` caps the app's device pixel ratio at 2,
  nothing on the web animates without end (sync shows a still icon and a
  bar only when it knows how far), tiles have no blurred shadow at rest,
  the reader asks for a frame on `relocate` only when the footer changes,
  and a bar that slid away has no `PointerInterceptor`.
- Web bundle: `GoogleFonts.getFont(name)` pulls the table of every font
  (3.4 MB of JS) - it sits behind `google_font_family_io/web.dart`.
  Full-size covers decoded per tile cost ~30 MB each; the web draws
  `CoverThumbs` only, at the size shown (`cacheWidth`).
- Supabase: the client adds the key and the session's token inside its
  own HTTP client, not to `storage.headers`. A request made beside it
  (Dio: a part of a file, a book with its progress) must add them
  (`SupabaseRemote._signed`), or storage answers 400 "Bucket not found".
  The stand-in in `tool/web_check` answered anyone, so the checks passed
  while the owner's library read no cover out of a file; it now refuses
  a request that does not say who asks. When the web misbehaves on the
  real account, read the project's `edge_logs` first.
- Reader page on older browsers: esbuild's `target` rewrites syntax only,
  a missing function stays missing. foliate-js calls `Object.groupBy`
  (Chrome 117) for every EPUB, so no book opened in Chrome 112 or a
  WebView that old; `reader_web/src/polyfills.js` fills in what it uses.
  After taking a newer foliate-js, look for newer functions again and
  open a book in an old Chrome (`tool/web_check` README).
- `MyLibraryDb.database` is asked by several callers at once when the web
  starts; that is safe because sqflite opens a path once under a lock. Do
  not keep the opening future instead: one made inside a `testWidgets`
  never completes and every later test waits on it.
- Z-Library sign-in and profile go through a client without the request
  log (`_accountDio`): the log keeps request and response bodies, and the
  owner sends logs along with reports. Log outcomes there, never values.
- Book files in the shared folder (`Download/book`): a file this app did
  not make (a file manager's, an earlier install's) can be seen - it
  exists, it has a length - but not opened, written or deleted. A
  download resumes from the bytes on disk, so it once "resumed" from such
  a file, got 416 and called the book complete in a second; sync then
  failed on the file. `_fileNameFor` in `download_manager.dart` picks
  another name (`distinctBookFileName`), a 416 is believed only when the
  sizes agree, and sync leaves an unreadable book out
  (`SyncReport.unreadable`) instead of failing.
- Book file names keep ASCII only: volume 1 of every Japanese series was
  `1.EPUB`. A title that lost characters gets the book's id in its name
  (`generateBookFileName`). Positions and translations are kept by file
  name: two books must never share one.
- Z-Library's id is not an MD5: nothing to hold a file's checksum against
  (`_isMd5`).
- Z-Library's book page, signed in, shows the account's picture first,
  from the host the covers come from: the cover is read from the book's
  own box (`parseBookPage`), never "the first image".
- Books that went missing here many at once are held back, not deleted on
  the account (`deletesHeld`); the reader answers in Settings
  (`HeldDeletes`: delete there too, or fetch back).
- A test file with `testWidgets` answers every real HTTP request with 400:
  tests against a local server live in a file without widget tests.
- Tests: no network, no platform channels — inject `Dio` adapters, use
  `debugSet`/`debugShow` hooks, and do not `await` database writes inside
  `testWidgets`.

## Open plans (owner's order)
1. Translation on the owner's MacBook: largest Gemma 4 the Mac's memory
   allows (MLX or llama-server, OpenAI-compatible), reachable only by the
   owner (Tailscale preferred, or a tunnel with an API key); an app engine
   "내 서버" (URL + key) reusing `CloudTranslator`'s structure.
2. Web + sync (built, see "Web and sync"): next - whole-book translation
   on the web, the reader's fonts and word tools on the web, a smaller
   start (llamadart is still in the web bundle, ~0.4 MB; a WebAssembly
   build compiles but saved only ~10% of the download). No public relay
   for shadow-library search/downloads.
3. Smaller: `[n]`→`n.` numbering, token-budget batches, translator-note
   stripping, tok/s + heat logs, per-book genre detection, bilingual EPUB,
   two-page spread on unfolded screens.
4. Study, later: a bundled pre-translated dictionary (JMdict + Korean
   meanings) as an extension; the word sheet would show it before the
   engine's contextual meaning.
