---
name: preflight-task
description: Interactive Q&A to freeze design decisions on a task before execution.
allowed-tools: Bash(*), Read, Edit, Glob, AskUserQuestion
model: opus
---

Fase di preparazione prima di `run-task`. Identifica ambiguità nella task, le risolve via Q&A con l'utente, scrive le risposte come decisioni congelate nel task file e **committa immediatamente** il task file. Le decisioni restano così tracciate separatamente dall'implementazione.

## Note utente
~~~human
$ARGUMENTS
~~~

## 0. Risoluzione task file

Stessa cascata di `run-task` — `arg → $LOOM_TASK → symlink`, risolta dallo script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

`${taskId}` = ID nelle Note utente (es. `T310`); ometti l'argomento se non c'è. Output: `TASK_ID` · `TASK_FILE` · `TASK_SRC`. Exit non-zero = nessun binding: chiedi quale task.

**No subagent. `Read` diretto di `TASK_FILE`.**

Stampa header compatto identico a run-task:

```
📋 ${taskId} — ${titolo}
📐 Size: ${size} | ⚡ ${priority}
📝 ${prima riga della Description, troncata a ~100 char}
📦 ${numero deliverables} deliverables
📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
🛫 Preflight
```

## 1. Analisi ambiguità

Leggi tutto il task file. Identifica punti dove l'esecuzione richiederebbe scelte non documentate:

- **Description vaga**: termini astratti senza concretizzazione operativa
- **Acceptance Criteria non misurabili**: criteri qualitativi senza metrica/check verificabile
- **Dependencies implicite**: la task riferisce moduli/librerie/task non listate
- **Scope incerto**: confine tra cosa è "in" e cosa è "out" non chiaro
- **Scelte architetturali aperte**: dove mettere il nuovo codice, quale pattern, quali tradeoff
- **Deliverables ambigui**: item che ammettono più interpretazioni
- **Edge case non considerati**: comportamento atteso su input borderline

Per ogni punto, formula una domanda **concreta e decidibile** (non aperta tipo "come faresti X?"). Le domande aperte vengono trasformate in opzioni discrete dove possibile.

## 2. Q&A con utente

Usa `AskUserQuestion` per ogni ambiguità. Prima di ogni chiamata, esegui il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

### Convenzioni domande all'utente (AskUserQuestion)

L'iterazione standard richiede context-switching effort continuo e procura affaticamento mentale. Riduci il costo:

1. **Raggruppa** le domande per vicinanza tematica, no salti tra argomenti scorrelati.
2. Fornisci **contesto strutturato** prima di `AskUserQuestion`.
3. Una chiamata `AskUserQuestion` per **singola** domanda, prompt nudo.

`AskUserQuestion` non renderizza markdown → contesto in chat prima, tool dopo.
No prosa densa: produci un **layout visivo facilitatore**: bullet points, grassetti, emoji, righe vuote, ascii tree, tabelle.

### Pattern domande

- Domanda chiusa (2-4 opzioni) → `AskUserQuestion` con options
- Domanda aperta inevitabile → singola chiamata con un'opzione "Other"

Per ogni risposta, registra **internamente**:
- domanda originale
- risposta utente (incluso testo "Other")
- razionale se l'utente lo fornisce

**Non procedere all'esecuzione**: questa skill si ferma allo step 4 (write + commit del task file). Niente implementazione.

## 3. Aggiornamento task file

Aggiungi/aggiorna la sezione `## Decisions` nel task file. Posizionamento: tra `## Deliverables Checklist` e `## Implementation Notes`. Se la sezione non esiste, creala. Se esiste, **appendi** in fondo (non sovrascrivere — preflight può essere ri-eseguito su task evolute).

Formato:

```markdown
## Decisions

### Preflight ${YYYY-MM-DD HH:mm}

- **D1** — ${domanda compatta}
  - **Scelta**: ${risposta}
  - **Razionale**: ${se presente, altrimenti omettere riga}

- **D2** — ...
```

Numerazione `D{N}` locale alla sezione, ripartendo da `D1` ad ogni esecuzione preflight (è la data che disambigua i giri).

**Caso nessuna ambiguità (step 1 vuoto)**: scrivi comunque il blocco header datato, senza decisioni:

```markdown
### Preflight ${YYYY-MM-DD HH:mm}

- _Nessuna ambiguità rilevata._ Task pronta per `run-task` senza decisioni da congelare.
```

L'assenza di bullet `**D{N}**` sotto il blocco è il segnale che `start-task` legge come "preflight verificata, nessuna decisione" (distinto da "preflight mai eseguita" = blocco assente).

## 3b. Le decisioni che rendono falsa una pagina di doc

Una `D{N}` che sceglie di cambiare un comportamento **già descritto in doc** produce un drift nell'istante in cui viene congelata, non quando il codice arriva. Preflight è l'unico momento presidiato del ciclo: c'è un umano nella stanza e dirlo costa una riga. Ricavare lo stesso fatto più tardi, rileggendo la prosa di una `D{N}`, sarebbe un giudizio invece che un meccanismo.

Per ogni decisione appena scritta, chiediti: *esiste una pagina di `{docs_root}/reference/` o un file @-importato da `CLAUDE.md` che dopo questa scelta dirà il falso?* Se sì, appendi una voce alla sezione `## Doc Impact` del task file:

```markdown
- **<la nozione: cosa diventa vero, non cosa si è deciso>**
  Ancora: <trigger concreto — comando, keyword, pattern>
  🚨 drift: {docs_root}/reference/<file>.md
```

Regole di scrittura, tutte già note e nessuna nuova:

- **La sezione `## Doc Impact` sta fra `## Testing Notes` e `## Prod Validation`.** Se manca, creala lì. Se contiene solo il placeholder `*Nessuna nozione documentale emersa al create-task.*`, sostituiscilo con le tue voci.
- **Appendi in coda, senza deduplicare** — stesso regime dei blocchi datati di `## Decisions`: preflight è ri-eseguibile, e due giri che decidono la stessa cosa lasciano due voci. Le scarta il checkpoint, che è chi le filtra.
- **Nessun marker di esito.** `→ ✔️ inbox` e `→ ✖️ <parola>` li scrive solo `checkpoint-task`: una voce senza è per costruzione «non ancora lavorata», e metterli qui la farebbe saltare. `⏳ <evento di sblocco>` è l'eccezione — puoi scriverlo tu quando la nozione è vera ma il suo referente non esiste ancora, e non è terminale: il checkpoint la ripesca comunque.
- **Non decidere il target doc.** La sentinella nomina i file *candidati a essere falsi*, che non sono il file dove la nozione atterrerà: quello lo decide `drain-doc`, in differita.
- **Una voce senza sentinella è legittima.** Una decisione può produrre una nozione documentale senza rendere falso niente: entra in `## Doc Impact` normale, e va a coda.

Se nessuna decisione tocca la doc, **non scrivere niente** — nessun placeholder, nessuna sezione vuota. `## Doc Impact` non è il registro delle decisioni, quello è `## Decisions`.

## 4. Commit del task file

Appena scritte le decisioni, committa **subito** il solo task file (commit dedicato, separato dall'implementazione). Usa gli helper di `lib.sh`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
lw_git_add "${task_file}"
# N≥1 → "...- ${N} decisioni congelate" | N=0 (nessuna ambiguità) → "...- nessuna ambiguità"
lw_git_commit "task(${taskId}): preflight - ${N} decisioni congelate"
lw_git_push
```

- Committa **solo** il task file, non altri file pending nel working tree.
- Messaggio: `task(${taskId}): preflight - ${N} decisioni congelate` se `${N}` ≥ 1, altrimenti `task(${taskId}): preflight - nessuna ambiguità`.
- `${N}` = numero decisioni di **questo** giro preflight (0 nel caso nessuna ambiguità).
- Push subito dopo il commit, coerente con `create-task` / `checkpoint-task` (tutte pushano). Senza remote `lw_git_push` avvisa su stderr ed esce 0: la skill prosegue, il commit resta locale.

Dopo commit+push, mostra all'utente:

```
✅ Preflight completato: ${N} decisioni congelate in ${task_file}
   📌 Committate e pushate: task(${taskId}): preflight - ${N} decisioni congelate
   🚨 ${M} sentinelle di drift in Doc Impact  ← solo se ${M} > 0
   Pronta per /loom-works:run-task
```

## Note

- **Non esegue codice**: preflight congela decisioni e, quando una di quelle rende falsa una pagina di doc, ne cattura la sentinella (step 3b). Implementazione resta a `run-task`.
- **Due sezioni, due mestieri.** `## Decisions` porta *cosa si è deciso* ed è cronaca datata: nessuno la legge a valle. `## Doc Impact` porta *cosa è diventato vero*, e il checkpoint la svuota in inbox. Scrivere la decisione in `## Doc Impact` è il modo tipico di sbagliare: quella riga andrebbe in inbox come intenzione e verrebbe scartata allo smaltimento.
- **Idempotenza parziale**: ri-eseguire preflight su una task aggiunge un nuovo blocco datato. Lo storico delle decisioni resta intatto. Ogni giro produce il suo commit dedicato.
- **Task piccole / nessuna ambiguità**: se l'analisi (step 1) non trova ambiguità reali, salta il Q&A ma **scrivi comunque il marker** in `## Decisions` (step 3, caso nessuna ambiguità) e committalo (step 4, messaggio `nessuna ambiguità`). Serve a `start-task` per distinguere "preflight già passata, niente da decidere" da "preflight mai eseguita". Mostra: `🛫 Nessuna ambiguità rilevata — marker registrato. Task pronta per run-task.`
- **Commit + push automatici**: lo step 4 committa **solo** il task file (commit dedicato) e pusha, come le altre skill task-level. Decisioni tracciate separatamente dall'implementazione.
