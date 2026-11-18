// An account no device has put covers on yet (as the owner's was): the
// library shows every book's real cover without fetching a single book -
// each is read out of its file by parts - and keeps it for other devices.
// argv: url mock shots profile
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, shots, profile = 'mobile'] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
if (profile === 'mobile') { await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true }); await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36') }
else await page.setViewport({ width: 1440, height: 900 })
const errors = []; page.on('pageerror', e => errors.push(String(e.message).slice(0, 200)))
await signedIn(page, mock)
await page.goto(url, { waitUntil: 'load' })
await sleep(4000); await page.screenshot({ path: `${shots}/bare_${profile}_1_4s.png` })
await sleep(8000); await page.screenshot({ path: `${shots}/bare_${profile}_2_12s.png` })
const st = await state(mock)
const total = st.books.reduce((s, b) => s + b.size_bytes, 0)
console.log(`[bare:${profile}]`, JSON.stringify({ dpr: await page.evaluate(() => [window.devicePixelRatio, document.querySelector('flutter-view canvas, flt-glass-pane canvas, canvas')?.width ?? null]),
  wholeBooksFetched: st.whole ?? 0, bytesReadKB: Math.round((st.ranged ?? 0) / 1024), libraryKB: Math.round(total / 1024),
  coversKept: Object.keys(st.uploads).filter(k => k.endsWith('.cover.jpg')).length, rowsWithCover: st.books.filter(b => b.cover_at).length, rowsWithDetails: st.books.filter(b => b.description != null).length,
  rangeRequests: st.calls.filter(c => /GET .*\.epub$/.test(c)).length, errors }))
await browser.close()
