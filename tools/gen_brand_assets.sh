#!/usr/bin/env bash
# Regenerates every raster brand asset from the SVG sources in branding/.
#   requires: rsvg-convert (librsvg), ImageMagick `convert`, Flutter SDK
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="$ROOT/branding"; OUT="$B/out"; APP="$ROOT/app"
mkdir -p "$OUT"

rsvg-convert -w 1024 -h 1024 "$B/app_icon.svg"            -o "$OUT/icon_1024.png"          # legacy launcher (rounded)
rsvg-convert -w 1024 -h 1024 "$B/app_icon_square.svg"     -o "$OUT/icon_square_1024.png"   # iOS / stores (full bleed)
rsvg-convert -w 1024 -h 1024 "$B/adaptive_foreground.svg" -o "$OUT/adaptive_foreground.png"
rsvg-convert -w 768  -h 768  "$B/logo_mark.svg"           -o "$OUT/splash_mark.png"
rsvg-convert -w 512  -h 512  "$B/app_icon_square.svg"     -o "$OUT/play_store_icon_512.png"

# Play Store feature graphic 1024×500 (SVG text → Pango/HarfBuzz shapes Bangla
# correctly; requires the Hind Siliguri font installed for fontconfig).
rsvg-convert -w 1024 -h 500 "$B/feature_graphic.svg" -o "$OUT/feature_graphic_1024x500.png"

# Web (PWA) icons for the browser build.
rsvg-convert -w 192 -h 192 "$B/app_icon_square.svg" -o "$APP/web/icons/Icon-192.png"
rsvg-convert -w 512 -h 512 "$B/app_icon_square.svg" -o "$APP/web/icons/Icon-512.png"
rsvg-convert -w 192 -h 192 "$B/adaptive_foreground.svg" -b '#006A4E' -o "$APP/web/icons/Icon-maskable-192.png"
rsvg-convert -w 512 -h 512 "$B/adaptive_foreground.svg" -b '#006A4E' -o "$APP/web/icons/Icon-maskable-512.png"
rsvg-convert -w 64 -h 64 "$B/app_icon.svg" -o "$APP/web/favicon.png"

cd "$APP"
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
dart run flutter_native_splash:create --path=flutter_native_splash.yaml
echo "✓ brand assets regenerated"
