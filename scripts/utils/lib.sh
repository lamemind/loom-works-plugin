#!/bin/bash

# =============================================================================
# lib.sh - Helper sourced da altri script loom-works
# Usage: source "${LOOM_WORKS_ROOT}/scripts/utils/lib.sh"
# =============================================================================
#
# Fornisce:
# - Wrapper git e read helper
# - Detection del remote: l'unica capability davvero variabile
#
# Env letto:
# - PROJECT_ROOT (default: $PWD)
#
# Modello: REPO SEMPRE, REMOTE OPZIONALE. Un progetto loom-works e' sempre un
# repo git — se non lo e', `git init` e' un prerequisito, non un modo alternativo
# di funzionare. Cio' che manca davvero in natura e' il REMOTE: si lavora in
# locale, si committa, e non c'e' dove pushare. Il gate sta quindi solo sul push.
#
# Config vera vive in plugin settings.json (project level), non nel sentinel.
# =============================================================================

# ---- Project root detection --------------------------------------------------
#
# Sale l'albero a partire da $PWD cercando il marker .claude/loom-works.json
# (config progetto OBBLIGATORIO, scritto da /loom-works:init). È l'UNICO marker:
# nessun fallback legacy — il vecchio sentinel .initialized non vale più.
# Se non trovato, fallback git toplevel. Final fallback: $PWD.
# Honor PROJECT_ROOT se già settato esplicitamente.

lw_find_project_root() {
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    local dir="$PWD"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -f "$dir/.claude/loom-works.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    local git_root
    git_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$git_root" ]]; then
        echo "$git_root"
        return 0
    fi
    echo "$PWD"
}

# ---- Remote detection ---------------------------------------------------------
#
# La sola capability variabile del modello. Gate su `origin` e non sulla presenza
# generica di un remote: tutto il resto della lib parla origin (il push con branch
# esplicito), quindi un remote di altro nome non renderebbe comunque pushabile il
# branch.

lw_has_remote() {
    git -C "$(lw_find_project_root)" remote get-url origin >/dev/null 2>&1
}

# ---- Docs root ---------------------------------------------------------------
#
# Precedenza: file config del progetto → LOOM_DOCS_ROOT → "docs".
#
# FONTE UNICA = il campo `docsRoot` di .claude/loom-works.json. E' PER-PROGETTO e
# committato: su un progetto che tiene la doc in runtime/ e' l'unica cosa che lo sa,
# e viaggia col repo. Il canale che c'era prima — il userConfig globale
# `doc_folder_name`, interpolato dalle skill nel flag --docs-root — e' stato rimosso
# (plugin v3.0.0): una preferenza utente vale per TUTTI i progetti, quindi non puo'
# descriverne uno non-default. Non era teoria: interpolava il valore globale `docs`
# su un progetto `runtime` e gli script giravano sulla cartella sbagliata in
# silenzio — non fallivano, misuravano zero file, e chi leggeva l'output credeva
# che la doc fosse a posto.
#
# `LOOM_DOCS_ROOT` sopravvive sotto il file come escape hatch (test, fixture senza
# file config). Resta SOTTO di proposito: un env sfuggito da una sessione o da un
# altro progetto non deve poter dirottare uno script su un progetto che ha gia'
# dichiarato la propria docs-root. Il piu' specifico batte il piu' generico —
# stesso principio del layer Config in project-config-architecture.md.
#
# Chi non puo' sourcare bash (il markdown delle skill) usa il wrapper CLI
# scripts/utils/docs-root.sh, gemello di resolve-task.sh.
#
# DUE LETTURE del campo: `jq` quando e' nel PATH e accetta il file, una regex bash
# altrimenti. `jq` non e' un prerequisito del plugin (Git for Windows non lo porta, `init` senza
# `jq` avvisa e prosegue), e una lettura che ripiegasse su "docs" quando manca
# rifarebbe il guasto silenzioso descritto sopra — su loom-works ogni script
# girerebbe su docs/, che non esiste, uscendo 0. Un errore «jq richiesto» non e'
# l'alternativa: questa funzione gira negli hook a ogni turno, e scatterebbe su
# ogni chiamante per un dato che si legge senza.
# La regex legge il file intero in una variabile (`read -d ''`, nessun processo
# figlio): `[[:space:]]` copre anche l'a-capo, quindi chiave e valore su due righe
# matchano come con `jq`, e il primo match vince — lo schema e' piatto, `docsRoot`
# compare solo al primo livello. Le due letture si collaudano con un banco a due
# giri, il secondo con un PATH senza `jq` (nel cappello:
# plugin-tests/docs-root/run.sh).
# Anche un file che `jq` rifiuta (una virgola finale lasciata da un edit a mano)
# passa alla regex: altrimenti l'esito dipenderebbe da quale binario ha la
# macchina — `docs` con `jq`, il valore giusto senza — e il ripiego sarebbe di
# nuovo silenzioso. Il file malformato lo segnala `cfg_validate`, non questa
# lettura.

lw_docs_root() {
    local cfg root from_file=""
    root="$(lw_find_project_root)"
    cfg="${root}/.claude/loom-works.json"
    if [[ -f "$cfg" ]]; then
        if ! { command -v jq >/dev/null 2>&1 \
                && from_file="$(jq -r '.docsRoot // empty' "$cfg" 2>/dev/null)"; }; then
            local json="" re='"docsRoot"[[:space:]]*:[[:space:]]*"([^"]*)"'
            IFS= read -r -d '' json < "$cfg" || true
            [[ "$json" =~ $re ]] && from_file="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$from_file" ]]; then
            echo "$from_file"
            return 0
        fi
    fi
    echo "${LOOM_DOCS_ROOT:-docs}"
}

# ---- Ancora di un record -----------------------------------------------------
#
# Stampa il path relativo a <root>; return 1 se non esiste, 2 se sta fuori da
# <root>. Un path relativo si prova prima sotto <root>, poi sotto $PWD.
#
# UNA REGOLA SOLA per tutti i registri che portano ancore — il record dello
# scarto (scarti.sh scarta) e lo scenario ignora (triage.sh scenario). Lo stesso
# file deve produrre la stessa stringa in entrambi: chi accoppia due record sullo
# stesso path (`sort | uniq -d` sulle ancore, o un join fra triage/ e scarti/) si
# regge su quella uguaglianza, e due copie della regola divergerebbero in silenzio.
#
# Il path si verifica sul FILESYSTEM e non su `git ls-files`: e' cio' che un
# rilevatore «path modificato dopo la data del record» legge, accoppiando
# `test -e` a `git log --since`.

lw_norm_ancora() {  # <root> <path>
    local root="$1" p="$2" abs
    if [[ "$p" == /* ]]; then
        abs="$p"
    elif [[ -e "${root}/${p}" ]]; then
        abs="${root}/${p}"
    else
        abs="${PWD}/${p}"
    fi
    abs="$(realpath -m -- "$abs" 2>/dev/null)" || return 1
    [[ -e "$abs" ]] || return 1
    case "$abs" in
        "$root"/?*) printf '%s\n' "${abs#"${root}/"}" ;;
        *) return 2 ;;
    esac
}

# ---- Task attiva: cascata di risoluzione -------------------------------------
#
# Contratto di famiglia, gemello di inject-task.sh (hook SessionStart) e della
# statusline. Due livelli:
#
#   1. arg esplicito -> chi invoca ha nominato la task
#   2. $LOOM_TASK    -> binding di SESSIONE (spawn deck)
#
# L'arg sta in cima o una sessione gia' vincolata non potrebbe piu' chiedere
# un'altra task. Il worktree non lega nessuna task: N sessioni parallele nello
# stesso worktree lavorano ognuna sulla sua, e solo l'env sa quale delle N sei tu.
# Nessun file nella docs-root fa da terzo gradino, nemmeno se c'e'.
#
# Stampa tre righe eval-abili (valori %q-quotati, path con spazi al sicuro):
#
#   TASK_ID=T48
#   TASK_FILE=/abs/path/runtime/tasks/T48-slug.md
#   TASK_SRC=arg|env
#
# TASK_SRC dichiara la provenienza invece di lasciarla silenziosa: chi la stampa
# in un report dice da dove viene la task su cui lavora.
#
# Uso — l'exit code NON sopravvive dentro `eval "$(...)"` (il fallimento resta
# nella command substitution, eval vede una stringa vuota e ritorna 0):
#
#   out="$(lw_resolve_task "$maybe_id")" || exit 1
#   eval "$out"
#
# Exit: 0 = risolta · 1 = nessuna fonte · 2 = id noto ma task file assente
lw_resolve_task() {   # [<task-id>]
    local id="${1:-}" src="" root docs dir file
    root="$(lw_find_project_root)"
    docs="$(lw_docs_root)"
    dir="${root}/${docs}/tasks"

    if [[ -n "$id" ]]; then
        src="arg"
    elif [[ -n "${LOOM_TASK:-}" ]]; then
        id="${LOOM_TASK}"
        src="env"
    fi

    if [[ -z "$id" ]]; then
        echo "ERROR: nessuna task attiva — nessun id passato e \$LOOM_TASK assente" >&2
        return 1
    fi

    file="$(ls "${dir}/${id}"-*.md 2>/dev/null | head -1)"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "ERROR: task file non trovato per ${id} in ${dir} (fonte: ${src})" >&2
        return 2
    fi

    printf 'TASK_ID=%q\nTASK_FILE=%q\nTASK_SRC=%q\n' "$id" "$file" "$src"
}

# ---- Figlie di un cappello ---------------------------------------------------
#
# La parentela la dichiara la FIGLIA (`**Parent Task**: T74`), quindi il padre non
# sa di averne: l'elenco si ricava solo scandagliando tutti i task file. Il calcolo
# sta qui e non in prosa nei body delle skill perche' il match ha un dettaglio che
# diverge in silenzio quando lo si riscrive: `grep 'Parent Task.*T7'` matcha anche
# `**Parent Task**: T74`. Serve un'ancora di fine-token, e la riga reale porta
# spesso testo dopo l'id — `**Parent Task**: T74 (asfaltamento del sistema doc)`.
#
# Ortogonale al marker di cappello (`Size: Epic`, dichiarato dal padre su di se'):
# quello dice "sono un cappello", questo dice "chi sono le mie figlie".
#
# Stampa una riga per figlia, ordinate per id numerico (T9 prima di T10):
#
#   TASK_CHILD=T76 /abs/path/runtime/tasks/T76-slug.md
#
# Nessuna figlia -> nessuna riga, exit 0.
# Exit: 0 = ok · 1 = id malformato
lw_task_children() {   # <task-id>
    local id="${1:-}" root docs dir f cid rows=""

    if [[ ! "$id" =~ ^T[0-9]+$ ]]; then
        echo "ERROR: id task malformato: '${id}' (atteso T<numero>)" >&2
        return 1
    fi

    root="$(lw_find_project_root)"
    docs="$(lw_docs_root)"
    dir="${root}/${docs}/tasks"

    for f in "${dir}"/*.md; do
        [[ -f "$f" ]] || continue
        grep -qE "^[[:space:]]*-?[[:space:]]*\*\*Parent Task\*\*:[[:space:]]*${id}([^0-9]|\$)" "$f" || continue
        cid="$(basename "$f" .md)"
        cid="${cid%%-*}"
        rows+="${cid#T}|${cid}|${f}"$'\n'
    done

    [[ -n "$rows" ]] || return 0

    printf '%s' "$rows" | sort -t'|' -k1,1n | while IFS='|' read -r _ cid f; do
        printf 'TASK_CHILD=%s %s\n' "$cid" "$f"
    done
}

# ---- Membri di un perimetro: epica o mandato ---------------------------------
#
# Un perimetro di lavoro vive in un task file in due forme, e le due differiscono
# solo nel punto da cui si leggono i membri (contratto: docs/mandate-format.md):
#
#   - `Size: Mandate` nell'header -> la lista `## Membri` del file, nell'ordine
#     del file: una riga a colonna zero che comincia con `- `, vale il primo
#     `T<numero>` della riga (stessa tolleranza di `**Parent Task**`)
#   - ogni altra task             -> le figlie, da lw_task_children
#
# Un lettore solo perche' orchestrator, checkpoint e recap contano gli stessi membri:
# due letture scritte a mano divergerebbero al primo task file con una forma
# inattesa, come il grep di `Parent Task` senza ancora di fine-token.
#
# Un membro epica o mandato resta una riga sola, mai espanso nei suoi membri:
# chi consuma lo orchestra a parte, e un ciclo fra mandati non puo' nascere qui.
# Un id ripetuto conta alla prima riga; il mandato che elenca se' stesso no.
#
# Stampa:
#
#   TASK_MEMBERS_SRC=list|parent
#   TASK_MEMBERS_COUNT=2
#   TASK_MEMBER=T52 /abs/path/runtime/tasks/T52-slug.md
#   TASK_MEMBER_MISSING=T58
#   TASK_MEMBER=T61 /abs/path/runtime/tasks/T61-slug.md
#
# TASK_MEMBER_MISSING e' un membro dichiarato senza task file: fuori dal
# conteggio, e non ferma il lettore — una task purgata da clean-tasks e' un caso
# normale, chi consuma decide. Un mandato senza `## Membri` da' zero membri: non
# ripiega sulle figlie, i membri di un mandato sono la sua lista.
#
# Nessun sottoprocesso per riga o per membro: su Git Bash ognuno costa ~150 ms.
# Exit: 0 = ok · 1 = id malformato · 2 = task file assente
lw_task_members() {   # <task-id>
    local id="${1:-}" root docs dir file="" candidate line size=""
    local in_section=0 in_fence=0 member path seen=" " rows="" count=0

    if [[ ! "$id" =~ ^T[0-9]+$ ]]; then
        echo "ERROR: id task malformato: '${id}' (atteso T<numero>)" >&2
        return 1
    fi

    root="$(lw_find_project_root)"
    docs="$(lw_docs_root)"
    dir="${root}/${docs}/tasks"

    for candidate in "${dir}/${id}"-*.md; do
        [[ -f "$candidate" ]] && { file="$candidate"; break; }
    done
    if [[ -z "$file" ]]; then
        echo "ERROR: task file non trovato per ${id} in ${dir}" >&2
        return 2
    fi

    # Size si legge solo nell'header, prima del primo `## `: la prosa di una
    # Description puo' nominare `Size: Mandate` senza esserlo.
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == "## "* ]] && break
        if [[ "$line" =~ ^-[[:space:]]*\*\*Size\*\*:[[:space:]]*([A-Za-z]+) ]]; then
            size="${BASH_REMATCH[1],,}"
            break
        fi
    done < "$file"

    if [[ "$size" != "mandate" ]]; then
        local children
        children="$(lw_task_children "$id")" || return 1
        echo "TASK_MEMBERS_SRC=parent"
        if [[ -z "$children" ]]; then
            echo "TASK_MEMBERS_COUNT=0"
        else
            count=0
            while IFS= read -r line; do count=$((count + 1)); done <<< "$children"
            echo "TASK_MEMBERS_COUNT=${count}"
            printf '%s\n' "${children//TASK_CHILD=/TASK_MEMBER=}"
        fi
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^##[[:space:]]+Membri[[:space:]]*$ ]]; then
            in_section=1; in_fence=0; continue
        fi
        [[ "$in_section" -eq 1 ]] || continue
        # chiude al prossimo heading di livello 1 o 2: un `###` dentro la
        # sezione raggruppa i membri, non la termina
        [[ "$in_fence" -eq 0 && "$line" =~ ^#{1,2}[[:space:]] ]] && break
        if [[ "$line" == '```'* ]]; then
            in_fence=$((1 - in_fence)); continue
        fi
        [[ "$in_fence" -eq 0 ]] || continue
        [[ "$line" =~ ^-[[:space:]] ]] || continue
        [[ "$line" =~ (^|[^A-Za-z0-9_])(T[0-9]+)([^0-9]|$) ]] || continue
        member="${BASH_REMATCH[2]}"
        [[ "$member" == "$id" || "$seen" == *" ${member} "* ]] && continue
        seen+="${member} "
        path=""
        for candidate in "${dir}/${member}"-*.md; do
            [[ -f "$candidate" ]] && { path="$candidate"; break; }
        done
        if [[ -n "$path" ]]; then
            rows+="TASK_MEMBER=${member} ${path}"$'\n'
            count=$((count + 1))
        else
            rows+="TASK_MEMBER_MISSING=${member}"$'\n'
        fi
    done < "$file"

    echo "TASK_MEMBERS_SRC=list"
    echo "TASK_MEMBERS_COUNT=${count}"
    printf '%s' "$rows"
}

# ---- Cella Prog della Tasks Overview -----------------------------------------
#
# Lettura e riscrittura della cella Prog di una riga `| T<n> | … |` in tasks.md,
# per gli script che promuovono (promote-wip, promote-ready): un awk solo, invece
# di una copia per chiamante che divergerebbe alla prima correzione.
#
# La colonna Prog si localizza dall'HEADER (`| ID | Pri | Prog | … |`), mai per
# posizione: un indice cablato smette di matchare al primo cambio di forma della
# tabella e produce un no-op muto.
#
# La tabella apre all'header e chiude alla PRIMA riga che non inizia con `|`; un
# secondo header ne riapre una. Stesso confine del deck (`overviewRows` in
# loom-deck/src/tasks.ts). Il confine serve perche' la prima cella `T<n>` non
# basta: le righe cross-deps dell'Execution Plan (`| T07 | — | ✔️T08 |`) hanno la
# stessa forma appena perdono il 🔒, e senza confine la promozione di T07
# riscriveva la cella Cross Deps col glifo, cancellando la dipendenza.
#
# Prezzo del confine: una riga vuota o un commento DENTRO la tabella la chiude,
# e le righe sotto non si trovano piu' — il chiamante lo riporta come WARN.
_LW_TASKS_MD_AWK_HEAD='
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function header_prog(   i) {
        if ($0 !~ /^[ \t]*\|/ || trim($2) != "ID") return 0
        for (i = 2; i <= NF; i++) if (trim($i) == "Prog") return i
        return 0
    }
'

# Stampa il glifo Prog della riga <task-id>, o niente se la riga non c'e'.
lw_tasks_md_prog_get() {   # <tasks-file> <task-id>
    awk -v id="$2" -F'|' "${_LW_TASKS_MD_AWK_HEAD}"'
        (p = header_prog()) > 0 { prog = p; next }
        prog > 0 && !/^[ \t]*\|/ { prog = 0; next }
        prog > 0 && trim($2) == id { print trim($prog); exit }
    ' "$1"
}

# Riscrive la cella Prog della riga <task-id> con <glifo>, in place.
# Exit: 0 = riga riscritta · 1 = nessuna riga (file intatto)
lw_tasks_md_prog_set() {   # <tasks-file> <task-id> <glifo>
    local tmp
    tmp=$(mktemp)
    if awk -v id="$2" -v glyph="$3" -F'|' -v OFS='|' "${_LW_TASKS_MD_AWK_HEAD}"'
        (p = header_prog()) > 0 { prog = p; print; next }
        prog > 0 && !/^[ \t]*\|/ { prog = 0 }
        prog > 0 && trim($2) == id { $prog = " " glyph " "; hit = 1; print; next }
        { print }
        END { exit(hit ? 0 : 1) }
    ' "$1" > "$tmp"; then
        mv "$tmp" "$1"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# ---- Baseline del diff di checkpoint -----------------------------------------
#
# Da dove parte la finestra <base>..HEAD di un checkpoint: il lavoro su un perimetro
# dall'ultimo avanzamento (checkpoint-mandate).
# NON e' un campo scritto nel task file: quello era un chicken-egg — il SHA si
# conosce solo DOPO il commit, ma scriverlo dentro il file appena committato lo
# modifica di nuovo, quindi il sed girava post-commit e lasciava il working tree
# sporco. Qui il baseline si deriva dalla history, ancorato al Progress Log:
#
#   - zero '### Avanzamento'  -> commit di CREAZIONE del task file
#   - >=1                     -> commit che ha INTRODOTTO l'ultimo header
#
# Il file va letto da HEAD, non dal working tree: al checkpoint la skill scrive
# '### Avanzamento N' PRIMA del commit, quindi sul working tree il pickaxe
# cercherebbe in history un header non ancora committato e uscirebbe vuoto.
#
# L'ancoraggio all'avanzamento rende il baseline il perimetro di cio' che si sta
# consolidando: un commit che sweep-a il task file per altro (una checkbox, le
# Decisions di preflight-task) non lo sposta piu'. In piu' l'hash esce sempre
# vivo dalla history, mentre un SHA storato puo' danglare dopo un rebase.
#
# Task file mai committato -> errore, non degradazione: una `git log` vuota
# passata a `git diff` significa "diff sull'intera history", cioe' una finestra
# falsa che si presenta come normale.
#
# Exit: 0 = SHA su stdout · 1 = non derivabile (messaggio su stderr)
lw_task_baseline_sha() {   # <task-file>
    local task_file="${1:?lw_task_baseline_sha: <task-file> richiesto}"
    local root top abs rel last sha
    root="$(lw_find_project_root)"
    top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$top" ]]; then
        echo "ERROR: baseline non derivabile: ${root} non e' un repo git" >&2
        return 1
    fi
    abs="$(realpath -m -- "$task_file" 2>/dev/null || true)"
    rel="${abs#"${top}/"}"

    if ! git -C "$top" cat-file -e "HEAD:${rel}" 2>/dev/null; then
        echo "ERROR: task file mai committato: ${rel}" >&2
        echo "       Il baseline del diff si deriva dalla history: committa il task file, poi rilancia." >&2
        return 1
    fi

    # "Ultimo" = N piu' alto, NON l'ultimo in ordine di file: il Progress Log si
    # trova scritto in entrambi i versi nel corpus (append in coda, oppure entry
    # nuova in testa) e un `tail -1` sul secondo caso prende il piu' VECCHIO —
    # baseline troppo indietro, finestra di diff che ingloba i checkpoint gia'
    # consolidati, senza nessun segnale. Il numero incrementale e' l'unico
    # ordinamento che non dipende da come la entry e' stata inserita.
    #
    # Poi pickaxe sull'header intero: -S conta le occorrenze, quindi regge anche
    # due avanzamenti con lo stesso testo (il secondo cambia comunque il conteggio).
    last="$(git -C "$top" show "HEAD:${rel}" \
            | grep -E '^### Avanzamento[[:space:]]+[0-9]+' \
            | sort -k3,3n | tail -1)"
    if [[ -n "$last" ]]; then
        sha="$(git -C "$top" log -S"$last" -1 --format=%H -- "$rel")"
    fi

    # Nessun avanzamento (o header legacy fuori formato): la finestra parte dalla
    # nascita della task — larga, mai falsa. Non e' un'anomalia da segnalare.
    if [[ -z "$sha" ]]; then
        sha="$(git -C "$top" log --diff-filter=A -1 --format=%H -- "$rel")"
    fi

    if [[ -z "$sha" ]]; then
        echo "ERROR: baseline non derivabile per ${rel}: nessun commit di creazione in history" >&2
        return 1
    fi
    printf '%s\n' "$sha"
}

# ---- Git wrappers -------------------------------------------------------------

lw_git_add() {
    git -C "$(lw_find_project_root)" add "$@"
}

# Stage + commit in una catena sola, limitata alla pathspec. Lo stage da solo non
# protegge niente: `git commit -m` SENZA pathspec committa l'intero indice, quindi
# un `lw_git_add <path>` seguito da un commit nudo portava dentro anche cio' che
# altre sessioni avevano lasciato in stage (un `git mv` stagia da se'). L'indice
# e' una zona comune del worktree: il perimetro lo fissa il COMMIT, non l'add.
#
# La pathspec e' obbligatoria: senza path la funzione rifiuta, perche' la forma
# senza path e' esattamente quella che produceva il guasto.
#
# Add e commit insieme perche' un commit parziale su un file che git non ha mai
# visto fallisce ("pathspec did not match"); `add -A` sulla pathspec registra
# creazioni, modifiche e cancellazioni solo su quei path. L'add salta i path che
# non esistono ne' su disco ne' nell'indice (gia' `git rm`-ati: l'add li rifiuta,
# il commit con pathspec li accetta perche' HEAD li conosce).
#
# Diff e commit saltano a loro volta i path che non stanno ne' su disco, ne'
# nell'indice, ne' in HEAD: un path cosi' non puo' produrre un diff, e passato a
# `git commit -- <pathspec>` lo fa uscire 1 ("pathspec did not match") anche con
# gli altri file in stage. Succede a chi nomina un file che in quel progetto non
# esiste — il checkpoint che mette `{docs_root}/reference/INDEX.md` nella pathspec
# di un consumer la cui doc vive in un corpus di gruppo, fuori dal repo.
#
# `-m` sta PRIMA di `--`: `--` chiude le opzioni, un `-m` dopo finirebbe fra i path.
#
# Exit: 0 = committato · 1 = add o commit falliti · 2 = nessuna modifica sui path
#       (no-op, nessun commit) · 3 = nessuna pathspec passata
lw_git_add_n_commit() {  # <msg> <path>...
    local msg="${1:-}" root p
    local -a to_add=() to_commit=()
    if [[ -z "$msg" ]]; then
        echo "ERROR: lw_git_add_n_commit: messaggio di commit mancante" >&2
        return 3
    fi
    shift
    if [[ $# -eq 0 ]]; then
        echo "ERROR: lw_git_add_n_commit: nessuna pathspec — un commit senza path committa l'intero indice, anche cio' che altre sessioni hanno in stage" >&2
        return 3
    fi
    root="$(lw_find_project_root)"
    for p in "$@"; do
        # i comandi git girano con -C root: un path relativo si risolve da li', non da $PWD
        if [[ -e "$p" || -L "$p" || -e "$root/$p" || -L "$root/$p" ]] \
           || [[ -n "$(git -C "$root" ls-files --cached -- "$p" 2>/dev/null)" ]]; then
            to_add+=("$p")
            to_commit+=("$p")
        elif [[ -n "$(git -C "$root" ls-tree -r --name-only HEAD -- "$p" 2>/dev/null)" ]]; then
            to_commit+=("$p")
        fi
    done
    if [[ ${#to_add[@]} -gt 0 ]]; then
        git -C "$root" add -A -- "${to_add[@]}" || return 1
    fi
    # lista vuota = nessun path esistente: un diff senza pathspec guarderebbe
    # l'intero indice, cioe' lo stage altrui
    [[ ${#to_commit[@]} -eq 0 ]] && return 2
    git -C "$root" diff --cached --quiet -- "${to_commit[@]}" && return 2
    git -C "$root" commit -m "$msg" -- "${to_commit[@]}" || return 1
    return 0
}

# Senza `origin` non fallisce: avvisa su stderr ed esce 0, cosi' la skill chiamante
# prosegue invece di rompersi a meta'. Il warning NON e' cosmetico — e' l'unica
# differenza percepibile fra "pushato" e "resta locale". Un no-op muto lascerebbe
# credere che il lavoro sia remoto, e ogni skill task-level chiude con un push.
lw_git_push() {
    if ! lw_has_remote; then
        echo "WARNING: nessun remote 'origin' — commit locali, niente push." >&2
        return 0
    fi
    local branch="${1:-}"
    if [[ -n "$branch" ]]; then
        git -C "$(lw_find_project_root)" push origin "$branch"
    else
        git -C "$(lw_find_project_root)" push
    fi
}

# ---- Git read helpers ---------------------------------------------------------

lw_current_branch() {
    git -C "$(lw_find_project_root)" branch --show-current
}

lw_current_sha() {
    git -C "$(lw_find_project_root)" rev-parse --short HEAD
}

lw_git_status_porcelain() {
    git -C "$(lw_find_project_root)" status --porcelain
}

# ---- Folder purge helpers ----------------------------------------------------

# Files that SURVIVE `git rm -rf <folder>`: untracked + ignored. `git rm` only
# touches TRACKED files, so a `.gitignore` inside the folder (or a root-level rule
# matching its content) leaves those files orphaned on disk after the purge. Lists
# them one-per-line, repo-relative; empty when the folder purges clean. <folder>
# is repo-relative. Note: `ls-files -o` WITHOUT `--exclude-standard` = untracked
# AND ignored — exactly the leftover set.
lw_folder_survivors() {  # <rel_folder>
    git -C "$(lw_find_project_root)" ls-files -o -- "$1" 2>/dev/null || true
}

# Guarded recursive delete for leftover ignored/untracked files that `git rm`
# cannot remove. Refuses anything not STRICTLY inside the canonicalized project
# root: no '/', no the root itself, no path outside it, no empty/unresolvable.
# Absolute-path only — "no disastri".
lw_safe_rmrf() {  # <path>
    local target root
    target="$(realpath -m -- "$1" 2>/dev/null || true)"
    root="$(realpath -m -- "$(lw_find_project_root)" 2>/dev/null || true)"
    if [[ -z "$target" || -z "$root" ]]; then
        echo "ERROR: lw_safe_rmrf: path non risolvibile: $1" >&2; return 1
    fi
    if [[ "$target" == "/" || "$target" == "$root" ]]; then
        echo "ERROR: lw_safe_rmrf: rifiuto rm di '/' o project root: $target" >&2; return 1
    fi
    case "$target" in
        "$root"/?*) : ;;   # deve stare STRETTAMENTE dentro il project root
        *) echo "ERROR: lw_safe_rmrf: path fuori dal project root ($root): $target" >&2; return 1 ;;
    esac
    rm -rf -- "$target"
}

# Shape of a task folder: `.YY-MM-DD-slug`, one single path component, inside
# project root. The two purge scripts touch a folder only when its `Folder` field
# has this shape: the field is free text in a task file, and without the guard
# any existing directory would count as a folder — `Folder: .` resolves to the
# project root and the apply would run `git rm -rf .`, `Folder: docs` would take
# the doc away. <rel_folder> is already normalized (no leading `./`, no trailing `/`).
lw_folder_shape_ok() {  # <rel_folder>
    local re='^\.[0-9]{2}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9][A-Za-z0-9._-]*$'
    [[ "$1" =~ $re ]]
}

# Who declares which task folder: one line `<folder>\t<task file basename>` for
# every task file in <tasks_dir> with a non-empty `Folder` field, minus the task
# files passed after <tasks_dir> — the tasks leaving in the same invocation — so
# the output names the tasks that keep a folder alive. Ordered by task id.
# The read is the one of read_field in the two purge scripts (first
# `- **Folder**:` line, first token of the value, so an annotation after the
# path does not spoil it), plus the normalization the scripts apply to their own
# field: leading `./` and one trailing `/` dropped, so `./.26-x/` and `.26-x` are
# the same folder.
# One awk pass over all files, not read_field per file: that is three processes
# per file, and in Git Bash a process costs ~150 ms.
lw_folder_declarers() {  # <tasks_dir> [<excluded task file>...]
    local dir="$1" f skip=" "
    shift
    for f in "$@"; do skip+="${f##*/} "; done
    local -a files=("$dir"/*.md)
    [[ ${#files[@]} -gt 0 && -e "${files[0]}" ]] || return 0
    awk -v skip="$skip" '
        FNR == 1 { found = 0; base = FILENAME; sub(/.*\//, "", base) }
        found { next }
        /^- \*\*Folder\*\*:/ {
            found = 1
            v = $0; sub(/^[^:]*: */, "", v)
            $0 = v
            if (NF == 0) next
            tok = $1
            sub(/^\.\//, "", tok); sub(/\/$/, "", tok)
            if (tok == "" || index(skip, " " base " ")) next
            print tok "\t" base
        }
    ' "${files[@]}" | LC_ALL=C sort -t "$(printf '\t')" -k2,2V
}

# Marked material of a task: the `## Materiale` entries that carry 💎 before
# their path — the user's "do not delete" — kept only when the path falls inside
# <rel_folder> and exists on disk, that is what a purge of that folder would
# delete. One root-relative path per line, in file order; empty when nothing
# marked is at risk. The caller decides whether the folder leaves in this
# invocation: a folder that stays puts nothing at risk, and is not asked about.
# Entry grammar, the one mandate.py reads: a line at column zero starting with
# `- `, glyphs, then the path in backticks. 💎 is a flag next to the role glyph
# (`📤💎`), so it is looked for anywhere before the first backtick.
# Path forms: `📁/…` resolved on <rel_folder>; an explicit path with `./` and
# `🏠/` dropped, inside when it is the folder or starts with `<folder>/`. A path
# with a `..` component is skipped: it can point outside the folder.
# One awk pass for the section: in Git Bash a process costs ~150 ms.
lw_folder_protected() {  # <task_file> <rel_folder>
    local tf="$1" rel="$2" root p
    [[ -n "$rel" && -f "$tf" ]] || return 0
    root="$(lw_find_project_root)"
    while IFS= read -r p; do
        [[ "$p" == "📁/"* ]] && p="${rel}/${p#📁/}"
        while [[ "$p" == ./* || "$p" == "🏠/"* ]]; do p="${p#./}"; p="${p#🏠/}"; done
        [[ "/${p}/" == */../* ]] && continue
        [[ "$p" == "$rel" || "$p" == "$rel"/* ]] || continue
        [[ -e "${root}/${p}" ]] || continue
        printf '%s\n' "$p"
    done < <(LC_ALL=C awk '
        /^## / { in_s = ($0 ~ /^## [Mm]ateriale/); next }
        in_s && /^- / {
            i = index($0, "`"); if (!i) next
            if (!index(substr($0, 1, i - 1), "💎")) next
            rest = substr($0, i + 1); j = index(rest, "`"); if (!j) next
            p = substr(rest, 1, j - 1)
            gsub(/^[ \t]+|[ \t]+$/, "", p)
            if (p != "") print p
        }
    ' "$tf")
}

# Removes from disk and index a task folder that leaves together with its task.
# `git rm` runs with --ignore-unmatch: on a folder with no tracked file — empty,
# or holding only untracked files under `--ignored-files purge` — a plain
# `git rm -rf` exits 128 ("non corrisponde ad alcun file"), and under `set -e`
# it stops the purge half-way: task file already out of the index, tasks.md row
# still there, no commit.
# What is left after `git rm` goes away in one of two ways:
#  - survivors listed by lw_folder_survivors (ignored, untracked): the gate has
#    already shown them and the caller chose keep|purge → guarded rm secco;
#  - no survivor: only the empty directories. Zero tracked and zero survivors
#    does not mean an empty directory — the content of a `.git` shows up neither
#    among tracked nor among untracked files — and an `rm -rf` would delete what
#    no gate has shown.
# <rel_folder> is repo-relative. The caller reads the tracked files BEFORE the
# call, if it needs them for the commit: afterwards they are gone from the index.
# Exit: 0 = folder gone from disk · 1 = error · 5 = folder still on disk
# (content git does not list: to be looked at by hand).
lw_folder_purge() {  # <rel_folder>
    local rel="$1" root abs
    if ! lw_folder_shape_ok "$rel"; then
        echo "ERROR: lw_folder_purge: '${rel}' non ha la forma .YY-MM-DD-slug — rifiuto" >&2
        return 1
    fi
    root="$(lw_find_project_root)"
    abs="${root}/${rel}"
    # Explicit checks: a caller using `lw_folder_purge … || rc=$?` turns off
    # `set -e` for the whole body, so a failing command would not stop here.
    git -C "$root" rm -rf --ignore-unmatch -- "$rel" || return 1
    [[ -e "$abs" ]] || return 0
    if [[ -n "$(lw_folder_survivors "$rel")" ]]; then
        lw_safe_rmrf "$abs" || return 1
        return 0
    fi
    find "$abs" -depth -type d -empty -delete || return 1
    [[ -e "$abs" ]] && return 5
    return 0
}

# ---- Error helpers -----------------------------------------------------------

die() {
    local msg="${*:-errore}"
    echo "ERROR: $msg" >&2
    local say_sh
    say_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/say.sh"
    if [[ -f "$say_sh" ]]; then
        # shellcheck source=/dev/null
        source "$say_sh" 2>/dev/null && say_auto "error $msg" 2>/dev/null || true
    fi
    exit 1
}
