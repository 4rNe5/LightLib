# Pictures of the app's screens

The app's own widgets drawn at a phone's size (411 x 914 dp) and an
unfolded foldable's (750 x 832 dp, with its fold down the middle), over a
real (ffi) database seeded with a small library: the library, a book's
page, the picture shown while a book opens, settings, search and home.
No device, no emulator - what a layout change looks like, in a minute.

```bash
SHOT_COVERS=/tmp/covers SHOT_FONTS=/tmp/fonts SHOT_OUT=/tmp/shots \
  flutter test --no-pub tool/ui_shots/shots_test.dart
```

| Variable | What it is |
|---|---|
| `SHOT_COVERS` | A folder with `books.json` - `[{"title", "author", "cover": "<file in the folder>", "description"}]` - and the cover pictures. Without it: nine books without covers |
| `SHOT_FONTS` | A folder with `Nunito-400.ttf` … `Nunito-900.ttf` (the app's font; the test runner cannot fetch it). Korean and Japanese are drawn with the machine's Noto Sans CJK |
| `SHOT_THEME` | `light` for the light theme (pictures named `light_…`); dark otherwise |
| `SHOT_OUT` | Where the PNGs go (`phone_1_library.png`, `fold_3_book.png` …) |

It is a test file so that it can pump widgets, and lives outside `test/`
so that `flutter test` does not run it.

What it cannot show: the reader's page (a web view) and anything that
moves. The screen's fold is given to the app as a device gives it
(`MediaQuery.displayFeatures`, in logical pixels).
