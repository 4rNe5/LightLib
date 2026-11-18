// An EPUB dropped on the window is added (drag events made in the page).
import puppeteer from 'puppeteer-core'
import { readFileSync } from 'node:fs'
const [url, epub, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] })
const page = await browser.newPage(); await page.setViewport({ width: 1440, height: 900 })
const errors = []; page.on('pageerror', e => errors.push(String(e.message).slice(0, 200)))
await page.goto(url, { waitUntil: 'load' }); await sleep(6000)
const b64 = readFileSync(epub).toString('base64')
const fire = (type, hold) => page.evaluate((type, b64) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0))
  const data = new DataTransfer(); data.items.add(new File([bytes], 'dropped.epub', { type: 'application/epub+zip' }))
  document.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: data }))
}, type, b64)
await fire('dragover'); await sleep(500)
await page.screenshot({ path: `${shots}/drop_1_over.png` })
await fire('drop'); await sleep(5000)
const kept = await page.evaluate(() => new Promise(resolve => { const open = indexedDB.open('lightlib_files'); open.onsuccess = () => { const req = open.result.transaction('files').objectStore('files').getAllKeys(); req.onsuccess = () => resolve(req.result) } }))
console.log('[drop] kept:', JSON.stringify(kept.filter(k => /^\/books\/|covers/.test(String(k)))), '| errors', JSON.stringify(errors))
await page.screenshot({ path: `${shots}/drop_2_added.png` })
await browser.close()
