---
name: align-doc
description: Allinea la doc a un perimetro di codice — caccia ai drift (la doc dice X, il codice fa Y). Fan-out di doc-auditor read-only, registro con verdetti, patch via doc-writer solo sulle voci approvate.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

Confronta la doc di progetto col **codice** e trova i **drift**: fatti documentati che il sorgente smentisce.

Input utente (perimetro: dir, glob, submodule, file doc — oppure vuoto):
~~~human
$ARGUMENTS
~~~

## Drift, non lacune

Il bersaglio non è coprire quello che manca, è **trovare quello che mente**.

- Una **lacuna** (fatto vero, non documentato) è auto-limitante: chi la incontra apre il codice.
- Un **drift** (fatto documentato ≠ realtà) è attivamente dannoso: la doc offline esiste proprio per *sostituire* la lettura del codice, quindi chi si fida agisce su una realtà che non esiste — e nessun segnale gli dice di verificare.

Da qui l'asimmetria di tutto il flusso: si parte dalle **affermazioni della doc** e si va a verificarle nel sorgente, mai il contrario. Partire dal codice produce copertura, non allineamento, e non termina mai.

Gemella di `lint-doc`, che misura la stessa doc contro il **contratto editoriale** invece che contro il codice. Stessa meccanica, fonte di verità opposta.

## Flusso

### 1. Risolvi i perimetri

Un perimetro = **una coppia** `sorgenti ↔ file doc`. Dall'input:

- **path di codice** (`loom-deck/src/`, `scripts/config/`) → trova la doc che lo descrive: `grep -rl` del nome dir/file dentro `{docs_root}/`, più i TLDR di `{docs_root}/reference/INDEX.md` che lo nominano.
- **file doc** (`reference/compass.md`) → trova i sorgenti: i path citati dentro il file stesso.
- **vuoto** → deriva i candidati dall'INDEX (ogni file reference che cita path di codice reali) e falli scegliere con `AskUserQuestion` — massimo 4 perimetri per esecuzione, altrimenti il registro diventa illeggibile e il gate dei verdetti impraticabile.

Se una coppia non si chiude (doc senza sorgenti identificabili), **non inventarla**: dillo e saltala. Un perimetro senza fonte di verità è lavoro per `lint-doc`, non per questa skill.

### 2. Fan-out doc-auditor

Un `Task` con `subagent_type: doc-auditor` **per perimetro**, tutti nello stesso messaggio → girano in parallelo. È possibile solo perché l'auditor è read-only: nessuno tocca il working tree, nessun conflitto.

Prompt per ogni auditor:

```
Perimetro:
- Sorgenti: <path/glob concreti>
- Doc: <file doc del perimetro>

Fonte di verità: codice

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.
Prefisso ID: <sigla corta del perimetro, es. DECK>

Cerca drift: parti dalle affermazioni verificabili della doc e aprine il sorgente.
Ogni finding porta EVIDENCE con path:linea letti davvero. Ritorna solo il registro.
```

### 3. Consolida il registro

Unisci i registri in **un unico file**, ordinato per severità (alta prima). Colloca:

- task attiva con `**Folder**:` popolato → `<task folder>/align-doc-findings.md`;
- altrimenti `AskUserQuestion`: nuova scratch folder (`/loom-works:scratch-new`) oppure registro solo in chat.

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

### 5. Applica — doc-writer solo su `fix-doc` e `split`

Raggruppa le voci approvate **per file doc target** e invoca un `doc-writer` per gruppo (mai due writer sullo stesso file: si sovrascrivono a vicenda). Sequenziali, non paralleli — questi scrivono davvero.

```
Nozione da documentare:
- **Nozione**: correggi i drift elencati in <file doc>. Per ognuno: la doc afferma <claim>, il codice fa <realtà> (evidenza <path:linea>). Riscrivi as-is la parte sbagliata.
- **Ancora primaria**: invariata salvo che un fix cambi il trigger del file

Contesto:
<le voci del registro per questo file: CLAIM / REALITY / EVIDENCE / FIX>

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.

Applica le patch direttamente (Write/Edit), non committare, non rigenerare l'indice.
Sostituisci la sezione sbagliata, non appendere una correzione accanto a quella vecchia.
Ritorna il contratto APPLIED: + INDEX_REBUILD_NEEDED.
```

`drop` passa dallo stesso canale (è una patch di rimozione). `code-divergent` **no**: la doc resta.

### 6. `code-divergent` → task, non patch

Per ogni voce con questo verdetto la doc descrive l'intenzione e il codice ci è andato contro: correggere la doc **cancellerebbe l'intenzione**. Proponi `/loom-works:create-task` con titolo e razionale già pronti, e lascia la scelta all'utente. Se una task per quel perimetro esiste già (cerca in `{docs_root}/tasks.md`), citala con la sua maniglia verbo+oggetto invece di aprirne una gemella.

### 7. Chiudi

- Se le patch hanno toccato `{docs_root}/reference/`:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
  ```
- **Non stampare i diff** in chat: bruciano contesto e sono già ispezionabili nel pannello git. Stampa la lista file dal contratto `APPLIED:`.
- **Stage, mai commit**: `git add -- <file>...`. Il commit è dell'utente o del `checkpoint-task`.
- Report finale: quanti finding per verdetto, quali file toccati, quali voci restano nel registro non applicate.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Il registro sopravvive all'esecuzione.** Le voci non applicate (severità bassa, verdetto rinviato) restano nel file: la prossima esecuzione sullo stesso perimetro parte da lì invece di riscoprirle.
- **Non fondere con `discover`**: quella presuppone doc **zero** e scansiona la struttura per produrre lo scaffold; questa presuppone doc **esistente** e la mette a confronto col codice.
- Un perimetro pulito che risulta pulito è l'esito migliore. Se un auditor torna con `FINDINGS: 0`, riportalo così — non rilanciarlo con istruzioni più aggressive per trovare qualcosa.
