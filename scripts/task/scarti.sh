#!/usr/bin/env bash

# =============================================================================
# scarti.sh — l'unico script che sa scrivere e interrogare il registro degli scarti
# Usage:
#   scarti.sh scarta --slug <slug> --chi umano|agente|delega --segnalazione <testo>
#                    --ancora <path> [--ancora <path>]... [--delega <testo>]
#                    [--supera <id>[#<voce>]]... [--perche <testo>] [--no-commit]
#                    [< il perché su stdin, in alternativa a --perche]
#   scarti.sh cerca  <ancora> [--superate]
#   scarti.sh migra
# =============================================================================
#
# Stato e requisiti rinviati: factory · T12 §Custodia — un limite del triage si segnala lì, non si apre una task qui.
#
# Questa e' la v0 di una feature progettata in factory: cio' che non fa e' scritto
# nel custode col segnale che lo renderebbe dovuto. Chi urta un limite usando il
# registro non ricostruisce da se' cosa manca e non apre una task in questo repo:
# il piano di crescita sta in un posto solo, e la riga sopra dice quale. Sta
# nell'artefatto e non nella doc perche' la doc e' as-is e non ammette id di task,
# e non in un task file perche' clean-tasks lo purga.
#
# Il registro degli scarti sta FUORI dal sistema documentale: la doc e' as-is e
# uno scarto e' datato e motivato per costruzione. Formato del record, sede e
# regole di supersessione: ${CLAUDE_PLUGIN_ROOT}/docs/scarti-format.md.
#
# Sede: {docs_root}/scarti/, un file per record, il nome del file E' l'id
# (YYYY-MM-DD-HHMM-<slug>). Un file per record e non un file unico perche' in
# detached piu' sessioni committano nello stesso worktree: un file condiviso
# entrerebbe intero nel commit della prima sessione che lo tocca.
#
# NON in adr/ della docs-root: quella cartella e' delle decisioni che confermano o
# cambiano un disegno, e un record che `cerca` trova fa tacere l'agente su una
# segnalazione. Una decisione positiva letta come scarto silenzierebbe una
# segnalazione che nessuno ha scartato.
#
# adr.sh, nella stessa cartella, e' il nome di prima: inoltra qui argomenti ed
# exit, perche' la regia lo chiama per nome.
#
# MIGRAZIONE — un progetto nato col registro in adr/ tiene li' i suoi scarti, e
# `cerca` non li vede: risponde «nessun record» come su un registro vuoto vero, e
# l'agente risolleva le segnalazioni gia' scartate. `migra` li sposta, sul solo
# progetto della cartella corrente; finche' non gira, `cerca` e `scarta` contano
# gli scarti rimasti in adr/ e lo dicono su stderr, senza cambiare l'exit — che
# e' il contratto letto da chi chiama. L'avviso scatta anche dopo la migrazione,
# quando una sessione rimasta su una versione precedente del plugin scrive un
# record nuovo in adr/.
#
# IMMUTABILITA' — l'invariante e' una riga sola: il comando rifiuta un path che
# esiste gia' (exit 2). Uno scarto superato si marca con un record NUOVO che
# nomina il vecchio in `Supera`; il vecchio resta leggibile dov'e'.
#
# DELEGA — il terzo autore: la regia che scarta su una delega che l'utente le ha
# dato nella sua chat. Vuole le parole della delega, alla lettera e su una riga
# (--delega), e le scrive nel campo `Delega` subito dopo `Chi`; senza, l'autore
# e' un rifiuto, e --delega con un altro autore pure. Le porta il record e non
# solo lo scenario di triage dello stesso scarto: questo comando si chiama anche
# da solo, senza scenario, e un record non si riscrive — il campo che manca alla
# nascita non si aggiunge piu'.
#
# Exit code per sottocomando:
#   scarta   0 record scritto
#            1 input malformato, ancora inesistente, chi = delega senza --delega
#              o --delega con un altro autore — NESSUNA scrittura
#            2 record gia' esistente — NESSUNA scrittura
#   cerca    0 almeno un record vivo trovato (elencato su stdout)
#            2 nessuno — e' il verdetto che l'agente legge prima di risollevare
#            1 errore d'uso
#   migra    0 almeno uno scarto spostato da adr/ a scarti/, e committato
#            2 niente da migrare (adr/ assente, vuota o senza scarti)
#            1 errore — NESSUN record spostato, nessun commit
#
# Il `2` distingue il rifiuto di riscrittura dall'input rotto: nelle famiglie di
# exit code del repo `2` e' sempre un VERDETTO e `1` un errore. Chi chiama sa
# quindi se riprovare con altri argomenti o con un altro slug.
#
# Env letto:
#   LOOM_SCARTI_NOW — epoch che sostituisce `now` (solo banco di test: id e
#                     campo Data devono essere deterministici per asserire su
#                     un path)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

ROOT="$(lw_find_project_root)"
SCARTI_DIR="${ROOT}/$(lw_docs_root)/scarti"
SCARTI_REL="$(lw_docs_root)/scarti"
# La sede di prima: la legge solo chi migra e chi avvisa che la migrazione manca.
VECCHIA_DIR="${ROOT}/$(lw_docs_root)/adr"
VECCHIA_REL="$(lw_docs_root)/adr"
# La riga che fa di un file uno scarto: la scrive `scarta` in ogni record, e
# distingue uno scarto da ogni altro file che sta in adr/.
RIGA_TIPO='- **Tipo**: scarto'

# `die` di lib.sh esce sempre 1 e suona il TTS: qui l'exit code e' il contratto,
# e un errore d'uso non e' un evento da annunciare a voce.
fail() {  # <exit> <messaggio>
    local rc="$1"; shift
    echo "[scarti] ERROR: $*" >&2
    exit "$rc"
}

# Gli scarti rimasti nella sede di prima, uno per riga (path assoluto). Solo i
# file di primo livello che portano la riga del tipo: un altro file in adr/ e' una
# decisione delle figure, e non e' affare di questo registro.
scarti_non_migrati() {
    [[ -d "$VECCHIA_DIR" ]] || return 0
    local f
    while IFS= read -r f; do
        grep -qxF -- "$RIGA_TIPO" "$f" && printf '%s\n' "$f"
    done < <(find "$VECCHIA_DIR" -maxdepth 1 -type f -name '*.md' | sort)
    return 0
}

# Su stderr, mai sull'exit: chi chiama legge l'exit di `cerca` come verdetto.
avvisa_non_migrati() {
    local n
    n="$(scarti_non_migrati | wc -l)"
    (( n > 0 )) || return 0
    echo "[scarti] AVVISO: ${n} scarti sono ancora in ${VECCHIA_REL}/, fuori dal registro — la ricerca non li vede. Spostali con: ${SCRIPT_DIR}/scarti.sh migra" >&2
}

# =============================================================================
# scarta
# =============================================================================
cmd_scarta() {
    local slug="" chi="" segnalazione="" perche="" delega="" delega_flag=0 no_commit=0
    local -a ancore_raw=() supera_raw=()

    avvisa_non_migrati

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --slug)         slug="${2:-}"; shift 2 ;;
            --chi)          chi="${2:-}"; shift 2 ;;
            --segnalazione) segnalazione="${2:-}"; shift 2 ;;
            --ancora)       ancore_raw+=("${2:-}"); shift 2 ;;
            --supera)       supera_raw+=("${2:-}"); shift 2 ;;
            --perche)       perche="${2:-}"; shift 2 ;;
            --delega)       delega="${2:-}"; delega_flag=1; shift 2 ;;
            --no-commit)    no_commit=1; shift ;;
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done

    # --- slug -----------------------------------------------------------------
    [[ -n "$slug" ]] || fail 1 "--slug obbligatorio — lo slug lo da' chi scrive, non si deriva dal testo: uno slug derivato non sarebbe prevedibile per chi deve citare il record in Supera"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
        || fail 1 "slug fuori formato: '${slug}' (atteso [a-z0-9-], iniziale alfanumerica)"

    # --- chi ------------------------------------------------------------------
    # Senza default di proposito: lo scarto deciso da un agente e' esattamente
    # cio' che l'umano vuole poter rileggere a campione, e un default renderebbe
    # i due indistinguibili. Lo stesso vale per lo scarto deciso su delega.
    case "$chi" in
        umano|agente|delega) ;;
        "") fail 1 "--chi obbligatorio (umano|agente|delega) — senza default: lo scarto dell'agente e quello su delega sono cio' che l'umano campiona" ;;
        *)  fail 1 "--chi deve essere umano|agente|delega (ricevuto: '${chi}')" ;;
    esac

    # --- delega: le parole dell'utente, solo con l'autore delega --------------
    if [[ "$chi" == delega ]]; then
        [[ -n "${delega//[[:space:]]/}" ]] \
            || fail 1 "--chi delega vuole --delega <le parole con cui l'utente ha dato la delega, alla lettera> — un record non si riscrive, e senza quelle parole lo scarto non e' riconducibile all'umano che l'ha affidato"
        [[ "$delega" == *$'\n'* ]] \
            && fail 1 "la delega sta su UNA riga: e' un campo di header — parole su piu' righe si uniscono con uno spazio"
    elif (( delega_flag )); then
        fail 1 "--delega vale solo con --chi delega: il record di '${chi}' non ha dove scriverla"
    fi

    # --- segnalazione ---------------------------------------------------------
    [[ -n "$segnalazione" ]] || fail 1 "--segnalazione obbligatoria"
    [[ "$segnalazione" == *$'\n'* ]] \
        && fail 1 "la segnalazione sta su UNA riga: e' cio' che l'agente confronta con quello che sta per risollevare"

    # --- perché: flag o stdin -------------------------------------------------
    if [[ -z "$perche" && ! -t 0 ]]; then
        perche="$(cat)"
    fi
    # trim delle righe vuote di testa e coda (la command substitution mangia gia'
    # i newline finali, ma --perche e un heredoc possono portarne di testa)
    while [[ "$perche" == $'\n'* ]]; do perche="${perche#$'\n'}"; done
    while [[ "$perche" == *$'\n' ]]; do perche="${perche%$'\n'}"; done
    [[ -n "$perche" ]] \
        || fail 1 "il perché e' obbligatorio: passalo con --perche o su stdin — uno scarto senza motivo non e' uno scarto, e' un rinvio"

    # --- ancore ---------------------------------------------------------------
    # La normalizzazione e' lw_norm_ancora di lib.sh, la stessa dello scenario
    # ignora di triage.sh: lo stesso file produce la stessa stringa nei due registri.
    [[ ${#ancore_raw[@]} -gt 0 ]] || fail 1 "--ancora obbligatoria (almeno una): senza un path il record non e' raggiungibile da chi cerca"
    local -a ancore=()
    local a norm rc
    for a in "${ancore_raw[@]}"; do
        norm="$(lw_norm_ancora "$ROOT" "$a")"; rc=$?
        case "$rc" in
            0) ancore+=("$norm") ;;
            2) fail 1 "ancora fuori dal project root (${ROOT}): ${a}" ;;
            *) fail 1 "ancora inesistente: ${a} — un path che non c'e' non e' un'ancora" ;;
        esac
    done

    # --- supera ---------------------------------------------------------------
    # Ogni <id> deve esistere in scarti/: un Supera verso un id inesistente e' un
    # refuso che nasconderebbe niente per sempre, in silenzio. Il frammento dopo
    # '#' NON si valida — il registro non ha ancora un parser di voci, e un
    # vincolo scritto adesso sulla loro forma sarebbe una premessa non misurata.
    local -a supera=()
    local s v id
    for s in ${supera_raw[@]+"${supera_raw[@]}"}; do
        while IFS= read -r v; do
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$v" ]] && continue
            id="${v%%#*}"
            [[ -n "$id" ]] || fail 1 "--supera senza id: '${v}'"
            [[ -f "${SCARTI_DIR}/${id}.md" ]] \
                || fail 1 "--supera nomina un record inesistente: ${id} (atteso ${SCARTI_REL}/${id}.md)"
            supera+=("$v")
        done < <(tr ',' '\n' <<< "$s")
    done

    # --- id e path ------------------------------------------------------------
    local now="${LOOM_SCARTI_NOW:-$(date +%s)}"
    local rec_id rec_data rec_file rec_rel
    rec_id="$(date -d "@${now}" '+%Y-%m-%d-%H%M' 2>/dev/null)" \
        || fail 1 "data non derivabile da LOOM_SCARTI_NOW='${now}'"
    rec_id="${rec_id}-${slug}"
    rec_data="$(date -d "@${now}" '+%Y-%m-%d %H:%M')"
    rec_file="${SCARTI_DIR}/${rec_id}.md"
    rec_rel="${SCARTI_REL}/${rec_id}.md"

    # L'INVARIANTE, in una riga: un record esistente non si riscrive.
    [[ -e "$rec_file" ]] && fail 2 "record gia' esistente: ${rec_rel} — un record non si modifica, uno scarto superato si marca con un record nuovo che lo nomina in Supera"

    mkdir -p "$SCARTI_DIR" || fail 1 "non riesco a creare ${SCARTI_REL}"

    # --- scrittura ------------------------------------------------------------
    # Il join si fa a mano e non con IFS + ${arr[*]}: un separatore di campo
    # globale riscriverebbe anche un path che contiene una virgola.
    local campo_ancore="" campo_supera="" x
    for x in "${ancore[@]}"; do campo_ancore+="${campo_ancore:+, }${x}"; done
    for x in ${supera[@]+"${supera[@]}"}; do campo_supera+="${campo_supera:+, }${x}"; done

    {
        printf '# %s\n\n' "$segnalazione"
        printf -- '- **Tipo**: scarto\n'
        printf -- '- **Data**: %s\n' "$rec_data"
        printf -- '- **Chi**: %s\n' "$chi"
        [[ "$chi" == delega ]] && printf -- '- **Delega**: %s\n' "$delega"
        printf -- '- **Ancore**: %s\n' "$campo_ancore"
        [[ -n "$campo_supera" ]] && printf -- '- **Supera**: %s\n' "$campo_supera"
        printf '\n## Perché\n\n%s\n' "$perche"
    } > "$rec_file" || fail 1 "scrittura fallita: ${rec_rel}"

    echo "-> record scritto: ${rec_rel}"

    # --- commit ---------------------------------------------------------------
    # Committa da se', con pathspec e senza push: il chiamante tipico e' il
    # modello in chat, in una sessione detached dove nessun altro commit
    # nominera' quel file — un record non committato e' uno scarto che puo'
    # ancora sparire. Chi batcha (una skill che chiude con un commit suo) passa
    # --no-commit.
    if (( no_commit )); then
        echo "   (--no-commit: il file resta da committare)"
        return 0
    fi
    local msg_seg="$segnalazione"
    [[ ${#msg_seg} -gt 60 ]] && msg_seg="${msg_seg:0:57}..."
    lw_git_add_n_commit "scarti: ${msg_seg}" "$rec_rel" >/dev/null
    case $? in
        0) echo "   committato: ${rec_rel}" ;;
        2) echo "   (nessuna modifica da committare)" ;;
        *) echo "[scarti] WARNING: commit fallito, il record resta sul disco: ${rec_rel}" >&2 ;;
    esac
    return 0
}

# =============================================================================
# cerca
# =============================================================================
#
# Match TESTUALE sul record intero — segnalazione, header e perché. Una regola
# sola copre path, keyword e id task, che stanno gia' dentro il testo: un campo
# ancora tipizzato in piu' sarebbe una seconda sorgente per la stessa ricerca, e
# le due divergerebbero al primo record scritto a mano.
#
# Un id task si cerca a PAROLA INTERA — `T16` non trova `T161` — come in
# resolve-task.sh --children. Tutto il resto e' sottostringa case-insensitive.
cmd_cerca() {
    local query="" mostra_superate=0

    avvisa_non_migrati

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --superate) mostra_superate=1; shift ;;
            -*) fail 1 "argomento ignoto: $1" ;;
            *) [[ -n "$query" ]] && fail 1 "una sola ancora per volta (ricevuto anche: $1)"
               query="$1"; shift ;;
        esac
    done
    [[ -n "$query" ]] || fail 1 "ancora richiesta: scarti.sh cerca <ancora> [--superate]"

    if [[ ! -d "$SCARTI_DIR" ]]; then
        echo "[scarti] registro vuoto: ${SCARTI_REL} non esiste" >&2
        return 2
    fi

    local -a records=()
    local f
    while IFS= read -r f; do records+=("$f"); done \
        < <(find "$SCARTI_DIR" -maxdepth 1 -type f -name '*.md' | sort)
    if [[ ${#records[@]} -eq 0 ]]; then
        echo "[scarti] registro vuoto: nessun record in ${SCARTI_REL}" >&2
        return 2
    fi

    # --- mappa della supersessione -------------------------------------------
    # Si costruisce sul registro INTERO, non sui soli match: un record superato
    # da uno che la query non trova resta superato.
    local -A sup_intero=() sup_voci=()
    local rid campo v tid frag
    for f in "${records[@]}"; do
        campo="$(sed -n 's/^- \*\*Supera\*\*:[[:space:]]*//p' "$f" | head -1)"
        [[ -n "$campo" ]] || continue
        rid="$(basename "$f" .md)"
        while IFS= read -r v; do
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$v" ]] && continue
            tid="${v%%#*}"; frag=""
            [[ "$v" == *#* ]] && frag="${v#*#}"
            if [[ -z "$frag" ]]; then
                sup_intero["$tid"]="${sup_intero[$tid]:+${sup_intero[$tid]}, }${rid}"
            else
                sup_voci["$tid"]="${sup_voci[$tid]:+${sup_voci[$tid]}, }${frag}"
            fi
        done < <(tr ',' '\n' <<< "$campo")
    done

    # --- selezione ------------------------------------------------------------
    local -a grep_opts
    if [[ "$query" =~ ^T[0-9]+$ ]]; then
        grep_opts=(-q -w -F --)
    else
        grep_opts=(-q -i -F --)
    fi

    local trovati=0 nascosti=0 id titolo chi data ancore
    for f in "${records[@]}"; do
        grep "${grep_opts[@]}" "$query" "$f" || continue
        id="$(basename "$f" .md)"

        # Superato INTERO -> fuori dalla query. Superato per VOCE -> resta, con
        # l'annotazione: nascondere un record intero perche' un altro ne supera
        # una voce sola sarebbe nascondere cio' che e' ancora vivo.
        if [[ -n "${sup_intero[$id]:-}" ]] && (( ! mostra_superate )); then
            nascosti=$((nascosti+1))
            continue
        fi

        titolo="$(sed -n '1s/^#[[:space:]]*//p' "$f")"
        chi="$(sed -n 's/^- \*\*Chi\*\*:[[:space:]]*//p' "$f" | head -1)"
        data="$(sed -n 's/^- \*\*Data\*\*:[[:space:]]*//p' "$f" | head -1)"
        ancore="$(sed -n 's/^- \*\*Ancore\*\*:[[:space:]]*//p' "$f" | head -1)"

        printf '%s · %s · %s' "$id" "${chi:-?}" "${data:-?}"
        [[ -n "${sup_intero[$id]:-}" ]] && printf '   [SUPERATO da %s]' "${sup_intero[$id]}"
        printf '\n'
        printf '  %s\n' "$titolo"
        [[ -n "$ancore" ]] && printf '  ancore: %s\n' "$ancore"
        # L'annotazione stampa i FRAMMENTI trovati nei Supera altrui, non il testo
        # della voce: non richiede un parser di voci, e resta vera quando i record
        # con voci arriveranno.
        [[ -n "${sup_voci[$id]:-}" ]] && printf '  voci superate: %s\n' "${sup_voci[$id]}"
        printf '  file: %s/%s.md\n\n' "$SCARTI_REL" "$id"
        trovati=$((trovati+1))
    done

    if (( trovati == 0 )); then
        # `nascosti` vale "0" quando non ce ne sono, e "0" e' una stringa non
        # vuota: il ramo si sceglie sul NUMERO, non sulla presenza della variabile.
        if (( nascosti > 0 )); then
            echo "[scarti] nessun record vivo per '${query}' (${nascosti} superati, nascosti — rilancia con --superate)" >&2
        else
            echo "[scarti] nessun record per '${query}'" >&2
        fi
        return 2
    fi
    (( nascosti > 0 )) && echo "[scarti] ${nascosti} record superati non mostrati (--superate per vederli)" >&2
    return 0
}

# =============================================================================
# migra
# =============================================================================
#
# Sposta nel registro gli scarti rimasti nella sede di prima, sul SOLO progetto
# della cartella corrente, come `cerca` e `scarta`. Non percorre il registry dei
# progetti: quello e' un fatto di questa macchina, e il comando deve girare anche
# dove il registry e' un altro; un giro su piu' progetti e' un ciclo fuori da qui.
#
# Sposta i soli file di primo livello che portano la riga del tipo. Ogni altro
# file resta in adr/ ed e' elencato: adr/ e' delle decisioni delle figure, e un
# `migra` lanciato settimane dopo non deve portarne una nel registro che fa
# tacere l'agente. A fine giro adr/ si toglie solo se e' rimasta vuota — git non
# traccia le cartelle, e sugli altri cloni sparisce da sola al pull.
#
# Tutto o niente: collisioni con un id gia' in scarti/, record non tracciati o
# modificati si controllano PRIMA del primo spostamento, e uno spostamento o un
# commit che fallisce a meta' rimette a posto quelli gia' fatti. Un record
# modificato o non committato e' lavoro di un'altra sessione: spostarlo lo
# porterebbe in un commit che non e' il suo.
#
# Il commit porta i soli file spostati, ai due path, e non pusha: un push
# pubblicherebbe tutti i commit che il ramo locale ha in piu' del remote, non il
# solo commit della migrazione.
#
# I file che citano un record per path (`adr/<id>.md`) non si riscrivono: un task
# file racconta un momento passato, e in un progetto vivo altre sessioni possono
# averli aperti. L'id non cambia, e `cerca <id>` stampa il path nuovo; `migra`
# li elenca.
cmd_migra() {
    [[ $# -eq 0 ]] \
        || fail 1 "migra non prende argomenti (ricevuto: $1) — gira sul progetto della cartella corrente"

    if [[ ! -d "$VECCHIA_DIR" ]]; then
        echo "[scarti] niente da migrare: ${VECCHIA_REL}/ non esiste" >&2
        return 2
    fi

    local -a da_spostare=() altri=()
    local -A spostabile=()
    local f nome
    while IFS= read -r f; do
        da_spostare+=("$f")
        spostabile["$f"]=1
    done < <(scarti_non_migrati)
    while IFS= read -r f; do
        [[ -n "${spostabile[$f]:-}" ]] || altri+=("$f")
    done < <(find "$VECCHIA_DIR" -mindepth 1 -maxdepth 1 | sort)

    if [[ ${#da_spostare[@]} -eq 0 ]]; then
        for f in ${altri[@]+"${altri[@]}"}; do
            echo "   resta in ${VECCHIA_REL}/: ${f##*/} — non e' uno scarto"
        done
        rmdir -- "$VECCHIA_DIR" 2>/dev/null \
            && echo "-> ${VECCHIA_REL}/ rimossa: era vuota"
        echo "[scarti] niente da migrare: nessuno scarto in ${VECCHIA_REL}/" >&2
        return 2
    fi

    # --- controlli, prima del primo spostamento -------------------------------
    local -a problemi=()
    local vecchio nuovo
    for f in "${da_spostare[@]}"; do
        nome="${f##*/}"
        vecchio="${VECCHIA_REL}/${nome}"
        nuovo="${SCARTI_REL}/${nome}"
        if [[ -e "${SCARTI_DIR}/${nome}" ]]; then
            problemi+=("${vecchio}: ${nuovo} esiste gia' — un record non si sovrascrive")
        elif ! git -C "$ROOT" ls-files --error-unmatch -- "$vecchio" >/dev/null 2>&1; then
            problemi+=("${vecchio}: non e' tracciato da git — committalo, poi rilancia")
        elif ! git -C "$ROOT" diff --quiet HEAD -- "$vecchio" 2>/dev/null; then
            problemi+=("${vecchio}: ha modifiche non committate — committale, poi rilancia")
        fi
    done
    if [[ ${#problemi[@]} -gt 0 ]]; then
        for f in "${problemi[@]}"; do echo "[scarti]   ${f}" >&2; done
        fail 1 "migrazione rifiutata, ${#problemi[@]} record non spostabili — nessun record spostato"
    fi

    # --- spostamento, tutto o niente ------------------------------------------
    local -a fatti=() paths=()
    rimetti() {  # rimette in adr/ i record gia' spostati
        local n
        mkdir -p -- "$VECCHIA_DIR"
        for n in ${fatti[@]+"${fatti[@]}"}; do
            git -C "$ROOT" mv -- "${SCARTI_REL}/${n}" "${VECCHIA_REL}/${n}" >/dev/null 2>&1 \
                || echo "[scarti] ERROR: non riesco a rimettere ${n} in ${VECCHIA_REL}/" >&2
        done
    }
    mkdir -p -- "$SCARTI_DIR" || fail 1 "non riesco a creare ${SCARTI_REL}"
    for f in "${da_spostare[@]}"; do
        nome="${f##*/}"
        if ! git -C "$ROOT" mv -- "${VECCHIA_REL}/${nome}" "${SCARTI_REL}/${nome}" >/dev/null; then
            rimetti
            fail 1 "git mv fallito su ${VECCHIA_REL}/${nome} — nessun record spostato"
        fi
        fatti+=("$nome")
        paths+=("${VECCHIA_REL}/${nome}" "${SCARTI_REL}/${nome}")
    done

    local rimossa=0
    rmdir -- "$VECCHIA_DIR" 2>/dev/null && rimossa=1

    local n_fatti=${#fatti[@]}
    if ! lw_git_add_n_commit "scarti: migra ${n_fatti} record da ${VECCHIA_REL}/ a ${SCARTI_REL}/" \
            "${paths[@]}" >/dev/null; then
        rimetti
        fail 1 "commit fallito — i record sono tornati in ${VECCHIA_REL}/"
    fi

    for nome in "${fatti[@]}"; do
        echo "-> spostato: ${VECCHIA_REL}/${nome} → ${SCARTI_REL}/${nome}"
    done
    echo "-> committato: $(git -C "$ROOT" log -1 --format=%h -- "${SCARTI_REL}/${fatti[0]}") (${n_fatti} record, senza push)"
    if (( rimossa )); then
        echo "-> ${VECCHIA_REL}/ rimossa: era vuota"
    else
        echo "-> ${VECCHIA_REL}/ resta: contiene file che non sono scarti"
        for f in ${altri[@]+"${altri[@]}"}; do
            echo "   resta in ${VECCHIA_REL}/: ${f##*/} — non e' uno scarto"
        done
    fi

    # --- chi cita un record spostato per path ---------------------------------
    local -a pattern=()
    for nome in "${fatti[@]}"; do pattern+=(-e "adr/${nome%.md}"); done
    local citanti
    citanti="$(git -C "$ROOT" grep -l -F "${pattern[@]}" 2>/dev/null)"
    if [[ -n "$citanti" ]]; then
        echo "-> citano un record spostato col path di prima (non riscritti: \`scarti.sh cerca <id>\` stampa il path nuovo):"
        while IFS= read -r f; do echo "   ${f}"; done <<< "$citanti"
    fi
    return 0
}

# =============================================================================
# dispatch
# =============================================================================
[[ $# -gt 0 ]] || fail 1 "sottocomando richiesto: scarta | cerca | migra"
SUB="$1"; shift
case "$SUB" in
    scarta) cmd_scarta "$@" ;;
    cerca)  cmd_cerca "$@" ;;
    migra)  cmd_migra "$@" ;;
    *) fail 1 "sottocomando ignoto: ${SUB} (attesi: scarta, cerca, migra)" ;;
esac
