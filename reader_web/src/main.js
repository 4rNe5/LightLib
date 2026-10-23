// LightLib's reader page. foliate-js (readest's fork) lays the book out -
// reflowable EPUBs in pages or one scroll, vertical Japanese with ruby,
// fixed-layout and SVG pages, the book's own CSS - and this file connects
// it to the Flutter app over flutter_inappwebview's JavaScript handlers:
//
//   app -> page: window.reader.open(), .next(), .goTo(), .setSettings(),
//                .setTranslations(), .showOriginal() ...
//   page -> app: {type: 'book' | 'relocate' | 'paragraphs' | 'visible' |
//                 'tap' | 'error' | 'log', ...}
//
// The CSS overrides follow readest's (apps/readest-app/src/utils/style.ts,
// AGPL-3.0, like this app).

import 'construct-style-sheets-polyfill'
import { makeBook } from '../foliate-js/view.js'
import { readerStyles } from './styles.js'
import { collectParagraphs, applyTranslation, restoreOriginal } from './paragraphs.js'

// ---------------------------------------------------------------------------
// Messages to the app
// ---------------------------------------------------------------------------

let bridgeReady = false
const pending = []
const deliver = msg => {
    try {
        window.flutter_inappwebview.callHandler('reader', msg)
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
if (window.flutter_inappwebview?.callHandler) onBridge()

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
    const items = collectParagraphs(doc)
    state.sections.set(index, items)
    post({ type: 'paragraphs', section: index, texts: items.map(p => p.text) })
    if (state.showTranslations) paintTranslations(index)
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
        const frame = doc.defaultView?.frameElement
        const rect = frame?.getBoundingClientRect?.() ?? { left: 0, top: 0 }
        const x = rect.left + e.clientX
        const width = window.innerWidth || 1
        const zone = x < width * 0.28 ? 'left' : x > width * 0.72 ? 'right' : 'center'
        if (zone === 'center' || state.settings?.flow === 'scrolled') {
            post({ type: 'tap', zone: 'center' })
            return
        }
        post({ type: 'turn' })
        if (pendingPaint.size) flushPaint()
        zone === 'left' ? state.view?.goLeft() : state.view?.goRight()
    })
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
    for (const [n, text] of done) {
        const item = items[n]
        if (item && item.shown !== text) {
            applyTranslation(item, text, state.translationLang)
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
            else for (const item of items) {
                restoreOriginal(item)
                item.shown = null
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
    reportVisible: () => state.lastRelocate && reportVisible(state.lastRelocate),
}
window.reader = reader
post({ type: 'pageReady' })
