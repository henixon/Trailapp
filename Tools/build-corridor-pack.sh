#!/usr/bin/env bash
# build-corridor-pack.sh — build an offline PMTiles vector-tile pack covering
# a GPX route corridor.
#
# Usage:
#   Tools/build-corridor-pack.sh ROUTE.gpx [CORRIDOR_METERS] [OUTPUT.pmtiles]
#
# Example:
#   Tools/build-corridor-pack.sh maclehose.gpx 1500 maclehose.pmtiles
#
# What it does:
#   1. Computes the GPX bounding box + padding with python3.
#   2. Downloads a regional OSM extract (default: Hong Kong from Geofabrik;
#      override with GEOFABRIK_URL for other regions).
#   3. Runs planetiler restricted to the bbox (--bounds) and writes PMTiles.
#
# Requirements: java 21+, python3, curl. planetiler.jar is downloaded
# automatically on first run (override with PLANETILER_JAR).
#
# The resulting .pmtiles is the artifact the watch's future offline tile
# renderer will consume (see BUILD_NOTES.md). Transfer it to the watch as a
# separate WatchConnectivity file transfer alongside the route package.
set -euo pipefail

GPX="${1:?usage: build-corridor-pack.sh ROUTE.gpx [CORRIDOR_METERS] [OUTPUT.pmtiles]}"
WIDTH="${2:-1500}"
OUT="${3:-corridor.pmtiles}"
GEOFABRIK_URL="${GEOFABRIK_URL:-https://download.geofabrik.de/asia/hong-kong-latest.osm.pbf}"
PLANETILER_VERSION="${PLANETILER_VERSION:-0.9}"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
PBF="$WORKDIR/hong-kong-latest.osm.pbf"
PLANETILER_JAR="${PLANETILER_JAR:-$WORKDIR/planetiler.jar}"

command -v java >/dev/null || { echo "java 21+ required"; exit 1; }
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
command -v curl >/dev/null || { echo "curl required"; exit 1; }

if [ ! -f "$PLANETILER_JAR" ]; then
  echo "Downloading planetiler $PLANETILER_VERSION..."
  curl -L -o "$PLANETILER_JAR" \
    "https://github.com/onthegomap/planetiler/releases/download/v${PLANETILER_VERSION}/planetiler.jar"
fi

if [ ! -f "$PBF" ]; then
  echo "Downloading OSM extract: $GEOFABRIK_URL"
  curl -L -o "$PBF" "$GEOFABRIK_URL"
fi

# Padded bbox from the GPX track points.
BBOX="$(python3 - "$GPX" "$WIDTH" <<'EOF'
import sys, xml.etree.ElementTree as ET, math
gpx, width = sys.argv[1], float(sys.argv[2])
ns = {"g": "http://www.topografix.com/GPX/1/1"}
root = ET.parse(gpx).getroot()
pts = [(float(e.get("lat")), float(e.get("lon")))
       for e in root.findall(".//g:trkpt", ns) or root.findall(".//g:rtept", ns)]
if not pts:
    # Fallback without namespace.
    pts = [(float(e.get("lat")), float(e.get("lon")))
           for e in root.iter() if e.tag.endswith("trkpt") or e.tag.endswith("rtept")]
lats = [p[0] for p in pts]; lons = [p[1] for p in pts]
pad_lat = width / 111320.0
pad_lon = width / (111320.0 * max(0.2, math.cos(math.radians(sum(lats) / len(lats)))))
print(f"{min(lons)-pad_lon},{min(lats)-pad_lat},{max(lons)+pad_lon},{max(lats)+pad_lat}")
EOF
)"
echo "Corridor bbox (minLon,minLat,maxLon,maxLat): $BBOX"

echo "Running planetiler (this can take a few minutes)..."
java -Xmx4g -jar "$PLANETILER_JAR" \
  --osm-path="$PBF" \
  --bounds="$BBOX" \
  --maxzoom=14 \
  --output="$OUT" \
  --force

echo "Wrote $OUT"
ls -lh "$OUT"
