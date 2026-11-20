# Translation checks on real books

What the app's own detectors count in a translation (`lib/services/translation/`:
`translation_style.dart`, `translation_qa.dart`, `book_glossary.dart`), on books
kept outside the repository. Nothing here ships with the app, and no book text
belongs in this folder: results that quote a book stay on the machine that made
them.

Both files are run with `flutter test` (the app's code needs Flutter), and are
skipped unless their variables are set. They live outside `test/`, so the
ordinary `flutter test` never runs them.

## A finished translation, counted

A book and the EPUB the app exported with its translation (Library → the book →
export translated EPUB).

```bash
EVAL_SOURCE=book.epub EVAL_TRANSLATED=book.ko.epub \
/opt/flutter/bin/flutter test --no-pub tool/translation_eval/book_report_test.dart
```

Several books: paths with commas between, in the same order. `EVAL_GLOSSARY`
(a glossary's JSON, one per book) replaces the names read from the book alone.

| Row | What it is |
|---|---|
| 이름이 용어집과 다른 문단 | `missedNames`: the source names someone and the translation does not write the name as the glossary does |
| 이름 자동 교정이 고칠 문단 | `enforceGlossary` changes the paragraph (a space in a name, a long vowel, a letter off, kanji left) |
| 동작 현재형 비율 | narration sentences ending -ㄴ다/-는다 among those ending in a tense (`koreanEnding`) |
| 시제가 튄 문단 | `tenseSlips`: an action told in the present between past-tense sentences, or where the book's sentence ends in 〜た |
| 그녀에 기댄 문단 | `leansOnShe` |
| 직역투 문단 | `readsStiff` |
| 다시 쓸 문단 | what each engine would send back once more: its share is the extra requests the checks cost |

The paragraphs are paired within each chapter file. The reader's splitter does
not count a translation without a letter (“……”) as a paragraph, so the pairing
steps over the wordless lines whose translation went missing; a chapter that
still does not pair up is left out and named on stderr. A sign of a bad pairing:
`tooShort`/`tooLong` in the hundreds.

## The phone's way, against a model on this machine

```bash
llama-server -m gemma-4-E4B-it-Q4_0.gguf -c 4096 -t 2 --reasoning off --port 8089
EVAL_SERVER=http://127.0.0.1:8089 EVAL_SOURCE=book.epub EVAL_OUT=out.json \
/opt/flutter/bin/flutter test --no-pub tool/translation_eval/device_pipeline_test.dart
```

| Variable | |
|---|---|
| `EVAL_STARTS` | where each twelve-paragraph stretch begins (reader paragraph numbers, commas between); six spread over the book when left out |
| `EVAL_GLOSSARY` | `make` (the model makes it, as the app does; the default), `book` (the names the book spells itself), or a glossary's JSON |
| `EVAL_FIX=0` | stop after the first answers: no paragraph is sent back |
| `EVAL_OUT` | sources, first answers, final answers and every paragraph sent back, as JSON (it holds the book's text: keep it out of the repository) |

It follows `LocalLlmTranslator._translateBatchNow` step for step with the app's
own functions, but it is a copy of those steps: when that method changes, this
file must follow. Not the same as the phone: no scheduler, the instructions
always a system message, llama.cpp on a CPU instead of LiteRT-LM on a GPU, so
its speed says nothing about a phone's. `--reasoning off` matters: the app
generates with thinking off, and without it the server spends the answer's
tokens thinking. In an 8 GB session the server and the full `flutter test`
do not fit together (the server is killed, the run ends with "Connection
closed"): one at a time.

## Gemini's way, against the API

```bash
EVAL_GEMINI_KEY=... EVAL_SOURCE=book.epub EVAL_TRANSLATED=book.ko.epub \
EVAL_STARTS=400,890,1400 EVAL_OUT=out.json \
/opt/flutter/bin/flutter test --no-pub tool/translation_eval/gemini_pipeline_test.dart
```

The app's own `GlossaryService` (the book read whole) and `CloudTranslator`,
with the traffic counted: requests and tokens by kind, what was sent back and
why, and the first answers beside the final ones (a paragraph sent back is
shown as it stood before). `EVAL_TRANSLATED` adds the same paragraphs of an
earlier translation as a third column.

| Variable | |
|---|---|
| `EVAL_GEMINI_MODEL` | `gemini-3.5-flash` when left out; any id the API has |
| `EVAL_COUNT` | paragraphs in a stretch (80, one request); 0 makes the glossary only |
| `EVAL_GLOSSARY` | `make` (default: the book is read, one request for each 30,000 characters), `book`, or a glossary's JSON (no reading: the cheap way to try a change again) |
| `EVAL_SERIES` | glossaries of the series' other volumes, standing in for the library |
| `EVAL_THINKING` | `speed` (default), `balanced` or `quality`: thinking tokens are billed as output |
| `EVAL_STYLE=0` | no tense or 그녀 check |
| `EVAL_POLISH=1` | the reader's "smooth out stiff sentences" on |

It spends the key's quota, and the free tier's is small: 20 requests a day for
`gemini-3.5-flash` - a glossary and five stretches. When the day's quota runs
out the app stops asking and the rest comes back empty; the log says "Gemini
quota used up for today". The key is read from the environment only; `EVAL_OUT`
holds the book's text and stays out of the repository.

Count what a check changed before trusting what it counts: the first tense
check lowered "동작 현재형 비율" by turning the book's own present (a habit, a
feeling) into the past. The table cannot tell a slip from the author's tense;
the sentences in `EVAL_OUT`'s `sentBack` can.

## Which reads better

```bash
EVAL_GEMINI_KEY=... python3 tool/translation_eval/judge.py \
    --model gemini-3.8-flash old=old.json new=new.json
```

Each file is an `EVAL_OUT` of the two tests above. For every paragraph the
files share, a stronger model sees the Japanese and the translations under
numbers, shuffled per paragraph, and names the best, the worst and any with a
mistranslation; one request for forty paragraphs. It is the only check here
that reads the prose - and it is a model of the translators' own family, so
what it prefers is a pointer for a person to read, not a verdict. Its noise is
large: two runs of the same model and prompt were judged 64 : 47. Read a gap
smaller than that as none.

## What these cannot tell

- Whether a rewritten paragraph reads better: they count patterns, a reader
  judges prose.
- The detectors' own misses: the ending classes agree with Kiwi (a
  morphological analyser) on 98.4–99.7% of narration sentences of three books;
  a sample of flagged slips read by hand was right about two times in three.
