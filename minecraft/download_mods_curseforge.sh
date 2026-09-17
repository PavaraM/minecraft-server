#!/usr/bin/env bash
#
# download_mods_curseforge.sh — Fetch the mods that Modrinth couldn't match
# (or had no compatible version for) from CurseForge instead.
#
# Requires: curl, jq, and a CurseForge API key.
#
# Getting a key:
#   1. Sign in at https://console.curseforge.com/
#   2. Go to "API Keys" and generate one.
#   3. Export it before running this script:
#        export CURSEFORGE_API_KEY="your-key-here"
#
# Usage:
#   export CURSEFORGE_API_KEY="..."
#   ./download_mods_curseforge.sh [output_dir]
#
# Behavior mirrors the Modrinth script: search by cleaned mod name, find a
# file matching the target Minecraft version + Fabric loader, download it.
# Anything unmatched is skipped (not fatal) and logged for manual lookup.

set -uo pipefail

# ---- Config ---------------------------------------------------------------

GAME_VERSION="26.2"     # Minecraft version to match against
MC_GAME_ID=432             # CurseForge's internal ID for Minecraft
MOD_CLASS_ID=6              # CurseForge's internal ID for the "Mods" category
FABRIC_LOADER_TYPE=4        # CurseForge modLoaderType enum value for Fabric
OUTPUT_DIR="${1:-./mods}"
API_BASE="https://api.curseforge.com/v1"

# These are the mods the Modrinth script couldn't resolve. Adjust freely.
MOD_LIST=(
  "1.3.1-TPA_mod-26.2.jar"
  "epic-structures-igloo-1.0.5 1.21+ 26+.jar"
  "ForgeConfigAPIPort-v26.2.1-mc26.2.x-Fabric.jar"
  "friendsandfoes-fabric-4.0.27+mc26.2.jar"
  "gravestones-1.4.2+26.2+A.jar"
  "IllagerInvasion-v26.2.0-mc26.2.x-Fabric.jar"
  "ingeniumapi-1.0.2-FABRIC-MC-26.X.jar"
  "jauml-fabric-26.2-2.1.1.jar"
  "muchmoredungeons-fabric-26.2-1.2.0.jar"
  "MutantMonsters-v26.2.2-mc26.2.x-Fabric.jar"
  "MutantsZombies-1.3.3-Fabric-mc26.1.jar"
  "placeholder-api-3.1.0-beta.1+26.2.jar"
  "pneumonocore-1.3.1+26.2+A.jar"
  "PuzzlesLib-v26.2.3-mc26.2.x-Fabric.jar"
  "ResourcefulLib-5.0.3.jar"
  "roomfortwo-fabric-26.2-0.2.0.jar"
  "SkinsRestorer-Mod-Fabric-15.12.5.jar"
  "treechopmod-1.2.0+mc26.2.x.jar"
)

# Optional: force a specific search term for mods whose display name
# doesn't search well as-is. Format: "original_name=>search_term"
SEARCH_OVERRIDES=(
  "1.3.1-TPA_mod-26.2.jar=>tpa"
  "epic-structures-igloo-1.0.5 1.21+ 26+.jar=>epic structures igloo"
  "ForgeConfigAPIPort-v26.2.1-mc26.2.x-Fabric.jar=>forge config api port"
  "jauml-fabric-26.2-2.1.1.jar=>jauml"
  "ingeniumapi-1.0.2-FABRIC-MC-26.X.jar=>ingenium"
  "placeholder-api-3.1.0-beta.1+26.2.jar=>placeholder api"
  "PuzzlesLib-v26.2.3-mc26.2.x-Fabric.jar=>puzzles lib"
  "SkinsRestorer-Mod-Fabric-15.12.5.jar=>skinsrestorer"
)

# ---- Setup ------------------------------------------------------------

command -v curl >/dev/null 2>&1 || { echo "Error: curl is required." >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Error: jq is required."   >&2; exit 1; }

if [[ -z "${CURSEFORGE_API_KEY:-}" ]]; then
  echo "Error: CURSEFORGE_API_KEY is not set." >&2
  echo "Get a key at https://console.curseforge.com/ and run:" >&2
  echo "  export CURSEFORGE_API_KEY=\"your-key-here\"" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
SKIPPED_LOG="$OUTPUT_DIR/skipped_mods.log"
: > "$SKIPPED_LOG"

downloaded=0
skipped=0

# ---- Helpers ------------------------------------------------------------

# Calls the CurseForge API and separates the HTTP status from the body,
# so a non-JSON error response (403, 429, HTML error page, etc.) shows up
# as a clear message instead of a cryptic jq parse error.
# Usage: api_get <url> [curl extra args...]
# Sets globals: API_STATUS, API_BODY
api_get() {
  local url="$1"; shift
  local tmp
  tmp=$(mktemp)
  API_STATUS=$(curl -s -G -o "$tmp" -w "%{http_code}" \
    -H "x-api-key: $CURSEFORGE_API_KEY" \
    -H "Accept: application/json" \
    "$@" "$url")
  API_BODY=$(cat "$tmp")
  rm -f "$tmp"
}

# One-time sanity check so a bad/revoked key fails fast with a clear
# message instead of 34 confusing per-mod warnings.
verify_api_key() {
  api_get "$API_BASE/games" --data-urlencode "pageSize=1"
  if [[ "$API_STATUS" == "401" || "$API_STATUS" == "403" ]]; then
    echo "Error: CurseForge rejected the API key (HTTP $API_STATUS)." >&2
    echo "Response: $API_BODY" >&2
    echo "" >&2
    echo "This usually means the key is invalid, revoked, or malformed." >&2
    echo "Generate a fresh one at https://console.curseforge.com/ and re-export it:" >&2
    echo "  export CURSEFORGE_API_KEY=\"your-key-here\"" >&2
    exit 1
  elif [[ "$API_STATUS" != "200" ]]; then
    echo "Warning: unexpected response from CurseForge during key check (HTTP $API_STATUS)." >&2
    echo "Response: $API_BODY" >&2
    echo "Continuing anyway — individual mod lookups may fail." >&2
  else
    echo "CurseForge API key verified OK."
  fi
}

clean_name() {
  local name="$1"
  name="${name%.jar}"
  name="${name//_/ }"
  name="${name//-/ }"
  name="${name//+/ }"
  name=$(echo "$name" | sed -E \
    -e 's/\b[vV]?[0-9]+(\.[0-9]+)+([a-zA-Z0-9.]*)?\b//g' \
    -e 's/\b(fabric|forge|mc|MC|beta|alpha|x)\b//gi' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^ *//; s/ *$//')
  echo "$name"
}

get_override() {
  local orig="$1"
  local entry
  for entry in "${SEARCH_OVERRIDES[@]}"; do
    if [[ "${entry%%=>*}" == "$orig" ]]; then
      echo "${entry#*=>}"
      return 0
    fi
  done
  return 1
}

# ---- Main loop ------------------------------------------------------------

verify_api_key

for mod in "${MOD_LIST[@]}"; do
  echo "----------------------------------------------------------------"
  echo "Processing: $mod"

  query=$(get_override "$mod") || query=$(clean_name "$mod")
  echo "  Search query: '$query'"

  # 1. Search CurseForge for a matching mod
  api_get "$API_BASE/mods/search" \
    --data-urlencode "gameId=$MC_GAME_ID" \
    --data-urlencode "classId=$MOD_CLASS_ID" \
    --data-urlencode "searchFilter=$query" \
    --data-urlencode "sortField=2" \
    --data-urlencode "sortOrder=desc" \
    --data-urlencode "pageSize=5"

  if [[ "$API_STATUS" != "200" ]]; then
    echo "  WARNING: search request failed (HTTP $API_STATUS): $API_BODY"
    echo "$mod  ->  search request failed (HTTP $API_STATUS: $API_BODY)" >> "$SKIPPED_LOG"
    skipped=$((skipped + 1))
    continue
  fi

  mod_id=$(echo "$API_BODY" | jq -r '.data[0].id // empty')
  mod_name=$(echo "$API_BODY" | jq -r '.data[0].name // empty')

  if [[ -z "$mod_id" ]]; then
    echo "  WARNING: No CurseForge project found for '$mod' (query: '$query')."
    echo "$mod  ->  no project match (query: '$query')" >> "$SKIPPED_LOG"
    skipped=$((skipped + 1))
    continue
  fi
  echo "  Matched project: $mod_name (id: $mod_id)"

  # 2. Find a file matching game version + Fabric loader
  api_get "$API_BASE/mods/$mod_id/files" \
    --data-urlencode "gameVersion=$GAME_VERSION" \
    --data-urlencode "modLoaderType=$FABRIC_LOADER_TYPE" \
    --data-urlencode "pageSize=1"

  if [[ "$API_STATUS" != "200" ]]; then
    echo "  WARNING: files request failed (HTTP $API_STATUS): $API_BODY"
    echo "$mod  ->  files request failed for project '$mod_name' (HTTP $API_STATUS: $API_BODY)" >> "$SKIPPED_LOG"
    skipped=$((skipped + 1))
    continue
  fi

  file_id=$(echo "$API_BODY" | jq -r '.data[0].id // empty')
  file_name=$(echo "$API_BODY" | jq -r '.data[0].fileName // empty')
  download_url=$(echo "$API_BODY" | jq -r '.data[0].downloadUrl // empty')

  # Some CurseForge mods have downloadUrl disabled by the author; fall back
  # to constructing it from the file id if missing.
  if [[ -z "$download_url" && -n "$file_id" ]]; then
    id_prefix="${file_id:0:4}"
    id_suffix="${file_id:4}"
    download_url="https://edge.forgecdn.net/files/${id_prefix}/${id_suffix}/${file_name}"
  fi

  if [[ -z "$file_id" || -z "$download_url" ]]; then
    echo "  WARNING: No file found for '$mod_name' matching Fabric / $GAME_VERSION."
    echo "$mod  ->  matched project '$mod_name' (id: $mod_id) but no compatible file (fabric $GAME_VERSION)" >> "$SKIPPED_LOG"
    skipped=$((skipped + 1))
    continue
  fi

  # 3. Download
  dest="$OUTPUT_DIR/${file_name:-$mod}"
  echo "  Downloading: $download_url"
  if curl -s -L -o "$dest" "$download_url"; then
    echo "  Saved to: $dest"
    downloaded=$((downloaded + 1))
  else
    echo "  WARNING: Download failed for '$mod' ($download_url)."
    echo "$mod  ->  download request failed ($download_url)" >> "$SKIPPED_LOG"
    skipped=$((skipped + 1))
  fi

  sleep 0.3  # be polite to the API
done

echo "----------------------------------------------------------------"
echo "Done. Downloaded: $downloaded   Skipped: $skipped"
if [[ "$skipped" -gt 0 ]]; then
  echo "See $SKIPPED_LOG for mods that need manual attention."
fi