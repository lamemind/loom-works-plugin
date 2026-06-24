#!/bin/bash
# Remove the loom-works task-widget from a statusLine script, idempotently.
# Strips:
#   - the marked block:  # >>> loom-works:task-widget >>>  ...  # <<< loom-works:task-widget <<<
#   - any wire line ending with the marker comment: # loom-works:task-widget:wire
#
# Safe / idempotent: no markers → no-op. Begin without end → refuses (no edit).
# Used by statusline-task-unpatch, and by statusline-task-patch for clean re-sync.
set -euo pipefail

TARGET="${1:?usage: strip.sh <statusline-script>}"
[ -f "$TARGET" ] || { echo "strip: not a file: $TARGET" >&2; exit 1; }

BEGIN='# >>> loom-works:task-widget >>>'
END='# <<< loom-works:task-widget <<<'
WIRE='# loom-works:task-widget:wire'

# Guard against truncating the whole file on a half-written block.
if grep -qF "$BEGIN" "$TARGET" && ! grep -qF "$END" "$TARGET"; then
    echo "strip: begin marker without end marker — refusing to edit $TARGET" >&2
    exit 5
fi

tmp=$(mktemp)
awk -v b="$BEGIN" -v e="$END" '
    index($0, b) { skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    skip { next }
    { print }
' "$TARGET" | grep -vF "$WIRE" > "$tmp"

if cmp -s "$TARGET" "$tmp"; then
    rm -f "$tmp"
    echo "strip: no loom-works task-widget present — nothing to remove ($TARGET)"
else
    cat "$tmp" > "$TARGET"
    rm -f "$tmp"
    echo "strip: removed loom-works task-widget from $TARGET"
fi
