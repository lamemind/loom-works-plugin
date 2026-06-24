#!/bin/bash
# Resolve the path of the user's statusLine script from Claude Code settings.
# Prints the absolute script path on stdout, or fails with a diagnostic on stderr.
#
# Exit codes:
#   0  found → path printed
#   2  no settings file with a statusLine
#   3  statusLine present but not a `command` pointing to a real .sh file (inline command?)
set -euo pipefail

cmd=""
for SETTINGS in "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
    [ -f "$SETTINGS" ] || continue
    c=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
    if [ -n "$c" ]; then cmd="$c"; break; fi
done

if [ -z "$cmd" ]; then
    echo "resolve-target: no .statusLine.command in ~/.claude/settings*.json" >&2
    exit 2
fi

# The command may be like: `bash /abs/path/status-line.sh` — pick the last token
# that resolves to an existing file.
target=""
for tok in $cmd; do
    t="${tok%\"}"; t="${t#\"}"          # strip surrounding quotes
    t="${t/#\~/$HOME}"                  # expand leading ~
    [ -f "$t" ] && target="$t"
done

if [ -z "$target" ]; then
    echo "resolve-target: statusLine command has no script file (inline command?): $cmd" >&2
    exit 3
fi

printf '%s\n' "$target"
