// The first 15 s of a signed-in visit as a phone (CPU 4x slower): how long
// the page's thread is busy, in what, and how many frames are drawn.
import puppeteer from 'puppeteer-core'
import { signedIn, reset } from './session.mjs'
const [url, mock, label = ''] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage()
await page.setViewport({ width: 393, height: 851, deviceScaleFactor: 2.75, isMobile: true, hasTouch: true })
await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
const cdp = await page.createCDPSession()
await cdp.send('Performance.enable'); await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 })
await signedIn(page, mock)
await page.evaluateOnNewDocument(() => { if (window.top !== window) return; window.__frames = 0; const raf = window.requestAnimationFrame.bind(window); window.requestAnimationFrame = cb => raf(t => { window.__frames++; cb(t) }); window.__long = 0; new PerformanceObserver(l => { for (const e of l.getEntries()) window.__long += e.duration }).observe({ type: 'longtask', buffered: true }); window.addEventListener('flutter-first-frame', () => { window.__ff = Math.round(performance.now()) }) })
await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 1000 }); await cdp.send('Profiler.start')
await page.goto(url, { waitUntil: 'load' }); await sleep(15000)
const { profile } = await cdp.send('Profiler.stop')
const self = new Map(); const byId = new Map(profile.nodes.map(n => [n.id, n])); let total = 0
profile.samples.forEach((id, i) => { const f = byId.get(id).callFrame; const key = f.functionName === '(idle)' ? '(idle)' : /canvaskit/.test(f.url) ? 'canvaskit' : /main\.dart\.js/.test(f.url) ? 'app script' : /sqlite|sqflite/.test(f.url) ? 'sqlite' : f.functionName || '(other)'; self.set(key, (self.get(key) ?? 0) + (profile.timeDeltas[i] ?? 0)); total += profile.timeDeltas[i] ?? 0 })
const m = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(x => [x.name, x.value]))
const f = await page.evaluate(() => [window.__frames, Math.round(window.__long), window.__ff])
console.log(JSON.stringify({ label, firstFrameMs: f[2], frames: f[0], longTaskMs: f[1], busySec: +m.TaskDuration.toFixed(1), scriptSec: +m.ScriptDuration.toFixed(1), top: [...self.entries()].filter(([k]) => k !== '(idle)').sort((a, b) => b[1] - a[1]).slice(0, 7).map(([k, v]) => `${k} ${(v / 1e6).toFixed(1)}s`) }))
await browser.close()
