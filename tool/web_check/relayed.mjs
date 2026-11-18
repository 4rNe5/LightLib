// The site that passes the sync project's requests on (Cloudflare Pages,
// built with SYNC_RELAY=/sb) on a network that does not reach the project:
// every request to the project's own address fails here, as it does
// there. Signing in is Google's button on the page (a stand-in hands the
// token), the library lists, a book comes with its progress and opens -
// all of it through /sb.
// argv: url mock shots
// url: `node serve.mjs ../../build/web 8096 ../../vercel.json / relay=<mock>`,
// or Cloudflare's own runtime on the real output (README).
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset, asked, ref } from './session.mjs'
const [url, mock, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const log = (...a) => console.log('[relayed]', ...a)
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    // The network that does not reach the project: its name leads nowhere.
    `--host-resolver-rules=MAP ${ref}.supabase.co 0.0.0.0`] })
const page = await browser.newPage()
await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 })
const errors = [], direct = []
page.on('pageerror', e => errors.push(String(e.message).slice(0, 300)))
page.on('console', m => { if (/Content Security Policy|Refused to/.test(m.text())) errors.push('console: ' + m.text().slice(0, 300)) })
page.on('request', r => { if (r.url().includes('.supabase.co')) direct.push(r.url().slice(0, 90)) })
// Not signed in; only Gemini and Google's script are stood in for here.
await signedIn(page, mock, { signIn: false })
const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(900) }
const labels = () => page.evaluate(() => [...new Set([...document.querySelectorAll('flt-semantics')].filter(n => !n.querySelector('flt-semantics')).map(n => (n.getAttribute('aria-label') || n.textContent || '').trim()).filter(Boolean))])
const find = text => page.evaluate(text => {
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => (n.getAttribute('aria-label') || n.textContent || '').trim().includes(text))
    .map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text)
const click = async text => { const at = await find(text); if (!at) throw new Error(`no "${text}" on screen`); await page.mouse.click(at.x, at.y) }

await page.goto(url, { waitUntil: 'load' }); await sleep(7000); await semantics()
log('before signing in:', JSON.stringify((await labels()).filter(l => /Sign in|All books/.test(l))))
await click('Sign in with Google'); await sleep(2500)
const overlay = await page.evaluate(() => { const o = document.getElementById('lightlib-google-sign-in'), b = document.getElementById('gsi-stand-in'); if (!o || !b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } })
log('Google\'s button over the page:', !!overlay)
await page.screenshot({ path: `${shots}/relayed_1_button.png` })
// Escape closes it without signing in; asked again, the button is back.
await page.keyboard.press('Escape'); await sleep(600)
log('closed by Escape:', await page.evaluate(() => !document.getElementById('lightlib-google-sign-in')), '| still signed out:', !!(await find('Sign in with Google')))
await click('Sign in with Google'); await sleep(2000)
const again = await page.evaluate(() => { const r = document.getElementById('gsi-stand-in').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } })
await page.mouse.click(again.x, again.y)
await sleep(9000); await semantics()
const after = await labels()
log('after signing in: overlay gone', await page.evaluate(() => !document.getElementById('lightlib-google-sign-in')), '| account', after.find(l => l.includes('owner@example.test'))?.split('\n')[0] ?? null, '| books', after.find(l => /^All books/.test(l))?.replace('\n', ' '))
await page.screenshot({ path: `${shots}/relayed_2_library.png` })
let st = await state(mock)
log('token sign-ins the project saw:', JSON.stringify(st.idTokens ?? []))
// A book: its card, then "Read" fetches the file through the relay.
const tile = await find('雨上がりの約束'); await page.mouse.click(tile.x, tile.y - 60); await sleep(1500); await semantics()
const read = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].filter(n => /^(Read|Continue reading)$/.test((n.getAttribute('aria-label') || n.textContent || '').trim())).map(n => { const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } }).sort((a, b) => b.y - a.y)[0])
await page.mouse.click(read.x, read.y)
const seen = new Set()
for (let i = 0; i < 12; i++) { await sleep(250); await semantics(); for (const l of await labels()) if (/MB \/ /.test(l)) seen.add(l) }
await sleep(9000)
const frame = page.frames().find(f => /\/reader\/(index\.html)?($|[?#])/.test(f.url()))
const chars = frame ? await frame.evaluate(() => { let n = 0; const walk = root => { for (const f of root.querySelectorAll('iframe')) n += f.contentDocument?.body?.innerText?.length ?? 0; for (const el of root.querySelectorAll('*')) if (el.shadowRoot) walk(el.shadowRoot) }; walk(document); return n }).catch(e => 'error ' + e.message) : 'no reader'
await page.screenshot({ path: `${shots}/relayed_3_reader.png` })
st = await state(mock)
// (Counted by serve.mjs; Cloudflare's own local runtime does not say.)
const relayed = await fetch(new URL('/__relayed', url)).then(r => r.json()).then(j => j.relayed).catch(() => null)
log('progress while the book came:', JSON.stringify([...seen].slice(0, 2)), '| reader text chars:', chars)
log('requests through /sb:', relayed, '| the project asked directly (stand-in rewrite):', asked.project, '| tried by its own address:', direct.length, '| book files fetched:', st.whole ?? 0, '| refused by the project:', st.refused ?? 0)
log('errors', JSON.stringify(errors.slice(0, 6)))
await browser.close()
