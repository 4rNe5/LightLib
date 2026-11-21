#!/usr/bin/env bash
# Vercel's "Ignored Build Step" (vercel.json `ignoreCommand`): exit 0
# skips the build, anything else builds.
#
# What changed is asked against the last deployment that succeeded on
# this branch (VERCEL_GIT_PREVIOUS_SHA), not the commit before HEAD: a
# branch moved forward by many commits at once (beta fast-forwarded onto
# main) was skipped when its last commit touched only notes and tests,
# and the site stayed on the old build. When that commit is not known,
# or not in Vercel's shallow clone and cannot be fetched, it builds.
paths=(lib web assets reader_web pubspec.yaml pubspec.lock vercel.json
  tool/vercel_build.sh tool/vercel_ignore.sh tool/stamp_page.py)
prev="${VERCEL_GIT_PREVIOUS_SHA:-}"
[ -n "$prev" ] || exit 1
if ! git cat-file -e "$prev^{commit}" 2>/dev/null; then
  git fetch -q --depth=1 origin "$prev" 2>/dev/null || exit 1
fi
git diff --quiet "$prev" HEAD -- "${paths[@]}"
