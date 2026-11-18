// The new web library end to end, signed in against the stand-in project:
// the library lists every book without fetching a file; a book's card;
// the file comes when "Read" is pressed, with its progress shown; the
// reader; what the browser keeps afterwards. Real mouse/touch only.
// argv: url mock shots profile(desktop|mobile)
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, shots, profile = 'desktop'] = process.argv.slice(2)
const mobile = profile === 'mobile'
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log(`[lib:${profile}]`, ...a)
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=ko-KR'] })
const page = await browser.newPage()
if (mobile) {
  await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
  await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
} else await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 })
const errors = []
page.on('pageerror', e => errors.push(String(e.stack ?? e.message ?? e).slice(0, 900)))
page.on('console', m => { if (m.type() === 'error' || /Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 240)) })
await signedIn(page, mock)
await page.evaluateOnNewDocument(() => {
  Object.defineProperty(navigator, 'language', { get: () => 'ko-KR' })
  Object.defineProperty(navigator, 'languages', { get: () => ['ko-KR', 'ko'] })
})
const tap = (x, y) => mobile ? page.touchscreen.tap(x, y) : page.mouse.click(x, y)
const shot = name => page.screenshot({ path: `${shots}/lib_${profile}_${name}.png` })
// Where a widget is: the semantics tree is only read (the taps are real).
const semantics = async () => {
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder'); if (!p) return
    p.click()
    const r = p.getBoundingClientRect(); const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 }
    for (const t of ['pointerdown', 'pointerup', 'click']) p.dispatchEvent(new PointerEvent(t, o))
  })
  await sleep(900)
}
const find = (text, { exact = false } = {}) => page.evaluate((text, exact) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2, w: nodes[0].width, h: nodes[0].height } : null
}, text, exact)
const tapText = async (text, opts) => { const at = await find(text, opts); if (!at) { log(`!! no "${text}" on screen`); return null } await tap(at.x, at.y); return at }
const calls = async re => (await state(mock)).calls.filter(c => re.test(c))

await page.goto(url, { waitUntil: 'load' })
await sleep(mobile ? 9000 : 7000)
await semantics()
await shot('1_library')
const titles = ['春の駅', '月影の図書館', '雨上がりの約束']
log('listed', JSON.stringify(await Promise.all(titles.map(async t => !!(await find(t))))),
  '| book files fetched on load:', (await calls(/GET .*\.epub$/)).length,
  '| covers fetched:', (await calls(/GET .*\.cover\.jpg$/)).length)

// A book's card.
await tapText('雨上がりの約束')
await sleep(1200); await semantics()
await shot('2_card')
const readLabel = (await find('이어 읽기', { exact: true })) ? '이어 읽기' : '책 읽기'
log('card: button', readLabel, !!(await find(readLabel, { exact: true })), '| in the account', !!(await find('계정에 보관됨')))

// "Read": the file comes (7 MB, slowly), its progress shown.
await tapText(readLabel, { exact: true })
await sleep(900)
await shot('3_fetching')
await semantics()
log('while fetching:', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).filter(t => /받는 중|MB|여는 중/.test(t)).slice(0, 4))))
let frame
for (let i = 0; i < 40 && !frame; i++) { await sleep(500); frame = page.frames().find(f => f.url().includes('/reader/index.html')) }
await sleep(5000)
const text = frame ? await frame.evaluate(() => {
  const out = []; const walk = root => { for (const f of root.querySelectorAll('iframe')) { try { const d = f.contentDocument; if (d) { out.push(d.body?.innerText ?? ''); walk(d) } } catch {} } for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot) }
  walk(document); return out.join('').length
}).catch(e => 'error ' + e) : 'no reader'
await shot('4_reader')
log('reader text chars:', text, '| book files fetched in all:', (await calls(/GET .*\.epub$/)).length, '| title bar:', await page.title())

// Keys turn pages (desktop): the position moves.
if (!mobile && frame) {
  const where = () => frame.evaluate(() => window.reader && JSON.stringify(window.reader.debugLocation?.() ?? null)).catch(() => null)
  await page.mouse.click(720, 450); await sleep(400)
  await page.keyboard.press('ArrowLeft'); await sleep(900)
  await page.keyboard.press('PageDown'); await sleep(900)
  await shot('4b_after_keys')
}
// Back to the library: the book is here now, and read a little.
if (mobile) { await page.touchscreen.tap(196, 425); await sleep(700); await page.touchscreen.tap(24, 28) } else { await page.mouse.click(720, 450); await sleep(500); await page.mouse.click(24, 28) }
await sleep(2500); await semantics()
await shot('5_back')
const st = await state(mock)
log('progress rows with a fraction:', st.progress.filter(p => p.fraction != null).length, '| reading sent:', (await calls(/rpc\/put_reading/)).length)

if (!mobile) {
  // Search and the side bar.
  await page.keyboard.press('Slash'); await sleep(400)
  await page.keyboard.type('月影', { delay: 30 }); await sleep(1200); await semantics()
  await shot('6_search')
  log('search: found', !!(await find('月影の図書館')), '| others hidden', !(await find('星を拾う少年')))
  await page.keyboard.press('Escape'); await sleep(500)
  await tapText('이 브라우저에 있음'); await sleep(900); await semantics()
  await shot('7_downloaded')
  log('filter "on this browser": the fetched one', !!(await find('雨上がりの約束')), '| others hidden', !(await find('月影の図書館')))
  await tapText('전체'); await sleep(600)
  // Right-click menu.
  const at = await find('春の駅')
  if (at) await page.mouse.click(at.x, at.y - 80, { button: 'right' }); await sleep(700); await semantics()
  await shot('8_menu')
  log('right-click menu:', !!(await find('서재에서 삭제')))
  await page.keyboard.press('Escape'); await sleep(400)
  // Settings.
  await tapText('설정', { exact: true }); await sleep(1200); await semantics()
  await shot('9_settings')
  log('settings dialog: sync switch', !!(await find('Gemini 키 동기화')))
  await tapText('이 브라우저 저장 공간'); await sleep(900); await semantics()
  await shot('9b_storage')
}
log('errors', JSON.stringify(errors.slice(0, 6)))
await browser.close()
