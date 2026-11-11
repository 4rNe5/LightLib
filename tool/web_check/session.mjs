// A signed-in browser for the web tests: the session supabase_flutter
// keeps in localStorage, and the owner's project answered by mocksb.mjs.
export const ref = 'ggagbhdqdrmomrednwfx'
export const uid = '00000000-0000-4000-8000-000000000001'
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url')
export const session = () => {
  const exp = Math.floor(Date.now() / 1000) + 36000
  const user = { id: uid, aud: 'authenticated', role: 'authenticated', email: 'owner@example.test', app_metadata: { provider: 'google' }, user_metadata: {}, created_at: '2026-11-01T00:00:00Z' }
  return { access_token: `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: uid, email: user.email, role: 'authenticated', aud: 'authenticated', exp })}.sig`,
    token_type: 'bearer', expires_in: 36000, expires_at: exp, refresh_token: 'refresh', user }
}
/** Signs [page] in before the app starts and sends the project's requests to the stand-in at [mock]. */
export async function signedIn(page, mock, { signIn = true } = {}) {
  if (signIn) await page.evaluateOnNewDocument((key, value) => { try { localStorage.setItem(key, value) } catch {} }, `sb-${ref}-auth-token`, JSON.stringify(session()))
  await page.setRequestInterception(true)
  page.on('request', req => {
    const url = req.url()
    if (url.startsWith(`https://${ref}.supabase.co/`)) return req.continue({ url: mock + url.slice(`https://${ref}.supabase.co`.length) })
    // Gemini answered here (the real API is never called): "OK" to a test,
    // each numbered paragraph back as "[KO] ...".
    if (url.startsWith('https://generativelanguage.googleapis.com/')) {
      const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type,x-goog-api-key', 'Access-Control-Allow-Methods': 'POST,GET,OPTIONS' }
      if (req.method() === 'OPTIONS') return req.respond({ status: 204, headers: cors })
      let text = 'OK'
      try {
        const body = JSON.parse(req.postData() ?? '{}')
        const user = body.contents?.[0]?.parts?.[0]?.text ?? ''
        const nl = user.indexOf('\n')
        if (user.startsWith('Translate the') && nl > 0) text = JSON.stringify({ translations: JSON.parse(user.slice(nl + 1)).paragraphs.map(p => ({ n: p.n, text: '[KO] ' + p.text })) })
        else if (body.generationConfig?.responseFormat || body.generationConfig?.responseMimeType) text = '{}'
      } catch { text = '{}' }
      return req.respond({ status: 200, headers: cors, contentType: 'application/json', body: JSON.stringify({
        candidates: [{ content: { role: 'model', parts: [{ text }] }, finishReason: 'STOP' }], usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 100, totalTokenCount: 200 } }) })
    }
    req.continue()
  })
}
export const state = async mock => (await fetch(mock + '/__state')).json()
export const reset = async mock => { await fetch(mock + '/__reset') }
