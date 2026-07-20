#!/bin/bash
set -euo pipefail

# =============================================================================
# register.sh - Registra il progetto CWD nel registry dconf (file → dconf)
# Usage: register.sh [<project-dir>]     (default: $PWD)
# =============================================================================
#
# Legge <project-dir>/.claude/loom-works.json, valida, scrive l'identità nel
# registry /org/lamemind/loom/projects/<id>/ (emoji, owner, name, dir, surfaces).
# One-shot additivo a `loom-works init`. Idempotente (riscrive le stesse chiavi).
# Noop silenzioso se dconf assente.
# =============================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/lib-config.sh"

PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if ! reg_available; then
    echo "[register] dconf assente → noop"
    exit 0
fi

f="$(cfg_file_path "$PROJECT_DIR")"
cfg_validate "$f" || die "config non valido o assente: $f"

id="$(reg_pull "$PROJECT_DIR")"
emoji="$(cfg_field "$f" emoji)"
owner="$(cfg_field "$f" owner)"
name="$(cfg_field "$f" name)"

echo "[register] '$id' → registry ($(reg_project_path "$id"))"
echo "[register]   label:    $(cfg_label "$emoji" "$owner" "$name")"
echo "[register]   dir:      $PROJECT_DIR"
echo "[register]   surfaces: $(cfg_enabled_surfaces "$f" | tr '\n' ' ')"
echo "[register]   launch:   $(cfg_launch_count "$f") voce/i"

defsurface="$(cfg_field "$f" defaultSurface)"
echo "[register]   default:  ${defsurface:-terminal (implicito)}"
