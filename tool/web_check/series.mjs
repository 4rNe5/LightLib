// A series made on the web, in headless Chrome with real clicks, signed
// in against the stand-in project: two of the account's books (neither
// is in this browser) are chosen from a tile's menu and by a click,
// named and grouped; the row shows; the account has the series under
// the books' MD5s; the row's menu undoes it, and the account is told.
// argv: url mock shots
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log('[series]', ...a)
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--lang=en-US'] })
const page = await browser.newPage()
await page.setViewport({ width: 1440, height: 900 })
const errors = []
page.on('pageerror', e => errors.push(String(e.message ?? e).slice(0, 300)))
page.on('console', m => { if (m.type() === 'error' || /Content Security Policy|Refused/.test(m.text())) errors.push('console: ' + m.text().slice(0, 300)) })
await signedIn(page, mock)

const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(800) }
const find = (text, { exact = false } = {}) => page.evaluate((text, exact) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => { const l = label(n); return exact ? l === text : l.includes(text) })
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text, exact)
const tapText = async (text, opts) => { await semantics(); const at = await find(text, opts); if (!at) { log(`!! no "${text}" on screen`); return null } await page.mouse.click(at.x, at.y); return at }
const series = async () => {
  const row = (await state(mock)).settings.find(s => s.name === 'series')
  return row ? { device: row.device, value: JSON.parse(row.value || '{}') } : null
}

await page.goto(url, { waitUntil: 'load' }); await sleep(9000); await semantics()
const md5 = Object.fromEntries((await state(mock)).books.map(b => [b.title, b.md5]))
// Two books whose tiles are on screen now (the grid, not the card of the
// last book read).
const onScreen = []
for (const title of Object.keys(md5)) {
  // (Not a title another one begins with: "春の駅" and "春の駅 2".)
  if (Object.keys(md5).some(t => t !== title && t.startsWith(title))) continue
  const at = await find(title)
  if (at && at.y > 380 && at.y < 860) onScreen.push(title)
}
const [one, two] = onScreen
if (!two) { log('!! fewer than two tiles on screen', JSON.stringify(onScreen)); await browser.close(); process.exit(1) }
log('before: the account has a series setting:', !!(await series()), '| book files in this browser: 0 fetched')

// A tile's menu starts the choosing; a click adds another.
const at = await find(one)
await page.mouse.click(at.x, at.y - 90, { button: 'right' }); await sleep(800)
await tapText('Select', { exact: true }); await sleep(700); await semantics()
log('the bar after one:', !!(await find('1 selected')))
const at2 = await find(two)
await page.mouse.click(at2.x, at2.y - 90); await sleep(700); await semantics()
log('after a click on another tile:', !!(await find('2 selected')), '| no card opened:', !(await find('Read', { exact: true })))
await page.screenshot({ path: `${shots}/series_1_chosen.png` })

await tapText('Group as a series'); await sleep(900)
// (The field comes with a name the titles suggest: replaced.)
await page.keyboard.down('Control'); await page.keyboard.press('KeyA'); await page.keyboard.up('Control')
await page.keyboard.type('My series', { delay: 15 }); await sleep(300)
await tapText('Save', { exact: true }); await sleep(3500); await semantics()
log('the row shows:', !!(await find('My series')), '| "2 volumes":', !!(await find('2 volumes')))
await page.screenshot({ path: `${shots}/series_2_grouped.png` })
let s = await series()
log('on the account:', s ? `from ${s.device}` : 'NOTHING',
  '| both books under the name:', !!s && [md5[one], md5[two]].every(m => (s.value['My series'] ?? []).includes(m)))

// Kept over a reload (the browser's own copy of the map).
await page.reload({ waitUntil: 'load' }); await sleep(9000); await semantics()
log('after a reload the row is there:', !!(await find('My series')))

// Undone from the row.
// (The engine puts a label in the node's text, not always in aria-label;
// and the book being read has a "More" of its own: the series' is the
// one on the line of its name.)
const menu = await page.evaluate(() => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const name = [...document.querySelectorAll('flt-semantics')].filter(n => label(n) === '2 volumes')
    .map(n => n.getBoundingClientRect()).find(r => r.width > 0)
  const buttons = [...document.querySelectorAll('flt-semantics[role="button"]')].filter(n => label(n) === 'More')
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0)
  if (!name || !buttons.length) return null
  const r = buttons.sort((a, b) => Math.abs(a.y - name.y) - Math.abs(b.y - name.y))[0]
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
})
if (menu) await page.mouse.click(menu.x, menu.y); else log('!! no menu on the row')
await sleep(800)
await tapText('Ungroup series'); await sleep(3500); await semantics()
log('the row is gone:', !(await find('2 volumes')))
s = await series()
log('the account told they are out:', !!s && [md5[one], md5[two]].every(m => (s.value[''] ?? []).includes(m)), '| nothing left under the name:', !!s && !s.value['My series'])
await page.screenshot({ path: `${shots}/series_3_undone.png` })
log('page errors', JSON.stringify(errors.slice(0, 8)))
await browser.close()
