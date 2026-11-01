# Reader page

The EPUB renderer of the app's reader: [foliate-js](https://github.com/johnfactotum/foliate-js)
(readest's fork, commit `50435d7`, MIT, in `foliate-js/`) plus `src/`, the bridge
to the Flutter app (`lib/ui/book_reader_page.dart`). Style overrides follow
[readest](https://github.com/readest/readest) (AGPL-3.0).

The app loads the built page from `assets/reader/`, committed so that a Flutter
build needs no Node. After changing anything here:

```sh
cd reader_web
npm ci
npm run build   # writes ../assets/reader/index.html and reader.js
```

`src/study.js` holds the study helpers (furigana, the word under a tap, a
book's JLPT spread) on [kuromoji.js](https://github.com/takuyaa/kuromoji.js)
(Apache-2.0). Its dictionary is not bundled: the app downloads it once and
serves it at `/reader/dict/`. Their text logic is tested with the real
dictionary:

```sh
npm test
```
