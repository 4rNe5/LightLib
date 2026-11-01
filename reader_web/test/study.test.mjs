// The study helpers' text logic (reader_web/src/study.js) with the real
// kuromoji dictionary: `npm test` (Node 18+). The page-side parts
// (furigana in the DOM, taps, positions) were checked in Chromium.
import { test, before } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import kuromoji from 'kuromoji'
import {
    rubyParts, baseOf, sentenceAt, tokenAt, describeWord, levelOf, readJlpt, hiragana,
    isContentWord, countWords, newCount, summary, furiganaFilter, useTokenizer,
} from '../src/study.js'

let tokenizer
before(async () => {
    tokenizer = await new Promise((resolve, reject) =>
        kuromoji.builder({ dicPath: new URL('../node_modules/kuromoji/dict/', import.meta.url).pathname })
            .build((e, t) => (e ? reject(e) : resolve(t))))
    useTokenizer(tokenizer)
    readJlpt(readFileSync(new URL('../../assets/study/jlpt.tsv', import.meta.url), 'utf8'))
})

const token = text => tokenizer.tokenize(text)

test('readings go over the kanji only', () => {
    assert.deepEqual(rubyParts('食べる', 'たべる'), [['食', 'た'], ['べる', null]])
    assert.deepEqual(rubyParts('言い残し', 'いいのこし'), [['言', 'い'], ['い', null], ['残', 'のこ'], ['し', null]])
    assert.deepEqual(rubyParts('消しゴム', 'けしごむ'), [['消', 'け'], ['しゴム', null]])
    assert.deepEqual(rubyParts('大人', 'おとな'), [['大人', 'おとな']])
    assert.deepEqual(rubyParts('ゲーム', 'げーむ'), [['ゲーム', null]])
    // A reading that does not line up goes over the whole word.
    assert.deepEqual(rubyParts('お母さん', 'かあさん'), [['お母さん', 'かあさん']])
})

test('dictionary forms and their readings', () => {
    const [eat] = token('食べた')
    assert.deepEqual(baseOf(eat), { base: '食べる', reading: 'たべる' })
    const [went] = token('行った')
    assert.deepEqual(baseOf(went), { base: '行く', reading: 'いく' })
    assert.equal(hiragana('タベル'), 'たべる')
})

test('JLPT levels, kana words by reading', () => {
    assert.equal(levelOf('食べる', 'たべる'), 5)
    assert.equal(levelOf('監視', 'かんし'), 1)
    assert.equal(levelOf('たべる', 'たべる'), 5)
    assert.equal(levelOf('幽鬼', 'ゆうき'), 0)
    const hard = furiganaFilter('hard', 4)
    const [watch] = token('監視')
    const [eat] = token('食べる')
    assert.equal(hard(watch), true)
    assert.equal(hard(eat), false)
})

test('the sentence around a word, and the word at an offset', () => {
    const text = '「行くぞ」と彼は言った。扉が開いた！　静かだった'
    assert.equal(sentenceAt(text, 1), '「行くぞ」と彼は言った。')
    assert.equal(sentenceAt(text, 13), '扉が開いた！')
    assert.equal(sentenceAt(text, text.length - 1), '静かだった')
    const found = tokenAt('とぶっきらぼうに言い残していった。', 9)
    assert.equal(found.token.surface_form, '言い残し')
    assert.equal(found.start, 8)
    const w = describeWord(found.token, 'とぶっきらぼうに言い残していった。', found.start)
    assert.equal(w.base, '言い残す')
    assert.equal(w.reading, 'いいのこす')
    assert.equal(w.sentence, 'とぶっきらぼうに言い残していった。')
})

test('counting a text: content words only, by level', () => {
    const acc = newCount()
    countWords(['彼は扉を開けて、パンを食べた。', 'パンを食べた。'], acc)
    const s = summary(acc)
    const words = Object.fromEntries(s.words.map(w => [w.base, w]))
    assert.equal(words['食べる'].count, 2)
    assert.equal(words['食べる'].level, 5)
    assert.equal(words['扉'].count, 1)
    assert.equal(words['扉'].sentence, '彼は扉を開けて、パンを食べた。')
    assert.equal(words['は'], undefined) // particles are not words to learn
    assert.equal(words['彼'], undefined) // nor pronouns
    assert.ok(s.byLevel[5].tokens >= 2)
    assert.equal(s.tokens, Object.values(s.byLevel).reduce((a, b) => a + b.tokens, 0))
    assert.equal(isContentWord(token('。')[0]), false)
})
