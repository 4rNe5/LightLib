// Mobile web, real touches only: the reader's bars, a sheet, a message
// with a button, and the page itself afterwards. argv: url epub shots
import puppeteer, { KnownDevices } from 'puppeteer-core'
const [url, epub, shots] = process.argv.slice(2)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const proxy = process.env.USE_PROXY ? [`--proxy-server=${process.env.HTTPS_PROXY}`] : []
const browser = await puppeteer.launch({ executablePath: process.env.CHROME ?? '/usr/bin/google-chrome', headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', ...proxy] })
const page = await browser.newPage()
await page.emulate(KnownDevices['Pixel 5'])
await page.setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
const errors = []
page.on('pageerror', e => errors.push(String(e.message).slice(0, 200)))
const log = (...a) => console.log('[touch]', ...a)
await page.goto(url, { waitUntil: 'load' }); await sleep(7000)
const vw = page.viewport().width, vh = page.viewport().height
const [chooser] = await Promise.all([page.waitForFileChooser({ timeout: 10000 }), page.touchscreen.tap(vw - 70, vh - 44)])
await chooser.accept([epub]); await sleep(5000)
await page.touchscreen.tap(72, 190); await sleep(1800)
await page.screenshot({ path: `${shots}/touch_0_card.png` })
// The card's button (bottom of the dialog).
await page.touchscreen.tap(170, 742); await sleep(9000)
const top = (x, y) => page.evaluate((x, y) => {
  const e = document.elementFromPoint(x, y); return e ? e.tagName.toLowerCase() + (e.closest('flt-platform-view') ? ' (platform view)' : '') : null
}, x, y)
const framePE = () => page.evaluate(() => [...document.querySelectorAll('iframe')].map(f => getComputedStyle(f).pointerEvents).join(','))
log('under the "Aa" button:', await top(vw - 24, 28), '| under the middle:', await top(vw / 2, vh / 2))
await page.screenshot({ path: `${shots}/touch_a_reader.png` })

// 1. "Aa": the reader settings sheet.
await page.touchscreen.tap(vw - 24, 28); await sleep(2500)
log('after tapping Aa: iframe pointer-events =', await framePE())
await page.screenshot({ path: `${shots}/touch_b_sheet.png` })
// 2. Tap the barrier above the sheet: it closes, the page takes taps again.
await page.touchscreen.tap(vw / 2, 81); await sleep(2000)
log('after closing the sheet: iframe pointer-events =', await framePE())
await page.screenshot({ path: `${shots}/touch_c_closed.png` })
// 2b. A tap in the middle of the page reaches the book again (the bars hide).
await page.touchscreen.tap(vw / 2, vh / 2); await sleep(1500)
await page.screenshot({ path: `${shots}/touch_c2_page_tap.png` })
await page.touchscreen.tap(vw / 2, vh / 2); await sleep(1500)
// 3. The translate button (no key: a message with a settings button).
await page.touchscreen.tap(221, 28); await sleep(2500)
await page.screenshot({ path: `${shots}/touch_d_message.png` })
log('under the message button:', await top(vw - 50, vh - 40))
// 4. The message's button opens the settings page.
await page.touchscreen.tap(vw - 50, vh - 40); await sleep(3000)
await page.screenshot({ path: `${shots}/touch_e_settings.png` })
log('errors', JSON.stringify(errors))
await browser.close()
