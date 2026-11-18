// Cloudflare Pages runs this for /sb/* (and nothing else: _routes.json).
import { relay } from '../../relay.js'

export const onRequest = ({ request, env }) =>
  relay(request, env.SUPABASE_URL ? { upstream: env.SUPABASE_URL } : {})
