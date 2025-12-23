#!/bin/bash
# Apply log viewer patch to formatted.js
#
# Usage: ./apply_patch.sh [input.js] [output.js]

SCRIPT_DIR="$(dirname "$0")"
INPUT="${1:-/home/sdancer/webpack/formatted.js}"
OUTPUT="${2:-/home/sdancer/webpack/formatted_logged.js}"
PATCH_FILE="$SCRIPT_DIR/log_patch.js"

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo "Error: Patch file not found: $PATCH_FILE"
  exit 1
fi

echo "Applying log viewer patch..."
echo "  Input:  $INPUT"
echo "  Output: $OUTPUT"

# Get first line (shebang) and rest of file
head -1 "$INPUT" > "$OUTPUT"
cat "$PATCH_FILE" >> "$OUTPUT"
tail -n +2 "$INPUT" >> "$OUTPUT"

echo "Done! Patched file: $OUTPUT"
echo ""
echo "Start the log viewer:"
echo "  cd $SCRIPT_DIR && mix phx.server"
echo ""
echo "Run the patched Claude Code:"
echo "  node $OUTPUT"
