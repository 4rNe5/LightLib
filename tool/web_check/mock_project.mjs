// A stand-in for the owner's Supabase project (REST, RPC, Storage, Auth)
// for the web tests: in memory, started from a library made by
// make_library.py. argv: dir port
// GET /__state: rows and every call made; book files come slowly so a
// download's progress can be seen.
import http from 'node:http'
import { readFileSync, existsSync } from 'node:fs'
const [dir, port] = process.argv.slice(2)
export const uid = '00000000-0000-4000-8000-000000000001'
const seed = JSON.parse(readFileSync(`${dir}/library.json`, 'utf8'))
const fresh = () => ({
  books: structuredClone(seed.books), progress: structuredClone(seed.progress), translations: structuredClone(seed.translations),
  glossaries: [], settings: [], uploads: {}, removed: [], calls: [], times: [],
})
let db = fresh()
const cors = {
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,PATCH,PUT,DELETE,OPTIONS',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Range', 'Access-Control-Max-Age': '600',
}
const user = { id: uid, aud: 'authenticated', role: 'authenticated', email: 'owner@example.test', app_metadata: { provider: 'google' }, user_metadata: {}, created_at: '2026-11-01T00:00:00Z' }
const send = (res, status, body, headers = {}) => {
  const data = body === undefined ? '' : typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body)
  res.writeHead(status, { ...cors, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers, 'Content-Length': Buffer.byteLength(data) })
  res.end(data)
}
const filters = url => [...url.searchParams].filter(([k, v]) => v.startsWith('eq.')).map(([k, v]) => [k, v.slice(3)])
const pick = (rows, url) => {
  const f = filters(url)
  const cols = (url.searchParams.get('select') ?? '*').split(',').map(s => s.trim())
  return rows.filter(r => f.every(([k, v]) => String(r[k]) === v)).map(r => cols[0] === '*' ? r : Object.fromEntries(cols.map(c => [c, r[c] ?? null])))
}
const newer = (old, at) => !old || new Date(old.updated_at) < new Date(at)
const rpc = {
  put_progress: p => { const o = db.progress.find(r => r.md5 === p.p_md5); if (newer(o, p.p_updated_at)) { db.progress = db.progress.filter(r => r !== o); db.progress.push({ md5: p.p_md5, position: p.p_position, completed: p.p_completed, fraction: null, updated_at: p.p_updated_at }) } },
  put_reading: p => { const o = db.progress.find(r => r.md5 === p.p_md5); if (newer(o, p.p_updated_at)) { db.progress = db.progress.filter(r => r !== o); db.progress.push({ md5: p.p_md5, position: p.p_position, completed: p.p_completed, fraction: p.p_fraction, updated_at: p.p_updated_at }) } },
  put_glossary: p => { const o = db.glossaries.find(r => r.md5 === p.p_md5); if (newer(o, p.p_updated_at)) { db.glossaries = db.glossaries.filter(r => r !== o); db.glossaries.push({ md5: p.p_md5, data: p.p_data, updated_at: p.p_updated_at }) } },
  put_setting: p => { const o = db.settings.find(r => r.name === p.p_name); if (newer(o, p.p_updated_at)) { db.settings = db.settings.filter(r => r !== o); db.settings.push({ name: p.p_name, value: p.p_value, device: p.p_device, updated_at: p.p_updated_at }) } },
  merge_translations: p => {
    let t = db.translations.find(r => r.md5 === p.p_md5 && r.lang === p.p_lang && r.style === p.p_style)
    if (!t) db.translations.push(t = { md5: p.p_md5, lang: p.p_lang, style: p.p_style, entries: {}, entry_count: 0 })
    Object.assign(t.entries, p.p_delta); t.entry_count = Math.max(t.entry_count, Object.keys(t.entries).length); t.updated_at = new Date().toISOString()
    return [{ entry_count: t.entry_count, updated_at: t.updated_at }]
  },
}
// The first part of a multipart body, or the body itself.
const fileOf = (body, type) => {
  const m = /boundary=(.+)$/.exec(type ?? '')
  if (!m) return body
  const start = body.indexOf('\r\n\r\n') + 4
  const end = body.lastIndexOf(`\r\n--${m[1].replace(/^"|"$/g, '')}`)
  return body.subarray(start, end > start ? end : body.length)
}
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x'); const path = decodeURIComponent(url.pathname)
  if (req.method === 'OPTIONS') return send(res, 204)
  const chunks = []
  req.on('data', c => chunks.push(c))
  req.on('end', () => {
    const raw = Buffer.concat(chunks)
    const json = () => { try { return JSON.parse(raw.toString('utf8') || '{}') } catch { return {} } }
    if (path === '/__state') return send(res, 200, { ...db, uploads: Object.fromEntries(Object.entries(db.uploads).map(([k, v]) => [k, v.length])) })
    if (path === '/__reset') { db = fresh(); return send(res, 200, {}) }
    if (path === '/__set') { Object.assign(db, json()); return send(res, 200, {}) }
    db.calls.push(`${req.method} ${path}${url.search ? '?' + [...url.searchParams.keys()].join('&') : ''}`); db.times.push(Date.now())
    if (path.startsWith('/auth/v1/')) {
      if (path.endsWith('/logout')) return send(res, 204)
      if (path.endsWith('/user')) return send(res, 200, user)
      return send(res, 200, { access_token: 'x', token_type: 'bearer', expires_in: 36000, refresh_token: 'r', user })
    }
    let m
    if ((m = /^\/rest\/v1\/rpc\/(\w+)$/.exec(path))) {
      const fn = rpc[m[1]]; if (!fn) return send(res, 404, { message: 'no such function' })
      const out = fn(json()); return out === undefined ? send(res, 204) : send(res, 200, out)
    }
    if ((m = /^\/rest\/v1\/(\w+)$/.exec(path))) {
      const table = m[1]; if (!Array.isArray(db[table])) return send(res, 404, { message: 'no such table' })
      if (req.method === 'GET') {
        const rows = pick(db[table], url)
        if ((req.headers.accept ?? '').includes('vnd.pgrst.object')) return rows.length === 1 ? send(res, 200, rows[0]) : send(res, 406, { code: 'PGRST116', message: 'not one row', details: `${rows.length} rows` })
        return send(res, 200, rows)
      }
      const keys = table === 'settings' ? ['name'] : table === 'translations' ? ['md5', 'lang', 'style'] : ['md5']
      if (req.method === 'POST') {
        for (const row of [json()].flat()) {
          const old = db[table].find(r => keys.every(k => r[k] === row[k]))
          if (old) Object.assign(old, row); else db[table].push({ cover_at: null, added_at: new Date().toISOString(), ...row })
        }
        return send(res, 201)
      }
      const f = filters(url); const hit = r => f.every(([k, v]) => String(r[k]) === v)
      if (req.method === 'PATCH') { for (const r of db[table]) if (hit(r)) Object.assign(r, json()); return send(res, 204) }
      if (req.method === 'DELETE') { db[table] = db[table].filter(r => !hit(r)); return send(res, 204) }
    }
    if (path === '/storage/v1/object/books' && req.method === 'DELETE') {
      for (const p of json().prefixes ?? []) { db.removed.push(p); delete db.uploads[p.split('/').pop()] }
      return send(res, 200, [])
    }
    if ((m = /^\/storage\/v1\/object\/books\/([^/]+)\/(.+)$/.exec(path))) {
      const name = m[2]
      if (req.method === 'GET') {
        const file = `${dir}/files/${name}`
        const body = db.removed.some(p => p.endsWith('/' + name)) ? null : db.uploads[name] ?? (existsSync(file) ? readFileSync(file) : null)
        if (!body) return send(res, 400, { statusCode: '404', error: 'not_found', message: 'Object not found' })
        res.writeHead(200, { ...cors, 'Content-Type': name.endsWith('.jpg') ? 'image/jpeg' : 'application/epub+zip', 'Content-Length': body.length })
        // Slowly, so progress shows: 256 KB every 70 ms.
        let at = 0
        const step = () => { if (at >= body.length) return res.end(); res.write(body.subarray(at, at += 256 * 1024)); setTimeout(step, body.length > 1024 * 1024 ? 70 : 0) }
        return step()
      }
      db.uploads[name] = fileOf(raw, req.headers['content-type'])
      return send(res, 200, { Key: `books/${m[1]}/${name}`, Id: name })
    }
    send(res, 404, { message: `mock: ${req.method} ${path}` })
  })
}).listen(Number(port), '127.0.0.1')
