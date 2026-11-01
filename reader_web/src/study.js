// Study helpers for Japanese books: kuromoji (IPADIC) for words, their
// dictionary forms and readings; furigana over kanji; the word under a
// tap; the sentence around a word; a book's spread of JLPT levels.
//
// kuromoji's dictionary is not bundled: the app downloads it once and
// serves it at /reader/dict/ (lib/services/study/japanese_tools.dart).

import kuromoji from 'kuromoji'
import { textOf } from './paragraphs.js'

const KANJI = /[㐀-䶿一-鿿豈-﫿々〆ヶ]/
const JAPANESE = /[぀-ヿ㐀-䶿一-鿿豈-﫿々〆ー]/
const KANA_ONLY = /^[぀-ヿー]+$/

// ---------------------------------------------------------------------------
// Tokenizer and JLPT levels
// ---------------------------------------------------------------------------

let tokenizer = null
let loading = null
const jlpt = new Map()
const jlptByReading = new Map()

export const toolsReady = () => !!tokenizer

/** A tokenizer built elsewhere (tests build one in Node). */
export const useTokenizer = t => { tokenizer = t }

/** Loads the tokenizer (once) and the JLPT list. */
export function loadTools(base) {
    if (tokenizer) return Promise.resolve(true)
    loading ??= Promise.all([
        new Promise((resolve, reject) =>
            kuromoji.builder({ dicPath: `${base}/dict/` }).build((err, t) => (err ? reject(err) : resolve(t)))),
        fetch(`${base}/study/jlpt.tsv`).then(r => (r.ok ? r.text() : '')).catch(() => ''),
    ]).then(([t, list]) => {
        readJlpt(list)
        tokenizer = t
        return true
    }).catch(e => {
        loading = null
        throw e
    })
    return loading
}

/** The JLPT list (word, reading, level per line); a word on several
 *  levels counts at the easiest. */
export function readJlpt(list) {
    for (const line of list.split('\n')) {
        const [word, reading, level] = line.split('\t')
        if (!word || !level) continue
        const l = Number(level)
        if (!(jlpt.get(word) >= l)) jlpt.set(word, l)
        if (reading && !(jlptByReading.get(reading) >= l)) jlptByReading.set(reading, l)
    }
}

export const hiragana = s => (s ?? '').replace(/[ァ-ヶ]/g, c => String.fromCharCode(c.charCodeAt(0) - 0x60))

export const tokenize = text => (tokenizer ? tokenizer.tokenize(text) : [])

/** The dictionary form of a token, and how it reads. */
export function baseOf(token) {
    const surface = token.surface_form
    const base = token.basic_form && token.basic_form !== '*' ? token.basic_form : surface
    const reading = token.reading && token.reading !== '*' ? hiragana(token.reading) : ''
    if (!reading) return { base, reading: KANA_ONLY.test(base) ? hiragana(base) : '' }
    if (base === surface) return { base, reading }
    let k = 0
    while (k < surface.length && k < base.length && surface[k] === base[k]) k++
    const tail = hiragana(surface.slice(k))
    if (!reading.endsWith(tail)) return { base, reading: '' }
    return { base, reading: reading.slice(0, reading.length - tail.length) + hiragana(base.slice(k)) }
}

/** 5 (N5, easiest) .. 1 (N1); 0 when the word is on no list. */
export function levelOf(base, reading) {
    const l = jlpt.get(base)
    if (l) return l
    if (KANA_ONLY.test(base)) return jlptByReading.get(hiragana(base)) ?? 0
    return 0
}

/** Words worth learning: not particles, symbols, numbers or names. */
export function isContentWord(token) {
    const pos = token.pos
    const d1 = token.pos_detail_1
    if (!['名詞', '動詞', '形容詞', '副詞', '連体詞', '感動詞', '接続詞'].includes(pos)) return false
    if (['数', '固有名詞', '非自立', '代名詞', '接尾', '特殊'].includes(d1)) return false
    if (pos === '動詞' && d1 === '接尾') return false
    return JAPANESE.test(token.surface_form)
}

// ---------------------------------------------------------------------------
// Furigana
// ---------------------------------------------------------------------------

const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** [text, reading | null] parts of a word: readings over its kanji only
 *  (食べる -> [食, た], [べる, null]). */
export function rubyParts(surface, reading) {
    if (!reading || !KANJI.test(surface)) return [[surface, null]]
    const runs = surface.match(/[㐀-䶿一-鿿豈-﫿々〆ヶ]+|[^㐀-䶿一-鿿豈-﫿々〆ヶ]+/g)
    if (runs.length === 1) return [[surface, reading]]
    const pattern = runs.map(r => (KANJI.test(r[0]) ? '(.+?)' : escapeRe(hiragana(r)))).join('')
    const m = new RegExp(`^${pattern}$`).exec(reading)
    if (!m) return [[surface, reading]]
    let g = 1
    return runs.map(r => (KANJI.test(r[0]) ? [r, m[g++]] : [r, null]))
}

const RUBY_SKIP = 'ruby, rt, rp, .ll-bi, script, style'

/** Puts readings over the kanji words of a paragraph that [keep] picks. */
export function addFurigana(el, keep) {
    if (!tokenizer) return
    const doc = el.ownerDocument
    const nodes = []
    const walker = doc.createTreeWalker(el, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (KANJI.test(n.data) && !n.parentElement?.closest(RUBY_SKIP)) nodes.push(n)
    }
    for (const node of nodes) {
        const tokens = tokenizer.tokenize(node.data)
        if (!tokens.some(t => KANJI.test(t.surface_form))) continue
        const frag = doc.createDocumentFragment()
        let text = ''
        const flush = () => { if (text) { frag.append(doc.createTextNode(text)); text = '' } }
        for (const t of tokens) {
            const surface = t.surface_form
            const reading = t.reading && t.reading !== '*' ? hiragana(t.reading) : ''
            if (!KANJI.test(surface) || !reading || !keep(t)) { text += surface; continue }
            for (const [part, rt] of rubyParts(surface, reading)) {
                if (!rt) { text += part; continue }
                flush()
                const ruby = doc.createElement('ruby')
                ruby.className = 'll-furi'
                // Invisible to positions: a CFI saved with furigana on
                // resolves with it off, and the other way round.
                ruby.setAttribute('cfi-skip', '')
                const r = doc.createElement('rt')
                r.setAttribute('cfi-inert', '')
                r.textContent = rt
                ruby.append(part, r)
                frag.append(ruby)
            }
        }
        flush()
        node.replaceWith(frag)
    }
}

export function removeFurigana(el) {
    const rubies = el.querySelectorAll('ruby.ll-furi')
    if (!rubies.length) return
    for (const ruby of rubies) {
        ruby.querySelector('rt')?.remove()
        ruby.replaceWith(...ruby.childNodes)
    }
    el.normalize()
}

/** Whether a word gets furigana: 'all', or 'hard' - harder than the
 *  reader's level (and words on no list). */
export function furiganaFilter(mode, level) {
    if (mode === 'all') return () => true
    return token => {
        const { base, reading } = baseOf(token)
        const l = levelOf(base, reading)
        return l === 0 || l < level
    }
}

// ---------------------------------------------------------------------------
// Words and sentences in a paragraph
// ---------------------------------------------------------------------------

/** The length of the paragraph's text (as textOf reads it) before
 *  (node, offset). */
export function textOffset(el, node, offset) {
    const range = el.ownerDocument.createRange()
    range.setStart(el, 0)
    range.setEnd(node, offset)
    const box = el.ownerDocument.createElement('div')
    box.append(range.cloneContents())
    return textOf(box).length
}

/** A DOM range over the paragraph text [start, end), or null. */
export function rangeOf(el, start, end) {
    const doc = el.ownerDocument
    const at = target => {
        const walker = doc.createTreeWalker(el, NodeFilter.SHOW_TEXT)
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
            if (n.parentElement?.closest('rt, rp, .ll-bi')) continue
            if (textOffset(el, n, n.length) < target) continue
            let lo = 0, hi = n.length
            while (lo < hi) {
                const mid = (lo + hi) >> 1
                if (textOffset(el, n, mid) < target) lo = mid + 1
                else hi = mid
            }
            return [n, lo]
        }
        return null
    }
    const a = at(start)
    const b = at(end)
    if (!a || !b) return null
    const range = doc.createRange()
    range.setStart(...a)
    range.setEnd(...b)
    return range
}

const SENTENCE_END = /[。！？!?…‥]+[」』）)】〉》"']*|\n/g

/** The sentence of [text] around [index]. */
export function sentenceAt(text, index) {
    let start = 0
    let end = text.length
    SENTENCE_END.lastIndex = 0
    for (let m; (m = SENTENCE_END.exec(text));) {
        const stop = m.index + m[0].length
        if (stop <= index) start = stop
        else { end = stop; break }
    }
    const s = text.slice(start, end).trim()
    return s.length > 240 ? text.slice(Math.max(0, index - 120), index + 120).trim() : s
}

/** The word at [offset] of a paragraph's text: its token and where it starts. */
export function tokenAt(text, offset, tokens = tokenize(text)) {
    for (const t of tokens) {
        const start = t.word_position - 1
        if (offset >= start && offset < start + t.surface_form.length) return { token: t, start }
    }
    return null
}

/** What the app shows for a word. */
export function describeWord(token, text, start) {
    const { base, reading } = baseOf(token)
    return {
        surface: token.surface_form,
        base,
        reading,
        pos: token.pos,
        posDetail: token.pos_detail_1,
        level: levelOf(base, reading),
        sentence: sentenceAt(text, start),
        start,
    }
}

/** The character box under (x, y), as [node, offset], or null. */
export function charAt(doc, x, y) {
    const caret = doc.caretRangeFromPoint?.(x, y)
    const node = caret?.startContainer
    if (!node || node.nodeType !== 3) return null
    const r = doc.createRange()
    for (const o of [caret.startOffset, caret.startOffset - 1]) {
        if (o < 0 || o >= node.length) continue
        r.setStart(node, o)
        r.setEnd(node, o + 1)
        for (const box of r.getClientRects()) {
            if (x >= box.left - 1 && x <= box.right + 1 && y >= box.top - 1 && y <= box.bottom + 1) {
                return JAPANESE.test(node.data[o]) ? [node, o] : null
            }
        }
    }
    return null
}

export function highlight(doc, range) {
    const win = doc?.defaultView
    try {
        if (!win?.CSS?.highlights || !win.Highlight) return
        win.CSS.highlights.clear()
        if (range) win.CSS.highlights.set('ll-word', new win.Highlight(range))
    } catch { /* not supported */ }
}

// ---------------------------------------------------------------------------
// A book's difficulty
// ---------------------------------------------------------------------------

const LEVELS = [5, 4, 3, 2, 1, 0]

/** Counts a section's words by JLPT level into [acc]. */
export function countWords(texts, acc) {
    for (const text of texts) {
        for (const t of tokenize(text)) {
            if (!isContentWord(t)) continue
            const { base, reading } = baseOf(t)
            const level = levelOf(base, reading)
            acc.tokens++
            acc.byLevel[level].tokens++
            const key = `${base}\t${reading}`
            let w = acc.words.get(key)
            if (!w) {
                acc.words.set(key, w = { base, reading, level, count: 0, sentence: '' })
                acc.byLevel[level].unique++
            }
            if (!w.count) w.sentence = sentenceAt(text, t.word_position - 1)
            w.count++
        }
    }
}

export const newCount = () => ({
    tokens: 0,
    byLevel: Object.fromEntries(LEVELS.map(l => [l, { tokens: 0, unique: 0 }])),
    words: new Map(),
})

/** The counts as sent to the app: totals, and each level's most frequent
 *  words (the 80 of each). */
export function summary(acc) {
    const top = []
    for (const level of LEVELS) {
        const words = [...acc.words.values()].filter(w => w.level === level)
        words.sort((a, b) => b.count - a.count)
        top.push(...words.slice(0, 80))
    }
    return { tokens: acc.tokens, unique: acc.words.size, byLevel: acc.byLevel, words: top }
}
