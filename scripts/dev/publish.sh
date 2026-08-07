#!/usr/bin/env bash

# =============================================================================
# publish.sh — ciclo di pubblicazione del plugin, in un comando solo
# Usage: publish.sh --patch|--minor|--major "<messaggio commit>" [--project <dir>]
# =============================================================================
#
# Un deliverable del plugin NON ESISTE finche' non e' pubblicato: chi invoca il path
# canonico ${CLAUDE_PLUGIN_ROOT}/... esegue la CACHE version-pinned, non il sorgente in
# loom-works-plugin/. Il ciclo che colma la distanza e' sempre lo stesso, e questo script
# lo esegue per intero:
#
#   1. GATE   check-injection-budget.sh — esce non-zero e ferma tutto
#   2. BUMP   version in .claude-plugin/plugin.json
#   3. COMMIT il messaggio passato + " + bump vX.Y.Z", versione nello STESSO commit
#   4. PUSH   origin main (repo del plugin)
#   5. UPDATE claude plugin marketplace update + claude plugin update
#   6. VERIFY la cache attesa ~/.claude/plugins/cache/<owner>/<name>/<nuova>/ esiste
#   7. GITLINK commit del puntatore al submodule nel cappello (solo quel path)
#
# Il passo 6 e' la ragione per cui lo script esiste. Un `plugin update` fallito NON da'
# segnale: senza verifica si continua a lavorare credendo che il codice nuovo sia in
# esercizio mentre gira ancora la versione vecchia — il modo piu' efficiente di perdere
# un'ora a debuggare codice che non e' in esecuzione.
#
# L'unico passo NON automatizzabile e' il restart della sessione: gli hook SessionStart
# si leggono alla nascita del processo. Lo script chiude stampando l'istruzione esplicita.
#
# Nessun --dry-run: un ramo di codice che esiste solo per la prova e' un ramo che non
# collauda il ramo vero. Il collaudo di questo script e' un run reale.
#
# Exit: 0 = pubblicato · 1 = un passo e' fallito (lo script si ferma li') · 2 = errore uso
# =============================================================================

set -uo pipefail

BUMP=""
MSG=""
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --patch|--minor|--major) BUMP="${1#--}"; shift ;;
    --project) PROJECT="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    -*) echo "arg sconosciuto: $1" >&2; exit 2 ;;
    *) [ -n "$MSG" ] && { echo "messaggio gia' passato: $MSG" >&2; exit 2; }; MSG="$1"; shift ;;
  esac
done

[ -n "$BUMP" ] || { echo "manca --patch|--minor|--major" >&2; exit 2; }
[ -n "$MSG" ]  || { echo "manca il messaggio di commit" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/.claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || { echo "plugin.json non trovato: $MANIFEST" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq richiesto" >&2; exit 2; }

# Il gate misura le hook entry contro i task file di un PROGETTO: il submodule sta dentro
# il cappello, che e' il progetto che ne possiede. Default = parent del plugin root.
[ -n "$PROJECT" ] || PROJECT="$(dirname "$ROOT")"

NAME="$(jq -r '.name' "$MANIFEST")"
CUR="$(jq -r '.version' "$MANIFEST")"
[[ "$CUR" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || {
  echo "versione non semver in plugin.json: $CUR" >&2; exit 2; }
MAJ="${BASH_REMATCH[1]}"; MIN="${BASH_REMATCH[2]}"; PAT="${BASH_REMATCH[3]}"

case "$BUMP" in
  patch) PAT=$((PAT + 1)) ;;
  minor) MIN=$((MIN + 1)); PAT=0 ;;
  major) MAJ=$((MAJ + 1)); MIN=0; PAT=0 ;;
esac
NEW="$MAJ.$MIN.$PAT"

# owner del marketplace: il path di cache e' <owner>/<name> e il target di update e'
# <name>@<owner>, ma l'owner NON sta nel manifest del plugin — si legge dalla chiave
# "<name>@<owner>" dell'installato.
INSTALLED="$HOME/.claude/plugins/installed_plugins.json"
OWNER="$(jq -r --arg n "$NAME" '.plugins | keys[] | select(startswith($n + "@"))' \
  "$INSTALLED" 2>/dev/null | head -1)"
OWNER="${OWNER#*@}"
[ -n "$OWNER" ] || { echo "'$NAME' non risulta installato in $INSTALLED — installalo prima di pubblicare" >&2; exit 2; }

CACHE="$HOME/.claude/plugins/cache/$OWNER/$NAME/$NEW"

step() { echo; echo "── $* ─────────────────────────────────────────" | cut -c1-78; }
die()  { echo; echo "FERMO: $*" >&2; exit 1; }

echo "plugin  $NAME@$OWNER"
echo "version $CUR → $NEW  ($BUMP)"
echo "sorgente $ROOT"
echo "progetto $PROJECT   (perimetro del gate)"

# ── 1. GATE ──────────────────────────────────────────────────────────────────
step "1/7 gate — budget di iniezione"
"$ROOT/scripts/dev/check-injection-budget.sh" --project "$PROJECT" \
  || die "una hook entry sfora il budget. Pota, poi ripubblica. Niente e' stato committato."

# ── 2. BUMP ──────────────────────────────────────────────────────────────────
step "2/7 bump — $CUR → $NEW"
BRANCH="$(git -C "$ROOT" branch --show-current)"
[ "$BRANCH" = "main" ] || die "il repo del plugin e' su '$BRANCH', non su main. Un branch protegge il sorgente, non l'esercizio."

tmp="$(mktemp)"
jq --arg v "$NEW" '.version = $v' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
echo "plugin.json aggiornato"

# ── 3. COMMIT ────────────────────────────────────────────────────────────────
step "3/7 commit — versione nello stesso commit dei deliverables"
git -C "$ROOT" add -A
git -C "$ROOT" status --short
git -C "$ROOT" commit -q -m "$MSG + bump v$NEW" || die "commit fallito nel repo del plugin"
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "commit $SHA"

# ── 4. PUSH ──────────────────────────────────────────────────────────────────
step "4/7 push — origin main"
git -C "$ROOT" push -q origin main || die "push fallito. Il commit $SHA e' locale: risolvi e ripushalo a mano."

# ── 5. UPDATE ────────────────────────────────────────────────────────────────
step "5/7 update — marketplace + plugin"
claude plugin marketplace update "$OWNER" \
  || die "marketplace update fallito. A mano: claude plugin marketplace update $OWNER && claude plugin update $NAME@$OWNER"
claude plugin update "$NAME@$OWNER" \
  || die "plugin update fallito. A mano: claude plugin update $NAME@$OWNER — NON considerare pubblicata la v$NEW finche' non passa."

# ── 6. VERIFY ────────────────────────────────────────────────────────────────
step "6/7 verifica — la cache attesa esiste"
[ -d "$CACHE" ] || die "cache assente: $CACHE
Il plugin update e' passato senza errori ma non ha materializzato la v$NEW.
Finche' quella cartella non c'e', ogni invocazione di \${CLAUDE_PLUGIN_ROOT} esegue
ancora la versione vecchia — e nessun errore te lo direbbe."
echo "$CACHE"

# ── 7. GITLINK ───────────────────────────────────────────────────────────────
step "7/7 gitlink — puntatore al submodule nel cappello"
SUB="$(basename "$ROOT")"
if ! git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "SKIP: $PROJECT non e' un repo git — nessun gitlink da aggiornare"
elif ! git -C "$PROJECT" ls-files --error-unmatch "$SUB" >/dev/null 2>&1; then
  echo "SKIP: '$SUB' non e' tracciato in $PROJECT — nessun gitlink da aggiornare"
else
  # Solo il path del submodule, MAI `git add -A`: questo script gira mentre una task ha
  # lavoro in corso nel cappello, e un -A se lo porterebbe dentro in silenzio.
  git -C "$PROJECT" add "$SUB"
  if git -C "$PROJECT" diff --cached --quiet -- "$SUB"; then
    echo "gitlink gia' allineato"
  else
    git -C "$PROJECT" commit -q -m "chore(plugin): submodule a v$NEW ($MSG)" -- "$SUB" \
      || die "commit del gitlink fallito nel cappello"
    git -C "$PROJECT" push -q origin "$(git -C "$PROJECT" branch --show-current)" \
      || die "push del gitlink fallito. Il plugin E' pubblicato: resta solo da pushare il cappello."
    echo "gitlink committato e pushato"
  fi
fi

cat <<EOF

═══════════════════════════════════════════════════════════════
  $NAME v$NEW PUBBLICATO

  RIAVVIA LA SESSIONE CLAUDE CODE, ORA.

  Gli hook SessionStart si leggono alla nascita del processo: questa
  sessione porta ancora i contratti della v$CUR. Le skill nuove non
  sono invocabili e quelle vecchie parlano di cose che non esistono
  piu' — e' l'unico passo che questo script non puo' fare per te.
═══════════════════════════════════════════════════════════════
EOF
