// The relay passes a request of this site's page on to the project as it
// came, and nothing else anywhere.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { relay, project } from '../relay.js'

const site = 'https://lightlib.pages.dev'
/** A stand-in for the project that says what it was asked. */
const recorder = (answer = () => new Response('ok')) => {
  const asked = []
  const send = async (url, init) => {
    const body = init.body ? Buffer.from(await new Response(init.body).arrayBuffer()) : null
    asked.push({ url, method: init.method, headers: Object.fromEntries(init.headers), body, redirect: init.redirect })
    return answer(url, init)
  }
  return { asked, send }
}
const own = { 'sec-fetch-site': 'same-origin' }

test('a table request goes to the project with its key, token and query', async () => {
  const { asked, send } = recorder(() => new Response('[{"md5":"a"}]', { status: 200, headers: { 'content-type': 'application/json', 'content-range': '0-0/*', 'access-control-allow-origin': '*' } }))
  const res = await relay(new Request(`${site}/sb/rest/v1/books?select=md5&deleted_at=is.null`, {
    headers: { ...own, apikey: 'sb_publishable_k', authorization: 'Bearer token', 'accept-profile': 'public', prefer: 'return=minimal', cookie: 'x=1', referer: site + '/' },
  }), { send })
  assert.equal(asked[0].url, `${project}/rest/v1/books?select=md5&deleted_at=is.null`)
  assert.equal(asked[0].headers.apikey, 'sb_publishable_k')
  assert.equal(asked[0].headers.authorization, 'Bearer token')
  assert.equal(asked[0].headers['accept-profile'], 'public')
  assert.equal(asked[0].headers.prefer, 'return=minimal')
  for (const gone of ['cookie', 'referer', 'host', 'sec-fetch-site']) assert.equal(asked[0].headers[gone], undefined, gone)
  assert.equal(asked[0].redirect, 'manual')
  assert.equal(res.status, 200)
  assert.equal(await res.text(), '[{"md5":"a"}]')
  assert.equal(res.headers.get('content-range'), '0-0/*')
  assert.equal(res.headers.get('access-control-allow-origin'), null)
})

test('a part of a book: the Range goes, the 206 and its bytes come back', async () => {
  const file = Buffer.from(Array.from({ length: 5000 }, (_, i) => i % 251))
  const { asked, send } = recorder((url, init) => {
    const [, a, b] = /bytes=(\d+)-(\d+)/.exec(init.headers.get('range'))
    return new Response(file.subarray(+a, +b + 1), { status: 206, headers: { 'content-range': `bytes ${a}-${b}/${file.length}` } })
  })
  const res = await relay(new Request(`${site}/sb/storage/v1/object/books/uid/abc.epub`, { headers: { ...own, range: 'bytes=100-1123', authorization: 'Bearer t', apikey: 'k' } }), { send })
  assert.equal(asked[0].url, `${project}/storage/v1/object/books/uid/abc.epub`)
  assert.equal(asked[0].headers.range, 'bytes=100-1123')
  assert.equal(res.status, 206)
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), file.subarray(100, 1124))
  assert.equal(res.headers.get('content-range'), 'bytes 100-1123/5000')
})

test('a book sent up arrives whole, by the same method', async () => {
  const book = Buffer.alloc(3 * 1024 * 1024, 7)
  const { asked, send } = recorder(() => new Response('{"Key":"books/uid/abc.epub"}'))
  const res = await relay(new Request(`${site}/sb/storage/v1/object/books/uid/abc.epub`, {
    method: 'POST', body: book, headers: { ...own, origin: site, 'content-length': String(book.length), 'content-type': 'application/epub+zip', 'x-upsert': 'true', authorization: 'Bearer t', apikey: 'k' },
  }), { send })
  assert.equal(asked[0].method, 'POST')
  assert.equal(asked[0].body.length, book.length)
  assert.equal(asked[0].headers['content-length'], String(book.length))
  assert.equal(asked[0].headers['content-type'], 'application/epub+zip')
  assert.equal(asked[0].headers['x-upsert'], 'true')
  assert.equal(asked[0].headers.origin, undefined)
  assert.equal(res.status, 200)
})

test('signing in with a Google token, and the project\'s refusals, pass as they are', async () => {
  const { asked, send } = recorder(() => new Response('{"error":"invalid_grant"}', { status: 400, headers: { 'content-type': 'application/json' } }))
  const res = await relay(new Request(`${site}/sb/auth/v1/token?grant_type=id_token`, { method: 'POST', body: '{"provider":"google","id_token":"x"}', headers: { ...own, origin: site, 'content-type': 'application/json', apikey: 'k' } }), { send })
  assert.equal(asked[0].url, `${project}/auth/v1/token?grant_type=id_token`)
  assert.equal(asked[0].body.toString(), '{"provider":"google","id_token":"x"}')
  assert.equal(res.status, 400)
  assert.equal(await res.text(), '{"error":"invalid_grant"}')
})

test('nothing but the project\'s three services is reached', async () => {
  const { asked, send } = recorder()
  for (const path of ['/sb', '/sb/', '/sb/functions/v1/x', '/sb/realtime/v1/websocket', '/sb/rest/v2/x', '/sb/auth/v1', '/sb//evil.example/rest/v1/x', '/sb/../rest/v1/x', '/other/rest/v1/books', '/sbrest/v1/books']) {
    const res = await relay(new Request(site + path, { headers: own }), { send })
    assert.equal(res.status, 404, path)
  }
  assert.equal(asked.length, 0)
  // Whatever the path holds, the host asked is the project's.
  await relay(new Request(`${site}/sb/rest/v1/@evil.example/x?u=https://evil.example`, { headers: own }), { send })
  assert.equal(new URL(asked[0].url).origin, project)
})

test('another site\'s page is refused', async () => {
  const { asked, send } = recorder()
  const refused = [
    { origin: 'https://evil.example' },
    { 'sec-fetch-site': 'cross-site' },
    { 'sec-fetch-site': 'same-site' },
    { origin: 'https://evil.example', 'sec-fetch-site': 'cross-site' },
  ]
  for (const headers of refused) {
    const res = await relay(new Request(`${site}/sb/rest/v1/books`, { headers }), { send })
    assert.equal(res.status, 403, JSON.stringify(headers))
  }
  assert.equal(asked.length, 0)
  // The site's own page, with or without those headers (older browsers send none).
  for (const headers of [own, { origin: site }, {}]) {
    assert.equal((await relay(new Request(`${site}/sb/rest/v1/books`, { headers }), { send })).status, 200)
  }
})

test('a redirect is handed to the browser, not followed here', async () => {
  const { send } = recorder(() => new Response(null, { status: 302, headers: { location: 'https://accounts.google.com/o/oauth2/v2/auth?x=1' } }))
  const res = await relay(new Request(`${site}/sb/auth/v1/authorize?provider=google`, { headers: own }), { send })
  assert.equal(res.status, 302)
  assert.equal(res.headers.get('location'), 'https://accounts.google.com/o/oauth2/v2/auth?x=1')
})
