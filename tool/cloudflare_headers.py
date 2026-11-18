#!/usr/bin/env python3
"""The headers vercel.json sends, as Cloudflare Pages' _headers file (one
policy for every host). argv: vercel.json out/_headers"""
import json, re, sys

conf, out = sys.argv[1:3]
lines = []
for rule in json.load(open(conf))['headers']:
    source = rule['source']
    if source == '/(.*)':
        paths = ['/*']
    else:
        # "/(a|b|c)?": the site's first page and those files.
        m = re.fullmatch(r'/\(([^()]+)\)\?', source)
        if not m:
            sys.exit('a source this does not know: ' + source)
        paths = ['/'] + ['/' + name for name in m.group(1).split('|')]
    for path in paths:
        lines.append(path)
        for h in rule['headers']:
            line = f"  {h['key']}: {h['value']}"
            if len(line) > 2000:
                sys.exit('a header too long for _headers: ' + h['key'])
            lines.append(line)
if sum(1 for l in lines if not l.startswith(' ')) > 100:
    sys.exit('more rules than _headers takes')
open(out, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
