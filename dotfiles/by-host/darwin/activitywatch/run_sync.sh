#!/bin/bash
set -euo pipefail

src="${AW_IMPORT_SRC:?AW_IMPORT_SRC must be set}"
dst="$HOME/.local/share/aw-import-screentime"

/bin/mkdir -p "$dst"
/usr/bin/rsync -a --delete --exclude '.venv' "$src"/ "$dst"/
/bin/chmod -R u+rwX "$dst"

cd "$dst"
exec /opt/homebrew/bin/uv run aw-import-screentime events import --since 1d --limit 0 --storefront pl --storefront us --storefront ch
