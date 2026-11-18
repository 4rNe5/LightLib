// The tab while a book is being read (after the library settled).
// argv: url mock label(before|after)
import puppeteer from 'puppeteer-core'
import { readFileSync } from 'node:fs'
import { signedIn, state, reset } from './session.mjs'
const [url, mock, label] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
await reset(mock)
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage(); await page.setViewport({ width: 1440, height: 900 })
await signedIn(page, mock)
await page.goto(url, { waitUntil: 'load' })
let quietSince = Date.now(), last = 0
for (;;) { await sleep(500); const st = await state(mock); if (st.calls.length !== last) { last = st.calls.length; quietSince = Date.now() } if (Date.now() - quietSince > 4000) break }
const semantics = async () => { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await sleep(700) }
const find = (text, exact) => page.evaluate((text, exact) => {
  const label = n => (n.getAttribute('aria-label') || n.textContent || '').trim()
  const nodes = [...document.querySelectorAll('flt-semantics')].filter(n => exact ? label(n) === text : label(n).includes(text)).map(n => n.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0).sort((a, b) => a.width * a.height - b.width * b.height)
  return nodes.length ? { x: nodes[0].x + nodes[0].width / 2, y: nodes[0].y + nodes[0].height / 2 } : null
}, text, exact)
await semantics()
let at = await find('黄昏の天文台'); await page.mouse.click(at.x, at.y - 60); await sleep(1500)
if (label === 'after') { await semantics(); at = (await find('Read', true)) ?? (await find('Continue reading', true)); const all = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].filter(n => /^(Read|Continue reading)$/.test((n.getAttribute('aria-label') || n.textContent || '').trim())).map(n => { const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } })); const b = all.sort((a, b) => b.y - a.y)[0]; await page.mouse.click(b.x, b.y) }
await sleep(12000)
const { processInfo } = await (await browser.target().createCDPSession()).send('SystemInfo.getProcessInfo')
const priv = id => { try { const r = readFileSync(`/proc/${id}/smaps_rollup`, 'utf8'); return (Number(/Private_Dirty:\s+(\d+)/.exec(r)[1]) + Number(/Private_Clean:\s+(\d+)/.exec(r)[1])) / 1024 } catch { return 0 } }
const renderers = processInfo.filter(p => p.type === 'renderer').map(p => priv(p.id))
console.log(JSON.stringify({ label, reading: !!page.frames().find(f => f.url().includes('/reader/index.html')), tabMB: Math.round(Math.max(0, ...renderers)), gpuMB: Math.round(processInfo.filter(p => p.type === 'GPU').map(p => priv(p.id)).reduce((a, b) => a + b, 0)), heapMB: Math.round((await page.metrics()).JSHeapUsedSize / 1048576) }))
await browser.close()
