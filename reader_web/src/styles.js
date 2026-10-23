// The CSS laid over every book document: the app's theme, type settings
// and fixes for badly made EPUBs. Most rules follow readest
// (apps/readest-app/src/utils/style.ts, AGPL-3.0); the book's own layout
// (vertical writing, ruby, image pages) is otherwise left alone.

const INLINE = 'a, abbr, b, bdi, bdo, br, cite, code, data, dfn, em, font, i, img, kbd, mark, q, rb, rp, rt, rtc, ruby, s, samp, small, span, strong, sub, sup, time, tt, u, var, wbr'

// The Japanese publishers' generic names (電書協 EPUB 3 guide): without a
// font behind them the text falls to a Latin serif and CJK glyphs come
// from per-character fallback, which breaks vertical metrics.
const local = names => names.map(n => `local("${n}")`).join(', ')
const MINCHO = ['Noto Serif CJK JP', 'NotoSerifCJKjp-Regular', 'Noto Serif JP', 'Source Han Serif JP',
    'Hiragino Mincho ProN', 'HiraMinProN-W3', 'Yu Mincho', 'YuMincho', 'MS Mincho']
const GOTHIC = ['Noto Sans CJK JP', 'NotoSansCJKjp-Regular', 'Noto Sans JP', 'Source Han Sans JP',
    'Hiragino Sans', 'HiraginoSans-W3', 'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'YuGothic', 'Meiryo']
const JP_GENERIC_FACES = ['serif-ja', 'serif-ja-v'].map(f =>
    `@font-face { font-family: "${f}"; src: ${local(MINCHO)}; }`).concat(
    ['sans-serif-ja', 'sans-serif-ja-v'].map(f =>
        `@font-face { font-family: "${f}"; src: ${local(GOTHIC)}; }`)).join('\n')

export function readerStyles(s) {
    const fg = s.foreground ?? '#000'
    const bg = s.background ?? '#fff'
    const secondary = s.secondary ?? fg
    const link = s.link ?? fg
    const size = s.fontSize ?? 18
    const lineHeight = s.lineHeight ?? 1.7
    const spacing = s.letterSpacing ?? 0
    const writing = s.writing ?? 'auto'
    const forced = writing === 'horizontal' ? 'horizontal-tb' : writing === 'vertical' ? 'vertical-rl' : null
    const family = s.fontFamily ? `${s.fontFamily}, ` : ''
    const faces = (s.fontFaces ?? []).map(f =>
        `@font-face { font-family: "${f.family}"; src: url("${f.url}"); font-display: swap; }`).join('\n')
    return `
${faces}
${JP_GENERIC_FACES}
@namespace epub "http://www.idpf.org/2007/ops";
html {
    color-scheme: ${s.dark ? 'dark' : 'light'};
    color: ${fg};
    background: transparent !important;
    font-size: ${size}px !important;
    -webkit-text-size-adjust: none;
    text-size-adjust: none;
    -webkit-touch-callout: none;
    hanging-punctuation: allow-end last;
    orphans: 2;
    widows: 2;
}
${forced ? `html, body { writing-mode: ${forced} !important; -webkit-writing-mode: ${forced} !important; }
/* the book's vertical blocks follow too, except image pages */
body *:not(svg):not(svg *):not(img) { writing-mode: inherit !important; }` : ''}
html, body {
    max-height: unset;
    -webkit-user-select: text;
}
body {
    color: inherit;
    background: transparent !important;
    overflow: unset;
    padding: unset;
    margin: unset;
    line-height: unset;
    ${s.bold ? 'font-weight: 600;' : ''}
}
${s.fontFamily ? `body, body *:not(rt):not(code):not(pre) { font-family: ${family}serif !important; }` : ''}
${s.dark ? `
/* dark themes: text the book colours black would vanish */
body *:not(a):not(svg):not(svg *):not(img) { color: inherit !important; border-color: ${secondary} !important; }
body *:not(img):not(svg) { background-color: transparent !important; }
img { filter: none; }` : ''}
a, a:link, a:visited { color: ${link}; text-decoration-color: ${secondary}; }
::selection { background: ${s.selection ?? 'rgba(80,140,255,.35)'}; }

p, blockquote, dd, li, div:not(:has(*:not(${INLINE}))) {
    line-height: ${lineHeight} !important;
    ${spacing ? `letter-spacing: ${spacing}px !important;` : ''}
    ${s.justify ? 'text-align: justify;' : ''}
    hanging-punctuation: allow-end last;
}
:lang(ja), :lang(zh), :lang(ko) { widows: 1; orphans: 1; }
p.leading-image { text-indent: initial !important; }

/* images: whole on one page, never stretched past it */
img, svg, video { max-width: 100%; }
svg:where(:not([width])), img:where(:not([width])) { width: auto; }
svg:where(:not([height])), img:where(:not([height])) { height: auto; }
img { -webkit-touch-callout: none; -webkit-user-drag: none; }
img.has-text-siblings { height: 1em; vertical-align: baseline; }
div:has(> img, > svg) { max-width: 100% !important; }
figure > div:has(img) { height: auto !important; }
sup img { height: 1em; }

/* notes live in their popups, not in the text */
aside[epub|type~="footnote"], aside[epub|type~="endnote"],
aside[epub|type~="note"], aside[epub|type~="rearnote"] { display: none; }

pre, code { white-space: pre-wrap !important; }
table { max-width: 100%; }
p { display: block; }

.ll-translated { font-family: inherit; }
`
}
