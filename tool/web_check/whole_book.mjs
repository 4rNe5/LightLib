// "Translate this book to the end" on the web, in headless Chrome with
// real clicks, Gemini answered by a stand-in: a book is added, its card
// opened, the button pressed; the card says how far, then that it is
// done; every paragraph of the book is kept in the browser, without the
// reader ever opened. argv: url mock epub shots
import puppeteer from 'puppeteer-core'
import { signedIn } from './session.mjs'
const [url, mock, epub, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log('[whole]', ...a)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=en-US'] })
const page = await browser.newPage()
await page.setViewport({ width: 1440, height: 900 })
const errors = []
page.on('pageerror', e => errors.push(String(e.message ?? e).slice(0, 300)))
page.on('console', m => { if (m.type() === 'error' || /Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 300)) })
let gemini = 0
await signedIn(page, mock, { signIn: false })
page.on('request', req => { if (req.url().startsWith('https://generativelanguage.googleapis.com/') && req.method() === 'POST') gemini++ })

const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(800) }
const find = (text, { exact = false } = {}) => page.evaluate((text, exact) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text, exact)
const tapText = async (text, opts) => { await semantics(); const at = await find(text, opts); if (!at) { log(`!! no "${text}" on screen`); return null } await page.mouse.click(at.x, at.y); return at }
const files = () => page.evaluate(() => new Promise(resolve => {
  const open = indexedDB.open('lightlib_files')
  open.onsuccess = () => {
    const store = open.result.transaction('files').objectStore('files')
    const keys = store.getAllKeys()
    keys.onsuccess = async () => {
      const out = {}
      for (const k of keys.result) {
        if (!String(k).startsWith('/translations/') || String(k).endsWith('.redo')) continue
        out[k] = await new Promise(r => { const g = open.result.transaction('files').objectStore('files').get(k); g.onsuccess = () => r(g.result) })
      }
      resolve(Object.fromEntries(Object.entries(out).map(([k, v]) => {
        try { const j = JSON.parse(new TextDecoder().decode(v)); const vals = Object.values(j); return [k, { paragraphs: vals.length, translated: vals.filter(t => String(t).startsWith('[KO]')).length }] } catch { return [k, null] }
      })))
    }
  }
  open.onerror = () => resolve({})
}))

// A Gemini key as the app keeps it, put there before the app starts (a
// file of the site that is not the app), then the app and the book.
await page.goto(new URL('version.json', url).href, { waitUntil: 'load' })
await page.evaluate(() => new Promise((resolve, reject) => {
  const open = indexedDB.open('lightlib_files', 1)
  open.onupgradeneeded = () => open.result.createObjectStore('files')
  open.onsuccess = () => {
    const tx = open.result.transaction('files', 'readwrite')
    tx.objectStore('files').put(new TextEncoder().encode('AIzaTestKeyForE2E'), '/support/gemini_api_key')
    tx.oncomplete = () => { open.result.close(); resolve() }
    tx.onerror = () => reject(tx.error)
  }
  open.onerror = () => reject(open.error)
}))
await page.goto(url, { waitUntil: 'load' }); await sleep(8000); await semantics()
const [chooser] = await Promise.all([page.waitForFileChooser({ timeout: 15000 }), tapText('Add EPUB')])
await chooser.accept([epub]); await sleep(6000); await semantics()

// The book's card, and the button on it.
await tapText('春の駅'); await sleep(1500); await semantics()
log('the card offers it:', !!(await find('Translate this whole book')), '| says what it does:', !!(await find('while this tab is open')))
await page.screenshot({ path: `${shots}/whole_1_card.png` })
await tapText('Translate this whole book')
let seen = [], done = false
for (let i = 0; i < 40 && !done; i++) {
  await sleep(1500); await semantics()
  const label = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).find(l => /^\d+\/\d+ paragraphs/.test(l)))
  if (label && seen[seen.length - 1] !== label) seen.push(label)
  done = !!(await find('Translation complete')) || !!(await find('Translated', { exact: true }))
  if (i === 2) await page.screenshot({ path: `${shots}/whole_2_running.png` })
}
await page.screenshot({ path: `${shots}/whole_3_done.png` })
log('progress shown on the card:', JSON.stringify(seen.slice(0, 6)), '| done said:', done)
log('requests to Gemini:', gemini)
log('kept in the browser:', JSON.stringify(await files()))
log('the reader was never opened:', !page.frames().some(f => f.url().includes('/reader/index.html')))
log('page errors', JSON.stringify(errors.slice(0, 8)))
await browser.close()
