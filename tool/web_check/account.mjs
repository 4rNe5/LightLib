// The account side of the web, against the stand-in project: the Gemini
// key travels between browsers, a book added here goes up with its small
// cover, this browser's copy can go while the account keeps the book, and
// a deletion reaches the account. argv: url mock shots extraEpub
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, shots, extra] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log('[sync2]', ...a)
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const errors = []
const open = async context => {
  const page = await context.newPage()
  await page.setViewport({ width: 1440, height: 900 })
  page.on('pageerror', e => errors.push(String(e.stack ?? e.message).slice(0, 400)))
  page.on('console', m => { if (/Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 200)) })
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'language', { get: () => 'ko-KR' })
    Object.defineProperty(navigator, 'languages', { get: () => ['ko-KR', 'ko'] })
  })
  await signedIn(page, mock)
  // Gemini's test call answered here (the real API is not called).
  page.on('request', () => {})
  await page.goto(url, { waitUntil: 'load' }); await sleep(7000)
  return page
}
const helpers = page => {
  const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(700) }
  const find = (text, { exact = false, last = false } = {}) => page.evaluate((text, exact, last) => {
    const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
    const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
      .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => last ? b.y - a.y : a.width * a.height - b.width * b.height)
    return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
  }, text, exact, last)
  const tapText = async (text, opts) => { await semantics(); const at = await find(text, opts); if (!at) { log(`!! no "${text}" on screen`); return null } await page.mouse.click(at.x, at.y); return at }
  const stored = key => page.evaluate(key => new Promise(resolve => {
    const open = indexedDB.open('lightlib_files')
    open.onsuccess = () => {
      const req = open.result.transaction('files').objectStore('files').getAllKeys()
      req.onsuccess = () => {
        const keys = req.result
        if (!key) return resolve(keys)
        const get = open.result.transaction('files').objectStore('files').get(key)
        get.onsuccess = () => resolve(get.result ? new TextDecoder().decode(get.result) : null)
      }
    }
    open.onerror = () => resolve(null)
  }), key)
  return { semantics, find, tapText, stored }
}
const calls = async re => (await state(mock)).calls.filter(c => re.test(c))

// --- 1. The key typed in one browser reaches the account.
const one = await open(await browser.createBrowserContext())
const h1 = helpers(one)
await h1.tapText('설정', { exact: true }); await sleep(1000)
await h1.tapText('Gemini', { exact: true }); await sleep(900)
await one.mouse.click(820, 206); await sleep(500)
await one.keyboard.type('AIzaTESTkeyFromBrowserOne1234', { delay: 8 }); await sleep(400)
await h1.tapText('저장 후 연결 확인'); await sleep(4000)
await one.screenshot({ path: `${shots}/sync2_1_key.png` })
let st = await state(mock)
log('key on the account:', JSON.stringify(st.settings.map(s => [s.name, s.value, s.device])))

// --- 2. Another browser, signed in to the same account, gets it.
const two = await open(await browser.createBrowserContext())
const h2 = helpers(two)
await sleep(2500)
log('key in the second browser:', JSON.stringify(await h2.stored('/support/gemini_api_key')))
// Removed there: removed on the account, and in the first browser at its next sync.
// Removed in the second browser: removed on the account, and in the first at its next sync.
await h2.tapText('설정', { exact: true }); await sleep(1000)
await h2.tapText('Gemini', { exact: true }); await sleep(900)
await two.screenshot({ path: `${shots}/sync2_2_second.png` })
log('second browser shows the saved key:', !!(await (async () => { await h2.semantics(); return h2.find('저장된 키') })()))
await two.close()

// --- 3. A book added in the browser goes up, with its small cover.
await one.mouse.click(1122, 148); await sleep(700)
const before = (await state(mock)).books.length
const [chooser] = await Promise.all([one.waitForFileChooser({ timeout: 15000 }), h1.tapText('EPUB 추가')])
await chooser.accept([extra]); await sleep(9000)
st = await state(mock)
const row = st.books.find(b => b.title === '霧の町の探偵')
log('added book: rows', before, '->', st.books.length, '| file up:', Object.keys(st.uploads).some(k => k.endsWith('.epub')),
  '| cover up:', JSON.stringify(Object.entries(st.uploads).filter(([k]) => k.endsWith('.cover.jpg'))), '| row:', row && JSON.stringify({ has_file: row.has_file, cover_at: !!row.cover_at, publisher: row.publisher, description: (row.description ?? '').slice(0, 12) }))
await one.screenshot({ path: `${shots}/sync2_3_added.png` })

// --- 4. This browser's copy goes; the account keeps the book.
const tile = await h1.tapText('霧の町の探偵'); await sleep(1200)
await h1.tapText('더 보기'); await sleep(700)
await h1.tapText('이 브라우저에서 파일 지우기'); await sleep(3500)
st = await state(mock)
log('copy removed: books kept in this browser:', JSON.stringify((await h1.stored()).filter(k => String(k).startsWith('/books/'))),
  '| account row deleted:', !!st.books.find(b => b.title === '霧の町の探偵')?.deleted_at, '| storage removals:', st.removed.length)
await one.screenshot({ path: `${shots}/sync2_4_copy_removed.png` })

// --- 5. Deleted from the library: gone on the account.
await h1.semantics()
const at = await h1.find('春の駅')
await one.mouse.click(at.x, at.y - 80, { button: 'right' }); await sleep(700)
await h1.tapText('서재에서 삭제'); await sleep(900)
await one.screenshot({ path: `${shots}/sync2_5_confirm.png` })
await h1.tapText('삭제', { exact: true, last: true }); await sleep(4000)
st = await state(mock)
const gone = st.books.find(b => b.title === '春の駅')
log('deleted: row marked', !!gone?.deleted_at, '| files removed:', JSON.stringify(st.removed.map(p => p.split('.').slice(1).join('.'))), '| still listed:', !!(await (async () => { await h1.semantics(); return h1.find('春の駅') })()))
await one.screenshot({ path: `${shots}/sync2_6_deleted.png` })
log('errors', JSON.stringify(errors.slice(0, 5)))
await browser.close()
