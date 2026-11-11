# Checks of the web app

The built web app (`build/web`) run in headless Chrome: real mouse clicks
and touches at real coordinates, the sync project answered by a stand-in
that lives in memory (no account, nothing on the owner's project is
touched), Gemini answered by a stand-in too (the API is never called).

```bash
cd tool/web_check && npm install          # puppeteer-core; Chrome at $CHROME or /usr/bin/google-chrome
python3 make_library.py /tmp/lib24 24     # 24 made-up EPUBs with covers, and the account's rows
python3 make_epub.py /tmp/haru.epub       # one small vertical book without a cover

node serve.mjs ../../build/web 8094 ../../vercel.json &   # like Vercel: its headers (CSP), brotli
node mock_project.mjs /tmp/lib24 8099 &                   # the stand-in project

node library.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots desktop   # or: mobile
node account.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots /tmp/other.epub
node translate.mjs http://127.0.0.1:8094/ /tmp/haru.epub /tmp/shots
node reader_taps.mjs http://127.0.0.1:8094/ /tmp/haru.epub /tmp/shots
node desktop_reading.mjs http://127.0.0.1:8094/ /tmp/horizontal.epub /tmp/shots
node drop.mjs http://127.0.0.1:8094/ /tmp/other.epub /tmp/shots
```

| Script | What it shows |
|---|---|
| `library.mjs` | Signed in: every book listed without one file fetched; a book's card; "Read" fetches that one file with its progress; the reader; back in the library the book is here and read a little; search, the side bar, the right-click menu, settings |
| `account.mjs` | The Gemini key typed in one browser is on the account and in a second browser; a book added here goes up with its details and small cover; this browser's copy goes while the account keeps the book; a deletion reaches the account |
| `translate.mjs` | Not signed in: an EPUB added, opened, translated (stand-in), kept over a reload, shown without a key |
| `reader_taps.mjs` | A phone: the reader's bars, a sheet over the page and a message's button take real taps |
| `desktop_reading.mjs` | A horizontal book in a wide window: the column's width when scrolling, two pages when turning, keys and wheel |
| `drop.mjs` | An EPUB dropped on the window is added |
| `load.mjs` | First load as a phone on 4G or a desktop: first paint, first frame, bytes, memory (`node load.mjs <url> mobile`) |
| `visit.mjs` | A signed-in visit to the 24-book account: what is fetched before the library is ready, what the tab holds |
| `reading_memory.mjs` | The tab while a book is read |

`account.mjs` wants an EPUB that is not in the stand-in's library (make a
second library with another count and take a file from its `files/`), and
`desktop_reading.mjs` a horizontal one.

The semantics tree is only read to find where a widget is; every click is
a real pointer event at that place (a click on a semantics node once
passed while real taps did not). `page.keyboard.press('/')` sends the
number pad's slash, which the Flutter engine trips over: use `'Slash'`.
In headless Chrome everything is drawn in software, so times are several
times a real machine's; compare builds, not absolute numbers.
