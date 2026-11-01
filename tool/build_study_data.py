#!/usr/bin/env python3
"""Builds the reader's study data in assets/study/ (run again to refresh).

  jlpt.tsv      word, reading, level (5 = N5 ... 1 = N1), one per line:
                open-anki-jlpt-decks (MIT, Jamie Sinclair), src/n1-n5.csv,
                https://github.com/jamsinclair/open-anki-jlpt-decks
  hanja_ko.tsv  kanji, Korean readings (hangul, '·' between):
                KANJIDIC2 (CC BY-SA 4.0, EDRDG), korean_h readings,
                http://www.edrdg.org/kanjidic/kanjidic2.xml.gz

usage: build_study_data.py <open-anki-jlpt-decks/src> <kanjidic2.xml.gz>
"""

import csv
import gzip
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'study'


def norm(t):
    t = re.sub(r'^\(.*?\)\s*', '', t.strip())
    t = re.sub(r'\s*\(する\)$', '', t)
    return t.replace('～', '').replace('〜', '').strip()


def jlpt(src):
    best = {}
    for level in (5, 4, 3, 2, 1):
        with open(Path(src) / f'n{level}.csv', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                words = [norm(w) for w in re.split(r'[;、,／/]', row['expression'])]
                reads = [norm(r) for r in re.split(r'[;、,／/]', row['reading'])]
                for i, w in enumerate(words):
                    if not w:
                        continue
                    r = reads[i] if i < len(reads) else reads[0]
                    if r.endswith('する') and not w.endswith('する') and r != w:
                        r = r[:-2]
                    key = (w, r)
                    # A word listed at several levels counts at the easiest.
                    if key not in best or best[key] < level:
                        best[key] = level
    lines = sorted(f'{w}\t{r}\t{l}' for (w, r), l in best.items())
    return lines


def hanja(path):
    root = ET.fromstring(gzip.open(path).read())
    lines = []
    for c in root.iter('character'):
        lit = c.findtext('literal')
        ko = [r.text for r in c.iter('reading') if r.get('r_type') == 'korean_h']
        if lit and ko:
            lines.append(f'{lit}\t{"·".join(dict.fromkeys(ko))}')
    return sorted(lines)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    OUT.mkdir(parents=True, exist_ok=True)
    j = jlpt(sys.argv[1])
    h = hanja(sys.argv[2])
    (OUT / 'jlpt.tsv').write_text('\n'.join(j) + '\n', encoding='utf-8')
    (OUT / 'hanja_ko.tsv').write_text('\n'.join(h) + '\n', encoding='utf-8')
    print(f'jlpt.tsv {len(j)} words, hanja_ko.tsv {len(h)} kanji')


if __name__ == '__main__':
    main()
