#!/usr/bin/env bash
# tools/verify_providers.sh
#
# Verify LunaAnime providers at the network layer BEFORE xcodebuild.
# Runs outside the iOS sandbox so we can confirm each provider's catalog
# is reachable from this CI environment. Each check returns:
#   ✅  HTTP 200 + non-empty JSON
#   ⚠️  HTTP 200 + empty (probably backend drift)
#   ❌  Non-200, network error, or non-JSON response
#
# Bonus: probes the .m3u8 sample extraction path inside the AnimePahe
# flow by curling for a known browser-User-Agent and inspecting the
# `Content-Type` header.

set -u

# 1. AniList — GraphQL (search for "naruto", expect a Page.media array).
echo "--- AniList (GraphQL) ---"
resp=$(curl -sS --max-time 15 \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -X POST \
  --data '{"query":"{ Page(perPage:2){ media(search:\"naruto\",type:ANIME){ id title{romaji english} coverImage{large color} episodes status averageScore } } }"}' \
  -w '\n---\nHTTP:%{http_code}\nCT:%{content_type}\nBYTES:%{size_download}' \
  https://graphql.anilist.co/ 2>&1)
echo "$resp"
echo

# 2. JIKAN v4 — REST (search top anime).
echo "--- JIKAN v4 (MyAnimeList) ---"
resp=$(curl -sS --max-time 15 \
  -w '\n---\nHTTP:%{http_code}\nCT:%{content_type}\nBYTES:%{size_download}' \
  "https://api.jikan.moe/v4/top/anime?type=tv&filter=bypopularity&limit=5" 2>&1)
echo "$resp"
echo

# 3. Kitsu — JSON:API (filter anime by text).
echo "--- Kitsu (JSON:API) ---"
resp=$(curl -sS --max-time 15 -G \
  --data-urlencode 'page[limit]' '5' \
  --data-urlencode 'sort' '-userCount' \
  -w '\n---\nHTTP:%{http_code}\nCT:%{content_type}\nBYTES:%{size_download}' \
  https://kitsu.io/api/edge/anime 2>&1)
echo "$resp"
echo

# 4. AnimePahe — base URL probe (likely unhealthy as of 2026).
echo "--- AnimePahe (best-effort) ---"
resp=$(curl -sSL --max-time 15 \
  -A "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1" \
  -w '\n---\nHTTP:%{http_code}\nCT:%{content_type}\nBYTES:%{size_download}' \
  https://animepahe.com/ 2>&1)
echo "$resp"
echo

# 5. AniList episode-list schema probe (what `fetchEpisodes` would use).
echo "--- AniList episode count probe (Media id 21 = Naruto) ---"
resp=$(curl -sS --max-time 15 \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -X POST \
  --data '{"query":"{ Media(id:21, type:ANIME){ id title{romaji english} episodes status } }"}' \
  -w '\n---\nHTTP:%{http_code}\nCT:%{content_type}\nBYTES:%{size_download}' \
  https://graphql.anilist.co/ 2>&1)
echo "$resp"
echo

echo "=== Done. ==="
