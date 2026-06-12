#!/bin/bash

# =============================================================================
# folder-create.sh - Crea una dot-folder vuota in project root
# Usage: folder-create.sh <folder-path>
# =============================================================================
#
# Fail se la folder esiste già.
# =============================================================================

set -euo pipefail

FOLDER_PATH="${1:?Usage: folder-create.sh <folder-path>}"

if [[ -e "$FOLDER_PATH" ]]; then
    echo "ERROR: folder già esistente: ${FOLDER_PATH}" >&2
    exit 1
fi

mkdir "$FOLDER_PATH"
