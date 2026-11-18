// Web build end to end in headless Chrome: add an EPUB through the file
// picker, open it, turn translation on with Gemini answered by a stand-in
// (the real API is not called), and check the translations reach the
// page and survive a reload (IndexedDB).
import puppeteer from 'puppeteer-core'

const base = process.argv[2] ?? 'http://127.0.0.1:8097/'
const epub = process.argv[3]
const shots = process.argv[4]
const log = (...a) => console.log('[e2e]', ...a)
const sleep = ms => new Promise(r => setTimeout(r, ms))

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=en-US'],
})
const page = await browser.newPage()
await page.setViewport({ width: 1280, height: 860 })
const errors = []
page.on('pageerror', e => errors.push(String(e.message ?? e).slice(0, 300)))
page.on('console', m => { if (m.type() === 'error' || /Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 300)) })

// Gemini stand-in: echoes each numbered paragraph as "[KO] ...".
let geminiCalls = 0
await page.setRequestInterception(true)
page.on('request', req => {
  const url = req.url()
  if (!url.startsWith('https://generativelanguage.googleapis.com/')) return req.continue()
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'content-type,x-goog-api-key',
    'Access-Control-Allow-Methods': 'POST,GET,OPTIONS',
  }
  if (req.method() === 'OPTIONS') return req.respond({ status: 204, headers: cors })
  geminiCalls++
  let text = 'OK'
  try {
    const body = JSON.parse(req.postData() ?? '{}')
    const user = body.contents?.[0]?.parts?.[0]?.text ?? ''
    const nl = user.indexOf('\n')
    if (user.startsWith('Translate the') && nl > 0) {
      const payload = JSON.parse(user.slice(nl + 1))
      text = JSON.stringify({
        translations: payload.paragraphs.map(p => ({ n: p.n, text: '[KO] ' + p.text })),
      })
    } else if (body.generationConfig?.responseFormat || body.generationConfig?.responseMimeType) {
      text = '{}'
    }
  } catch (e) { text = '{}' }
  req.respond({
    status: 200, headers: cors, contentType: 'application/json',
    body: JSON.stringify({
      candidates: [{ content: { role: 'model', parts: [{ text }] }, finishReason: 'STOP' }],
      usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 100, totalTokenCount: 200 },
    }),
  })
})

const enableSemantics = async () => {
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())
  await sleep(800)
}
// Clicks the semantics node whose label contains [text].
const clickLabel = async (text, { exact = false } = {}) => {
  const box = await page.evaluate((text, exact) => {
    const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
    const nodes = [...document.querySelectorAll('flt-semantics')]
      .filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
      .map(n => ({ n, r: n.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0)
      // The smallest node that says it (a button, not the page around it).
      .sort((a, b) => a.r.width * a.r.height - b.r.width * b.r.height)
    if (!nodes.length) return null
    const r = nodes[0].r
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
  }, text, exact)
  if (!box) throw new Error(`no "${text}" on screen`)
  await page.mouse.click(box.x, box.y)
  return box
}
// A tile opens the book's card; its button opens the book.
const openBook = async title => {
  await clickLabel(title)
  await sleep(1500)
  await enableSemantics()
  const buttons = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .filter(n => /^(Read|Continue reading)$/.test((n.getAttribute('aria-label') || n.textContent || '').trim()))
    .map(n => { const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } }).sort((a, b) => b.y - a.y))
  if (!buttons.length) throw new Error('no Read button on the card')
  await page.mouse.click(buttons[0].x, buttons[0].y)
}
const labels = () => page.evaluate(() =>
  [...new Set([...document.querySelectorAll('flt-semantics')]
    .filter(n => !n.querySelector('flt-semantics'))
    .map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).filter(Boolean))])

// 1. The app, with a Gemini key already saved (IndexedDB, as the app keeps it).
await page.goto(base, { waitUntil: 'load' })
await sleep(7000)
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
await page.reload({ waitUntil: 'load' })
await sleep(7000)
await enableSemantics()
log('library labels', JSON.stringify((await labels()).slice(0, 12)))

// 2. Add the EPUB through the picker.
const [chooser] = await Promise.all([
  page.waitForFileChooser({ timeout: 15000 }),
  clickLabel('Add EPUB'),
])
await chooser.accept([epub])
await sleep(5000)
const afterAdd = await labels()
log('after add', JSON.stringify(afterAdd.slice(0, 12)))
await page.screenshot({ path: `${shots}/e2e_1_library.png` })

// 3. Open it.
await openBook('春の駅')
await sleep(7000)
const frame = page.frames().find(f => f.url().includes('/reader/index.html'))
log('reader frame', frame ? frame.url() : 'MISSING')
await page.screenshot({ path: `${shots}/e2e_2_reader.png` })
const reader = frame && await frame.evaluate(() => ({
  view: !!document.querySelector('foliate-view'),
  text: document.querySelector('foliate-view')?.shadowRoot ? 'shadow' : '',
}))
log('reader state', JSON.stringify(reader))

// 4. Translation on: the reader's top bar (shown on open).
await enableSemantics()
const top = (await labels()).filter(l => /translat/i.test(l))
log('translate buttons', JSON.stringify(top))
await clickLabel(top[0])
await sleep(9000)
const translated = frame && await frame.evaluate(() => {
  // foliate renders sections in iframes inside its shadow root.
  const out = []
  const walk = root => {
    for (const f of root.querySelectorAll('iframe')) {
      try { const d = f.contentDocument; if (d) { out.push(d.body?.innerText ?? ''); walk(d) } } catch {}
    }
    for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot)
  }
  walk(document)
  const all = out.join('\n')
  return { ko: (all.match(/\[KO\]/g) ?? []).length, sample: all.slice(0, 160) }
})
log('gemini calls', geminiCalls, 'translated paragraphs on page', JSON.stringify(translated))
await page.screenshot({ path: `${shots}/e2e_3_translated.png` })

// 5. Back, reload: the book and its translations are still in the browser.
await page.goBack().catch(() => {})
await page.reload({ waitUntil: 'load' })
await sleep(7000)
await enableSemantics()
const kept = await page.evaluate(() => new Promise(resolve => {
  const open = indexedDB.open('lightlib_files')
  open.onsuccess = () => {
    const req = open.result.transaction('files').objectStore('files').getAllKeys()
    req.onsuccess = () => resolve(req.result)
  }
}))
log('stored paths', JSON.stringify(kept))
log('library after reload', JSON.stringify(await page.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')].some(n => (n.textContent || '').includes('春の駅')))))
await page.screenshot({ path: `${shots}/e2e_4_reload.png` })
// 6. No Gemini key (as on a browser that only syncs): the saved
// translations still show, with no request to Gemini.
await page.evaluate(() => new Promise(resolve => {
  const open = indexedDB.open('lightlib_files')
  open.onsuccess = () => {
    const tx = open.result.transaction('files', 'readwrite')
    tx.objectStore('files').delete('/support/gemini_api_key')
    tx.oncomplete = () => { open.result.close(); resolve() }
  }
}))
await page.reload({ waitUntil: 'load' })
await sleep(7000)
await enableSemantics()
const callsBefore = geminiCalls
await openBook('春の駅')
await sleep(7000)
await enableSemantics()
const frame2 = page.frames().find(f => f.url().includes('/reader/index.html'))
// Translation was left on: it comes back by itself; tap if it is off.
const countKo = () => frame2.evaluate(() => {
  const out = []
  const walk = root => {
    for (const f of root.querySelectorAll('iframe')) {
      try { const d = f.contentDocument; if (d) { out.push(d.body?.innerText ?? ''); walk(d) } } catch {}
    }
    for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot)
  }
  walk(document)
  return (out.join('\n').match(/\[KO\]/g) ?? []).length
})
let savedOnly = await countKo()
if (savedOnly === 0) {
  const t = (await labels()).filter(l => /translat/i.test(l))
  if (t.length) { await clickLabel(t[0]); await sleep(4000) }
  savedOnly = await countKo()
}
log('no key: saved translations on page', savedOnly, 'new gemini calls', geminiCalls - callsBefore)
await page.screenshot({ path: `${shots}/e2e_5_saved_only.png` })
log('page errors', JSON.stringify(errors.slice(0, 8)))
await browser.close()
