#!/usr/bin/env python3
"""Makes the built page change whenever what is sent with it does.

The page's headers (the content policy, vercel.json) can change while its
bytes do not. A browser that has the page then asks "changed?", is told
"no" (304) - and Vercel's 304 carries none of those headers, so the
browser keeps the policy it got the first time. Claude's address was let
out by a new policy that way, and every browser that had opened the site
before went on refusing it.

So the page carries a line that changes with the policy and with the
commit: a new page, a full answer, the new headers.
argv: vercel.json build/web/index.html"""
import hashlib, os, re, subprocess, sys

conf, page = sys.argv[1:3]
policy = hashlib.sha256(open(conf, 'rb').read()).hexdigest()[:12]
commit = next((os.environ[k] for k in ('VERCEL_GIT_COMMIT_SHA', 'GITHUB_SHA',
                                       'WORKERS_CI_COMMIT_SHA', 'CF_PAGES_COMMIT_SHA')
               if os.environ.get(k)), '')
if not commit:
    try:
        commit = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True,
                                text=True, check=True).stdout.strip()
    except Exception:
        commit = 'unknown'
meta = f'<meta name="lightlib-build" content="{commit[:12]}.{policy}">'
text = open(page, encoding='utf-8').read()
text = re.sub(r'\n?\s*<meta name="lightlib-build"[^>]*>', '', text)
# After the charset (which must stay near the top of the page).
text, n = re.subn(r'(<meta charset="[^"]*">)', lambda m: m.group(1) + '\n  ' + meta, text, count=1)
if n != 1:
    sys.exit('no <meta charset> in ' + page)
open(page, 'w', encoding='utf-8').write(text)
print('page stamped', commit[:12], policy)
