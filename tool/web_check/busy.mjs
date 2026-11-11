// How busy the page's thread is, as a phone (CPU 4x slower): frames Flutter
// draws and time spent while nothing is touched, while the library is
// scrolled, and in the reader (idle, scrolling, turning pages).
// argv: url mock label
import puppeteer from 'puppeteer-core'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, label = ''] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
const cdp = await page.createCDPSession()
await cdp.send('Performance.enable')
await signedIn(page, mock)
// Every frame the app asks the browser for is counted (Flutter draws only when asked).
await page.evaluateOnNewDocument(() => {
  if (window.top !== window) return
  window.__frames = 0
  const raf = window.requestAnimationFrame.bind(window)
  window.requestAnimationFrame = cb => raf(t => { window.__frames++; cb(t) })
  window.__long = 0
  new PerformanceObserver(l => { for (const e of l.getEntries()) window.__long += e.duration }).observe({ type: 'longtask', buffered: true })
})
await page.goto(url, { waitUntil: 'load' })
await sleep(12000)
await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 })
const metrics = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]))
const measure = async (name, ms, act) => {
  const m0 = await metrics(); const f0 = await page.evaluate(() => [window.__frames, window.__long])
  const t0 = Date.now()
  if (act) await act()
  const rest = ms - (Date.now() - t0); if (rest > 0) await sleep(rest)
  const m1 = await metrics(); const f1 = await page.evaluate(() => [window.__frames, window.__long])
  const wall = (Date.now() - t0) / 1000
  console.log(JSON.stringify({ label, what: name, seconds: +wall.toFixed(1), frames: f1[0] - f0[0], busyPct: Math.round((m1.TaskDuration - m0.TaskDuration) / wall * 100), scriptPct: Math.round((m1.ScriptDuration - m0.ScriptDuration) / wall * 100), longTaskMs: Math.round(f1[1] - f0[1]) }))
}
const swipe = async (x, y0, y1, steps = 12) => {
  await page.touchscreen.touchStart(x, y0)
  for (let i = 1; i <= steps; i++) { await page.touchscreen.touchMove(x, y0 + (y1 - y0) * i / steps); await sleep(16) }
  await page.touchscreen.touchEnd()
}
await measure('library idle', 4000)
await measure('library scroll', 5000, async () => { for (let i = 0; i < 4; i++) { await swipe(200, 650, 250); await sleep(500) } for (let i = 0; i < 4; i++) { await swipe(200, 250, 650); await sleep(500) } })
// A book (first tile), its card, read.
await page.touchscreen.tap(72, 330); await sleep(2500)
await measure('card open idle', 3000)
await page.touchscreen.tap(170, 742)
for (let i = 0; i < 60; i++) { await sleep(500); if ((await page.title()) !== 'LightLib') break }
await sleep(4000)
await measure('reader idle (bars shown)', 4000)
await page.touchscreen.tap(196, 425); await sleep(1500)
await measure('reader idle (bars hidden)', 4000)
await measure('reader page turns x6', 6000, async () => { for (let i = 0; i < 6; i++) { await page.touchscreen.tap(40, 425); await sleep(900) } })
await page.screenshot({ path: process.argv[5] ?? '/dev/null' }).catch(() => {})
await browser.close()
