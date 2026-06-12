#!/bin/bash

# =============================================================================
# probe-env.sh - Stampa env var rilevanti per diagnostica plugin
# =============================================================================

echo "=== CLAUDE_PLUGIN_* ==="
env | grep -E '^CLAUDE_PLUGIN(_|$)' | sort || echo "(nessuna)"

echo ""
echo "=== CLAUDE_PLUGIN_OPTION_* (user_config) ==="
env | grep -E '^CLAUDE_PLUGIN_OPTION_' | sort || echo "(nessuna — user_config non esportata)"

echo ""
echo "=== Argomenti passati ==="
echo "ARGS: $*"

echo ""
echo "=== PWD ==="
pwd
