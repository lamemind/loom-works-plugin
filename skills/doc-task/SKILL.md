---
name: doc-task
description: Create a new documentary task (D{N} prefix) with a dedicated template.
allowed-tools: Bash(*), Read, Write, Edit, AskUserQuestion
model: opus
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Crea una nuova task documentale. I deliverable sono editoriali (sezioni di doc approvate, aggiornate o create), non code. La task vive nel task-system esistente come qualsiasi altra, con prefix `D{N}` e template dedicato.

## Quando una D-task è la risposta giusta

Nasce **solo su invocazione esplicita** — nessun automatismo la genera. Il gate `## Doc Impact` al checkpoint di una code task non ne apre: le voci rinviate lì restano senza marker e le raccoglie `align-doc` sul perimetro task.

Soglia dimensionale: il lavoro dev'essere **multi-chunk**, cioè partizionabile in scope che `/loom-works:run-doc` esegue a giri con un `doc-writer` fresco per chunk. Se la nozione è singola, la risposta è `/loom-works:capture-doc` (one-shot inline): aprire una D per essa paga il ciclo — task file, planning con conferma utente, checkpoint per giro — su un lavoro che non lo ammortizza.

Se non sei sicuro che il lavoro sia multi-chunk, chiedilo prima di creare la task.

Due modalità:
- **Interattiva** (default): estrazione dal contesto + domande mirate sui campi incerti
- **YOLO**: deduce tutto dalla descrizione e dal contesto conversazionale, nessuna domanda

Input utente:
~~~human
$ARGUMENTS
~~~

## Rilevamento Modalità

Cerca keyword nell'input: **"yolo"**, **"no domande"**, **"senza domande"**
- Se presente → modalità YOLO
- Altrimenti → modalità interattiva

## Parent Task (opzionale, passato a mano)

Se `$ARGUMENTS` contiene `parent=T{N}` (es. `parent=T07`), la D-task viene legata a una code task: popola il campo `**Parent Task**` nel file. Nessuna skill passa più questo argomento — lo scrive l'utente quando vuole che il parent non si chiuda prima della doc.

Quando lo ricevi, sei tu a chiudere il cerchio sul parent (non c'è un caller che lo faccia):
- appendi `- [ ] D{taskId} (<maniglia verbo+oggetto>) chiusa` in `## Acceptance Criteria` del parent
- marca in `## Doc Impact` del parent le voci coperte da questa D con `→ ✔️ D{taskId}`, così il gate al checkpoint non le ripresenta

A chiusura della D-task (suo checkpoint con done), `checkpoint-task` flagga indietro la checkbox nel parent via lookup del campo `**Parent Task**`.

---

## Estrazione arricchita dal contesto conversazionale

**Principio** (diverso da `create-task`): per task-doc la conversazione che precede il comando è la fonte principale per **tutti** i campi, non solo per un eventuale Doc Impact. La nozione, il target, i deliverable e le fonti spesso sono già stati enunciati durante il design del problema — catturarli evita di far ripetere all'utente.

Analizza il contesto conversazionale immediatamente precedente all'invocazione di `doc-task` ed estrai pre-compilazioni plausibili per:

- **Description**: il "perché" della task, l'esigenza documentale emersa
- **Target**: file/aree doc nominate nella discussione (path, livello online/offline, azione drift/extend/create)
- **Deliverables Checklist**: sezioni/ancore che la discussione ha implicato dover esistere a fine task
- **Fonti**: file sorgente citati, commit di riferimento, link, altri task file, riferimenti conversazionali
- **Acceptance Criteria**: vincoli o condizioni di validazione emersi

**Pattern dell'utente**: se l'input contiene "come appena discusso", "come discusso", "come emerso" o varianti, la discussione precedente è la sorgente primaria — non chiedere conferme sui campi già inferibili, cattura e procedi. In modalità interattiva chiedi solo sui campi non deducibili (o chiedi una conferma compatta finale prima di scrivere).

In modalità YOLO: estrazione silenziosa, nessuna domanda. Campi non deducibili restano placeholder espliciti (es. `_TBD_`) che l'utente può raffinare a mano.

---

## Modalità YOLO

Quando attiva, oltre all'estrazione sopra:
- **Nome task**: dalla descrizione → kebab-case (prime 3-4 parole significative)
- **Priorità**: Med (default)
- **Durata**: 1-3 ore (default)
- **Lane**: nessuna (task-doc nasce come spot su main, coerente con DESIGN §5)

Esempio: `/loom-works:doc-task yolo riorganizza sezione logging in common-package`
→ Nome: `riorganizza-sezione-logging-common-package`

---

## Flusso di Creazione

### 1. Generazione ID task
```bash
TASK_ID=$(${CLAUDE_PLUGIN_ROOT}/scripts/utils/get-next-task-id.sh --prefix D)
```
Output: ID completo con prefix D (es: D01, D02, D03). Counter indipendente da quello delle code task (`T{N}`).

### 2. Raccolta dettagli

In modalità interattiva, dopo l'estrazione dal contesto, raccogli/conferma in quest'ordine. Se un campo è già estratto con confidenza alta, proponilo come default e lascia all'utente solo conferma o edit.

1. **Nome task**: kebab-case (valida formato)
2. **Priorità**: High / Med / Low
3. **Durata stimata**
4. **Description**: prosa discorsiva (perché la task esiste, contesto)
5. **Target**: lista strutturata, una voce per area doc. Per ognuna:
   - **path** — es. `{docs_root}/reference/logging.md`
   - **verdetto atteso**, uno dei quattro del contratto: `online` (in `{docs_root}/project/`, caricata via `@-import` da `CLAUDE.md`) · `offline` (in `{docs_root}/reference/`) · `→ codice` (non si scrive, si punta con `file + simbolo`) · `→ fonte viva` (non si copia, si punta col comando più la forma della domanda giusta)
   - **azione**: `create` (nuovo file) · `extend` (aggiungere sezioni) · `drift` (riallineare alla fonte nativa del layer) · `pointer` (sostituire prosa esistente con un puntatore — è l'azione dei due verdetti di rimando) · `drop` (cancellare: la nozione non sopravvive all'imbuto)

   Il verdetto scritto qui è una **previsione fatta prima di lavorare**, non un vincolo: chi esegue applica l'imbuto di selezione (`doc-criteria.md`) al materiale reale e può ribaltarlo, inclusa la conclusione «non scriverla». Un Target che dice `online`/`offline` su ogni voce, senza un solo rimando, di norma non ha applicato l'imbuto — e impegna la task a scrivere prosa che il codice già possiede.
6. **Acceptance Criteria**: condizioni di validazione ("tutte le ancore coperte", "INDEX rigenerato", ecc.)
7. **Deliverables Checklist**: sezioni doc approvate a fine task. Distinto dal Target:
   - **Target** = dove metto le mani (superficie di lavoro)
   - **Deliverables** = cosa deve essere presente e approvato (risultato atteso)
8. **Fonti**: bullet libera. File sorgente, commit hash, link, riferimenti conversazionali, altri task file

In modalità YOLO: salta le domande, usa l'estrazione + default. Campi senza segnale diventano `_TBD_` nel file.

### 3. Lane (opzionale)

Default: **nessuna lane** (DESIGN §5). La task-doc nasce come task spot su main.

Chiedi solo se:
- L'input utente contiene indicazioni di lane ("nella lane X", "per la lane Y")
- La discussione precedente implica isolamento pesante

Se serve selezionare, leggi il grafo da `${DOCS_ROOT}/tasks.md` e proponi le lane esistenti via `AskUserQuestion` (come fa `create-task`), più opzione "Nessuna (task spot)" e "Nuova lane".

### 4. Creazione file task

Crea `${DOCS_ROOT}/tasks/${TASK_ID}-${taskName}.md` copiando il template:

```
${CLAUDE_PLUGIN_ROOT}/templates/doc-task-template.md
```

Sostituisci i placeholder:

| Placeholder | Valore |
|---|---|
| `{{taskId}}` | es. `D01` |
| `{{Descrizione_breve}}` | titolo corto (≤100 char) |
| `{{data_corrente}}` | `YYYY-MM-DD HH:mm` |
| `{{priorita_raccolta}}` | High / Med / Low |
| `{{durata_standard}}` | es. `2h`, `1 giornata` |
| `{{lane}}` | nome lane o lasciare vuoto/omesso |
| `{{parent_task}}` | ID task parent (es. `T07`) se `$ARGUMENTS` conteneva `parent=T{N}`, altrimenti vuoto |
| `{{parent_task_maniglia}}` | maniglia verbo+oggetto del parent fra parentesi, letta dalla sua riga in `tasks.md` (es. `(unificare docs-root)`) — vuoto se non c'è parent. Un id nudo su file non aggancia più niente quando il file si rilegge a settimane di distanza |
| `{{descrizione_dettagliata}}` | prosa sotto `## Description` |
| `{{target_raccolto}}` | lista strutturata sotto `## Target` |
| `{{criteri_accettazione_raccolti}}` | bullet sotto `## Acceptance Criteria` |
| `{{checklist_deliverables_raccolta}}` | checklist `- [ ]` sotto `## Deliverables Checklist` |
| `{{fonti_raccolte}}` | bullet sotto `## Fonti` |

**Sezione `## Execution`**: lasciare intatta (commento HTML guida + `### Rounds` vuoto + `### Resume context` vuoto). I chunk li popola `/loom-works:run-doc` al primo giro. Non pre-scrivere chunks qui.

### 5. Finalizzazione

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/create-task.sh \
    ${TASK_ID} ${task-name} "${descrizione_breve}" ${priority}
```

Lo script:
- Deriva automaticamente `K=📝` dal prefix `D` (⚙️ per altri prefix)
- Aggiunge la riga alla tabella `## Tasks Overview` di `${DOCS_ROOT}/tasks.md`
- Committa e pusha (senza remote il push avvisa su stderr e prosegue)

### 6. Feedback finale

Esegui il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "doc task created"
```

Stampa:
- Path file creato
- ID assegnato (es. `D01`)
- **Next steps** suggeriti:
  1. `/loom-works:start-task ${TASK_ID}` — attiva la task, symlink `current-task.md`, Progress → 🟡
  2. `/loom-works:run-doc` — avvia il workflow a giri (pianifica chunks → spawn doc-writer)

---

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note di Esecuzione

- **Task-doc ≠ code task**: niente Size (S/M/L), niente Servizi coinvolti, niente File critici di codice, niente Doc Impact (la doc **è** l'obiettivo, non un side-effect). Campi del template code che spariscono: Dependencies, Implementation Notes, Testing Notes, Doc Impact, Prod Validation.
- **Lane di default: nessuna**. Task-doc è spot finché non serve isolamento pesante.
- **Path assoluti** per tutte le operazioni filesystem
- **Timestamp** formato `YYYY-MM-DD HH:mm`
- **Kebab-case** per task name se contiene spazi
