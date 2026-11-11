// A signed-in visit to an account with 24 books (the stand-in project):
// what the browser fetches before the library can be used, and what the
// tab holds afterwards. argv: url mock label [profile]
import puppeteer from 'puppeteer-core'
import { readFileSync } from 'node:fs'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, label, profile = 'desktop'] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
if (profile === 'mobile') {
  await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
  await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
} else await page.setViewport({ width: 1440, height: 900 })
await signedIn(page, mock)
await page.evaluateOnNewDocument(() => { window.addEventListener('flutter-first-frame', () => { window.__ff = Math.round(performance.now()) }) })
const t0 = Date.now()
await page.goto(url, { waitUntil: 'load' })
// Until the project has been quiet for 4 s (the first sync is over).
let quietSince = Date.now(), last = 0, listedAt = null
for (;;) {
  await sleep(500)
  const st = await state(mock)
  if (listedAt === null && st.calls.some(c => /GET \/rest\/v1\/books/.test(c))) listedAt = Date.now() - t0
  if (st.calls.length !== last) { last = st.calls.length; quietSince = Date.now() }
  if (Date.now() - quietSince > 4000 || Date.now() - t0 > 120000) break
}
const settled = quietSince - t0
const st = await state(mock)
const files = st.calls.filter(c => /GET .*\.epub$/.test(c)).length, covers = st.calls.filter(c => /GET .*\.cover\.jpg$/.test(c)).length
await sleep(3000)
const mem = async () => {
  const { processInfo } = await (await browser.target().createCDPSession()).send('SystemInfo.getProcessInfo')
  const priv = id => { try { const r = readFileSync(`/proc/${id}/smaps_rollup`, 'utf8'); return (Number(/Private_Dirty:\s+(\d+)/.exec(r)[1]) + Number(/Private_Clean:\s+(\d+)/.exec(r)[1])) / 1024 } catch { return 0 } }
  const renderers = processInfo.filter(p => p.type === 'renderer').map(p => priv(p.id))
  return { tabMB: Math.round(Math.max(0, ...renderers)), gpuMB: Math.round(processInfo.filter(p => p.type === 'GPU').map(p => priv(p.id)).reduce((a, b) => a + b, 0)), heapMB: Math.round((await page.metrics()).JSHeapUsedSize / 1048576) }
}
const stored = await page.evaluate(async () => Math.round(((await navigator.storage.estimate()).usage ?? 0) / 1024))
console.log(JSON.stringify({ label, profile, firstFrameMs: await page.evaluate(() => window.__ff), bookListAskedMs: listedAt, syncQuietMs: settled, bookFilesFetched: files, coversFetched: covers, projectCalls: st.calls.length, storedKB: stored, ...(await mem()) }))
if (process.argv[6]) await page.screenshot({ path: process.argv[6] })
await browser.close()
