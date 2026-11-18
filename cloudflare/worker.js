// Cloudflare Workers runs this for what is not a file of the site
// (wrangler.jsonc: the files in dist are served without it): /sb/* is
// passed on to the sync project, anything else is not here.
import { relay, prefix } from './relay.js'

export default {
  fetch(request, env) {
    const { pathname } = new URL(request.url)
    if (pathname.startsWith(prefix + '/')) {
      return relay(request, env.SUPABASE_URL ? { upstream: env.SUPABASE_URL } : {})
    }
    return env.ASSETS.fetch(request)
  },
}
