---
name: align-doc
description: Allinea la doc alla fonte nativa del suo layer — caccia ai drift (la doc dice X, il codice o la fonte viva dicono Y). Integra anche le nozioni di una task chiusa. Non presidiata, committa da sé. Fan-out di doc-auditor read-only, registro con verdetti, patch via doc-writer, collaudo via doc-verifier.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Confronta la doc di progetto con la **fonte nativa del suo layer** e trova i **drift**: fatti documentati che la fonte smentisce.

Input utente (perimetro: dir, glob, submodule, file doc, task ID — oppure vuoto):
~~~human
$ARGUMENTS
~~~

## Drift, non lacune

Il bersaglio non è coprire quello che manca, è **trovare quello che mente**.

- Una **lacuna** (fatto vero, non documentato) è auto-limitante: chi la incontra apre la fonte.
- Un **drift** (fatto documentato ≠ realtà) è attivamente dannoso: la doc offline esiste proprio per *sostituire* quella lettura, quindi chi si fida agisce su una realtà che non esiste — e nessun segnale gli dice di verificare.

Da qui l'asimmetria di tutto il flusso: si parte dalle **affermazioni della doc** e si va a verificarle nella fonte, mai il contrario. Partire dalla fonte produce copertura, non allineamento, e non termina mai.

L'unica eccezione è il perimetro **task** (§0): lì le affermazioni da verificare non stanno nella doc, stanno nel task file — ma la direzione resta la stessa, dall'affermazione alla fonte.

Gemella di `lint-doc`, che misura la stessa doc contro il **contratto editoriale** invece che contro la fonte nativa. Stessa meccanica, fonte di verità opposta.

## Non presidiata — nessuna domanda, e il collaudo è un agente

`AskUserQuestion` non è nel toolset. La skill sceglie il perimetro con un criterio deterministico (§1), applica i verdetti dell'auditor senza farli approvare, li fa collaudare da `doc-verifier` (§6) e committa (§7).

Il gate umano che stava fra il registro e la patch è stato **rimosso**: era l'unico collaudo della skill, e non può esserlo per una skill che gira anche di notte. Chi lo sostituisce misura la patch contro il contratto, non contro il gusto di chi guarda.

**Guardia in ingresso, prima di qualunque altra cosa.** Se `git diff --cached --quiet` esce non-zero l'indice è già popolato da qualcun altro: **fermati e dillo**. Il commit di questa skill ha una pathspec esplicita, e con un indice sporco porterebbe via lavoro non tuo.

**Mai staged fino al commit.** Lo stage git è uno per *worktree*, non per sessione: una patch lasciata nell'indice viene raccolta dal `git add -A` di qualunque altra sessione che committi nel frattempo. Le patch vivono quindi solo nel working tree, il collaudo legge `git diff` non-staged, e il commit è una catena unica — `git add -- <path...> && git commit -m "..." -- <path...>`.

## La fonte nativa non è sempre il codice

Ogni affermazione appartiene a un layer, e il layer decide contro **cosa** si misura:

- **codice** — si apre e si legge. Nomi di simboli, default, precedenze, formati, sequenze di chiamata.
- **fonte viva** — si **interroga**: `--help` di un CLI, uno schema servito da un MCP, un endpoint, la suite di test. Risponde dallo stato attuale, quindi la sua risposta non può essere stantia.

Chi interroga dipende da dove arriva la fonte. Se basta `Bash` (un `--help`, una query da riga di comando), la esegue l'auditor. Se serve uno strumento che l'auditor non ha — un MCP — **la query la fai tu prima del fan-out** e passi la risposta nel prompt come materiale già raccolto, stesso pattern con cui `lint-doc` passa le misure di `doc-metrics.sh`. Se la fonte non è raggiungibile da nessuno dei due, il perimetro si dichiara non verificabile e si salta: una verifica simulata è peggio di una verifica mancata.

È il caso in cui la doc di uno schema DB va misurata contro il DB, non contro il codice che lo interroga.

## Flusso

### 0. Perimetro «task» — le nozioni di una task che ha finito di muoversi

Solo se l'input è un **task ID** (`T63`) o «task attiva». Il perimetro non è un'area di fonte: sono le nozioni che quella task ha prodotto, da verificare e far atterrare. Dal §3 in poi il flusso è identico — cambia solo da dove escono le affermazioni da verificare.

**Indice d'ingresso: le voci `## Doc Impact` senza marker.** Il checkpoint ne appende uno a ogni voce che lavora — `→ ✔️ inbox` o `→ ✖️ <parola>` — quindi l'assenza è esattamente il segnale «mai guardata»: non serve inventare un registro. Conseguenza pratica — una task su cui nessun checkpoint ha girato entra comunque nello scope.

**Bound di scope**: apri le fonti **di quella task e basta**. Nessuna scansione delle folder del progetto, nessun giro su altre task. Senza questo bound il costo tolto al checkpoint rientra intero dalla finestra.

Tre fonti, che non valgono uguale:

- **`## Doc Impact`** — scritta a `create-task`, cioè *prima* di lavorare. È una **previsione**, non un referto: ha già il formato giusto (nozione + ancora) e per questo sembra affidabile, ma l'esecuzione può averla smentita. Si verifica contro il risultato, non si integra alla lettera.
- **task file** (Description, Implementation Notes, Progress Log) — segnale/rumore basso: per lo più intenzione e cronaca. Si legge per capire il contesto, non per copiarne frasi.
- **task folder** (campo `**Folder**:`, se popolato) — valore più alto *e* costo più alto: è dove stanno referto e sentenza. **Si legge per nomi e intestazioni**, aprendo solo i file che promettono nozione (`valutazione-*`, `findings`, benchmark); mai i dump. È l'INDEX applicato alla folder.

**Ogni voce è un semilavorato**, e questo cambia il ruolo: non la riformatti, la lavori.

- **potenzialmente ridondante** → deduplica contro il corpo del file doc target prima di proporla: la nozione può già esserci, scritta meglio.
- **potenzialmente incompleta** → hai **licenza di cercare** (altre fonti, il codice). Chi ha scritto la voce lo ha fatto prima di lavorare; tu arrivi dopo, col codice assestato e la nozione ferma.

Il rischio specifico di questo perimetro è opposto al drift: **gonfiare la doc con materiale di processo**. Una folder contiene anche alternative bocciate con motivazione *provvisoria*, poi riprese — quelle sono scarto, non sentenza. Lo tagliano i test «sopravvive alla task» e «sopravvive al refactor» di `doc-criteria.md`; la parola che fa il lavoro è **definitiva**.

Al fan-out (§2) passa all'auditor l'**elenco esplicito** delle nozioni candidate, ognuna con la fonte nativa contro cui verificarla. È l'elenco che gli toglie il tetto dei 3 gap: la selezione l'hai già fatta tu.

Chiudendo (§7), marca nel task file ogni voce integrata con `→ ✔️ align` — stesso schema dei marker `→ ✔️ inbox` / `→ ✖️ <parola>` che appende il checkpoint. Senza il marker il prossimo `checkpoint-task` rilavora voci già collocate, e le manda in inbox una seconda volta.

### 1. Risolvi i perimetri

Un perimetro = **una coppia** `fonte ↔ file doc`. Dall'input:

- **path di codice** (`loom-deck/src/`, `scripts/config/`) → trova la doc che lo descrive: `grep -rl` del nome dir/file dentro `{docs_root}/`, più i TLDR di `{docs_root}/reference/INDEX.md` che lo nominano.
- **file doc** (`reference/compass.md`) → trova la fonte: i path citati dentro il file stesso; e se il file descrive un sistema interrogabile (uno schema DB, un CLI esterno), la fonte è **quello**, non il codice che lo usa.
- **vuoto** → deriva i candidati dall'INDEX (ogni file reference che cita path o comandi reali) e prendi i **primi 4 per char decrescente**. Il cap è di concorrenza, il criterio è deterministico: un file grosso porta più affermazioni verificabili, quindi più drift per auditor speso. Dichiara sempre quali perimetri hai preso e quali sono rimasti fuori — una selezione taciuta si legge come copertura completa.

Se una coppia non si chiude (doc senza fonte identificabile), **non inventarla**: dillo e saltala. Un perimetro senza fonte di verità è lavoro per `lint-doc`, non per questa skill.

Se la fonte è viva e richiede un MCP, **interrogala ora**, prima del fan-out: raccogli le risposte alle domande che la doc pretende di sostituire (la forma di una tabella, l'elenco reale delle opzioni) e portale nel prompt dell'auditor.

### 2. Fan-out doc-auditor

Un `Task` con `subagent_type: doc-auditor` **per perimetro**, tutti nello stesso messaggio → girano in parallelo. È possibile solo perché l'auditor è read-only: nessuno tocca il working tree, nessun conflitto.

Prompt per ogni auditor:

```
Perimetro:
- Fonte: <path/glob concreti, oppure il comando/schema da interrogare>
- Doc: <file doc del perimetro>

Fonte di verità: fonte-nativa

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — otto test e sette tipologie offline, da leggere quando la collocazione non è ovvia.
Prefisso ID: <sigla corta del perimetro, es. DECK>

Risposte pre-raccolte: <solo se la fonte viva è MCP-only — le risposte che hai già ottenuto>

Cerca drift: parti dalle affermazioni verificabili della doc e apri o interroga la fonte.
Segnala relayer quando la doc ha copiato ciò che la fonte già risponde.
Ogni finding porta EVIDENCE verificata davvero (path:linea, o il comando interrogato).
Ritorna solo il registro.
```

Sul perimetro **task** (§0) il prompt cambia in tre punti: `Nozioni candidate:` con l'elenco esplicito al posto della doc da ispezionare, `Doc:` diventa il file target su cui deduplicare, e la richiesta è «verifica ogni nozione contro la fonte nativa e dì quali reggono» invece di «cerca drift».

### 3. Consolida il registro

Unisci i registri in **un unico file**, ordinato per severità (alta prima). Dove atterra lo risolve uno script, non una domanda:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/resolve-registry-path.sh" --name align-doc-findings.md
```

Cascata: task attiva con `**Folder**:` popolato → quella folder · task attiva senza folder → la crea (`set-task-folder.sh`, che riscrive il campo) · nessuna task → scratch `.YY-MM-DD-align-doc-findings`. Usa la riga `REGISTRY_PATH=` che stampa.

Mai dentro `{docs_root}/`: è materiale di lavoro, non doc di progetto.

Poi presenta in chat la **sintesi**, non il registro intero: una riga per finding (`ID · severità · file doc · claim → realtà · verdetto proposto`). Il dettaglio sta nel file.

I verdetti proposti dagli auditor **valgono come approvati**: non c'è un passo che li raccoglie e li fa confermare. Quello che li misura è il collaudo del §6, e misura la patch — non l'intenzione.

### 4. Applica — doc-writer su `fix-doc`, `relayer`, `split`

Raggruppa le voci approvate **per file doc target** e invoca un `doc-writer` per gruppo (mai due writer sullo stesso file: si sovrascrivono a vicenda). Sequenziali, non paralleli — questi scrivono davvero.

**Ogni voce porta il proprio verdetto**, non solo le `relayer`. Il writer non giudica: se una voce arriva senza verdetto e senza target esplicito, o rifiuta o improvvisa — è il modo tipico in cui una correzione atterra nel posto sbagliato.

```
Rotte da applicare — verdetto e target sono già decisi e vincolanti, non rivalutarli.
Target: <file doc>

<una voce per finding del registro:>
NOTION: <il claim, come la doc lo scrive oggi>
VERDICT: fix-doc | relayer | drop
TARGET: <file>.md §<sezione>
POINTER: <file + simbolo> | <comando + forma della domanda> | —
EVIDENCE: <path:linea | comando interrogato>
WRITE: <cosa deve diventare la sezione — per fix-doc la realtà as-is; per relayer «cancella la copia, resta il puntatore»; per drop il motivo>

Contesto:
<le voci del registro per questo file: CLAIM / REALITY / EVIDENCE / FIX>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Formule TLDR: ${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md — il TLDR resta invariato salvo che un fix cambi il trigger del file.

Applica le patch direttamente (Write/Edit), non committare, non rigenerare l'indice, non stagiare niente.
Sostituisci la sezione sbagliata, non appendere una correzione accanto a quella vecchia.
Ritorna il contratto APPLIED: + INDEX_REBUILD_NEEDED.
```

Il `POINTER:` di una `relayer` lo produce **l'auditor**, che ha già aperto la fonte per giudicare: il writer lo trascrive senza riaprire niente. Aggiornare la copia invece di cancellarla la farebbe driftare di nuovo.

`drop` e `relayer` passano dallo stesso canale (sono patch di rimozione, con o senza puntatore che resta). `code-divergent` **no**: la doc resta.

### 5. `code-divergent` → task, non patch

Per ogni voce con questo verdetto la doc descrive l'intenzione e la fonte ci è andata contro: correggere la doc **cancellerebbe l'intenzione**. Proponi `/loom-works:create-task` con titolo e razionale già pronti, e lascia la scelta all'utente. Se una task per quel perimetro esiste già (cerca in `{docs_root}/tasks.md`), citala con la sua maniglia verbo+oggetto invece di aprirne una gemella.

### 6. Guardiani, poi collaudo — `doc-verifier` sul diff

Prima gli script, che non hanno opinioni:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"       # solo se le patch hanno toccato reference/
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
```

**Exit 2 è un verdetto, non un comando fallito** — su `build-index.sh` significa indice scritto ma TLDR oltre il cap, su `check-doc-links.sh` riferimenti appesi. Il secondo è il caso tipico qui: i verdetti `relayer` e `drop` **cancellano** una sezione, e il puntatore che la citava resta valido sul path e falso sulla `§` — invisibile a un grep. Risolvi i `NOSECTION` con `Edit` finché lo script non esce 0; il resto passa al collaudo, che decide se è rollback o coda.

Poi il collaudo, una volta, a patch applicate e prima del commit. `Task` con `subagent_type: doc-verifier`.

```
Patch da collaudare — allineamento su <i perimetri>.

File toccati (dai contratti APPLIED: dei writer):
<la lista coi marker NEW / MOD / DEL>

Registro dei verdetti che hanno ordinato questa patch:
<le voci del registro: claim / realtà / verdetto / target>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.

Esiti dei guardiani (fatti deterministici, non ricontarli):
- build-index.sh: exit <n> <+ i TLDR oltre cap che ha elencato, se ce ne sono>
- check-doc-links.sh: exit <n>, riferimenti appesi residui: <la lista, o «nessuno»>

La patch non è staged: leggila con `git diff` sul working tree.
Ritorna solo il referto.
```

- **`LABEL: accodato` non boccia**: un file che dopo la patch supera la soglia di split o scende sotto il pavimento è topologia che la patch ha *rivelato*, non causato, e la raccoglie `lint-doc` alla prossima misura. Riportala e prosegui.
- **`OUTCOME: rollback` annulla la patch**, per file secondo il marker: `MOD` → `git checkout -- <path>` · `NEW` → `rm -- <path>` · `DEL` → `git checkout -- <path>`. Le voci del registro tornano non applicate, col motivo — la `RULE:` della violazione — scritto sopra. Niente commit, e i marker `→ ✔️ align` del §0 **non** si scrivono: quelle nozioni non sono atterrate.

Se hai già rigenerato l'indice, dopo un rollback **rigeneralo di nuovo**: contiene la voce di un file che adesso non esiste più, ed è drift prodotto dal rollback stesso.

### 7. Chiudi e committa

Solo su collaudo `pass`.

- Sul perimetro **task** (§0): marca `→ ✔️ align` le voci `## Doc Impact` integrate, nel task file. È l'unico file di runtime che questa skill tocca — e lo tocca lei, mai il `doc-writer`, che ha `{docs_root}/tasks/` fuori dal proprio perimetro.
- **Non stampare i diff** in chat: bruciano contesto e sono già ispezionabili nel pannello git. Stampa la lista file dal contratto `APPLIED:`.
- **Committa**, catena unica con pathspec esplicita:
  ```bash
  git add -- <path...> && git commit -m "docs(align): <perimetro>" -m "<corpo>" -- <path...>
  ```
  La pathspec sono tutti i file di `APPLIED:`, più `INDEX.md` se il rebuild l'ha toccato e il task file se hai scritto i marker. Su un `DEL` serve `git add -A -- <path>`, o la cancellazione non entra nell'indice e il commit fa rinascere il file. Il **corpo** porta il blocco `DISCARDED:` del writer: è materiale che ha deciso di non scrivere, e il posto durevole di quel verdetto è il messaggio di commit.
- **Non pusha.** Finché i commit restano locali l'undo è una riga; pushati, diventa un force-push su un ramo che altre sessioni possono già aver letto.
- Report finale: quanti finding per verdetto, quali file toccati, quali voci restano nel registro non applicate, e l'esito del collaudo. Su `rollback` la riga di chiusura dice **cosa** ha violato la patch, non «bocciata».

## Note

- **Il registro sopravvive all'esecuzione.** Le voci non applicate (severità bassa, verdetto rinviato) restano nel file: la prossima esecuzione sullo stesso perimetro parte da lì invece di riscoprirle.
- **Non fondere con `discover`**: quella presuppone doc **zero** e scansiona la struttura per produrre lo scaffold; questa presuppone doc **esistente** e la mette a confronto con la fonte.
- **Perimetro task vs `capture-doc`**: stessa destinazione, momento diverso. `capture-doc` integra una nozione **calda**, mentre la task è aperta e il codice si muove ancora; il §0 la integra **dopo**, con più fonti e la nozione ferma. Il secondo non rimpiazza il primo — lo rende non obbligatorio.
- Un perimetro pulito che risulta pulito è l'esito migliore. Se un auditor torna con `FINDINGS: 0`, riportalo così — non rilanciarlo con istruzioni più aggressive per trovare qualcosa.
