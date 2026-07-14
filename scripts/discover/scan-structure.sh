#!/bin/bash

# =============================================================================
# scan-structure.sh - Static scan del progetto per bootstrap documentale
# Usage: scan-structure.sh [--root <path>] [--depth N]
# =============================================================================
#
# Produce un report markdown deterministico con:
#   - Tipo di ecosistema rilevato (node, python, go, rust, java, php, mixed)
#   - Monorepo detection (npm/pnpm/lerna/nx/turbo/cargo workspace, go work)
#   - Top-level packages / subprojects
#   - Entry points (bin, main, scripts)
#   - Directory tree (depth configurabile, default 2)
#   - File count per estensione (top 10)
#   - Presence check: tests, CI, docker, kubernetes
#   - Remote git
#
# Zero inferenza, zero LLM. Solo fatti estraibili con shell + jq (se presente).
# Output su stdout. Eventuali warning su stderr.
# =============================================================================

set -euo pipefail

ROOT="$PWD"
DEPTH=2

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)  ROOT="$2"; shift 2 ;;
        --depth) DEPTH="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

cd "$ROOT"

has() { command -v "$1" >/dev/null 2>&1; }

# ---------- helpers ----------

section() { printf '\n## %s\n\n' "$1"; }

kv() { printf -- '- **%s**: %s\n' "$1" "$2"; }

fence() { printf '```%s\n' "${1:-}"; }
endfence() { printf '```\n'; }

# ---------- header ----------

printf '# Static Scan Report\n\n'
kv "Root" "$ROOT"
kv "Scanned at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------- git ----------

section "Git"
if [[ -d .git ]] || git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    kv "Repo" "yes"
    remote_raw="$(git config --get remote.origin.url 2>/dev/null || echo "(none)")"
    # Strip credentials embedded in URL (https://TOKEN@host/... or https://user:pass@host/...)
    remote="$(echo "$remote_raw" | sed -E 's#(https?://)[^/@]+@#\1#')"
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")"
    kv "Remote" "$remote"
    kv "Branch" "$branch"
else
    kv "Repo" "no"
fi

# ---------- ecosystem detection ----------

section "Ecosystem"

declare -a ECOS=()
[[ -f package.json ]]     && ECOS+=("node")
[[ -f pyproject.toml ]] || [[ -f setup.py ]] || [[ -f requirements.txt ]] && ECOS+=("python")
[[ -f go.mod ]]           && ECOS+=("go")
[[ -f Cargo.toml ]]       && ECOS+=("rust")
[[ -f pom.xml ]] || [[ -f build.gradle ]] || [[ -f build.gradle.kts ]] && ECOS+=("jvm")
[[ -f composer.json ]]    && ECOS+=("php")
[[ -f Gemfile ]]          && ECOS+=("ruby")
[[ -f mix.exs ]]          && ECOS+=("elixir")

if [[ ${#ECOS[@]} -eq 0 ]]; then
    kv "Detected" "(none — plain files / markdown / docs?)"
else
    kv "Detected" "$(IFS=,; echo "${ECOS[*]}")"
fi

# ---------- monorepo detection ----------

section "Monorepo"

MONOREPO="no"
MONOTOOL=""

if [[ -f package.json ]] && has jq; then
    ws=$(jq -r '.workspaces // empty | if type=="array" then join(",") elif type=="object" then (.packages // [] | join(",")) else . end' package.json 2>/dev/null || echo "")
    if [[ -n "$ws" ]]; then MONOREPO="yes"; MONOTOOL="npm/yarn workspaces ($ws)"; fi
fi
[[ -f pnpm-workspace.yaml ]]  && MONOREPO="yes" && MONOTOOL="pnpm workspaces"
[[ -f lerna.json ]]           && MONOREPO="yes" && MONOTOOL="${MONOTOOL:+$MONOTOOL + }lerna"
[[ -f nx.json ]]              && MONOREPO="yes" && MONOTOOL="${MONOTOOL:+$MONOTOOL + }nx"
[[ -f turbo.json ]]           && MONOREPO="yes" && MONOTOOL="${MONOTOOL:+$MONOTOOL + }turbo"
[[ -f go.work ]]              && MONOREPO="yes" && MONOTOOL="${MONOTOOL:+$MONOTOOL + }go work"
if [[ -f Cargo.toml ]] && grep -q '^\s*\[workspace\]' Cargo.toml 2>/dev/null; then
    MONOREPO="yes"; MONOTOOL="${MONOTOOL:+$MONOTOOL + }cargo workspace"
fi

kv "Monorepo" "$MONOREPO"
[[ -n "$MONOTOOL" ]] && kv "Tooling" "$MONOTOOL"

# ---------- ecosystem-per-dir helper ----------

# Echoes comma-separated ecosystem tags detected in $1, empty if none.
detect_eco() {
    local d="$1"
    local tags=""
    [[ -f "$d/package.json" ]]    && tags="${tags}node,"
    [[ -f "$d/composer.json" ]]   && tags="${tags}php,"
    [[ -f "$d/pyproject.toml" ]] || [[ -f "$d/setup.py" ]] || [[ -f "$d/requirements.txt" ]] && tags="${tags}python,"
    [[ -f "$d/go.mod" ]]          && tags="${tags}go,"
    [[ -f "$d/Cargo.toml" ]]      && tags="${tags}rust,"
    [[ -f "$d/pom.xml" ]] || [[ -f "$d/build.gradle" ]] || [[ -f "$d/build.gradle.kts" ]] && tags="${tags}jvm,"
    [[ -f "$d/Gemfile" ]]         && tags="${tags}ruby,"
    [[ -f "$d/mix.exs" ]]         && tags="${tags}elixir,"
    # Vue/Svelte/Next — already covered by package.json, but record framework hint
    if [[ -f "$d/package.json" ]] && has jq; then
        local fw
        fw=$(jq -r '.dependencies // {} | keys + (.devDependencies // {} | keys) | join(",")' "$d/package.json" 2>/dev/null || echo "")
        case ",$fw," in
            *,vue,*)      tags="${tags}vue," ;;
        esac
        case ",$fw," in
            *,next,*)     tags="${tags}next," ;;
        esac
        case ",$fw," in
            *,svelte,*)   tags="${tags}svelte," ;;
        esac
        case ",$fw," in
            *,@angular/core,*) tags="${tags}angular," ;;
        esac
    fi
    # Laravel hint
    if [[ -f "$d/composer.json" ]] && has jq; then
        grep -q 'laravel/framework' "$d/composer.json" 2>/dev/null && tags="${tags}laravel,"
    fi
    echo "${tags%,}"
}

# Extract package name from whatever manifest is in $1.
name_of() {
    local d="$1"
    if [[ -f "$d/package.json" ]] && has jq; then
        jq -r '.name // ""' "$d/package.json" 2>/dev/null; return
    fi
    if [[ -f "$d/composer.json" ]] && has jq; then
        jq -r '.name // ""' "$d/composer.json" 2>/dev/null; return
    fi
    if [[ -f "$d/Cargo.toml" ]]; then
        grep -m1 '^name' "$d/Cargo.toml" | sed 's/.*=\s*"\(.*\)".*/\1/'; return
    fi
    if [[ -f "$d/pyproject.toml" ]]; then
        grep -m1 '^name' "$d/pyproject.toml" | sed 's/.*=\s*"\(.*\)".*/\1/'; return
    fi
    if [[ -f "$d/go.mod" ]]; then
        head -1 "$d/go.mod" | awk '{print $2}'; return
    fi
    if [[ -f "$d/pom.xml" ]]; then
        grep -m1 '<artifactId>' "$d/pom.xml" | sed -E 's|.*<artifactId>(.*)</artifactId>.*|\1|'; return
    fi
    echo ""
}

# ---------- top-level packages (monorepo containers) ----------

section "Top-level packages (monorepo containers)"

PKG_DIRS=()
for candidate in packages apps services libs modules crates; do
    if [[ -d "$candidate" ]]; then
        while IFS= read -r -d '' d; do
            if [[ -n "$(detect_eco "$d")" ]]; then
                PKG_DIRS+=("${d#./}")
            fi
        done < <(find "$candidate" -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null)
    fi
done

if [[ ${#PKG_DIRS[@]} -eq 0 ]]; then
    printf '(none detected — single-package or non-standard layout)\n'
else
    printf '| Path | Name | Ecosystem |\n| ---- | ---- | --------- |\n'
    for d in "${PKG_DIRS[@]}"; do
        n=$(name_of "$d"); [[ -z "$n" ]] && n="(unknown)"
        eco=$(detect_eco "$d"); [[ -z "$eco" ]] && eco="(none)"
        printf '| `%s` | %s | %s |\n' "$d" "$n" "$eco"
    done
fi

# ---------- sub-projects (multi-repo workspace) ----------

section "Sub-projects (direct children with ecosystem markers)"

printf '_Cattura il caso "workspace di N progetti indipendenti" (no monorepo tooling, ogni sub-dir è un repo/progetto a se)._\n\n'

SUB_DIRS=()
while IFS= read -r -d '' d; do
    # Skip hidden dirs and standard monorepo containers (already covered above)
    base="$(basename "$d")"
    case "$base" in
        .*|node_modules|dist|build|target|coverage|vendor|packages|apps|services|libs|modules|crates|docs|tests|test) continue ;;
    esac
    if [[ -n "$(detect_eco "$d")" ]]; then
        SUB_DIRS+=("${d#./}")
    fi
done < <(find . -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

if [[ ${#SUB_DIRS[@]} -eq 0 ]]; then
    printf '(none detected)\n'
else
    printf '| Path | Name | Ecosystem | Files | Key subdirs |\n'
    printf '| ---- | ---- | --------- | -----:| ----------- |\n'
    for d in "${SUB_DIRS[@]}"; do
        n=$(name_of "$d"); [[ -z "$n" ]] && n="(unknown)"
        eco=$(detect_eco "$d"); [[ -z "$eco" ]] && eco="(unknown)"
        nfiles=$(find "$d" -type f -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/target/*' 2>/dev/null | wc -l)
        # Key subdirs: first few level-1 dirs that suggest structure
        keys=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
            | grep -vE '/(\.|node_modules|vendor|dist|build|target|coverage|\.idea|\.github)$' \
            | sed "s|^$d/||" | sort | head -6 | tr '\n' ' ')
        printf '| `%s` | %s | %s | %s | %s |\n' "$d" "$n" "$eco" "$nfiles" "$keys"
    done
fi

# ---------- entry points ----------

section "Entry points"

if [[ -f package.json ]] && has jq; then
    main=$(jq -r '.main // "(none)"' package.json 2>/dev/null)
    bin=$(jq -r '.bin | if type=="string" then . elif type=="object" then (keys | join(",")) else "(none)" end' package.json 2>/dev/null)
    scripts=$(jq -r '.scripts // {} | keys | join(", ")' package.json 2>/dev/null)
    kv "main" "$main"
    kv "bin" "$bin"
    [[ -n "$scripts" ]] && kv "npm scripts" "$scripts"
fi

[[ -f Cargo.toml ]]    && kv "Cargo" "$(grep -m1 '^name' Cargo.toml | sed 's/.*=\s*"\(.*\)".*/\1/')"
[[ -f go.mod ]]        && kv "go module" "$(head -1 go.mod | awk '{print $2}')"
[[ -f pyproject.toml ]] && kv "python project" "$(grep -m1 '^name' pyproject.toml | sed 's/.*=\s*"\(.*\)".*/\1/')"

# Dockerfile / compose
[[ -f Dockerfile ]]          && kv "Dockerfile" "yes"
[[ -f docker-compose.yml ]] || [[ -f compose.yml ]] && kv "docker-compose" "yes"

# CI
ci=""
[[ -d .github/workflows ]] && ci="${ci}github-actions "
[[ -f .gitlab-ci.yml ]]    && ci="${ci}gitlab-ci "
[[ -f .circleci/config.yml ]] && ci="${ci}circleci "
[[ -n "$ci" ]] && kv "CI" "$ci"

# Tests
tests=""
[[ -d tests ]] || [[ -d test ]] && tests="${tests}tests/ "
find . -maxdepth 4 -type d \( -name __tests__ -o -name spec \) 2>/dev/null | head -1 | grep -q . && tests="${tests}spec/_tests_/ "
[[ -n "$tests" ]] && kv "Tests" "$tests"

# ---------- directory tree ----------

section "Directory tree (depth $DEPTH)"

fence
EXCLUDE_RE='(^|/)(node_modules|\.git|dist|build|target|\.next|\.turbo|\.cache|coverage|\.venv|venv|__pycache__)($|/)'
find . -maxdepth "$DEPTH" -type d 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" \
    | sed 's|^\./||' \
    | sort \
    | awk 'NF' \
    | head -80
endfence

# ---------- file counts by extension ----------

section "File counts (top 15 extensions)"

fence
find . -type f 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" \
    | awk -F. 'NF>1 {print $NF}' \
    | sort | uniq -c | sort -rn | head -15 \
    | awk '{printf "%6d  .%s\n", $1, $2}'
endfence

# ---------- candidate fulcri ----------

section "Candidate fulcri (heuristic)"

printf '_Pure euristica da nomi di directory — l'"'"'utente conferma/corregge in interview._\n\n'

# Servizi candidati: top-level dirs con nomi che suggeriscono servizi
printf '### Services (dir patterns)\n'
find . -maxdepth 3 -type d 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" \
    | sed 's|^\./||' \
    | grep -iE '/(server|service|api|worker|daemon|runner|scheduler|gateway|controller|handler|dispatcher)s?$|^(server|service|api|worker|daemon|runner|scheduler|gateway)s?$' \
    | sort -u | head -20 | sed 's/^/- /' \
    || printf '(none found)\n'

printf '\n### Entities / domain (dir patterns)\n'
find . -maxdepth 3 -type d 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" \
    | sed 's|^\./||' \
    | grep -iE '/(model|entity|entities|domain|schema|types?)s?$|^(model|entity|domain|schema)s?$' \
    | sort -u | head -20 | sed 's/^/- /' \
    || printf '(none found)\n'

printf '\n### Core modules (top-level src subdirs)\n'
for srcdir in src lib app packages; do
    if [[ -d "$srcdir" ]]; then
        find "$srcdir" -mindepth 1 -maxdepth 2 -type d 2>/dev/null \
            | grep -Ev "$EXCLUDE_RE" \
            | sort -u | head -25 | sed 's/^/- /'
    fi
done | head -30

# ---------- doc status ----------

section "Existing documentation"

DOC_FILES=0
[[ -f README.md ]] && kv "README.md" "yes" && DOC_FILES=$((DOC_FILES+1)) || kv "README.md" "no"
[[ -f CLAUDE.md ]] && kv "CLAUDE.md" "yes" && DOC_FILES=$((DOC_FILES+1)) || kv "CLAUDE.md" "no"
_lw_docs="${LOOM_DOCS_ROOT:-docs}"
[[ -d "${_lw_docs}" ]] && kv "${_lw_docs}/" "$(find "${_lw_docs}" -maxdepth 3 -name '*.md' 2>/dev/null | wc -l) .md files" || kv "${_lw_docs}/" "(absent)"
if [[ -f .claude/loom-works.json ]]; then
    kv ".claude/loom-works.json" "present (project config — init already run)"
else
    kv ".claude/loom-works.json" "(absent — run /loom-works:init first)"
fi

# ---------- end ----------

printf '\n---\n_End of scan._\n'
