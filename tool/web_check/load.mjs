// First load of the web app as a phone on 4G or a desktop sees it.
// argv: url profile(mobile|desktop) [label]
// Reports: first paint, first Flutter frame, bytes, requests, memory.
import puppeteer from 'puppeteer-core'
import { readFileSync, readdirSync } from 'node:fs'
const [url, profile = 'mobile', label = ''] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
const cdp = await page.createCDPSession()
await cdp.send('Network.enable')
if (profile === 'mobile') {
  await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
  await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
  // "Fast 4G": 9 Mbit/s down, 170 ms round trip; a mid phone's CPU.
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 170, downloadThroughput: 9e6 / 8, uploadThroughput: 3e6 / 8 })
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 })
} else {
  await page.setViewport({ width: 1440, height: 900 })
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 20, downloadThroughput: 50e6 / 8, uploadThroughput: 20e6 / 8 })
}
const reqs = new Map()
cdp.on('Network.responseReceived', e => reqs.set(e.requestId, { url: e.response.url, status: e.response.status, bytes: 0 }))
cdp.on('Network.loadingFinished', e => { const r = reqs.get(e.requestId); if (r) r.bytes = e.encodedDataLength })
await page.evaluateOnNewDocument(() => {
  window.__t = {}
  new PerformanceObserver(l => { for (const e of l.getEntries()) window.__t[e.name] = Math.round(e.startTime) }).observe({ type: 'paint', buffered: true })
  window.addEventListener('flutter-first-frame', () => { window.__t.flutterFirstFrame = Math.round(performance.now()) })
})
const run = async tag => {
  reqs.clear()
  const t0 = Date.now()
  await page.goto(url, { waitUntil: 'load', timeout: 120000 })
  for (let i = 0; i < 600; i++) { if (await page.evaluate(() => window.__t.flutterFirstFrame)) break; await sleep(100) }
  const t = await page.evaluate(() => window.__t)
  await sleep(4000)
  const all = [...reqs.values()]
  const bytes = all.reduce((s, r) => s + r.bytes, 0)
  const top = all.filter(r => r.bytes > 40000).sort((a, b) => b.bytes - a.bytes).map(r => `${r.url.split('/').slice(-1)[0].slice(0, 40)} ${(r.bytes / 1024).toFixed(0)}K`)
  const heap = (await page.metrics()).JSHeapUsedSize
  // The tab's own renderer (the one holding the most), all renderers, and
  // the GPU process (CanvasKit's textures live there).
  const { processInfo } = await (await browser.target().createCDPSession()).send('SystemInfo.getProcessInfo')
  const priv = id => { try { const r = readFileSync(`/proc/${id}/smaps_rollup`, 'utf8'); return (Number(/Private_Dirty:\s+(\d+)/.exec(r)[1]) + Number(/Private_Clean:\s+(\d+)/.exec(r)[1])) / 1024 } catch { return 0 } }
  const renderers = processInfo.filter(p => p.type === 'renderer').map(p => priv(p.id))
  const tabMB = Math.round(Math.max(0, ...renderers)), renderersMB = Math.round(renderers.reduce((a, b) => a + b, 0))
  const gpuMB = Math.round(processInfo.filter(p => p.type === 'GPU').map(p => priv(p.id)).reduce((a, b) => a + b, 0))
  console.log(JSON.stringify({ label, profile, tag, firstPaint: t['first-paint'], firstContentfulPaint: t['first-contentful-paint'], flutterFirstFrame: t.flutterFirstFrame,
    requests: all.length, transferredKB: Math.round(bytes / 1024), jsHeapMB: +(heap / 1048576).toFixed(1), tabMB, renderersMB, gpuMB, top }))
}
await run('cold')
await run('warm')
await browser.close()
