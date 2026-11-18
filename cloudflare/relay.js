// The owner's sync project, reached through this site: a network that
// does not reach *.supabase.co still reaches the site, so the app built
// for it (tool/cloudflare_build.sh, SYNC_RELAY=/sb) sends what it would
// send to the project to /sb/... here, and this passes it on unchanged -
// the key, the session's token, a Range, the body - and the answer back.
//
// It passes on to that one project only, the three services the app
// uses, and only what a page of this site itself sends.

export const project = 'https://ggagbhdqdrmomrednwfx.supabase.co'
export const prefix = '/sb'
const services = /^\/(auth|rest|storage)\/v1\//
// Not the project's business, or set again by whoever sends the request on.
// (The body's length stays: the project's storage is told how long a book is.)
const dropped = ['host', 'cookie', 'origin', 'referer', 'connection']

/** The answer to [request]; [upstream] is the project (tests pass their own, and their own [send]). */
export async function relay(request, { upstream = project, send = fetch } = {}) {
  const url = new URL(request.url)
  const path = url.pathname.slice(prefix.length)
  if (!url.pathname.startsWith(prefix + '/') || !services.test(path)) {
    return new Response('Not found', { status: 404 })
  }
  // Another site's page is not served (a browser says where a request
  // comes from; requests of this site's own pages are same-origin).
  const origin = request.headers.get('origin')
  const site = request.headers.get('sec-fetch-site')
  if ((origin && origin !== url.origin) || (site && site !== 'same-origin' && site !== 'none')) {
    return new Response('Forbidden', { status: 403 })
  }
  const headers = new Headers(request.headers)
  for (const name of dropped) headers.delete(name)
  for (const name of [...headers.keys()]) {
    if (name.startsWith('cf-') || name.startsWith('sec-') || name.startsWith('x-forwarded-')) headers.delete(name)
  }
  const bodiless = request.method === 'GET' || request.method === 'HEAD'
  const answer = await send(upstream + path + url.search, {
    method: request.method,
    headers,
    body: bodiless ? undefined : request.body,
    // A body is passed on as it comes, not gathered first (a book).
    ...(bodiless ? {} : { duplex: 'half' }),
    // A redirect is the browser's to follow.
    redirect: 'manual',
  })
  const out = new Headers(answer.headers)
  // The page is this site's own: nothing here is for other origins.
  for (const name of [...out.keys()]) {
    if (name.startsWith('access-control-')) out.delete(name)
  }
  out.set('cache-control', out.get('cache-control') ?? 'no-store')
  return new Response(answer.body, { status: answer.status, statusText: answer.statusText, headers: out })
}
