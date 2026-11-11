// LightLib's reader page. foliate-js (readest's fork) lays the book out -
// reflowable EPUBs in pages or one scroll, vertical Japanese with ruby,
// fixed-layout and SVG pages, the book's own CSS - and this file connects
// it to the Flutter app over flutter_inappwebview's JavaScript handlers
// (the web app: postMessage to the page around this one's iframe):
//
//   app -> page: window.reader.open(), .next(), .goTo(), .setSettings(),
//                .setTranslations(), .showOriginal(), .setStudy(),
//                .loadStudyTools(), .analyze() ...
//   page -> app: {type: 'book' | 'relocate' | 'paragraphs' | 'visible' |
//                 'tap' | 'word' | 'selection' | 'studyTools' |
//                 'analysis' | 'error' | 'log', ...}
//
// The CSS overrides follow readest's (apps/readest-app/src/utils/style.ts,
// AGPL-3.0, like this app).

import 'construct-style-sheets-polyfill'
import { makeBook } from '../foliate-js/view.js'
import { readerStyles } from './styles.js'
import { collectParagraphs, applyTranslation, restoreOriginal, applyBilingual, removeBilingual } from './paragraphs.js'
import {
    loadTools, toolsReady, addFurigana, removeFurigana, furiganaFilter, tokenize, tokenAt,
    describeWord, charAt, textOffset, rangeOf, highlight, sentenceAt, baseOf, levelOf,
    countWords, newCount, summary,
} from './study.js'

// ---------------------------------------------------------------------------
// Messages to the app
// ---------------------------------------------------------------------------

let bridgeReady = false
const pending = []
// The web app shows this page in an iframe of its own origin and listens
// for messages on its window; the phone app injects flutter_inappwebview.
const embedded = window.parent !== window
const deliver = msg => {
    try {
        if (window.flutter_inappwebview?.callHandler) window.flutter_inappwebview.callHandler('reader', msg)
        else if (embedded) window.parent.postMessage({ lightlibReader: msg }, location.origin)
    } catch (e) {
        console.log('[reader] message lost', e)
    }
}
const post = msg => (bridgeReady ? deliver(msg) : pending.push(msg))
const onBridge = () => {
    if (bridgeReady) return
    bridgeReady = true
    pending.splice(0).forEach(deliver)
}
window.addEventListener('flutterInAppWebViewPlatformReady', onBridge)
if (window.flutter_inappwebview?.callHandler || embedded) onBridge()

window.addEventListener('error', e => post({ type: 'log', level: 'error', message: String(e.message) }))
window.addEventListener('unhandledrejection', e =>
    post({ type: 'log', level: 'error', message: String(e.reason?.stack ?? e.reason) }))

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const state = {
    view: null,
    book: null,
    settings: null,
    file: null,
    // section index -> [{ el, text }] of the loaded document
    sections: new Map(),
    // section index -> Map(paragraph number -> translation)
    translations: new Map(),
    showTranslations: false,
    translationLang: null,
    lastRelocate: null,
    // Study: how translations show ('replace' | 'below' | 'hidden'),
    // furigana ('off' | 'hard' | 'all'), the reader's JLPT level (5..1),
    // whether a tap on a word looks it up.
    study: { layout: 'replace', furigana: 'off', level: 3, wordTap: false },
    japanese: false,
}

const flattenToc = (items, depth = 0, out = []) => {
    for (const item of items ?? []) {
        out.push({ label: (item.label ?? '').trim(), href: item.href ?? '', depth })
        if (item.subitems?.length) flattenToc(item.subitems, depth + 1, out)
    }
    return out
}

const isCJK = lang => /^(ja|zh|ko)\b/i.test(lang ?? '')

/** The writing mode the page uses: the book's own unless the app forces one. */
const writingFor = settings => settings?.writing ?? 'auto'

// ---------------------------------------------------------------------------
// Opening a book
// ---------------------------------------------------------------------------

async function loadFile(url, name) {
    const res = await fetch(url)
    if (!res.ok) throw new Error(`book not readable (${res.status})`)
    const blob = await res.blob()
    return new File([blob], name || 'book.epub', { type: blob.type || 'application/epub+zip' })
}

async function createView({ book, settings, location }) {
    const root = document.getElementById('reader')
    root.replaceChildren()
    state.sections.clear()

    // A vertical (right-to-left) book shown horizontally reads left to
    // right; readest does the same (getBookDirFromWritingMode).
    if (book.__originalDir === undefined) book.__originalDir = book.dir
    const writing = writingFor(settings)
    book.dir = writing === 'horizontal' && book.__originalDir === 'rtl' && isCJK(book.metadata?.language)
        ? 'ltr'
        : writing === 'vertical' ? 'rtl' : book.__originalDir

    const view = document.createElement('foliate-view')
    root.append(view)
    view.addEventListener('load', e => onDocLoad(e.detail))
    view.addEventListener('relocate', e => onRelocate(e.detail))
    view.addEventListener('external-link', e => {
        e.preventDefault()
        post({ type: 'externalLink', href: e.detail.href })
    })
    await view.open(book)
    state.view = view
    applySettings(settings, { initial: true })

    try {
        if (location?.cfi) await view.init({ lastLocation: location.cfi })
        else if (location?.fraction > 0) await view.goToFraction(location.fraction)
        else await view.init({ lastLocation: null })
    } catch (e) {
        post({ type: 'log', level: 'warn', message: `saved position not found: ${e}` })
        await view.goToFraction(0)
    }
    return view
}

async function open(options) {
    try {
        state.settings = options.settings ?? {}
        state.file = await loadFile(options.url, options.name)
        const book = await makeBook(state.file)
        state.book = book
        const lang = Array.isArray(book.metadata?.language) ? book.metadata.language[0] : book.metadata?.language
        state.japanese = /^ja\b/i.test(lang ?? '')
        const view = await createView({ book, settings: state.settings, location: options })
        post({
            type: 'book',
            title: book.metadata?.title ?? '',
            language: Array.isArray(book.metadata?.language)
                ? book.metadata.language[0] ?? ''
                : book.metadata?.language ?? '',
            dir: book.__originalDir ?? '',
            fixedLayout: !!view.isFixedLayout,
            sections: book.sections.length,
            toc: flattenToc(book.toc),
        })
    } catch (e) {
        post({ type: 'error', message: String(e?.message ?? e) })
    }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

function applySettings(settings, { initial = false } = {}) {
    const previous = state.settings
    state.settings = settings
    const view = state.view
    if (!view) return
    const r = view.renderer
    const fixed = view.isFixedLayout

    // A different writing mode or page direction needs the book laid out
    // again from the start: reopen it where the reader is.
    if (!initial && previous && (writingFor(previous) !== writingFor(settings))) {
        const cfi = state.lastRelocate?.cfi
        view.close()
        return createView({ book: state.book, settings, location: { cfi } })
    }

    document.documentElement.style.setProperty('--ll-bg', settings.background ?? '#fff')
    document.body.style.background = settings.background ?? '#fff'
    if (!fixed) {
        r.setStyles?.(readerStyles(settings))
        r.setAttribute('flow', settings.flow === 'scrolled' ? 'scrolled' : 'paginated')
        const side = Math.max(0, Math.round(settings.margin ?? 24))
        r.setAttribute('margin-left', `${side}px`)
        r.setAttribute('margin-right', `${side}px`)
        r.setAttribute('margin-top', `${settings.marginTop ?? 20}px`)
        r.setAttribute('margin-bottom', `${settings.marginBottom ?? 28}px`)
        r.setAttribute('gap', '0%')
        r.setAttribute('column-gap', `${side * 2}px`)
        r.setAttribute('max-inline-size', `${settings.maxInlineSize ?? 1080}px`)
        r.setAttribute('max-column-count', String(settings.maxColumns ?? 2))
    }
    if (settings.animated !== false) r.setAttribute('animated', '')
    else r.removeAttribute('animated')
    for (const { doc } of r.getContents?.() ?? []) if (doc) themeDocument(doc, settings)
}

/** Marks the document for the theme's CSS (dark pages, image tone). */
function themeDocument(doc, settings) {
    doc.documentElement.classList.toggle('ll-dark', !!settings.dark)
}

// ---------------------------------------------------------------------------
// Documents as they load
// ---------------------------------------------------------------------------

/** Japanese publishers' books (電書協 guide) switch their layout rules
 *  with .vrtl / .hltr classes: a forced direction swaps them, so the
 *  book's own indents and margins for that direction apply. */
function swapWritingClasses(doc, writing) {
    const [from, to] = writing === 'horizontal' ? ['vrtl', 'hltr']
        : writing === 'vertical' ? ['hltr', 'vrtl'] : [null, null]
    if (!from) return
    for (const el of [doc.documentElement, ...doc.querySelectorAll(`.${from}`)]) {
        if (el.classList.contains(from)) {
            el.classList.remove(from)
            el.classList.add(to)
        }
    }
}

function onDocLoad({ doc, index }) {
    swapWritingClasses(doc, writingFor(state.settings))
    themeDocument(doc, state.settings ?? {})
    fixImages(doc)
    listenForTaps(doc)
    listenForKeys(doc)
    listenForSelection(doc, index)
    const items = collectParagraphs(doc)
    state.sections.set(index, items)
    post({ type: 'paragraphs', section: index, texts: items.map(p => p.text) })
    if (state.showTranslations) paintTranslations(index)
    syncFurigana(index)
}

/** Images that sit inside a line of text, and image-led paragraphs, as
 *  readest marks them (applyImageStyle). */
function fixImages(doc) {
    for (const img of doc.querySelectorAll('img')) {
        const paragraph = img.closest('p')
        if (paragraph) {
            const before = doc.createRange()
            before.setStart(paragraph, 0)
            before.setEndBefore(img)
            if (!before.toString().trim()) paragraph.classList.add('leading-image')
        }
        const parent = img.parentNode
        if (parent?.nodeType === 1) {
            const nodes = Array.from(parent.childNodes)
            const text = nodes.some(n => n.nodeType === 3 && n.textContent.trim())
            const inline = nodes.every(n => n.nodeType !== 1 || n.tagName !== 'BR')
            if (text && inline) img.classList.add('has-text-siblings')
        }
    }
}

/** A keyboard and a mouse wheel (the web on a desktop): the arrows, Page
 *  Up/Down and Space turn pages, and so does the wheel where pages are
 *  turned rather than scrolled. The app handles the same keys when they
 *  reach it instead of this page. */
function turnByKey(e) {
    if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.altKey) return
    const target = e.target
    if (target?.isContentEditable || /^(input|textarea|select)$/i.test(target?.tagName ?? '')) return
    const view = state.view
    if (!view) return
    const scrolled = state.settings?.flow === 'scrolled'
    switch (e.key) {
        case 'ArrowLeft': view.goLeft(); break
        case 'ArrowRight': view.goRight(); break
        case 'PageDown': view.next(); break
        case 'PageUp': view.prev(); break
        case ' ': e.shiftKey ? view.prev() : view.next(); break
        // Scrolling text keeps the browser's own line-by-line arrows.
        case 'ArrowDown': if (scrolled) return; view.next(); break
        case 'ArrowUp': if (scrolled) return; view.prev(); break
        default: return
    }
    e.preventDefault()
    post({ type: 'turn' })
    if (pendingPaint.size) flushPaint()
}

let wheelLockedUntil = 0
function turnByWheel(e) {
    if (e.ctrlKey || state.settings?.flow === 'scrolled' || !state.view) return
    const delta = Math.abs(e.deltaY) >= Math.abs(e.deltaX) ? e.deltaY : e.deltaX
    e.preventDefault()
    if (Math.abs(delta) < 8) return
    const now = Date.now()
    if (now < wheelLockedUntil) return
    // A wheel's notch turns one page; a touchpad's glide (many small
    // steps) turns one too.
    wheelLockedUntil = now + (Math.abs(delta) >= 60 ? 260 : 620)
    post({ type: 'turn' })
    if (pendingPaint.size) flushPaint()
    delta > 0 ? state.view.next() : state.view.prev()
}

function listenForKeys(target) {
    if (target.__llKeys) return
    target.__llKeys = true
    target.addEventListener('keydown', turnByKey)
    target.addEventListener('wheel', turnByWheel, { passive: false })
}
listenForKeys(document)

/** Taps: the outer thirds turn pages, the middle shows or hides the app's
 *  bars. A tap that ends a selection or follows a link is not a turn. */
function listenForTaps(doc) {
    if (doc.__llTaps) return
    doc.__llTaps = true
    doc.addEventListener('click', e => {
        if (e.defaultPrevented) return
        if (e.target.closest?.('a[href]')) return
        const selection = doc.getSelection?.()
        if (selection && !selection.isCollapsed) return
        // A hidden translation shows on a tap (and hides on the next).
        const hidden = e.target.closest?.('.ll-bi-hidden')
        if (hidden) {
            hidden.classList.toggle('ll-bi-shown')
            post({ type: 'reveal' })
            return
        }
        const frame = doc.defaultView?.frameElement
        const rect = frame?.getBoundingClientRect?.() ?? { left: 0, top: 0 }
        const x = rect.left + e.clientX
        const width = window.innerWidth || 1
        const zone = x < width * 0.2 ? 'left' : x > width * 0.8 ? 'right' : 'center'
        if (state.study.wordTap && zone === 'center' && lookUpAt(doc, e.clientX, e.clientY)) return
        const turnZone = state.study.wordTap ? zone : (x < width * 0.28 ? 'left' : x > width * 0.72 ? 'right' : 'center')
        if (turnZone === 'center' || state.settings?.flow === 'scrolled') {
            post({ type: 'tap', zone: 'center' })
            return
        }
        post({ type: 'turn' })
        if (pendingPaint.size) flushPaint()
        turnZone === 'left' ? state.view?.goLeft() : state.view?.goRight()
    })
}

// ---------------------------------------------------------------------------
// Study
// ---------------------------------------------------------------------------

/** The section and paragraph holding [node]. */
function paragraphOf(node) {
    for (const [section, items] of state.sections) {
        for (let n = 0; n < items.length; n++) {
            if (items[n].el.contains(node)) return { section, n, item: items[n] }
        }
    }
    return null
}

let highlighted = null

/** Looks up the word under (x, y) of [doc]; false when there is none. */
function lookUpAt(doc, x, y) {
    if (!toolsReady() || !state.japanese) return false
    const hit = charAt(doc, x, y)
    if (!hit) return false
    const [node, offset] = hit
    if (node.parentElement?.closest('rt, rp, .ll-bi')) return false
    const where = paragraphOf(node)
    // A paragraph showing its translation in place has no Japanese words.
    if (!where || where.item.original != null) return false
    const { section, n, item } = where
    const at = textOffset(item.el, node, offset)
    item.tokens ??= tokenize(item.text)
    const found = tokenAt(item.text, at, item.tokens)
    if (!found || !/[^\s]/.test(found.token.surface_form)) return false
    const word = describeWord(found.token, item.text, found.start)
    highlighted = doc
    highlight(doc, rangeOf(item.el, found.start, found.start + found.token.surface_form.length))
    post({ type: 'word', section, n, ...word })
    return true
}

/** A selection held still for a moment: the app offers to look it up. */
function listenForSelection(doc, index) {
    if (doc.__llSelection) return
    doc.__llSelection = true
    let timer = null
    doc.addEventListener('selectionchange', () => {
        clearTimeout(timer)
        timer = setTimeout(() => {
            const sel = doc.getSelection?.()
            const text = sel && !sel.isCollapsed ? sel.toString().replace(/\s+/g, ' ').trim() : ''
            if (!text) { post({ type: 'selection', text: '' }); return }
            const range = sel.getRangeAt(0)
            const where = paragraphOf(range.startContainer)
            const msg = { type: 'selection', text: text.slice(0, 400), section: index }
            if (where && where.item.original == null) {
                const start = textOffset(where.item.el, range.startContainer, range.startOffset)
                msg.n = where.n
                msg.sentence = sentenceAt(where.item.text, start)
                if (toolsReady() && state.japanese) {
                    const words = tokenize(text).filter(t => !/^\s+$/.test(t.surface_form))
                    if (words.length === 1) {
                        const { base, reading } = baseOf(words[0])
                        Object.assign(msg, { base, reading, pos: words[0].pos, level: levelOf(base, reading) })
                    }
                }
            }
            post(msg)
        }, 380)
    })
}

/** Furigana as the study settings want them, on one loaded section. */
function syncFurigana(section) {
    const items = state.sections.get(section)
    if (!items) return
    const on = state.study.furigana !== 'off' && state.japanese && toolsReady()
    const keep = on ? furiganaFilter(state.study.furigana, state.study.level) : null
    for (const item of items) {
        // Paragraphs showing a translation in place get theirs back with
        // the original.
        if (item.original != null) continue
        if (item.furigana === (on ? state.study.furigana + state.study.level : null)) continue
        removeFurigana(item.el)
        if (on) addFurigana(item.el, keep)
        item.furigana = on ? state.study.furigana + state.study.level : null
    }
}

function setStudy(study) {
    const before = state.study
    state.study = { ...before, ...study }
    if (study.japanese !== undefined) state.japanese = !!study.japanese
    if (before.layout !== state.study.layout && state.showTranslations) {
        for (const [section, items] of state.sections) {
            for (const item of items) {
                removeBilingual(item)
                restoreOriginal(item)
                item.shown = null
            }
            syncFurigana(section)
            paintTranslations(section)
        }
    }
    for (const section of state.sections.keys()) syncFurigana(section)
    if (!state.study.wordTap) clearHighlight()
}

function clearHighlight() {
    if (highlighted) highlight(highlighted, null)
    highlighted = null
}

async function loadStudyTools() {
    try {
        await loadTools(new URL('.', location.href).href.replace(/\/$/, ''))
        for (const section of state.sections.keys()) syncFurigana(section)
        post({ type: 'studyTools', ready: true })
    } catch (e) {
        post({ type: 'studyTools', ready: false, message: String(e?.message ?? e) })
    }
}

/** Every section's words by JLPT level; progress as it goes. */
async function analyze() {
    const book = state.book
    if (!book || !toolsReady()) return post({ type: 'analysis', error: 'not ready' })
    const acc = newCount()
    const total = book.sections.length
    for (let i = 0; i < total; i++) {
        const section = book.sections[i]
        try {
            if (section.linear === 'no' || !section.createDocument) continue
            const doc = await section.createDocument()
            countWords(collectParagraphs(doc).map(p => p.text), acc)
        } catch (e) {
            post({ type: 'log', level: 'warn', message: `analysis skipped section ${i}: ${e}` })
        }
        post({ type: 'analysis', progress: (i + 1) / total })
        await new Promise(r => setTimeout(r, 0))
    }
    post({ type: 'analysis', result: summary(acc) })
}

// ---------------------------------------------------------------------------
// Position
// ---------------------------------------------------------------------------

function onRelocate(detail) {
    state.lastRelocate = detail
    const index = detail.index ?? detail.section?.current
    const loc = detail.location ?? {}
    post({
        type: 'relocate',
        cfi: detail.cfi ?? '',
        fraction: detail.fraction ?? 0,
        section: index ?? -1,
        sections: detail.section?.total ?? state.book?.sections?.length ?? 0,
        page: loc.current ?? 0,
        pages: loc.total ?? 0,
        tocLabel: detail.tocItem?.label?.trim() ?? '',
        tocHref: detail.tocItem?.href ?? '',
        atStart: !!state.view?.renderer?.atStart,
        atEnd: !!state.view?.renderer?.atEnd,
    })
    reportVisible(detail)
}

/** Which paragraphs of the section are on screen, for the translator. */
function reportVisible(detail) {
    const range = detail.range
    const index = detail.index ?? indexOfRange(range)
    const items = state.sections.get(index)
    if (!items || !range) return
    let first = -1
    let last = -1
    for (let i = 0; i < items.length; i++) {
        let hit = false
        try { hit = range.intersectsNode(items[i].el) } catch { hit = false }
        if (hit) {
            if (first < 0) first = i
            last = i
        } else if (first >= 0) break
    }
    if (first < 0) {
        // Between paragraphs (an image page): the next one after the range.
        for (let i = 0; i < items.length; i++) {
            try {
                if (range.comparePoint(items[i].el, 0) >= 0) { first = last = i; break }
            } catch { /* other document */ }
        }
    }
    post({ type: 'visible', section: index, first, last })
}

function indexOfRange(range) {
    const doc = range?.startContainer?.ownerDocument
    for (const { doc: d, index } of state.view?.renderer?.getContents?.() ?? []) {
        if (d === doc) return index
    }
    return -1
}

// ---------------------------------------------------------------------------
// Translation
// ---------------------------------------------------------------------------

function paintTranslations(section) {
    const items = state.sections.get(section)
    const done = state.translations.get(section)
    if (!items || !done) return
    const layout = state.study.layout
    for (const [n, text] of done) {
        const item = items[n]
        if (item && item.shown !== text) {
            if (layout === 'replace') {
                removeBilingual(item)
                applyTranslation(item, text, state.translationLang)
            } else {
                applyBilingual(item, text, state.translationLang, layout === 'hidden')
            }
            item.shown = text
        }
    }
}

// Every swapped paragraph lays the section out again; arrivals are
// gathered and painted together, at most every 1.2 s, and right away on a
// page turn (the page about to show should be translated).
const pendingPaint = new Set()
let paintTimer = null
let lastPaint = 0
function flushPaint() {
    clearTimeout(paintTimer)
    paintTimer = null
    lastPaint = Date.now()
    if (!state.showTranslations) { pendingPaint.clear(); return }
    for (const s of pendingPaint) paintTranslations(s)
    pendingPaint.clear()
}
function schedulePaint() {
    if (paintTimer || !pendingPaint.size) return
    const wait = Math.max(0, 1200 - (Date.now() - lastPaint))
    paintTimer = setTimeout(() => requestAnimationFrame(flushPaint), wait)
}

const reader = {
    open,
    next: () => state.view?.next(),
    prev: () => state.view?.prev(),
    goLeft: () => state.view?.goLeft(),
    goRight: () => state.view?.goRight(),
    goTo: target => state.view?.goTo(target).catch(e =>
        post({ type: 'log', level: 'warn', message: `goTo ${target}: ${e}` })),
    goToFraction: f => state.view?.goToFraction(f),
    setSettings: settings => applySettings(settings),
    /** [entries]: {section, n, text}; shown at once while translating. */
    setTranslations(entries, lang) {
        if (lang) state.translationLang = lang
        for (const { section, n, text } of entries) {
            let map = state.translations.get(section)
            if (!map) state.translations.set(section, map = new Map())
            map.set(n, text)
            pendingPaint.add(section)
        }
        schedulePaint()
    },
    showTranslations(on, lang) {
        if (lang) state.translationLang = lang
        state.showTranslations = !!on
        for (const [section, items] of state.sections) {
            if (on) paintTranslations(section)
            else {
                for (const item of items) {
                    removeBilingual(item)
                    restoreOriginal(item)
                    item.shown = null
                }
                syncFurigana(section)
            }
        }
    },
    clearTranslations() {
        reader.showTranslations(false)
        state.translations.clear()
    },
    /** The text from the first visible paragraph on, for reading aloud. */
    textFromHere() {
        const d = state.lastRelocate
        const index = d?.index ?? indexOfRange(d?.range)
        const items = state.sections.get(index) ?? []
        let start = 0
        for (let i = 0; i < items.length; i++) {
            try { if (d.range.intersectsNode(items[i].el)) { start = i; break } } catch { break }
        }
        return { section: index, texts: items.slice(start).map(p => p.text), start }
    },
    nextSection: () => state.view?.renderer?.nextSection?.(),
    setStudy,
    loadStudyTools,
    analyze,
    clearHighlight,
    clearSelection() {
        for (const { doc } of state.view?.renderer?.getContents?.() ?? []) doc?.getSelection?.()?.removeAllRanges()
    },
    reportVisible: () => state.lastRelocate && reportVisible(state.lastRelocate),
}
window.reader = reader
post({ type: 'pageReady' })
