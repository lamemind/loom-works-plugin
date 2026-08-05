---
name: align-doc
description: Allinea la doc alla fonte nativa del suo layer — caccia ai drift (la doc dice X, il codice o la fonte viva dicono Y). Integra anche le nozioni di una task chiusa. Fan-out di doc-auditor read-only, registro con verdetti, patch via doc-writer solo sulle voci approvate.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
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

## La fonte nativa non è sempre il codice

Ogni affermazione appartiene a un layer, e il layer decide contro **cosa** si misura:

- **codice** — si apre e si legge. Nomi di simboli, default, precedenze, formati, sequenze di chiamata.
- **fonte viva** — si **interroga**: `--help` di un CLI, uno schema servito da un MCP, un endpoint, la suite di test. Risponde dallo stato attuale, quindi la sua risposta non può essere stantia.

Chi interroga dipende da dove arriva la fonte. Se basta `Bash` (un `--help`, una query da riga di comando), la esegue l'auditor. Se serve uno strumento che l'auditor non ha — un MCP — **la query la fai tu prima del fan-out** e passi la risposta nel prompt come materiale già raccolto, stesso pattern con cui `lint-doc` passa le misure di `doc-metrics.sh`. Se la fonte non è raggiungibile da nessuno dei due, il perimetro si dichiara non verificabile e si salta: una verifica simulata è peggio di una verifica mancata.

È il caso in cui la doc di uno schema DB va misurata contro il DB, non contro il codice che lo interroga.

## Flusso

### 0. Perimetro «task» — le nozioni di una task che ha finito di muoversi

Solo se l'input è un **task ID** (`T63`) o «task attiva». Il perimetro non è un'area di fonte: sono le nozioni che quella task ha prodotto, da verificare e far atterrare. Dal §3 in poi il flusso è identico — cambia solo da dove escono le affermazioni da verificare.

**Indice d'ingresso: le voci `## Doc Impact` non marcate `→ ✔️`.** Quel marker esiste già ed è esattamente il segnale «non consolidata»: non serve inventare un registro. Conseguenza pratica — un checkpoint frettoloso, che non ha scritto niente in doc, non perde niente: la task entra comunque nello scope.

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

Chiudendo (§7), marca nel task file ogni voce integrata con `→ ✔️ align` — stesso schema dei marker `→ ✔️ capture` / `→ ✔️ D{N}`. Senza il marker il prossimo `checkpoint-task` ripresenta al gate voci già consolidate.

### 1. Risolvi i perimetri

Un perimetro = **una coppia** `fonte ↔ file doc`. Dall'input:

- **path di codice** (`loom-deck/src/`, `scripts/config/`) → trova la doc che lo descrive: `grep -rl` del nome dir/file dentro `{docs_root}/`, più i TLDR di `{docs_root}/reference/INDEX.md` che lo nominano.
- **file doc** (`reference/compass.md`) → trova la fonte: i path citati dentro il file stesso; e se il file descrive un sistema interrogabile (uno schema DB, un CLI esterno), la fonte è **quello**, non il codice che lo usa.
- **vuoto** → deriva i candidati dall'INDEX (ogni file reference che cita path o comandi reali) e falli scegliere con `AskUserQuestion` — massimo 4 perimetri per esecuzione, altrimenti il registro diventa illeggibile e il gate dei verdetti impraticabile.

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

### 4. Gate dei verdetti — in blocco

I verdetti si raccolgono **una volta sola sul registro completo**, non finding per finding: N domande in sequenza costano più della lettura del registro e fanno perdere la vista d'insieme.

`AskUserQuestion` (prima il ping TTS):

- **conferma tutti** i verdetti proposti;
- **conferma tranne alcuni** → l'utente nomina gli ID da cambiare, e solo quelli diventano una domanda;
- **solo severità alta** → il resto resta nel registro, non applicato;
- **nessuno** → il registro resta come materiale, stop.

Annota il verdetto finale su ogni voce del file registro.

### 5. Applica — doc-writer su `fix-doc`, `relayer`, `split`

Raggruppa le voci approvate **per file doc target** e invoca un `doc-writer` per gruppo (mai due writer sullo stesso file: si sovrascrivono a vicenda). Sequenziali, non paralleli — questi scrivono davvero.

```
Nozione da documentare:
- **Nozione**: correggi i drift elencati in <file doc>. Per ognuno: la doc afferma <claim>, la fonte dice <realtà> (evidenza <path:linea | comando>). Riscrivi as-is la parte sbagliata.
- **Voci relayer**: non aggiornare la copia — cancellala e lascia il puntatore (file + simbolo per il codice, comando + forma della domanda per una fonte viva). Aggiornarla la farebbe driftare di nuovo.
- **Ancora primaria**: invariata salvo che un fix cambi il trigger del file

Contesto:
<le voci del registro per questo file: CLAIM / REALITY / EVIDENCE / FIX>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — otto test e sette tipologie offline, da leggere quando la collocazione non è ovvia.

Applica le patch direttamente (Write/Edit), non committare, non rigenerare l'indice.
Sostituisci la sezione sbagliata, non appendere una correzione accanto a quella vecchia.
Ritorna il contratto APPLIED: + INDEX_REBUILD_NEEDED.
```

`drop` e `relayer` passano dallo stesso canale (sono patch di rimozione, con o senza puntatore che resta). `code-divergent` **no**: la doc resta.

### 6. `code-divergent` → task, non patch

Per ogni voce con questo verdetto la doc descrive l'intenzione e la fonte ci è andata contro: correggere la doc **cancellerebbe l'intenzione**. Proponi `/loom-works:create-task` con titolo e razionale già pronti, e lascia la scelta all'utente. Se una task per quel perimetro esiste già (cerca in `{docs_root}/tasks.md`), citala con la sua maniglia verbo+oggetto invece di aprirne una gemella.

### 7. Chiudi

- Se le patch hanno toccato `{docs_root}/reference/`:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
  ```
  **Exit 2** = indice scritto, ma i TLDR elencati su stderr sono oltre il cap: violazione bloccante del contratto, non un comando fallito. Non annulla l'allineamento — riportala e lascia le voci a `lint-doc`, che è la skill di quel perimetro. Exit 1 = indice non scritto, quello è un errore.
- Se le patch hanno **rimosso** sezioni (verdetti `relayer` e `drop` cancellano, non solo correggono), verifica che non abbiano lasciato riferimenti appesi:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
  ```
  Exit 2 = ci sono riferimenti a file spariti (`DANGLING`) o a `§` che non esistono più (`NOSECTION`). Il secondo è il caso tipico qui: cancelli la sezione, e il puntatore che la citava resta valido sul path e falso sulla sezione — invisibile a un grep. Risolvili con `Edit` prima di chiudere.
- Sul perimetro **task** (§0): marca `→ ✔️ align` le voci `## Doc Impact` integrate, nel task file. È l'unico file di runtime che questa skill tocca — e lo tocca lei, mai il `doc-writer`, che ha `{docs_root}/tasks/` fuori dal proprio perimetro.
- **Non stampare i diff** in chat: bruciano contesto e sono già ispezionabili nel pannello git. Stampa la lista file dal contratto `APPLIED:`.
- **Stage, mai commit**: `git add -- <file>...`. Il commit è dell'utente o del `checkpoint-task`.
- Report finale: quanti finding per verdetto, quali file toccati, quali voci restano nel registro non applicate. Se il `doc-writer` ha ritornato un blocco `DISCARDED:`, riportalo: è materiale che ha deciso di **non** scrivere, e il posto durevole di quel verdetto è il corpo del messaggio di commit.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Il registro sopravvive all'esecuzione.** Le voci non applicate (severità bassa, verdetto rinviato) restano nel file: la prossima esecuzione sullo stesso perimetro parte da lì invece di riscoprirle.
- **Non fondere con `discover`**: quella presuppone doc **zero** e scansiona la struttura per produrre lo scaffold; questa presuppone doc **esistente** e la mette a confronto con la fonte.
- **Perimetro task vs `capture-doc`**: stessa destinazione, momento diverso. `capture-doc` integra una nozione **calda**, mentre la task è aperta e il codice si muove ancora; il §0 la integra **dopo**, con più fonti e la nozione ferma. Il secondo non rimpiazza il primo — lo rende non obbligatorio.
- Un perimetro pulito che risulta pulito è l'esito migliore. Se un auditor torna con `FINDINGS: 0`, riportalo così — non rilanciarlo con istruzioni più aggressive per trovare qualcosa.
