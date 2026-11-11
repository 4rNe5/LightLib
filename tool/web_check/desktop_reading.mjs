// A horizontal book in a desktop window: the column's width when
// scrolling, two pages side by side when turning, the keys and the wheel.
import puppeteer from 'puppeteer-core'
const [url, epub, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage(); await page.setViewport({ width: 1440, height: 900 })
const errors = []; page.on('pageerror', e => errors.push(String(e.message).slice(0, 200)))
await page.goto(url, { waitUntil: 'load' }); await sleep(6000)
const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(700) }
const find = (text, exact = false, lowest = false) => page.evaluate((text, exact, lowest) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => exact ? label(n) === text : label(n).includes(text)).map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => lowest ? b.y - a.y : a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text, exact, lowest)
const click = async (text, exact, lowest) => { await semantics(); const at = await find(text, exact, lowest); if (!at) { console.log('!! no', text); return } await page.mouse.click(at.x, at.y) }
const [chooser] = await Promise.all([page.waitForFileChooser({ timeout: 15000 }), click('Add EPUB')])
await chooser.accept([epub]); await sleep(4000)
await click('The Station in Spring'); await sleep(1500)
await click('Read', true, true); await sleep(7000)
const frame = page.frames().find(f => f.url().includes('/reader/index.html'))
// Where the text column sits in the window.
const column = () => frame.evaluate(() => {
  const view = document.querySelector('foliate-view'); let out = null
  const walk = root => { for (const f of root.querySelectorAll('iframe')) { const r = f.getBoundingClientRect(); const p = f.contentDocument?.querySelector('p'); if (p) { const pr = p.getBoundingClientRect(); out = { frameLeft: Math.round(r.left), frameWidth: Math.round(r.width), lineWidth: Math.round(pr.width) } } } for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot) }
  walk(document); return out
})
console.log('[desk] scrolled: column', JSON.stringify(await column()))
await page.screenshot({ path: `${shots}/desk_read_1_scrolled.png` })
// Space scrolls a page; the position moves.
const fraction = async () => { await semantics(); return page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).filter(t => /^\d+%$/.test(t))[0] ?? null) }
await page.mouse.click(720, 500); await sleep(500); await page.mouse.click(720, 500); await sleep(500)
const before = await fraction()
await page.keyboard.press('PageDown'); await sleep(900); await page.keyboard.press('Space'); await sleep(1200)
await page.mouse.click(720, 500); await sleep(700)
console.log('[desk] keys in the page (scrolling):', before, '->', await fraction())
// Pages: two side by side.
await page.mouse.click(1416, 28); await sleep(1500)
await click('Pages', false); await sleep(2500)
await page.keyboard.press('Escape'); await sleep(1200)
console.log('[desk] pages: column', JSON.stringify(await column()))
await page.screenshot({ path: `${shots}/desk_read_2_pages.png` })
await page.mouse.click(720, 500); await sleep(600)
const p0 = await fraction()
await page.mouse.click(720, 500); await sleep(400)
await page.keyboard.press('ArrowRight'); await sleep(1000)
await page.mouse.click(720, 500); await sleep(600)
const p1 = await fraction()
await page.mouse.click(720, 500); await sleep(400)
await page.mouse.move(720, 500); await page.mouse.wheel({ deltaY: 120 }); await sleep(1200)
await page.mouse.click(720, 500); await sleep(600)
console.log('[desk] pages: arrow', p0, '->', p1, '| wheel ->', await fraction())
await page.screenshot({ path: `${shots}/desk_read_3_turned.png` })
console.log('[desk] errors', JSON.stringify(errors))
await browser.close()
