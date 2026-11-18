// Static server like Vercel: vercel.json's headers, brotli for text and
// wasm (compressed once, kept), ETag revalidation.
import http from 'node:http'
import zlib from 'node:zlib'
import crypto from 'node:crypto'
import { readFileSync, existsSync, statSync } from 'node:fs'
import { join, extname } from 'node:path'
// argv: root port vercel.json|none [prefix] - "none" and a prefix
// (/LightLib/) stand for a host that sends no headers of ours and serves
// the app under a path (GitHub Pages).
// A fifth, relay=<project's address>, makes this the site that passes the
// sync project's requests on (Cloudflare Pages): /sb/* is answered by the
// same code that runs there (cloudflare/relay.js).
const [root, port, vercelJson, prefix = '/', relayArg = ''] = process.argv.slice(2)
const upstream = relayArg.startsWith('relay=') ? relayArg.slice(6) : null
const { relay } = upstream ? await import('../../cloudflare/relay.js') : {}
const { Readable } = await import('node:stream')
let relayed = 0
const conf = vercelJson === 'none' ? { headers: [] } : JSON.parse(readFileSync(vercelJson, 'utf8'))
const rules = conf.headers.map(h => ({ re: new RegExp('^' + h.source + '$'), headers: Object.fromEntries(h.headers.map(x => [x.key, x.value])) }))
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.css': 'text/css', '.tsv': 'text/tab-separated-values', '.svg': 'image/svg+xml', '.symbols': 'text/plain', '.bin': 'application/octet-stream' }
const squeeze = new Set(['.html', '.js', '.mjs', '.wasm', '.json', '.css', '.tsv', '.svg', '.otf', '.ttf', '.bin', '.symbols'])
const cache = new Map()
http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (p === '/__relayed') { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ relayed })) }
  if (upstream && p.startsWith('/sb/')) {
    relayed++
    const bodiless = req.method === 'GET' || req.method === 'HEAD'
    const headers = new Headers(); for (const [k, v] of Object.entries(req.headers)) if (k !== 'connection' && k !== 'transfer-encoding') headers.set(k, [].concat(v).join(', '))
    relay(new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers, body: bodiless ? undefined : Readable.toWeb(req), ...(bodiless ? {} : { duplex: 'half' }) }), { upstream })
      .then(answer => {
        const out = {}; answer.headers.forEach((v, k) => { if (k !== 'content-encoding' && k !== 'transfer-encoding' && k !== 'connection') out[k] = v })
        res.writeHead(answer.status, out)
        if (answer.body) Readable.fromWeb(answer.body).pipe(res); else res.end()
      })
      .catch(e => { res.writeHead(502); res.end(String(e)) })
    return
  }
  const headers = {}
  for (const r of rules) if (r.re.test(p)) Object.assign(headers, r.headers)
  if (!('Cache-Control' in headers)) headers['Cache-Control'] = 'public, max-age=0, must-revalidate'
  if (!p.startsWith(prefix)) { res.writeHead(404, headers); return res.end('404') }
  p = '/' + p.slice(prefix.length)
  if (p.endsWith('/')) p += 'index.html'
  const f = join(root, p)
  if (!existsSync(f) || !statSync(f).isFile()) { res.writeHead(404, headers); return res.end('404') }
  let e = cache.get(f)
  const st = statSync(f)
  if (!e || e.mtime !== st.mtimeMs) {
    const raw = readFileSync(f)
    const br = squeeze.has(extname(f)) && raw.length > 1024
    const body = br ? zlib.brotliCompressSync(raw, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 9 } }) : raw
    e = { mtime: st.mtimeMs, body, br, etag: '"' + crypto.createHash('md5').update(raw).digest('hex') + '"' }
    cache.set(f, e)
  }
  headers.ETag = e.etag
  if (req.headers['if-none-match'] === e.etag) { res.writeHead(304, headers); return res.end() }
  headers['Content-Type'] = types[extname(f)] ?? 'application/octet-stream'
  if (e.br) headers['Content-Encoding'] = 'br'
  headers['Content-Length'] = e.body.length
  res.writeHead(200, headers)
  res.end(e.body)
}).listen(Number(port), '127.0.0.1')
