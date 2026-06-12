#!/bin/bash

# =============================================================================
# scratch-new.sh - Crea uno scratch in project root
# Usage: scratch-new.sh <slug>
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================
#
# Crea: {PROJECT_ROOT}/.YY-MM-DD-{slug}/
#
# Fail se folder esiste (collisione stesso giorno + stesso slug).
# Slug atteso kebab-case [a-z0-9-]+, validato dalla skill.
# =============================================================================

set -euo pipefail

SLUG="${1:?Usage: scratch-new.sh <slug>}"

if [[ ! "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "ERROR: slug non valido: '${SLUG}' (atteso kebab-case [a-z0-9-]+)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DATE=$(date +%y-%m-%d)
SCRATCH_NAME=".${DATE}-${SLUG}"
SCRATCH_PATH="${PROJECT_ROOT}/${SCRATCH_NAME}"

if [[ -e "$SCRATCH_PATH" ]]; then
    echo "ERROR: scratch già esistente: ${SCRATCH_NAME}" >&2
    echo "  Usa uno slug diverso o lavora dentro la folder esistente." >&2
    exit 1
fi

"${SCRIPT_DIR}/../utils/folder-create.sh" "$SCRATCH_PATH"

echo "-> created scratch: ${SCRATCH_NAME}/"
