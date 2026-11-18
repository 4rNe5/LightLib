#!/usr/bin/env bash
# Cloudflare Pages' build (project root "cloudflare", command
# "bash ../tool/cloudflare_build.sh", output "dist"): the web app that
# asks the sync project through this site's own /sb (cloudflare/functions),
# for networks that do not reach the project. Output: cloudflare/dist.
set -euo pipefail
cd "$(dirname "$0")/.."

SYNC_RELAY=/sb bash tool/vercel_build.sh

rm -rf cloudflare/dist
cp -R build/web cloudflare/dist
# The same headers as on Vercel.
python3 tool/cloudflare_headers.py vercel.json cloudflare/dist/_headers
# Only /sb/* runs the function: every other request is a file, and those
# are not counted against the day's function requests.
printf '{"version":1,"include":["/sb/*"],"exclude":[]}\n' > cloudflare/dist/_routes.json
