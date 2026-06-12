#!/bin/bash
# =============================================================================
# Esempio hook on-lane-spawned
#
# Copia questo file nel tuo progetto, personalizzalo, poi configura:
#   user_config.on_lane_spawned_hook = "scripts/on-lane-spawned.sh"   (path relativo al project root)
#
# Invocato UNA SOLA VOLTA da spawn-lane, sulla LANE PARENT ROOT ({project}-{lane}).
# Esempio: progetto "loom-works" + lane "puppa" → eseguito con root = loom-works-puppa.
# Mono o multi repo è irrilevante: una sola esecuzione sulla root.
#
#   $1   = lane parent root (path assoluto)
#   CWD  = lane parent root (già dentro: puoi usare path relativi)
#
# Env disponibili:
#   LOOM_LANE          nome lane (es. "puppa")
#   LOOM_WORKTREE      lane parent root (= $1 = CWD)
#   LOOM_PROJECT_ROOT  project root originale (dove vive .claude/)
#
# Idempotenza: ri-eseguibile a mano dopo un fix (spawn-lane stampa il comando
# esatto in caso di failure).
# =============================================================================

set -euo pipefail

LANE_ROOT="$1"   # == ${LOOM_WORKTREE} == $PWD

echo "[on-lane-spawned] lane=${LOOM_LANE} root=${LANE_ROOT}"

# ---------------------------------------------------------------------------
# Esempio 1: copia .env dal progetto originale alla lane root
# ---------------------------------------------------------------------------

if [[ -f "${LOOM_PROJECT_ROOT}/.env" ]]; then
    cp "${LOOM_PROJECT_ROOT}/.env" "${LANE_ROOT}/.env"
    echo "  -> .env copiato: ${LOOM_PROJECT_ROOT}/.env → ${LANE_ROOT}/.env"
fi

# ---------------------------------------------------------------------------
# Esempio 2: wiring di settaggi locali (CWD è già la lane root)
# ---------------------------------------------------------------------------

# cp config/local.template.json ./config/local.json
# ln -sf "${LOOM_PROJECT_ROOT}/secrets" ./secrets

echo "[on-lane-spawned] ✔️ done"
