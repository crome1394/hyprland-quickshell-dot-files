#!/usr/bin/env bash
# NWS radar image fetcher for Quickshell RadarPill.
#
# Usage:
#   radar-fetch.sh fetch <lon> <lat> <zoom> <width> <height> [product]
#   radar-fetch.sh search <query>
#
# product: cref (default) | bref
#
# fetch → one JSON line:
#   {"ok":true,"path":"...","center_lon":..,"center_lat":..,"zoom":..,
#    "west":..,"south":..,"east":..,"north":..,"product":"cref",
#    "radar_time":"...","fetched_at":"..."}
#
# search → one JSON line:
#   {"ok":true,"lon":..,"lat":..,"zoom":..,"display_name":"...","query":"..."}
#
# Sources:
#   Radar   — NOAA OpenGeo WMS (same data as radar.weather.gov)
#   Basemap — Esri World Street Map (standard street/city map)
#   Search  — OpenStreetMap Nominatim (city/state, ZIP)
#
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/radar"
# Pixel budget for the full overscanned image (viewport × overscan, capped).
# 3840 (4K long edge) keeps full 3× isotropic overscan on large windows and
# yields sharper basemap/radar when the viewport itself is wide.
MAX_DIM="${RADAR_MAX_DIM:-3840}"
MIN_DIM=320
# Radar overlay opacity over the basemap (0–1).
RADAR_OPACITY="${RADAR_OPACITY:-0.75}"
# Default geographic overscan vs the visible viewport (3 ≈ load neighbors so
# you can pan a long way before a new download is needed).
DEFAULT_OVERSCAN="${DEFAULT_OVERSCAN:-3.0}"
USER_AGENT="quickshell-radar/1.0 (personal desktop widget; local use)"

json_err() {
    local msg="$1"
    local code="${2:-1}"
    if command -v jq >/dev/null 2>&1; then
        printf '{"ok":false,"error":%s}\n' "$(printf '%s' "$msg" | jq -Rs .)"
    else
        printf '{"ok":false,"error":"%s"}\n' "${msg//\"/\\\"}"
    fi
    exit "$code"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || json_err "missing command: $1"
}

product_layer() {
    case "$1" in
        bref|BREF|conus_bref_qcd) echo "conus_bref_qcd" ;;
        cref|CREF|conus_cref_qcd|"") echo "conus_cref_qcd" ;;
        *) json_err "unknown product: $1 (use cref or bref)" ;;
    esac
}

product_short() {
    case "$1" in
        conus_bref_qcd) echo "bref" ;;
        *) echo "cref" ;;
    esac
}

# Web-Mercator-ish geographic span for a viewport at (lon,lat,zoom).
# Returns: west south east north  (lon/lat degrees)
compute_bbox() {
    local lon="$1" lat="$2" zoom="$3" width="$4" height="$5"
    python3 - "$lon" "$lat" "$zoom" "$width" "$height" <<'PY'
import math, sys
lon = float(sys.argv[1])
lat = float(sys.argv[2])
zoom = float(sys.argv[3])
width = float(sys.argv[4])
height = float(sys.argv[5])

# Degrees per pixel at this zoom (tile size 256, full world 360° at z=0)
deg_per_px = 360.0 / (256.0 * (2.0 ** zoom))
cos_lat = max(0.2, math.cos(math.radians(lat)))
half_w = (width / 2.0) * deg_per_px / cos_lat
half_h = (height / 2.0) * deg_per_px

west = lon - half_w
east = lon + half_w
south = lat - half_h
north = lat + half_h

west = max(-180.0, min(180.0, west))
east = max(-180.0, min(180.0, east))
south = max(-85.0, min(85.0, south))
north = max(-85.0, min(85.0, north))
if east <= west:
    east = west + 0.01
if north <= south:
    north = south + 0.01
print(f"{west:.8f} {south:.8f} {east:.8f} {north:.8f}")
PY
}

# Suggest a zoom so a geographic bbox roughly fills the default viewport.
zoom_for_bbox() {
    local south="$1" north="$2" west="$3" east="$4"
    python3 - "$south" "$north" "$west" "$east" <<'PY'
import math, sys
south, north, west, east = map(float, sys.argv[1:5])
lat = (south + north) / 2.0
dlat = max(1e-6, abs(north - south))
dlon = max(1e-6, abs(east - west))
# Target ~700px map; leave margin so labels around the place are visible
target_px = 700.0
margin = 1.35
cos_lat = max(0.2, math.cos(math.radians(lat)))
# deg_per_px = 360 / (256 * 2^z) ; half-span = (px/2) * deg_per_px / cos
# Solve for z from the larger of lat/lon requirements
def z_for(span_deg, axis_px, use_cos):
    # span_deg * margin = axis_px * deg_per_px / (cos if lon else 1)
    factor = (use_cos and cos_lat) or 1.0
    deg_per_px = (span_deg * margin) / axis_px * factor
    # deg_per_px = 360 / (256 * 2^z)  →  2^z = 360 / (256 * deg_per_px)
    z = math.log2(360.0 / (256.0 * deg_per_px))
    return z

z_lat = z_for(dlat, target_px * 0.75, False)
z_lon = z_for(dlon, target_px, True)
z = min(z_lat, z_lon)
z = max(4.0, min(11.5, z))
print(f"{z:.3f}")
PY
}

clamp_dim() {
    local n="$1"
    if (( n < MIN_DIM )); then echo "$MIN_DIM"
    elif (( n > MAX_DIM )); then echo "$MAX_DIM"
    else echo "$n"
    fi
}

fetch() {
    need_cmd curl
    need_cmd python3
    need_cmd jq

    local lon="${1:-}"
    local lat="${2:-}"
    local zoom="${3:-7}"
    local width="${4:-900}"
    local height="${5:-600}"
    local product_in="${6:-cref}"
    local overscan_in="${7:-$DEFAULT_OVERSCAN}"

    [[ -n "$lon" && -n "$lat" ]] || json_err "usage: radar-fetch.sh fetch <lon> <lat> <zoom> <width> <height> [product] [overscan]"

    # Normalize numbers (reject empty / non-numeric)
    lon="$(printf '%.8f' "$lon" 2>/dev/null)" || json_err "invalid lon: $1"
    lat="$(printf '%.8f' "$lat" 2>/dev/null)" || json_err "invalid lat: $2"
    zoom="$(printf '%.6f' "$zoom" 2>/dev/null)" || json_err "invalid zoom: $3"
    overscan_in="$(printf '%.4f' "$overscan_in" 2>/dev/null)" || json_err "invalid overscan: $7"

    # Viewport pixel size (what the window shows at this zoom)
    local view_w view_h
    view_w="$(clamp_dim "${width%.*}")"
    view_h="$(clamp_dim "${height%.*}")"

    local layer
    layer="$(product_layer "$product_in")"
    local short
    short="$(product_short "$layer")"

    # Viewport geographic bbox, then expand by overscan and grow pixel size so
    # the user can pan within the buffer without reloading until they near the edge.
    #
    # Overscan is *isotropic* (same scale X/Y) so image aspect == viewport aspect
    # and QML Stretch does not warp the map.
    #
    # After the geo buffer is set, remaining MAX_DIM budget is used to supersample
    # (more pixels for the same lat/lon span → sharper basemap/radar when drawn).
    # JSON "overscan" is the *geographic* scale for QML, not the pixel ratio.
    local dims
    dims="$(python3 - "$lon" "$lat" "$zoom" "$view_w" "$view_h" "$overscan_in" "$MAX_DIM" <<'PY'
import math, sys
lon, lat, zoom = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
view_w, view_h = int(sys.argv[4]), int(sys.argv[5])
overscan = max(1.0, float(sys.argv[6]))
max_dim = int(sys.argv[7])

deg_per_px = 360.0 / (256.0 * (2.0 ** zoom))
cos_lat = max(0.2, math.cos(math.radians(lat)))
half_w = (view_w / 2.0) * deg_per_px / cos_lat
half_h = (view_h / 2.0) * deg_per_px

# Geographic isotropic overscan (same on both axes), limited by pixel budget.
max_iso = min(max_dim / float(view_w), max_dim / float(view_h))
geo_eff = min(overscan, max_iso)
geo_eff = max(1.0, geo_eff)

# Base pixels for that geo buffer, then supersample up to max_dim (keep aspect).
fw = float(view_w) * geo_eff
fh = float(view_h) * geo_eff
if fw > 0 and fh > 0 and (fw < max_dim or fh < max_dim):
    ss = min(max_dim / fw, max_dim / fh)
    if ss > 1.0:
        fw *= ss
        fh *= ss

fw = max(view_w, int(round(fw)))
fh = max(view_h, int(round(fh)))
if fw > max_dim or fh > max_dim:
    shrink = min(max_dim / float(fw), max_dim / float(fh))
    fw = max(view_w, int(math.floor(fw * shrink)))
    fh = max(view_h, int(math.floor(fh * shrink)))
    fw = min(fw, max_dim)
    fh = min(fh, max_dim)

west = lon - half_w * geo_eff
east = lon + half_w * geo_eff
south = lat - half_h * geo_eff
north = lat + half_h * geo_eff

west = max(-180.0, min(180.0, west))
east = max(-180.0, min(180.0, east))
south = max(-85.0, min(85.0, south))
north = max(-85.0, min(85.0, north))
if east <= west:
    east = west + 0.01
if north <= south:
    north = south + 0.01

print(f"{west:.8f} {south:.8f} {east:.8f} {north:.8f} {fw} {fh} {geo_eff:.6f}")
PY
)"
    # shellcheck disable=SC2086
    set -- $dims
    local west="$1" south="$2" east="$3" north="$4"
    local width="$5" height="$6"
    local overscan_eff="$7"

    mkdir -p "$CACHE_DIR"
    local base_png="${CACHE_DIR}/base.png"
    local radar_png="${CACHE_DIR}/radar.png"
    local out_png="${CACHE_DIR}/latest.png"
    local tmp_out="${CACHE_DIR}/latest.tmp.png"

    # WMS 1.3.0 + EPSG:4326 → BBOX is minLat,minLon,maxLat,maxLon
    local wms_bbox="${south},${west},${north},${east}"
    local wms_url="https://opengeo.ncep.noaa.gov/geoserver/conus/${layer}/ows"
    wms_url+="?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
    wms_url+="&LAYERS=${layer}&STYLES=&CRS=EPSG:4326"
    wms_url+="&BBOX=${wms_bbox}&WIDTH=${width}&HEIGHT=${height}"
    wms_url+="&FORMAT=image/png&TRANSPARENT=true"

    # Standard street basemap (cities/roads from the map service itself)
    local base_url="https://services.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export"
    base_url+="?bbox=${west},${south},${east},${north}"
    base_url+="&bboxSR=4326&imageSR=4326&size=${width},${height}&format=png&f=image&transparent=false"

    local curl_flags=(-fsSL --max-time 45 --retry 1 --retry-delay 1 -H "User-Agent: ${USER_AGENT}")

    if ! curl "${curl_flags[@]}" -o "$base_png" "$base_url"; then
        json_err "basemap download failed"
    fi
    if ! curl "${curl_flags[@]}" -o "$radar_png" \
        -H "Accept: image/png" \
        "$wms_url"; then
        json_err "radar WMS download failed"
    fi

    if ! file "$base_png" | grep -qi 'PNG'; then
        json_err "basemap response was not a PNG"
    fi
    if ! file "$radar_png" | grep -qi 'PNG'; then
        local hint
        hint="$(head -c 200 "$radar_png" | tr '\n' ' ')"
        json_err "radar response was not a PNG: ${hint}"
    fi

    # Simple composite: basemap + radar (no blur, no extra labels)
    python3 - "$base_png" "$radar_png" "$tmp_out" "$RADAR_OPACITY" <<'PY'
from PIL import Image
import sys

base = Image.open(sys.argv[1]).convert("RGBA")
rad = Image.open(sys.argv[2]).convert("RGBA")
out = sys.argv[3]
opacity = float(sys.argv[4])
if rad.size != base.size:
    rad = rad.resize(base.size, Image.Resampling.BILINEAR)
if opacity < 0.999:
    r, g, b, a = rad.split()
    a = a.point(lambda p: int(p * opacity))
    rad = Image.merge("RGBA", (r, g, b, a))
Image.alpha_composite(base, rad).save(out, "PNG")
PY

    mv -f "$tmp_out" "$out_png"

    local fetched_at
    fetched_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local radar_time=""
    radar_time="$(
        curl -fsSL --max-time 8 -H "User-Agent: ${USER_AGENT}" \
            "https://opengeo.ncep.noaa.gov/geoserver/conus/${layer}/ows?service=WMS&version=1.3.0&request=GetCapabilities" \
            2>/dev/null \
        | sed -n 's/.*Dimension name="time" default="\([^"]*\)".*/\1/p' \
        | head -1
    )" || true

    jq -nc \
        --arg path "$out_png" \
        --arg product "$short" \
        --arg layer "$layer" \
        --arg fetched_at "$fetched_at" \
        --arg radar_time "$radar_time" \
        --arg basemap "esri_world_street" \
        --argjson center_lon "$lon" \
        --argjson center_lat "$lat" \
        --argjson zoom "$zoom" \
        --argjson west "$west" \
        --argjson south "$south" \
        --argjson east "$east" \
        --argjson north "$north" \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson view_width "$view_w" \
        --argjson view_height "$view_h" \
        --argjson overscan "$overscan_eff" \
        '{
            ok: true,
            path: $path,
            product: $product,
            layer: $layer,
            basemap: $basemap,
            center_lon: $center_lon,
            center_lat: $center_lat,
            zoom: $zoom,
            west: $west,
            south: $south,
            east: $east,
            north: $north,
            width: $width,
            height: $height,
            view_width: $view_width,
            view_height: $view_height,
            overscan: $overscan,
            fetched_at: $fetched_at,
            radar_time: $radar_time
        }'
}

search_place() {
    need_cmd curl
    need_cmd jq
    need_cmd python3

    local query="${1:-}"
    query="$(printf '%s' "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$query" ]] || json_err "usage: radar-fetch.sh search <query>"

    local url
    # 5-digit ZIP (optional +4)
    if [[ "$query" =~ ^[0-9]{5}(-[0-9]{4})?$ ]]; then
        url="https://nominatim.openstreetmap.org/search?format=json&limit=5&addressdetails=0&countrycodes=us"
        url+="&postalcode=$(printf '%s' "$query" | jq -sRr @uri)"
    else
        url="https://nominatim.openstreetmap.org/search?format=json&limit=5&addressdetails=0&countrycodes=us"
        url+="&q=$(printf '%s' "$query" | jq -sRr @uri)"
    fi

    local raw
    raw="$(curl -fsSL --max-time 20 \
        -H "User-Agent: ${USER_AGENT}" \
        -H "Accept: application/json" \
        "$url")" || json_err "geocode request failed"

    # Prefer city/town/postcode; fall back to first hit
    local pick
    pick="$(printf '%s' "$raw" | jq -c '
        (map(select(.type == "postcode" or .addresstype == "postcode"
                    or .type == "city" or .addresstype == "city"
                    or .type == "town" or .addresstype == "town"
                    or .type == "administrative"))
         | .[0]) // .[0] // empty
    ')" || true

    if [[ -z "$pick" || "$pick" == "null" ]]; then
        # Retry without country filter (rare international / alternate names)
        url="https://nominatim.openstreetmap.org/search?format=json&limit=5&addressdetails=0"
        url+="&q=$(printf '%s' "$query" | jq -sRr @uri)"
        raw="$(curl -fsSL --max-time 20 \
            -H "User-Agent: ${USER_AGENT}" \
            -H "Accept: application/json" \
            "$url")" || json_err "geocode request failed"
        pick="$(printf '%s' "$raw" | jq -c '.[0] // empty')" || true
    fi

    if [[ -z "$pick" || "$pick" == "null" ]]; then
        json_err "no results for: $query"
    fi

    local lon lat display south north west east
    lon="$(printf '%s' "$pick" | jq -r '.lon')"
    lat="$(printf '%s' "$pick" | jq -r '.lat')"
    display="$(printf '%s' "$pick" | jq -r '.display_name // .name // "result"')"
    # Nominatim boundingbox: [south, north, west, east]
    south="$(printf '%s' "$pick" | jq -r '.boundingbox[0] // empty')"
    north="$(printf '%s' "$pick" | jq -r '.boundingbox[1] // empty')"
    west="$(printf '%s' "$pick" | jq -r '.boundingbox[2] // empty')"
    east="$(printf '%s' "$pick" | jq -r '.boundingbox[3] // empty')"

    local zoom="9.0"
    if [[ -n "$south" && -n "$north" && -n "$west" && -n "$east" ]]; then
        zoom="$(zoom_for_bbox "$south" "$north" "$west" "$east")"
    fi

    # ZIP → a bit closer; state/admin alone stays wider via bbox
    if [[ "$query" =~ ^[0-9]{5} ]]; then
        # floor zoom a touch higher for postal areas
        zoom="$(python3 -c "print(f'{max(9.0, min(11.0, float(\"$zoom\"))):.3f}')")"
    fi

    jq -nc \
        --arg query "$query" \
        --arg display_name "$display" \
        --argjson lon "$lon" \
        --argjson lat "$lat" \
        --argjson zoom "$zoom" \
        '{
            ok: true,
            query: $query,
            display_name: $display_name,
            lon: $lon,
            lat: $lat,
            zoom: $zoom
        }'
}

cmd="${1:-}"
case "$cmd" in
    fetch)
        shift
        fetch "$@"
        ;;
    search)
        shift
        search_place "$*"
        ;;
    *)
        json_err "usage: radar-fetch.sh fetch <lon> <lat> <zoom> <width> <height> [product] [overscan] | search <query>"
        ;;
esac
