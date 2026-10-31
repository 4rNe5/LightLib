# 📖 LightLib — FAQ

## What is LightLib?
An e-book library and reader for Android, made for Japanese light novels. It keeps each book's own layout (vertical writing, ruby, images), translates as you read, and keeps track of your reading.

---

## How do I install it?
Download `LightLib-<version>-build.<n>-arm64.apk` from the [latest release](https://github.com/4rNe5/LightLib/releases/latest) and open it on your phone (allow installs from your browser or file manager when Android asks). After that, updates come through the app.

## Samsung says the app may be harmful. Is it?
Galaxy phones check apps installed from outside the stores against the store's records; an app the store has never seen can be flagged on its first run. Choose to keep the app, or report the warning as a mistake through Samsung Members. The APK's SHA-256 is on every release page if you want to compare.

---

## Where do the books come from?
You can add EPUBs you already have (*My Library → Import EPUB / PDF*), or search the online catalogues the app looks through and download from there. Home shows what is popular on BOOK☆WALKER and among English titles, and a tap searches for that series.

## Is downloading books legal?
It depends on the book and on where you live. Books under copyright are their owners' property; check your local laws, and use the app for personal reading. See the [Disclaimer](README.md#disclaimer-%EF%B8%8F).

---

## How does translation work?
Turn translation on in the reader, and the paragraphs on screen are translated first, then the ones ahead. Two engines can do it:

| | On the phone | Gemini |
|---|---|---|
| Set up | Download Gemma 4 E2B or E4B in *Settings → On-device translation* | Add your own key from [Google AI Studio](https://aistudio.google.com/apikey) |
| Speed | About an hour or two per book | A book in minutes |
| Works offline | Yes | No |
| Cost | Free | Free tier covers several books a day; paid keys cost cents per book |

Both save to the same translation, so you can switch between them freely.

## Where does my text go?
Your library, positions, glossaries and translations stay on the phone (and in your backups). The phone's model keeps the text there too. With Gemini, the paragraphs being translated are sent to Google with your key — on the free tier Google may use them to improve its services; on a paid key it does not. Your key is stored on the device only and is not included in backups.

## What are the Gemini settings?
- **Model** — Gemini 3.5 Flash-Lite is the default (fast, generous free tier); larger Flash models trade speed for nuance.
- **Thinking** — speed first, balanced, or quality first. More thinking reads nuance better and takes longer.
- **Safety filters** — off by default so books rated 15+ and adult translate in full. A few things Google never translates whatever is set; those paragraphs stay in the original.
- **Continue on the device** — when the day's quota runs out, a paragraph is filtered, or there is no connection, the phone's model takes over.
- **Today's use** — requests against your limits, tokens, blocked paragraphs, your tier, the cost at paid prices, and when the quota resets.

## The phone gets warm while translating.
Translation runs the GPU hard. Background translation slows down as the phone warms and stops near the limit; *Translate this whole book* runs at full speed only while the app is open. Gemini does the work off the phone, so it stays cool.

## Can I read the translation in another app?
Yes: on the book's page, *Export translated EPUB* makes a regular EPUB with the translation in place (untranslated paragraphs stay in the original). Sharing the original book file does not include the translation.

## A translation looks wrong.
On the book's page, *Delete this book's translations* clears them; reading or *Translate this whole book* translates again. If it keeps happening, send the app's log (*Settings → Export Logs*) with a report.

---

## Where are the books stored?
In the folder chosen in *Settings → Storage Location* (the app's own folder by default). Translations sit in a hidden `.translations` folder next to the books, so they move with the folder and with backups.

## The app crashes or something is off.
- Make sure you have the latest build ([Releases](https://github.com/4rNe5/LightLib/releases)).
- Check the [issues](https://github.com/4rNe5/LightLib/issues); if it is new, open one with the log from *Settings → Export Logs* and a screenshot.

## How do I contribute or ask for a feature?
See [CONTRIBUTING.md](./CONTRIBUTING.md), or open an issue.

---

*Last updated: 2026-10-31*
