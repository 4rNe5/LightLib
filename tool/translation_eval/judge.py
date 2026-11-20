#!/usr/bin/env python3
"""Which translation reads better: a blind comparison by a stronger model.

The other checks of this folder count patterns; this one asks an engine to
read. For every paragraph the given translations share, it shows the
Japanese and each translation under a number, in an order shuffled per
paragraph, and asks which is best, which is worst and which has a real
mistranslation. It answers "is B better than A", not "is B good": a judge
of the same family as the translators has their blind spots, so its word
is a pointer for a reader to check, not a verdict.

    EVAL_GEMINI_KEY=... python3 tool/translation_eval/judge.py \
        [--model gemini-3.8-flash] [--chunk 40] [--seed 7] [--out result.json] \
        old=old.json new=new.json [third=third.json]

Each file is an EVAL_OUT of gemini_pipeline_test.dart or
device_pipeline_test.dart ("sources" and "final"; name=file.json:first
takes its first answers; a+b.json reads two files as one). One request
for each --chunk paragraphs. A --model that starts with "claude" is asked
through the Claude API with EVAL_CLAUDE_KEY ([EVAL_CLAUDE_WORKSPACE],
[--effort medium]): when the translators are of two families, a judge
from each says more than one. The key is read from the environment only;
--out holds the book's text and stays out of the repository.
"""
import argparse
import collections
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.request

SYSTEM = """You are a senior editor at a Korean publisher of Japanese light novels.
Each item is one paragraph of a novel: the Japanese, and several Korean translations of it under numbers, in a random order. The items are consecutive paragraphs, so the ones before an item are its context.
Judge the translations of each item by, in this order:
1. Accuracy: nothing mistranslated, added or left out; who does what to whom; the tense of the Japanese sentence and each speaker's speech level kept.
2. How it reads as published Korean prose: natural word order and endings, pronouns Korean would leave out left out, nothing that reads word for word.
3. Names written the way the other paragraphs write them.
Answer with JSON only: {"items": [{"n": 1, "best": 2, "worst": 1, "errors": [1]}, ...]} with one entry for every item.
- best: the number of the best translation; 0 when none is clearly better than the others.
- worst: the number of the worst; 0 when none is clearly worse.
- errors: the numbers of the translations with a real mistranslation or an omission; [] when there is none.
Small differences in wording that a reader would not notice are not a reason to pick one: answer 0."""


ANSWER = {
    'type': 'object',
    'additionalProperties': False,
    'required': ['items'],
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'additionalProperties': False,
        'required': ['n', 'best', 'worst', 'errors'],
        'properties': {
            'n': {'type': 'integer'},
            'best': {'type': 'integer'},
            'worst': {'type': 'integer'},
            'errors': {'type': 'array', 'items': {'type': 'integer'}},
        }}}},
}


def ask_claude(model, key, user, effort):
    """One request to the Claude API; usage under Gemini's names."""
    body = {
        'model': model,
        'max_tokens': 32000,
        'system': SYSTEM,
        'messages': [{'role': 'user', 'content': user}],
        'output_config': {
            'effort': effort,
            'format': {'type': 'json_schema', 'schema': ANSWER},
        },
    }
    headers = {'Content-Type': 'application/json', 'x-api-key': key,
               'anthropic-version': '2023-06-01'}
    workspace = os.environ.get('EVAL_CLAUDE_WORKSPACE')
    if workspace:
        headers['anthropic-workspace-id'] = workspace
    request = urllib.request.Request(
        'https://api.anthropic.com/v1/messages',
        data=json.dumps(body).encode(), headers=headers)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                data = json.load(response)
            text = ''.join(b.get('text', '') for b in data.get('content', [])
                           if b.get('type') == 'text')
            used = data.get('usage', {})
            thought = (used.get('output_tokens_details') or {}).get(
                'thinking_tokens', 0)
            return text, {
                'promptTokenCount': used.get('input_tokens', 0)
                + used.get('cache_read_input_tokens', 0)
                + used.get('cache_creation_input_tokens', 0),
                'candidatesTokenCount': used.get('output_tokens', 0) - thought,
                'thoughtsTokenCount': thought,
            }
        except urllib.error.HTTPError as e:
            detail = e.read().decode('utf-8', 'replace')
            if e.code in (429, 500, 529) and attempt < 3:
                time.sleep(20 * (attempt + 1))
                continue
            sys.exit(f'{model}: HTTP {e.code} {detail[:300]}')
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            if attempt == 3:
                sys.exit(f'{model}: {e}')
            time.sleep(20 * (attempt + 1))
    sys.exit('no answer')


def ask(model, key, user):
    body = {
        'systemInstruction': {'parts': [{'text': SYSTEM}]},
        'contents': [{'role': 'user', 'parts': [{'text': user}]}],
        'generationConfig': {
            'temperature': 0,
            'maxOutputTokens': 16384,
            'responseMimeType': 'application/json',
        },
    }
    request = urllib.request.Request(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        f'{model}:generateContent',
        data=json.dumps(body).encode(),
        headers={'Content-Type': 'application/json', 'x-goog-api-key': key})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                data = json.load(response)
            parts = data['candidates'][0]['content']['parts']
            return ''.join(p.get('text', '') for p in parts), data.get('usageMetadata', {})
        except urllib.error.HTTPError as e:
            detail = e.read().decode('utf-8', 'replace')
            if e.code == 429 and 'PerDay' in detail:
                sys.exit(f'the day\'s quota for {model} is used up')
            if e.code in (429, 500, 503) and attempt < 3:
                time.sleep(20 * (attempt + 1))
                continue
            sys.exit(f'{model}: HTTP {e.code} {detail[:300]}')
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            # A connection dropped on the way: asked again.
            if attempt == 3:
                sys.exit(f'{model}: {e}')
            time.sleep(20 * (attempt + 1))
    sys.exit('no answer')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('sets', nargs='+', help='name=file.json[:first|final]')
    parser.add_argument('--model', default='gemini-3.8-flash')
    parser.add_argument('--chunk', type=int, default=40)
    parser.add_argument('--seed', type=int, default=7)
    parser.add_argument('--effort', default='medium',
                        help='how much a Claude judge thinks')
    parser.add_argument('--out')
    args = parser.parse_args()
    claude = args.model.startswith('claude')
    variable = 'EVAL_CLAUDE_KEY' if claude else 'EVAL_GEMINI_KEY'
    key = os.environ.get(variable)
    if not key:
        sys.exit(f'{variable} is not set')

    names, by_source, order = [], {}, None
    for spec in args.sets:
        name, _, path = spec.partition('=')
        path, _, field = path.partition(':')
        sources, translations = [], []
        for part in path.split('+'):
            data = json.load(open(part, encoding='utf-8'))
            sources += data['sources']
            translations += data[field or 'final']
        names.append(name)
        by_source[name] = {
            re.sub(r'\s', '', s): t
            for s, t in zip(sources, translations) if t}
        if order is None:
            order = sources
    shared = [s for s in order
              if all(re.sub(r'\s', '', s) in by_source[n] for n in names)]
    rng = random.Random(args.seed)
    items = []
    for s in shared:
        texts = [by_source[n][re.sub(r'\s', '', s)] for n in names]
        shuffled = list(range(len(names)))
        rng.shuffle(shuffled)
        items.append({'source': s, 'texts': texts, 'order': shuffled,
                      'same': len(set(texts)) == 1})

    best = collections.Counter()
    worst = collections.Counter()
    errors = collections.Counter()
    judged = undecided = 0
    usage = collections.Counter()
    verdicts = []
    for start in range(0, len(items), args.chunk):
        chunk = items[start:start + args.chunk]
        user = json.dumps({'items': [
            {'n': k + 1, 'source': it['source'],
             'translations': {str(p + 1): it['texts'][i]
                              for p, i in enumerate(it['order'])}}
            for k, it in enumerate(chunk)]}, ensure_ascii=False)
        text, used = (ask_claude(args.model, key, user, args.effort) if claude
                      else ask(args.model, key, user))
        for k in ('promptTokenCount', 'candidatesTokenCount', 'thoughtsTokenCount'):
            usage[k] += used.get(k, 0)
        usage['requests'] += 1
        try:
            answer = {int(v['n']): v for v in json.loads(text)['items']}
        except Exception as e:  # pylint: disable=broad-except
            print(f'paragraphs {start}-{start + len(chunk)}: unreadable answer ({e})',
                  file=sys.stderr)
            continue
        for k, it in enumerate(chunk):
            v = answer.get(k + 1)
            if v is None or it['same']:
                continue
            judged += 1

            def who(number):
                number = int(number or 0)
                return names[it['order'][number - 1]] if 1 <= number <= len(names) else None
            b, w = who(v.get('best')), who(v.get('worst'))
            if b is None:
                undecided += 1
            else:
                best[b] += 1
            if w is not None:
                worst[w] += 1
            flagged = [who(x) for x in (v.get('errors') or [])]
            for name in flagged:
                if name:
                    errors[name] += 1
            verdicts.append({'source': it['source'], 'best': b, 'worst': w,
                             'errors': [f for f in flagged if f],
                             'translations': dict(zip(names, it['texts']))})
        print(f'{min(start + args.chunk, len(items))}/{len(items)}', file=sys.stderr)

    same = sum(1 for it in items if it['same'])
    print(f'\n심사 모델 {args.model}, 공통 문단 {len(items)}개 '
          f'(번역이 모두 같은 {same}개 제외, 심사 {judged}개, '
          f'우열 없음 {undecided}개), 요청 {usage["requests"]}회, '
          f'입력 {usage["promptTokenCount"]} / 출력 '
          f'{usage["candidatesTokenCount"] + usage["thoughtsTokenCount"]} 토큰\n')
    print('| 번역 | 가장 나음 | 가장 못함 | 오역·누락 지적 |')
    print('|---|---|---|---|')

    def share(n):
        return f'{n} ({100 * n / max(judged, 1):.1f}%)'
    for name in names:
        print(f'| {name} | {share(best[name])} | {share(worst[name])} | '
              f'{share(errors[name])} |')
    # Two by two, read off the same answers: one is ahead of another in
    # a paragraph where it was the best and the other was not, or the
    # other was the worst and it was not.
    if len(names) > 2:
        print('\n| 둘씩 (앞 : 뒤) | 앞이 나음 | 뒤가 나음 |')
        print('|---|---|---|')

        def rank(v, name):
            return (v['best'] == name) - (v['worst'] == name)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                ahead = sum(1 for v in verdicts if rank(v, a) > rank(v, b))
                behind = sum(1 for v in verdicts if rank(v, a) < rank(v, b))
                print(f'| {a} : {b} | {ahead} | {behind} |')
    if args.out:
        json.dump({'model': args.model, 'names': names, 'judged': judged,
                   'undecided': undecided, 'best': best, 'worst': worst,
                   'errors': errors, 'verdicts': verdicts},
                  open(args.out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
