#!/usr/bin/env bash
# Print non-secret FreshRSS config as JSON (never prints API password).
set -euo pipefail
SECRETS="${FRESHRSS_SECRETS:-${XDG_CONFIG_HOME:-$HOME/.config}/freshrss-quickshell/freshrss.env}"
LEGACY="${HOME}/.config/quickshell/secrets/freshrss.env"
if [[ ! -f "$SECRETS" && -f "$LEGACY" ]]; then
  SECRETS="$LEGACY"
fi

BASE_URL=""
USER=""
HAS_PASSWORD="false"
SCHEME="https"
HOST=""
EXISTS="false"

if [[ -f "$SECRETS" ]]; then
  EXISTS="true"
  set -a
  # shellcheck source=/dev/null
  source "$SECRETS"
  set +a
  BASE_URL="${FRESHRSS_BASE_URL:-}"
  USER="${FRESHRSS_USER:-}"
  if [[ -n "${FRESHRSS_API_PASSWORD// }" ]]; then
    HAS_PASSWORD="true"
  fi
fi

BASE_URL="${BASE_URL%/}"
if [[ "$BASE_URL" =~ ^https://(.*)$ ]]; then
  SCHEME="https"
  HOST="${BASH_REMATCH[1]}"
elif [[ "$BASE_URL" =~ ^http://(.*)$ ]]; then
  SCHEME="http"
  HOST="${BASH_REMATCH[1]}"
elif [[ -n "$BASE_URL" ]]; then
  SCHEME="https"
  HOST="$BASE_URL"
fi

export FR_SECRETS_PATH="$SECRETS" FR_EXISTS="$EXISTS" FR_SCHEME="$SCHEME" FR_HOST="$HOST" \
  FR_BASE="$BASE_URL" FR_USER="$USER" FR_HAS_PW="$HAS_PASSWORD"
python3 - <<'PY'
import json, os
print(json.dumps({
  "ok": True,
  "path": os.environ.get("FR_SECRETS_PATH", ""),
  "exists": os.environ.get("FR_EXISTS") == "true",
  "scheme": os.environ.get("FR_SCHEME", "https"),
  "host": os.environ.get("FR_HOST", ""),
  "baseUrl": os.environ.get("FR_BASE", ""),
  "user": os.environ.get("FR_USER", ""),
  "hasPassword": os.environ.get("FR_HAS_PW") == "true",
}, ensure_ascii=False))
PY
