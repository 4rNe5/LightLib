# Checks of the web app

The built web app (`build/web`) run in headless Chrome: real mouse clicks
and touches at real coordinates, the sync project answered by a stand-in
that lives in memory (no account, nothing on the owner's project is
touched), Gemini and Claude answered by stand-ins too (the APIs are never
called).

```bash
cd tool/web_check && npm install          # puppeteer-core; Chrome at $CHROME or /usr/bin/google-chrome
python3 make_library.py /tmp/lib24 24     # 24 made-up EPUBs with covers, and the account's rows
python3 make_epub.py /tmp/haru.epub       # one small vertical book without a cover

node serve.mjs ../../build/web 8094 ../../vercel.json &   # like Vercel: its headers (CSP), brotli
node mock_project.mjs /tmp/lib24 8099 &                   # the stand-in project

node library.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots desktop   # or: mobile
node account.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots /tmp/other.epub
node translate.mjs http://127.0.0.1:8094/ /tmp/haru.epub /tmp/shots
node claude.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/haru.epub /tmp/shots
node series.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots
node whole_book.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/haru.epub /tmp/shots
node reader_taps.mjs http://127.0.0.1:8094/ /tmp/haru.epub /tmp/shots
node desktop_reading.mjs http://127.0.0.1:8094/ /tmp/horizontal.epub /tmp/shots
node drop.mjs http://127.0.0.1:8094/ /tmp/other.epub /tmp/shots

BARE=1 node mock_project.mjs /tmp/lib24 8098 &            # an account no device has put covers on
node covers.mjs http://127.0.0.1:8094/ http://127.0.0.1:8098 /tmp/shots mobile
node busy.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 after
```

| Script | What it shows |
|---|---|
| `library.mjs` | Signed in: every book listed without one file fetched; a book's card; "Read" fetches that one file with its progress; the reader; back in the library the book is here and read a little; search, the side bar, the right-click menu, settings |
| `account.mjs` | The Gemini key typed in one browser is on the account and in a second browser; a book added here goes up with its details and small cover; this browser's copy goes while the account keeps the book; a deletion reaches the account |
| `claude.mjs` | Signed in to an account a phone put its Claude key on: the key comes with the first sync, Settings has its switch, Claude is chosen, a book is translated by it - every request saying it comes from a browser, none refused by the site's policy, none to Gemini |
| `series.mjs` | Signed in: two of the account's books (neither in this browser) chosen from a tile's menu and by a click, named, grouped; the row shows and the account has the series under their MD5s, sent from the web |
| `whole_book.mjs` | A book added, its card opened, "translate this whole book" pressed: every paragraph translated (stand-in) and kept in the browser, the reader never opened |
| `translate.mjs` | Not signed in: an EPUB added, opened, translated (stand-in), kept over a reload, shown without a key |
| `reader_taps.mjs` | A phone: the reader's bars, a sheet over the page and a message's button take real taps |
| `desktop_reading.mjs` | A horizontal book in a wide window: the column's width when scrolling, two pages when turning, keys and wheel |
| `drop.mjs` | An EPUB dropped on the window is added |
| `relayed.mjs` | The relayed site, the project unreachable by its own address: Google's button signs in, the library lists, a book comes and opens, all through `/sb` |
| `covers.mjs` | An account without small covers: every book's real cover shows without one book fetched (read out of each file by byte ranges), and is kept for the other devices |
| `busy.mjs`, `start_busy.mjs` | As a phone with a CPU four times slower: frames drawn and time the page's thread is busy while idle, scrolling the library, in the reader, and in the first 15 s |
| `load.mjs` | First load as a phone on 4G or a desktop: first paint, first frame, bytes, memory (`node load.mjs <url> mobile`) |
| `visit.mjs` | A signed-in visit to the 24-book account: what is fetched before the library is ready, what the tab holds |
| `reading_memory.mjs` | The tab while a book is read |

A page reloaded, or visited a second time, in the same headless browser
stays on the library's outline (the database's worker of the first visit
is still there): the deployed site does the same under this harness, a
person's browser does not. A check that needs something in place before
the app starts puts it there from a file of the site that is not the app
(`version.json`), then opens the app once.

The stand-in refuses a storage or table request without the project's
key and a session's token, in the project's own words (400 "Bucket not
found"): the app once read covers with such requests, and a stand-in that
answered anyone let it pass. `OPEN=1` brings the old answering back.

The site that passes the sync project's requests on (Cloudflare Pages):

```bash
FLUTTER_HOME=/opt/flutter bash ../cloudflare_build.sh      # ../../cloudflare/dist, as Cloudflare builds it
node mock_project.mjs /tmp/lib24 8099 &
# Cloudflare's own runtime on that output (npm install wrangler somewhere),
# as the Workers project runs it (as a Pages project: wrangler pages dev dist ... --binding SUPABASE_URL=...):
(cd ../../cloudflare && wrangler dev --ip 127.0.0.1 --port 8097 --var SUPABASE_URL:http://127.0.0.1:8099) &
node relayed.mjs http://127.0.0.1:8097/ http://127.0.0.1:8099 /tmp/shots
# or without wrangler, the same relay code under this folder's server:
node serve.mjs ../../cloudflare/dist 8096 ../../vercel.json / relay=http://127.0.0.1:8099 &
```

`relayed.mjs` runs the browser with the project's own name leading
nowhere (as on the network the site is for): signing in with Google's
button (stood in for by `session.mjs` - a real Google sign-in is not
something a test here can do), the library, a book fetched with its
progress, the reader - with no request to the project's own address.
Without `--var`, wrangler's relay asks the real project: enough to
see that it answers through it (`/sb/auth/v1/health` with the key).

An old browser (the owner once read in Chrome 112, where no book opened):

```bash
npx @puppeteer/browsers install chrome@113 --path /tmp/oldchrome   # the oldest "Chrome for Testing"
npm install --no-save puppeteer-core@20.2.1                        # a driver of its age (the current one cannot open a page in it)
CHROME=/tmp/oldchrome/chrome/linux-113.*/chrome-linux64/chrome node library.mjs http://127.0.0.1:8094/ http://127.0.0.1:8099 /tmp/shots desktop
```

Headless Chrome 113 keeps the database's shared worker after its tab is
gone, and a later visit in the same browser run waits on it for ever
(`translate.mjs` reloads, so it stops there). A restarted browser, two
tabs at once and the owner's own Chrome 112 did not show this.

A host that serves the app under a path and sends no headers (GitHub
Pages): build with `--base-href /LightLib/`, run `tool/pages_csp.py`, and
`node serve.mjs ../../build/web 8095 none /LightLib/`.

`account.mjs` wants an EPUB that is not in the stand-in's library (make a
second library with another count and take a file from its `files/`), and
`desktop_reading.mjs` a horizontal one.

The semantics tree is only read to find where a widget is; every click is
a real pointer event at that place (a click on a semantics node once
passed while real taps did not). `page.keyboard.press('/')` sends the
number pad's slash, which the Flutter engine trips over: use `'Slash'`.
In headless Chrome everything is drawn in software, so times are several
times a real machine's; compare builds, not absolute numbers.
