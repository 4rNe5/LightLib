// Paragraphs of a section for the translator: the leaf text blocks, their
// text exactly as the app's paragraphText() reads it (so both share one
// translation cache), and swapping a translation in and out.

const BLOCKS = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,dt,dd,figcaption,td,th,div,caption'
const DROPPED = new Set(['RT', 'RP', 'SCRIPT', 'STYLE'])
const LETTER = /\p{L}/u

/** paragraph_text.dart's paragraphText(): ruby readings dropped, <br> as a
 *  line break, runs of spaces collapsed, empty lines dropped. */
export function textOf(el) {
    let out = ''
    const walk = node => {
        if (node.nodeType === 1) {
            const tag = node.tagName.toUpperCase()
            if (DROPPED.has(tag)) return
            if (tag === 'BR') { out += '\n'; return }
        } else if (node.nodeType === 3) {
            out += node.data
            return
        }
        for (const child of node.childNodes) walk(child)
    }
    walk(el)
    return out.split('\n')
        .map(line => line.replace(/[ \t\r\f ]+/g, ' ').trim())
        .filter(line => line)
        .join('\n')
}

/** The leaf blocks with letters in them, in document order. */
export function collectParagraphs(doc) {
    const items = []
    const body = doc.body
    if (!body) return items
    for (const el of body.querySelectorAll(BLOCKS)) {
        if (el.querySelector(BLOCKS)) continue
        if (el.hasAttribute('data-foliate-chunk')) continue
        // An illustration with a caption stays as it is.
        if (el.querySelector('img, svg, image, video')) continue
        const text = textOf(el)
        if (!text || !LETTER.test(text)) continue
        items.push({ el, text, original: null, shown: null })
    }
    return items
}

const escapeHtml = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

export function applyTranslation(item, text, lang) {
    const { el } = item
    if (item.original == null) {
        item.original = el.innerHTML
        item.originalLang = el.getAttribute('lang')
    }
    el.innerHTML = escapeHtml(text).replace(/\n/g, '<br/>')
    el.classList.add('ll-translated')
    if (lang) el.setAttribute('lang', lang)
}

export function restoreOriginal(item) {
    if (item.original == null) return
    const { el } = item
    el.innerHTML = item.original
    el.classList.remove('ll-translated')
    if (item.originalLang == null) el.removeAttribute('lang')
    else el.setAttribute('lang', item.originalLang)
    item.original = null
}
