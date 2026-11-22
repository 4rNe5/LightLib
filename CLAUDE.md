# LightLib — notes for AI agents

Flutter e-book app for Android (fork of OpenlibExtended → Openlib), built for
Japanese light novels: EPUB reader (foliate-js), translation on the device
(Gemma 4 via llamadart), with Gemini or with Claude, background/whole-book
translation, library with widgets and series. Owner: 4rNe5. Reports go to the owner in Korean.

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
/opt/flutter/bin/flutter test --no-pub        # ~890 tests, ~3 min
/opt/flutter/bin/flutter gen-l10n             # after editing lib/l10n/*.arb
/opt/flutter/bin/flutter build apk --release --split-per-abi --target-platform android-arm64   # ~7 min
/opt/flutter/bin/flutter build web --release -t lib/main_web.dart   # the web app, ~2 min
flutter test --no-pub tool/ui_shots/shots_test.dart   # pictures of the screens, phone and unfolded (its README)
```
A cloud session whose container was replaced has no Flutter and no SDK:
the release `flutter_linux_<version>-stable.tar.xz` (the workflow's
`FLUTTER_VERSION`) into `/opt`, and the SDK's command-line tools with
`platforms;android-36` and `build-tools;36.0.0` into `/opt/android-sdk`.
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
- A pull request into `main` is merged with a merge commit (or rebased),
  never squashed: a squash writes every commit's message into one, its
  `[skip ci]` with them, and the release, Pages and Cloudflare all skip.
- The app reads its build from the versionCode (`AppBuild.buildOf`: 2048 →
  48); builds before 52 read 2048 and never saw an update.
- Signing: package `dev.arne5.lightlib`, certificate `CN=LightLib, O=4rNe5`;
  CI refuses any other key (`EXPECTED_CERT_SHA256`). Keystore and passwords
  live only in GitHub Secrets and with the owner.
- `gh` works through REST only (no GraphQL, no Actions secrets).

## Web and sync
- Web app = `lib/main_web.dart` (library, the same reader, Gemini or
  Claude):
  Vercel project `lightlib` builds it on every push that touches the app
  since its last deployment on that branch (`tool/vercel_ignore.sh`; it
  once looked at the last commit only, and a branch moved forward by many
  commits whose last one touched notes alone was never built)
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
  Series show as rows there too (`webSeries`, by the shared map: the
  web has no rows of its own for most books) and are made there as on a
  phone - books chosen from a tile's menu or with Ctrl/⌘, the bar, a
  name; a row's menu renames or undoes one. The web writes the shared
  map itself, by MD5 (`WebLibrary.setSeries`), and sync sends it.
  "Translate this whole book" is on a book's card
  (`web_book_translation.dart`): the library's translator
  (`BookTranslationService`, started in `main_web.dart`) works on that
  book while the tab is open, fetching it first if it is only on the
  account.
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
- A page's headers can change while the page does not: the browser
  that has it asks "changed?", Vercel answers 304 without the policy,
  and the browser keeps the policy it first got. `api.anthropic.com`
  was let out by a new `connect-src` that way and the owner's browser
  went on refusing it ("XMLHttpRequest onError" in the app, the policy
  named in the console). `tool/stamp_page.py` (run by
  `tool/vercel_build.sh`) puts a line in the built page that changes
  with the commit and with `vercel.json`. A deployment is checked as a
  browser that has the page sees it too: `curl -H 'If-None-Match:
  <the etag before>'` must come back 200 with the new header.
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
  `put_setting`, newest wins; a value up to 262,144 characters): the
  Gemini key, unless `syncGeminiKey` is 0; the Claude key with its
  workspace, unless `syncClaudeKey` is 0; the series (`series_sync.dart`: each
  book's MD5 under its series' name, under "" the books taken out).
  The series are a setting both sides add to: a device keeps the whole
  map (books that are not here too, `seriesShared`), writes into it
  what the reader changed here (`ser:<bookId>` marks, set by
  `MyLibraryDb.setSeries`), lets what arrives stand for every book it
  speaks of, and sends back what only it knew in the same run
  (`_settings`: after taking, what is here besides goes up). Two
  devices that both changed series while apart: the later one's map
  stands for the books both speak of. Progress/result notifications: `sync_notifier*.dart`. Only
  emails in `public.owners` can read or write (RLS). Engine rules and
  tests: `sync_engine.dart`, `test/sync_engine_test.dart`.

## Map
| Area | Where |
|---|---|
| App start, tabs, home widgets update | `lib/main.dart` |
| One pane or two (width classes, the fold of a foldable) | `lib/ui/adaptive.dart` (`useTwoPanes` from 600 dp, `verticalFoldOf`, `TwoPane`: the end pane starts just past the fold, `trailing` = the tabs' rail beside it) |
| The tabs' bar / rail | `lib/ui/components/app_nav_bar.dart` (a phone: the pill at the foot; from 600 dp: the same pill on end in the lower right corner, `AppNavRail.width` wide) |
| A library book: opening it, its page, the order of screens | `lib/ui/book_navigation.dart` (`openBookReader`, `pushBookPage`, `showBookFromOutside`, `libraryDetailProvider`), `lib/ui/components/book_detail.dart` (`BookDetail`: a page on a phone - `mybook_page.dart` - and the pane beside the shelf on a wide screen), `lib/ui/components/book_opening.dart` (the picture while a book opens) |
| How far a book was read, finished, read last | `MyLibraryDb.readingOf`, `setCompleted`, `readingChanged`; `LibraryBook.fraction/readAt/percent`, `continueReading` (`library_organization.dart`); the reader's `_saveNow(leaving:, finished:)` |
| Motion | `lib/ui/components/motion.dart` (`AppMotion`, `Pressable`, `Appear`, `ProgressBar`, `CountUp`, `FadeThroughRoute`; `EvenFrames`: what is to move right after heavy work waits for frames to come on time) - everything stands still with the system's "remove animations" |
| The pane beside the shelf (wide screens) | `LibraryNowReading` in `library_tiles.dart` (the book read last as a poster, the others and two numbers on equal columns), `LibraryRecapBento(narrow: true)`; a phone's shelf keeps `LibraryBentoPanel` |
| The reader's settings | `lib/services/reader_settings.dart` (`ReaderSettings.instance`, one store), `reader_settings_sheet.dart`: the reader's "Aa" sheet, and the same widget `embedded` in Settings under reading ("Reader defaults", `_ReaderDefaultsGroup`) |
| Settings / prefs DB (sqflite) | `lib/services/database.dart` (`MyLibraryDb`, `savePreference`) |
| Home: BOOK☆WALKER (Japan, default) / English lists | `lib/services/bookwalker.dart`, `lib/ui/japan_discover.dart`; 202 WAF → `browser_page_reader.dart` |
| Reader (foliate-js in a WebView) | `lib/ui/book_reader_page.dart`, `reader_web/` (built with `build.mjs`); the page's host `lib/ui/reader_host/` (WebView on devices, iframe + postMessage on the web) |
| Relay to the sync project (Cloudflare) | `cloudflare/` (`relay.js`, `worker.js` + `wrangler.jsonc`, `functions/sb/[[path]].js` for Pages, `test/`), `tool/cloudflare_build.sh`, `tool/cloudflare_headers.py` |
| Web app | `lib/main_web.dart`, `lib/web/` (`web_library_page` shell and grid, `web_series_bento` the series packed into rows, `web_book_dialog` a book's card, `web_book_opening` fetching a book, `web_cover`, `web_settings_page`, `browser` drops and storage), `web/index.html` + `splash.js` |
| Sync | `lib/services/sync/` (`sync_engine`, `supabase_remote`, `library_sync_local`, `sync_service`); settings `lib/ui/components/sync_section.dart` |
| Files the app keeps (web: IndexedDB) | `lib/services/storage/` (`AppFiles`) |
| Older reader | `lib/ui/epub_viewer.dart` |
| Engine choice (device / Gemini / Claude) | `lib/services/translation/translation_engine.dart` (`translationEnginePref`: one engine at a time, each engine's settings tell the others') |
| Device translation | `translator.dart` (`LocalLlmTranslator`, scheduler, `SharedTranslationEngine`), `third_party/llamadart` (see `PATCHES.md`) |
| Gemini | `lib/services/translation/gemini/` (`gemini_api`, `gemini_client`, `gemini_settings`: today's use kept per model, `usageOf`); settings UI `lib/ui/components/gemini_engine_section.dart` (the engine choice is there too) |
| What every engine off the phone shares | `cloud_engine.dart` (`CloudClient`, `CloudSettings`: results and errors are Gemini's types), `gemini/cloud_translator.dart` (prompts, checks, corrections - `gatherCorrections` for a book on its own: held, sent 24 together, an answer with one out of place not used, `misplacedCorrections`) |
| Claude (devices and the web; key in `claude_api_key`, shared with the owner's devices like Gemini's) | `lib/services/translation/claude/` (`claude_api`: models and prices, `claudeRequest`, `claudeSchema`, `claudeError`; `claude_client`; `claude_settings`: cost per model); settings UI `lib/ui/components/claude_engine_section.dart` |
| Prompts, styles | `translation_models.dart` (`batchPromptHead`, Korean light-novel style) |
| Checks and fixes | `translation_qa.dart` (`checkTranslation`, `finishTranslation`; names written as the glossary has them: `enforceGlossary`), `translation_style.dart` (how narration ends, read off the last syllables: `tenseSlips`, `leansOnShe`, `readsStiff`), `paragraph_text.dart` (`cleanTranslation`, `polishTranslation`) |
| Translations on real books, counted | `tool/translation_eval/` (its README): a book and its exported translation, the phone's steps against a `llama-server`, or `GlossaryService` and `CloudTranslator` against the API with a key |
| Paragraph split (shared by reader and library) | `paragraph_text.dart` (`readerParagraphs`, `epubReaderParagraphs`; `containsImage`, `glyphOf`: a glyph set as a picture is text), the page's own `reader_web/src/paragraphs.js` - the two must read every book alike |
| Saved translations | `translation_cache.dart` — one set per book × language × style (`shared`, `shared+plain`), JSON under `<books>/.translations/`; paragraphs to make again are marked beside it (`<set>.redo`, `redo`, `lookup` null while marked; `translation_repair.dart` `redoTranslationsWith`) |
| Glossary per book | `book_glossary.dart` (candidates, `BookSurvey`, `parseGlossaryAnswer`, `tidyNames`, `upgradeGlossary`; Gemini reading the whole book: `bookAnalysis*`), `japanese_names.dart` (the noun a name ends in, well-known places), `glossary_service.dart`, `series_glossary.dart` (the other volumes' names), `translation_repair.dart` (saved translations set right after a glossary is) |
| Library/background and "translate this whole book" | `book_translation_service.dart` (also the paragraphs marked to be made again, at once: `redo`, `redoWord`, a pass of those only), `lib/ui/components/priority_translation_card.dart` |
| A glossary outside the reader | `lib/ui/components/glossary_sheet.dart` (`showGlossarySheet`: a book's, or with `series` what its volumes have between them; a word set right asks which paragraphs to translate again - none, this book, the whole series): from a book's page (`mybook_page.dart`), a series' row in the library (`mylibrary_page.dart`), and on the web a book's card and a series' row menu |
| Series the reader makes | table `bookseries` (`MyLibraryDb.setSeries`), `library_organization.dart` (`librarySeries`: volumes by the number in their titles; `suggestedSeriesName`), `lib/ui/mylibrary_page.dart` (a long press chooses books, the bar over the foot of the list, a row per series; its books leave the grid unless something is searched), `series_glossary.dart` (`sameSeries`: titles and the reader's grouping, which has the last word; `passOnToSeries` an edit to the other volumes, `shareWithinSeries` on grouping; pref `seriesGlossaryShare`, on unless turned off); between devices `lib/services/sync/series_sync.dart` and `LibrarySyncLocal._reconcileSeries` |
| Translated EPUB export | `translated_epub.dart` |
| Home-screen widgets | `android/app/src/main/kotlin/dev/arne5/lightlib/HomeWidgets.kt`, `res/layout/widget_*`; what they show is written by `lib/services/home_widgets.dart` (`widgetSnapshot`: the book read last, its percent) when the library's books change |
| Pictures of the screens without a device | `tool/ui_shots/` (its README) |
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
- A glossary in the prompt is a hint, not a rule: both engines wrote
  준 타로, 유우나, 시즈크 beside the glossary's own form. Names are set
  right after the answer (`enforceGlossary`: a space, a long vowel, one
  letter off, kanji left whole or in part - only names the paragraph's
  source has, never another entry's word) and checked letter for letter
  (`missedNames`).
- 준 타로 was the app's own doing: `tidyNames` cut 純太郎 after 純, the
  hero's short name. A person's name is one word unless the book shows a
  family name (`GlossaryEntry.family`: the rest stands alone, or the
  first part takes さん/先生 and never くん/ちゃん). A name the book
  spells (furigana, hiragana) is written from that, whatever the model
  answered; hiragana names (しずく) are candidates too. What kind of
  word it is, the book says as well: E4B spelled しずく right and called
  it a term ("a drop"), and the heroine was dropped with the ordinary
  words - a word the book calls 〜ちゃん is a person
  (`_addressedAsPerson`), and `hiraganaNames` puts such names in even
  when no answer comes.
- One person, one spelling (`_onePersonOneSpelling`, glossary version 3):
  an engine reading a book wrote 結奈 = 유나 (the book's own ゆな) and,
  in the same list, 高森結奈 = 타카모리 유이나 and 結奈りん = 유이나린.
  With two of three entries saying 유이나, Flash-Lite wrote 유이나 in
  every paragraph of the book and the corrections brought back half. A
  full name is written with its parts' own entries, a pet form (りん,
  ちん, っち…) as the name and its tail, and where the book spells the
  full name the given name follows that; the reader's entries are
  followed and never changed. When names flip in a translation, read the
  glossary for two spellings of one person before blaming the engine.
- What someone is, is not who (glossary version 4): an engine reading
  崩壊世界の魔法杖職人 listed 魔女 as a person, with the heroine's title
  as its Korean (푸른마녀); the names check then wrote that for every
  witch of the book (花の魔女 → 꽃의 푸른마녀, 魔女集会 → 푸른마녀 집회,
  254 paragraphs). A role noun or a way of addressing is no entry
  (`_notNames`: 魔女, 勇者, 騎士…; `_notHiraganaNames`: ちゃん, さん…;
  `_neverAName` at upgrade and from the series), nor is an entry written
  exactly as a longer one that ends with it. A description someone goes
  by (`isTitle`: 青の魔女, 八王子の魔女, オコジョ教授) is words: the
  engine's Korean with its spaces, never spelled from the reading
  (하치오지노마조) or joined as a given name is (푸른마녀).
- The reader set a name right and the book kept the old one: an edit
  changed the glossary and nothing already saved (the repair after it
  only sets near-misses of the new form right). Deleting saved
  translations does not work either - sync is a union and the account
  gives them back. So they are marked to be made again (`<set>.redo`,
  on the device only; `TranslationCache.lookup` answers null until a new
  one is stored): on an edit, the paragraphs with the word whose
  translation has the form it had (`GlossaryService.onEdited` with the
  entry as it was; the series' other volumes in `passOnToSeries`), and
  every paragraph with the word when the reader ticks that in the edit
  dialog (`glossaryRedoAll`).
- A set of saved translations is kept by the language's code (`ko`):
  `translation_repair.dart` opened it by the English name the prompts
  use (`Korean`) - another, empty set, and nothing said so. So names set
  right after a glossary changed were never written into what was
  saved, and "every paragraph with this word" marked 0 for the owner an
  hour after it shipped. The tests passed: they made their sets by the
  same wrong name. `TranslationCache.open` asserts a code now; a test
  makes its sets as the app does (`target.code`), not as the function
  under test happens to. Marks alone do not change an open page either:
  the reader sends the page each paragraph once (`_sent`), so it starts
  its page over when it hears of them (`redoMarks`, `_onRedoMarked`).
- Paragraphs marked to be made again waited for the reader to come to
  them: a word wrong in a series was put right one screen at a time,
  each screen translating while it was read. `BookTranslationService.redo`
  makes them at once and to the end without a book being opened - the
  marked ones only (a book half translated is not finished on that
  account), an engine off the phone taking 24 that lie apart in one
  request, as it takes the ones sent back. The glossary is reached
  without opening a book for that, and for a series as one.
- A write to a real file begun inside `testWidgets` never comes back,
  and what waits for it stops there without a word: the glossary
  sheet's first test passed because the service changes what it holds
  in memory before it writes. A widget test that goes on after a write
  keeps the files in memory (`IdbAppFiles(newIdbFactoryMemory())`).
- A glyph set as a picture: the Japanese publishers' EPUBs write what
  the fonts lack as `<img class="gaiji" alt="…">`, and one book wrote
  every "!!?" so. The rule that leaves a block with a picture alone (an
  illustration with its caption) left those lines untranslated, 51 in
  that book. `glyphOf` tells the two apart (a `gaiji…` class, or an
  `alt` of marks only) and the line is read with the glyph in it; what
  an illustration is called (`alt="絵"`) is not a glyph. Such pictures
  are black on nothing: inverted in dark themes (`styles.js`).
- A glossary's rules changed: `BookGlossary.version`. An older one is set
  right from the book without a model (`upgradeGlossary`), and the saved
  translations after it (`translation_repair.dart`).
- Narration in the present is the book's own, not an engine's slip: in
  three books translated by Gemini, a sentence the book has in the past
  (〜た) came out in the present 0, 1 and 0 times; every -ㄴ다 sentence
  was a Japanese present. So the past is asked only of what happens in
  the scene (`tellsEventInPresent`, `tenseSlips`: one such sentence
  between past ones, sent back once). A habit, a general fact, a feeling
  or a guess stays as the book has it (자주 놀리곤 한다, 좋아한다, -ㄹ지도
  모른다): the first version sent those back too, and of 30 paragraphs
  it "fixed" 28 were the book's own present, 좋아한다 turned 좋아했다.
  A number that falls is not yet a translation that is better: read
  what a check changed before believing it.
- How far the style instructions carry depends on the model (book 3,
  narration told in the present): Gemini 3.5 Flash 34% → 9-15% with the
  instructions alone and 그녀 15 → 0-1; 3.5 Flash-Lite 34% → 32% and
  그녀 as before, so there the check does the work; E2B 16% → 7%, E4B
  about 5% either way. 그녀 and stiff paragraphs are sent back by Gemini
  only (stiff by the reader's choice, `geminiPolish`).
- An engine that reads the whole book lists what a list of names should
  not have, and answers well where the parser must not "correct" it
  (`parseBookAnalysis`): names with how they are addressed (純くん,
  玲子さん - skipped, the name alone is the entry; spelling the reading
  made 준쿤, 레이코산 and the check then forced them on the text), an
  ordinary place by its meaning (宿直室 → 숙직실: a reading is spelled
  only where the engine's own Korean is that sound, or for a person), a
  full name in two words (kept where the parts are names of their own,
  or the name has four letters or more: `family`). After such a
  reading, a katakana word nobody is addressed by is not asked about
  one line at a time (`unnamedCandidates`): イルカ at a dolphin show
  came back a person. A reading cut short with nobody to ask about the
  rest leaves the glossary not `complete`, to be made again.
- Gemini's free tier counts requests a day by model: 20 for
  `gemini-3.5-flash` (a book is 45 and more), and a 429 that names a
  per-day quota ends the day for that key (`usage.exhausted`). 3.5
  Flash is on the list (`geminiModels`) with that figure; 3.5 Flash-Lite
  stays the one a reader starts with. In the reader a screenful costs
  two requests - the translation, and the paragraphs sent back (a fixed
  2,000 tokens of instructions for three or four paragraphs). A book
  translated on its own holds those and sends them 24 together
  (`gatherCorrections`): 480 paragraphs were 6 requests and 1, not 6
  and 5, so a book is about 50 requests, not 90 - and one more for
  each 30,000 characters when its glossary is first made.
  "Balanced" thinking on Flash-Lite thought nothing (0 thinking tokens,
  the same answers within the noise of a second run).
- Whether a translation reads better is asked of a reader, or failing
  that of a stronger model that does not know which is which
  (`tool/translation_eval/judge.py`). Two runs of one model with one
  prompt came out 64 : 47 there: a difference that size is noise. When
  the translators are of two families, a judge of each is asked and
  what both say is believed.
- Claude (Messages API, `claude_api.dart`): no thinking is asked for
  differently by model (`ClaudeQuiet`: Haiku `disabled`, Sonnet
  `between_tools`, Opus cannot - it thought nothing at effort `low`
  anyway); `temperature` is not sent; a schema's objects are closed and
  carry no sizes (`claudeSchema`); a key not tied to a workspace needs
  `anthropic-workspace-id` (the error says so: `badKey`, shown as it
  is); "credit balance is too low" is the one error that ends the key
  for the day. From a page the API answers only a request that says it
  comes from a browser (`anthropic-dangerous-direct-browser-access:
  true`, sent on the web alone) and the site's policy must let it out
  (`connect-src` in `vercel.json`, which the other hosts copy). Claude
  was first built for devices only, the owner not asked: he found the
  web without it. What the web leaves out is his to decide. Claude counts about 1.5 times the tokens Gemini does for
  the same Japanese and Korean: compare prices on measured tokens.
  Book 3, 240 paragraphs, the same glossary, judged blind by Gemini 3.8
  Flash and by Claude Fable 5.2 (paragraphs where one was ahead of the
  other): Sonnet 5.5 over Gemini 3.5 Flash 70 : 21 and 72 : 20; Haiku
  5.5 about level with that Flash (Gemini's judge 51 : 32, then 22 : 30
  on a part of the same paragraphs judged again; Claude's 62 : 31) and
  well over Flash-Lite (93 : 27 and 81 : 29); Sonnet over Opus 5.5
  76 : 55 and 49 : 44 (Opus had the most mistranslations pointed out of
  the three). For 160 paragraphs at list prices: Haiku $0.005,
  Flash-Lite $0.02, 3.5 Flash $0.06, Sonnet $0.10, Opus $0.19. Haiku
  once gave a whole request back in Japanese (1 of 14): `leftoverSource`
  flagged all 80 and the correction request translated them - that
  check is what makes the cheap model usable. Thinking bought nothing:
  "balanced" on Sonnet thought nothing (0 thinking tokens), on Haiku it
  thought twice the answer's tokens and neither judge preferred it.
  Books 1 and 2 (240 paragraphs each, against the translations the
  owner had): Sonnet over those 102 : 44 / 102 : 34 and 111 : 64 /
  96 : 47, Haiku over them in book 1 (87 : 49 / 77 : 48) and level in
  book 2, Flash-Lite with today's steps not over them in either
  (67 : 75 / 55 : 82, 74 : 100 / 44 : 90): the steps set names and
  slips right, the prose is the model's.
- More context, tried (`tool/translation_eval` README; book 3, 480
  paragraphs, Claude's judge only - Gemini's answered 503 that day): a
  table of who speaks how to whom, after the instructions, read better
  than none on Sonnet (42 : 24) and cost nothing to speak of; a summary
  of the story so far did not (31 : 39, more mistranslations pointed
  out), nor both together. Given to Flash-Lite the notes did harm: the
  Japanese name forms in them (歌原さん) came out in its Korean (さんは
  left in the drafts, 53 paragraphs sent back, not 18). If the table is
  built in: names as the glossary writes them, never with an honorific.
  The polish option: 14 of 1,920 paragraphs were sent back as stiff,
  and the rewritten ones were not preferred (4 : 7).
- Sync keeps a setting's time to the millisecond; a finer time sent to
  the account looks newer there at the next run and is taken again.
  A setting's value was limited to 4,096 characters on the account:
  raised for the series (`20261120000000_series_setting.sql`).
- The library's bar of chosen books: a button with an icon does not let
  its label give way (it overflowed in English at 360 dp), and a
  snackbar still showing lies over it (`hideCurrentSnackBar` when a
  book is chosen).
- Android's own backup and device transfer would carry the files of the
  app's folder: the keys and the Z-Library session are left out by name
  (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`). A new file
  that holds a secret is added to both.
- `map[k] ??= work().whenComplete(() => map.remove(k))` never ends:
  `remove` returns that very future and `whenComplete` waits for it. Use
  a block body.
- A book against its exported translation: the reader's splitter does not
  count a translation without a letter (“……”) as a paragraph, so the two
  drift apart by index. `tool/translation_eval` pairs within chapters and
  steps over those lines; hundreds of `tooShort` mean a bad pairing, not
  a bad translation.
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
- DiamWall's newer gate answers a 307 back to the same page with a
  `__diamwall` cookie (then the page, or 517 "Access Denied"). Dio keeps
  no cookies and called it a redirect loop, so the mirror was given up.
  Z-Library's GETs go through `_getPastGate` (redirects by hand, the
  gate's cookie back to that host only, the account's cookies never to
  another host; a `/dl/` link follows only the gate's own 307, its 302
  to the file is the answer) and a 517 goes to the next mirror.
- This repository's history starts anew (2026-10-25, at OpenlibExtended
  v1.7.2 `c5ae926`): no common commit with upstream, so what upstream
  added since is compared by content, and what is taken names its
  commit in a comment.
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

- "Back" from a reader landed in another book's reader: a home-screen
  widget's tap pushed its book's page on whatever was on screen, so the
  stack became shelf → book A → reader A → book B → reader B. Screens
  round a book have one order (`book_navigation.dart`): the tabs, the
  book's page, the reader. A book asked for from outside closes what is
  open first (`showBookFromOutside`: routes are named `book:<id>`,
  `reader:<id>`; the very book already on screen is left alone).
- The web's library did not show where a book was left: it reloaded
  when the future of the page it pushed completed - and that page (the
  one that fetches the book) hands over to the reader with
  `pushReplacement`, which completes the future as the reader *opens*.
  A replaced route's future says nothing about the route that took its
  place. Whoever shows reading state listens to
  `MyLibraryDb.readingChanged`, which the reader counts up after its last
  position is written (a reader's `dispose` saves without waiting; a
  reload at the pop reads the position of a page ago).
- No book was ever "finished" in the app: `setCompleted` had no caller,
  a saved position reset the mark (`INSERT OR REPLACE` of the row) and
  the mark wiped the position. The reader marks a book at its last page
  (`atEnd` of the last section - a short book's last page starts well
  before 99.5% of it - or 99.5%, the web's rule), a book's page has the
  button both ways, the mark and the position each keep the other. A
  book read to its end on another device counts by its share alone.
- "Continue reading" was the newest book among those being read, not the
  one read last: `continueReading` orders by `pos:<file>` (when the
  position was saved, here or on the device it came from).
- Two panes on a foldable: the fold is at half the screen, the tabs'
  rail stands on the right, so the end pane is narrower than the start
  one (289 dp on a Z Fold 7: 750 − 375 − 6 − 80). What goes there must
  fit a 290 dp column - two buttons side by side become one under the
  other (`book_detail.dart`), the reading record's row has a floor of
  124 dp. `MediaQuery.displayFeatures` is in logical pixels, in tests
  too (`tester.view.displayFeatures`).
- A widget test's window is 800 x 600: wide. A test of a phone's layout
  sets `tester.view.physicalSize`; one that pushes a book's page on that
  window sees it step into the pane and leave the stack (`BookPage`
  does that when a phone is unfolded).
- A provider read to build a menu item started a fetch: the "open in
  site" address needs the mirror that is up
  (`annaArchiveBaseUrlProvider`), and watching it in `build` asked the
  network whenever a book's page was shown (in a widget test: a timer
  left pending). It is asked when the item is tapped.
- The way into a book stuttered on the owner's Z Fold 7 ("like a
  low-end phone"). Nothing here can time a phone's frames, so what was
  found is what the code did during that second, all of it changed and
  none of it measured: (1) the web view was made and the book loaded
  with the route - on Android that work is on the thread frames are
  drawn on - while the cover flew in; the reader now makes its page when
  the way in has ended (`_hostAllowed`). (2) The opening picture kept
  its cover drifting, a frame every 8 ms all through the loading; it
  stands still now (`test/motion_test.dart`). (3) Its backdrop was a
  blur as a layer (`ImageFiltered`, in a `RepaintBoundary`) over the
  whole screen, faded and scaled as it left; `BookCoverBackdrop` now
  blurs a 48 px copy once into a picture of its own (`toImageSync`) and
  stretches that. (4) It left the moment the first page was up, in the
  middle of the page's own work; it waits for frames to come evenly
  (`EvenFrames`: five on time, or 0.8 s) and goes as a plain fade.
  (5) A cover was decoded at the very width it was shown, so a cover
  flying from a tile to a page was decoded anew every frame of the way:
  `coverDecodeWidth` (a few steps), `gaplessPlayback`. The reader now
  writes what it drew into the log - "Opening frames": for the way in,
  the loading and the picture leaving, how many frames, how many over
  20 ms, the worst one (waited for the thread / build / raster). If it
  still stutters, read that line in the owner's log before changing
  anything else.
- The store's covers are thumbnails (`bookwalker.jp/thumbnail…`): the
  first of a ranking shown twice as large came out blurred, and its row
  did not line up with the captions beside it. Every cover of the home
  lists is one size; no numbers on them either (the owner's word, twice).
- The light theme's `primary` was white (`themes.dart`, from Openlib):
  whatever Material draws in it - a switch that is on, a checkbox, a
  slider, a spinner, a text button, an icon given the primary colour -
  was white on white. The web's settings had three switches nobody could
  see, a "sign out" button and a link that were not there, the reader's
  links and its "translation on" icon vanished on a light page. It is
  near black now (as white is in the dark theme); the screens under
  `modernSurfaceTheme` were never affected. What sits on the reader's
  page takes the page's colours (`ReaderPalette.accent`), not the app's:
  the app may be light and the page "night". Look with
  `tool/web_check/themes.mjs light` and `SHOT_THEME=light` in
  `tool/ui_shots` - white on white shows only in a picture.
- The web listed each series as a full-width row of covers, mostly
  empty: seven series took three screens. `web_series_bento.dart` packs
  them - a card as wide as its volumes, the first row with room
  (`packSeries`), each row's covers grown alike to reach the edge, a
  series longer than a line folded to a line and "+N"; one line under a
  cover (the volume: `volumeCaption`).
- `dart format` on a whole file of this repository rewrites it (most
  files were formatted by an older formatter: `settings_page.dart` came
  back with 770 lines changed). Format what is new by hand, or a new
  file.
- A `GlobalKey` above `MaterialApp` moves the whole app, navigator and
  all, to wherever the key is pumped next: a "new" app in the same test
  kept the old one's pages (`tool/ui_shots`: the fresh key goes on
  `MaterialApp` itself).

## Open plans (owner's order)
1. Translation on the owner's MacBook: largest Gemma 4 the Mac's memory
   allows (MLX or llama-server, OpenAI-compatible), reachable only by the
   owner (Tailscale preferred, or a tunnel with an API key); an app engine
   "내 서버" (URL + key) reusing `CloudTranslator`'s structure.
2. Web + sync (built, see "Web and sync"): next - the reader's fonts
   and word tools on the web, a smaller
   start (llamadart is still in the web bundle, ~0.4 MB; a WebAssembly
   build compiles but saved only ~10% of the download). No public relay
   for shadow-library search/downloads.
3. Smaller: `[n]`→`n.` numbering, token-budget batches, translator-note
   stripping, tok/s + heat logs, per-book genre detection, bilingual EPUB.
   Foldables, not done: the reader half open on a table (the page on the
   upper half, its controls on the lower) - nothing here can show a web
   view folded, so it waits for the owner's device; two pages for text
   written down the page.
   Translation quality, not done yet (project doc
   `claude/translation-quality-status.md`,
   `claude/translation-engines-status.md`): Gemini 3.5 Flash measured
   on more than book 3, runs of present-tense narration on
   Flash-Lite (left as the book has them), names the device finds without
   honorifics
   (kanji pairs that always go together), on the phone a draft whose
   flagged paragraphs go to Gemini when online, a no-kanji grammar for
   GGUF models. Claude: older models on
   the list.
4. Study, later: a bundled pre-translated dictionary (JMdict + Korean
   meanings) as an extension; the word sheet would show it before the
   engine's contextual meaning.
