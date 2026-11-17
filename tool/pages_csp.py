#!/usr/bin/env python3
"""GitHub Pages sends no headers of ours: the policy vercel.json sends as a
header goes into the built page as a <meta> (frame-ancestors, which a
<meta> cannot carry, left out). argv: vercel.json build/web/index.html"""
import html, json, re, sys

conf, page = sys.argv[1:3]
policy = next(h['value'] for rule in json.load(open(conf))['headers']
              for h in rule['headers'] if h['key'] == 'Content-Security-Policy')
policy = '; '.join(p for p in (x.strip() for x in policy.split(';'))
                   if p and not p.startswith('frame-ancestors'))
text = open(page, encoding='utf-8').read()
content = html.escape(policy, quote=False).replace('"', '&quot;')
meta = f'<meta http-equiv="Content-Security-Policy" content="{content}">'
# After the charset (which must stay near the top of the page).
text, n = re.subn(r'(<meta charset="[^"]*">)', lambda m: m.group(1) + '\n  ' + meta, text, count=1)
if n != 1:
    sys.exit('no <meta charset> in ' + page)
open(page, 'w', encoding='utf-8').write(text)
