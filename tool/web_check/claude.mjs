// Claude on the web, in headless Chrome with real clicks; the API is
// answered by a stand-in (never called).
//  1. Signed in to an account a phone put its Claude key on: the key
//     comes with the first sync, and Settings has the switch for it.
//  2. Settings -> Translation engine -> Claude; a book is added, opened
//     and translated: the requests go to Claude, say they come from a
//     browser (the API's CORS rule), and the site's policy lets them out.
// argv: url mock epub shots
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, epub, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log('[claude]', ...a)

await reset(mock)
// As the account is once a phone has shared its key (typed there before
// sync knew of it: the oldest time there is).
await fetch(mock + '/__set', { method: 'POST', body: JSON.stringify({ settings: [{
  name: 'claude_api_key', device: 'android', updated_at: '1970-01-01T00:00:00.001+00:00',
  value: JSON.stringify({ key: 'sk-ant-standin-key-from-the-phone-7Q2x', workspace: 'wrkspc_standin' }),
}] }) })

const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=en-US'] })
const page = await browser.newPage()
await page.setViewport({ width: 1440, height: 900 })
const errors = []
page.on('pageerror', e => errors.push(String(e.message ?? e).slice(0, 300)))
page.on('console', m => { if (m.type() === 'error' || /Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 300)) })

// What is asked of Claude (session.mjs answers in its place: each
// numbered paragraph back as "[KO] ...", and nothing for a request that
// does not say it comes from a browser).
const claude = { calls: 0, fromBrowser: 0, keyed: 0, workspace: 0, models: new Set() }
let gemini = 0
await signedIn(page, mock)
page.on('request', req => {
  const u = req.url()
  if (u.startsWith('https://generativelanguage.googleapis.com/') && req.method() === 'POST') gemini++
  if (!u.startsWith('https://api.anthropic.com/') || req.method() !== 'POST') return
  claude.calls++
  const h = req.headers()
  if (h['anthropic-dangerous-direct-browser-access'] === 'true') claude.fromBrowser++
  if (h['x-api-key'] === 'sk-ant-standin-key-from-the-phone-7Q2x') claude.keyed++
  if (h['anthropic-workspace-id'] === 'wrkspc_standin') claude.workspace++
  try { claude.models.add(JSON.parse(req.postData() ?? '{}').model) } catch {}
})

const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(800) }
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
    try {
      const get = open.result.transaction('files').objectStore('files').get(key)
      get.onsuccess = () => resolve(get.result ? new TextDecoder().decode(get.result) : null)
      get.onerror = () => resolve(null)
    } catch { resolve(null) }
  }
  open.onerror = () => resolve(null)
}), key)

// --- 1. The phone's key comes with the first sync.
await page.goto(url, { waitUntil: 'load' }); await sleep(9000)
const key = await stored('/support/claude_api_key')
log('key from the account in this browser:', key === 'sk-ant-standin-key-from-the-phone-7Q2x' ? 'yes' : `NO (${key == null ? 'none' : 'another'})`)
await tapText('Settings', { exact: true }); await sleep(1200); await semantics()
log('sync: the switch for the Claude key:', !!(await find('Share the Claude key')))
await page.screenshot({ path: `${shots}/claude_1_sync.png` })

// --- 2. The engine is chosen.
await tapText('Translation engine', { exact: true }); await sleep(1000); await semantics()
log('engine choice offers Claude:', !!(await find('Claude', { exact: true })), '| Gemini:', !!(await find('Gemini', { exact: true })),
  '| the phone\'s model (not on the web):', !!(await find('On device')))
await tapText('Claude', { exact: true }); await sleep(1500); await semantics()
log('Claude\'s settings shown: key set', !!(await find('…7Q2x')), '| models', !!(await find('Sonnet')))
await page.screenshot({ path: `${shots}/claude_2_engine.png` })
await page.keyboard.press('Escape'); await sleep(800)

// --- 3. A book translated by it.
await semantics()
const [chooser] = await Promise.all([page.waitForFileChooser({ timeout: 15000 }), tapText('Add EPUB')])
await chooser.accept([epub]); await sleep(6000); await semantics()
await tapText('春の駅'); await sleep(1500); await semantics()
const read = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
  .filter(n => /^(Read|Continue reading)$/.test((n.getAttribute('aria-label') || n.textContent || '').trim()))
  .map(n => { const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } }).sort((a, b) => b.y - a.y))
if (read.length) await page.mouse.click(read[0].x, read[0].y)
await sleep(8000); await semantics()
const frame = page.frames().find(f => f.url().includes('/reader/index.html'))
const buttons = await page.evaluate(() => [...new Set([...document.querySelectorAll('flt-semantics')]
  .map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).filter(l => /translat/i.test(l) && l.length < 40))])
if (buttons.length) await tapText(buttons[0])
await sleep(10000)
const ko = frame ? await frame.evaluate(() => {
  const out = []
  const walk = root => {
    for (const f of root.querySelectorAll('iframe')) { try { const d = f.contentDocument; if (d) { out.push(d.body?.innerText ?? ''); walk(d) } } catch {} }
    for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot)
  }
  walk(document)
  return (out.join('\n').match(/\[KO\]/g) ?? []).length
}) : -1
await page.screenshot({ path: `${shots}/claude_3_translated.png` })
log('translated paragraphs on the page:', ko)
log('requests to Claude:', claude.calls, '| saying they come from a browser:', claude.fromBrowser, '| with the account\'s key:', claude.keyed,
  '| with its workspace:', claude.workspace, '| models:', JSON.stringify([...claude.models]))
log('requests to Gemini:', gemini)
const st = await state(mock)
log('the account\'s key after this browser synced:', JSON.stringify(st.settings.filter(s => s.name === 'claude_api_key').map(s => [s.device, s.updated_at])))
log('page errors', JSON.stringify(errors.slice(0, 8)))
await browser.close()
