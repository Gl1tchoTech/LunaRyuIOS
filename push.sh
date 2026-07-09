#!/usr/bin/env bash
# push.sh — Push LunaAnime to GitHub in one command.
#
# Usage:
#   ./push.sh                                      # uses default freebuff-web URL
#   ./push.sh https://github.com/<owner>/LunaAnime.git
#
# Steps performed:
#   1. Configure 'origin' to point at the given URL (or default).
#   2. Print final local state (commit log, file count).
#   3. `git push -u origin main` so future pushes are just `git push`.
set -euo pipefail

DEFAULT_URL="https://github.com/freebuff-web/LunaAnime.git"
REMOTE_URL="${1:-$DEFAULT_URL}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository. cd into the project root first." >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  current="$(git remote get-url origin)"
  echo ">> origin exists, currently -> $current"
  if [ "$current" != "$REMOTE_URL" ]; then
    echo ">> updating origin URL to -> $REMOTE_URL"
    git remote set-url origin "$REMOTE_URL"
  fi
else
  echo ">> adding origin -> $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

echo
echo ">> Final local state"
echo "-- branch --" && git rev-parse --abbrev-ref HEAD
echo "-- working tree --" && (git status --short || true)
echo "-- recent commits --" && git log --oneline -5
echo "-- tracked files: $(git ls-files | wc -l | tr -d ' ') --"

echo
echo ">> Pushing 'main' to 'origin'…"
git push -u origin main

echo
echo ">> Done. Subsequent pushes are just: git push"
echo ">> View at: $REMOTE_URL"
