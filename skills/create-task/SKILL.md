---
name: create-task
description: Create a new task in the project task list with automation-ready metadata.
allowed-tools: Bash(*), Read, Write, Edit, AskUserQuestion
model: opus
---

Crea una nuova task. Supporta due modalità:
- **Interattiva** (default): raccoglie dettagli dall'utente
- **YOLO**: deduce tutto dalla descrizione, nessuna domanda

Input utente:
~~~human
$ARGUMENTS
~~~

## Rilevamento Modalità

Cerca keyword nell'input: **"yolo"**, **"no domande"**, **"senza domande"**
- Se presente → modalità YOLO
- Altrimenti → modalità interattiva

## Task Folder — Policy

Decisione binaria `CREATE_FOLDER=yes|no`:
- Trigger esplicito da input utente: `"con task folder"`, `"con folder"`, ecc → `CREATE_FOLDER=yes`
- In alternativa determinare da Size task:
  - **Size = L** → `CREATE_FOLDER=yes`
  - **Size = S | M** → `CREATE_FOLDER=no`

Nel template file, il campo `**Folder**:` viene popolato automaticamente.

---

## Modalità YOLO

Quando attiva, deduce automaticamente:
- **Nome task**: dalla descrizione → kebab-case (prime 3-4 parole significative)
- **Priorità**: Med (default)
- **Size**: M (default). Valori: S (express), M (standard), L (full validation)
- **Durata**: 1-2 ore (default)
- **Lane**: nessuna (task spot)
- **Dipendenze**: nessuna
- **Acceptance criteria**: "- [ ] Implementare quanto descritto"
- **Deliverables**: "- [ ] Codice funzionante"

Esempio: `/loom-works:create-task yolo migliorare logging dei servizi`
→ Nome: `migliorare-logging-servizi`, Desc: "Migliorare logging dei servizi"

---

## Flusso di Creazione

### 1. Generazione ID task
```bash
TASK_ID=$(${CLAUDE_PLUGIN_ROOT}/scripts/utils/get-next-task-id.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}")
```
Output: ID completo pronto all'uso (es: T319, T320). Prefix `T` hardcoded.

### 2. Raccolta dettagli (solo modalità interattiva)
1. **Nome task**: valida formato kebab-case
2. **Priorità**: High/Med/Low
3. **Size**: S/M/L (S = express, M = standard, L = full validation)
4. **Durata stimata**
5. **Servizi coinvolti**: bridge, runner, scheduler, pocketbase, xvfb, vnc
6. **File critici**
7. **Acceptance criteria**
8. **Deliverables**

### 2b. Lane e dipendenze (AskUserQuestion)

Dopo i dettagli base, due domande con AskUserQuestion. Prima di ognuna esegui il ping pre-domanda (vedi §Convenzione TTS):
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

**Domanda 1 — Lane**:
Leggi il grafo lane da `${user_config.doc_folder_name}/tasks.md`. Se esiste, mostra le lane come opzioni selezionabili:
```
In quale lane inserire ${TASK_ID}?

1) l1 (L1 Pipeline): ✔️T151 → ... → T155
2) l2 (Agent Infra): ✔️T143 → ... → T159
3) l3 (Data): ✔️T145 → ... → T150
4) l4 (Tools): ✔️T147 → ... → T158
5) Nuova lane (specificare nome)
6) Nessuna (task spot)
```
L'utente clicca e basta. Se "Nuova lane" → chiedi nome. Se "Nessuna" → task spot, no grafo.

**Domanda 2 — Dipendenze cross-lane**:
Se assegnata a una lane, analizza le task dalla tabella `${user_config.doc_folder_name}/tasks.md` e suggerisci dipendenze probabili.
Usa euristiche: task che toccano stessi servizi/file, task nella stessa area funzionale, task che appaiono nel grafo come predecessori naturali.
```
Dipendenze cross-lane per ${TASK_ID}?

Suggerite (in base all'analisi):
  [x] T153 — L1 Pipeline - validazione input
  [ ] T146 — A4 - meccanismo trigger worker

Altre (ID separati da virgola): ___
```
L'utente conferma i suggerimenti e/o aggiunge altri. Se nessuna dipendenza → la task viene aggiunta in coda alla lane senza cross-deps.

### 2c. Cattura Doc Impact (sempre, sia interattivo che YOLO)

Analizza il contesto conversazionale immediatamente precedente all'invocazione di `create-task` — la discussione che ha generato l'esigenza della task. Questo è il momento più ricco per catturare nozioni documentali: problema esplicitato, decisioni emerse, vincoli scoperti, trade-off risolti, pattern individuati.

**Scope della cattura: nozione + ancora. NON decidere il target doc.**

Il routing della nozione verso uno specifico file doc è una decisione che richiede conoscenza dell'intero landscape documentale e va deferita al processing (checkpoint-task + doc-writer, con accesso a INDEX). A create-task manca quel contesto — qualsiasi target ipotizzato qui è un guess rumoroso.

Estrai e popola la sezione `## Doc Impact` nel task file come bullet list conciso. Per ogni nozione:

- **Nozione**: cosa è emerso e merita documentazione (1-2 frasi, concrete)
- **Ancora primaria**: trigger concreto che la doc dovrebbe esporre (tag, keyword, comando, pattern). Esempio: `"interpretare il flag --watch del comando build"` è un'ancora; `"interazione con l'umano"` non lo è.

Se non emerge nulla di significativo, scrivi: `*Nessuna nozione documentale emersa al create-task.*`

**Pattern dell'utente**: se l'input contiene "come appena discusso", "come discusso", "come emerso" o varianti, la discussione precedente è la sorgente principale — non chiedere conferme, cattura e procedi.

**YOLO**: anche in modalità YOLO questa cattura è sempre attiva. Si salta la domanda all'utente ma si legge lo stesso il contesto conversazionale.

### 3. Creazione file task
Crea `${user_config.doc_folder_name}/tasks/${TASK_ID}-${taskName}.md` usando il template `${CLAUDE_PLUGIN_ROOT}/templates/task-template.md`.

### 3b. Task folder (condizionale)

Se `CREATE_FOLDER=yes` (vedi §Task Folder — Policy):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh ${TASK_ID} --slug ${task-name} --docs-root "${user_config.doc_folder_name}"
```

Lo script gestisce folder canonica `${PROJECT_ROOT}/.${YYYY-MM-DD}-${task-name}` in autonomia.

### 4. Finalizzazione
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/create-task.sh --mode "${user_config.project_mode}" --docs-root "${user_config.doc_folder_name}" ${TASK_ID} ${task-name} "${descrizione_breve}" ${priority}
# Priority: High | Med | Low
# descrizione_breve: max 64 caratteri (troncata automaticamente dallo script)
```
- Aggiunge la task alla tabella Tasks Overview di `${user_config.doc_folder_name}/tasks.md` (formato: `| ID | Pri | Prog | Task (max 64) |`)
- Committa e pusha le modifiche

### 5. Feedback finale
- Path file creato
- ID assegnato
- Suggerisci review del file
- Ping TTS fine creazione (la pre-analisi per fillare la task può durare >1min → l'utente va avvisato che è pronta):
  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "task $(say_id ${TASK_ID}) creata"
  ```

---

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

---

## Note di Esecuzione

- Usa sempre path assoluti
- Se task name contiene spazi → kebab-case
- Timestamp formato: YYYY-MM-DD HH:mm
- Adattati al branch corrente senza forzare cambi
