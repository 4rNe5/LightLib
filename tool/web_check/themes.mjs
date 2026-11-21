// Pictures of the web app's screens in one colour scheme, signed in to a
// library with series (make_library.py <dir> 40 series): the library, its
// sort menu, a series' menu, a book's right-click menu and card, every
// page of the settings, the reader with its bars and its "Aa" sheet. For
// looking at, light against dark: an icon or a switch drawn in white on
// white shows only in a picture. Real mouse/touch only.
// argv: url mock shots scheme(light|dark) profile(desktop|mobile)
import puppeteer from 'puppeteer-core'
import { signedIn, reset } from './session.mjs'
const [url, mock, shots, scheme = 'light', profile = 'desktop'] = process.argv.slice(2)
const mobile = profile === 'mobile'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log(`[themes:${scheme}:${profile}]`, ...a)
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=ko-KR'] })
const page = await browser.newPage()
if (mobile) {
  await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
  await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
} else await page.setViewport({ width: Number(process.env.WIDTH ?? 1440), height: 900, deviceScaleFactor: 1 })
await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: scheme }])
const errors = []
page.on('pageerror', e => errors.push(String(e.message ?? e).slice(0, 300)))
await signedIn(page, mock)
await page.evaluateOnNewDocument(() => {
  Object.defineProperty(navigator, 'language', { get: () => 'ko-KR' })
  Object.defineProperty(navigator, 'languages', { get: () => ['ko-KR', 'ko'] })
})
const tap = (x, y) => mobile ? page.touchscreen.tap(x, y) : page.mouse.click(x, y)
const shot = name => page.screenshot({ path: `${shots}/themes_${scheme}_${profile}_${name}.png` })
const semantics = async () => {
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder'); if (!p) return
    p.click()
    const r = p.getBoundingClientRect(); const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 }
    for (const t of ['pointerdown', 'pointerup', 'click']) p.dispatchEvent(new PointerEvent(t, o))
  })
  await sleep(700)
}
const find = (text, { exact = false } = {}) => page.evaluate((text, exact) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text, exact)
const tapText = async (text, opts) => { await semantics(); const at = await find(text, opts); if (!at) { log(`!! no "${text}"`); return null } await tap(at.x, at.y); return at }
const escape = async () => { await page.keyboard.press('Escape'); await sleep(600) }

await page.goto(url, { waitUntil: 'load' })
await sleep(mobile ? 9000 : 7000)
await shot('1_library')
if (!mobile) {
  await page.mouse.wheel({ deltaY: 700 }); await sleep(900)
  await shot('1b_library_scrolled')
  await page.mouse.wheel({ deltaY: -2000 }); await sleep(700)
}
// A series' menu.
await semantics()
const more = await page.evaluate(() => {
  const n = [...document.querySelectorAll('flt-semantics')].find(n => /^(더 보기|More)$/.test((n.getAttribute('aria-label') || n.textContent || '').trim()))
  if (!n) return null
  const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
})
if (more) { await tap(more.x, more.y); await sleep(700); await shot('2_series_menu'); await escape() } else log('!! no series menu')
// The sort menu (desktop: the button beside the search box).
if (!mobile) {
  await page.mouse.click(1248, 42); await sleep(700); await shot('3_sort_menu'); await escape()
}
// A book standing alone: its menu, then its card.
const single = await find('月影の図書館')
if (single) {
  if (!mobile) { await page.mouse.click(single.x, single.y - 80, { button: 'right' }); await sleep(700); await shot('4_book_menu'); await escape() }
  await tap(single.x, single.y); await sleep(1500); await shot('5_book_card'); await escape()
} else log('!! no standalone book on screen')
// Settings, every page of it.
if (await tapText('설정', { exact: true })) {
  await sleep(1200); await shot('6_settings')
  for (const [i, name] of ['번역', '번역 엔진', '이 브라우저 저장 공간'].entries()) {
    if (await tapText(name, { exact: true })) { await sleep(1000); await shot(`6${'bcd'[i]}_settings`) }
    if (mobile) { await escape(); await tapText('설정', { exact: true }); await sleep(900) }
  }
  await escape()
}
// The reader: a book that is in this browser after it is fetched.
await escape()
const book = await find('風待ちの丘 1')
if (book) {
  await tap(book.x, book.y); await sleep(1300)
  const read = (await find('이어 읽기', { exact: true })) ? '이어 읽기' : '책 읽기'
  await tapText(read, { exact: true })
  let frame
  for (let i = 0; i < 40 && !frame; i++) { await sleep(500); frame = page.frames().find(f => f.url().includes('/reader/index.html')) }
  await sleep(5000)
  await shot('7_reader')
  const vp = page.viewport()
  await tap(vp.width / 2, vp.height / 2); await sleep(900)
  await shot('7b_reader_bars')
  if (await tapText('Aa')) { await sleep(1200); await shot('7c_reader_settings') }
} else log('!! no series volume on screen')
log('errors', JSON.stringify(errors.slice(0, 5)))
await browser.close()
