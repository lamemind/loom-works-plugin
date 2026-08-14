---
name: run-task
description: Execute a task following an adaptive workflow based on size (S/M/L).
allowed-tools: Bash(*), Task, Read, Edit, Glob, AskUserQuestion, TodoWrite
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

## Note utente
~~~human
$ARGUMENTS
~~~

## 0. Presenta la task

Risolvi il task file con lo script, mai a mano — la cascata `arg → $LOOM_TASK → symlink` è una sola per tutta la famiglia:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

`${taskId}` = ID trovato nelle Note utente (es. `T310`); ometti l'argomento se non c'è. Output: `TASK_ID` · `TASK_FILE` (assoluto) · `TASK_SRC` ∈ `arg|env|symlink`. Exit non-zero = nessun binding risolvibile: chiedi all'utente quale task eseguire, non tirare a indovinare.

Fai **sempre** `Read` di `TASK_FILE`: in contesto può non esserci affatto (invocazione on-the-fly) o esserci troncato (budget dell'hook di iniezione). Il workflow operativo non cambia con `TASK_SRC` — cambia solo da dove è arrivato l'ID.

Stampa SEMPRE un riassunto compatto prima di qualsiasi altra azione:

```
📋 ${taskId} — ${titolo}
📐 Size: ${size} | ⚡ ${priority}
📝 ${prima riga della Description, troncata a ~100 char}
📦 ${numero deliverables} deliverables
📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
```

## Artefatti e materiale di lavoro

Output intermedi che non sono codice del progetto (dump, analisi, findings, script di supporto) → dentro la **task folder**, mai sparsi nel repo né sotto `{docs_root}/tasks/`.

- La task folder vive in **project root**, dot-prefixed; il campo `📁 Folder` la mostra root-relative (`./.YY-MM-DD-slug`). Sotto `{docs_root}/tasks/` stanno **solo** i task file `.md` — **mai** una folder.
- **Non creare folder a mano** (`mkdir`). Crearla/agganciarla solo via skill:
  - task senza folder che ora serve → `/loom-works:set-task-folder ${taskId}` (la colloca giusta in root + popola il campo Folder)
  - materiale fuori dal ciclo task → `/loom-works:scratch-new <slug>`
- CWD resta sempre project root: scrivi nei file passando il path della folder, non con `cd`.

## 1. Determina modalità dal campo Size

Leggi il campo **Size** dalla mappa proprietà della task.

| Size | Modalità | Comportamento |
|------|----------|---------------|
| **S** | Express | Vai dritto all'esecuzione. Niente validazione incrociata, niente scomposizione, niente piano. Leggi la task, capisci cosa fare, fallo. |
| **M** | Standard | Validazione leggera (requisiti chiari? dipendenze presenti?). Scomposizione con TodoWrite solo se servono >3 step. Esecuzione. |
| **L** | Full | Workflow completo: validazione profonda, scomposizione, pianificazione top-down, checkpoint intermedi. |

Se il campo Size è assente, tratta come **M**.

---

## Modalità S — Express

- Leggi la task, implementa, testa, builda
- Nessuna domanda all'utente salvo blocchi reali
- Nessun checkpoint intermedio
- Qualità e correttezza restano prioritarie

## Modalità M — Standard

### Validazione leggera
- La richiesta è chiara?
- Le dipendenze dichiarate esistono?
- Dubbi o ambiguità? AskUserQuestion PRIMA di procedere

### Esecuzione
- Scomposizione con TodoWrite solo se servono più di 3 step distinti
- Esecuzione unsupervised
- Checkpoint a fine lavoro (build OK, test OK)
- Dubbi architetturali? Chiedi all'utente PRIMA di procedere

## Modalità L — Full

### Validazione completa
- Verificare la richiesta, se è chiara e completa
- Verificare la collocazione dell'implementazione
- Verificare se i requisiti sono soddisfatti (l'implementazione dipende da altre funzionalità? sono identificabili, verificabili? Sono effettivamente presenti?)
- Verificare quali librerie esterne sono necessarie (sono esplicitamente dichiarate nel contesto?)
- Dubbi o ambiguità? AskUserQuestion PRIMA di procedere

### Scomposizione in sotto-step
- Scomporre l'attività in step più piccoli con TodoWrite
- Ogni step chiaramente definito, discreto, con obiettivo specifico e misurabile
- Per ogni step, identificare prerequisiti, dipendenze, pattern di implementazione
- Tutte le decisioni architetturali concordate con l'utente PRIMA di procedere

### Pianificazione top-down
- Piano di implementazione top-down
- Panoramica ad alto livello suddivisa in micro-step
- Ogni micro-step validabile e testabile
- Decisioni architetturali concordate con l'utente PRIMA di procedere

### Esecuzione Operativa
- Unsupervised, qualità e correttezza vincono su velocità
- È tutto gittato, l'utente controllerà ogni riga di codice
- Checkpoint intermedi: fermarsi, richiedere feedback, attendere verifica
- Buildare a ogni checkpoint

### Checkpoint intermedi
- Definire checkpoint durante l'implementazione
- Stabilire quando fermarsi per valutare i progressi
- Specificare cosa mostrare o dimostrare a ogni checkpoint
- Richiedere feedback periodico

---

## Dopo l'esecuzione

A lavoro completato, esegui il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "$(say_id ${taskId}) done"
```
In caso di blocco reale: `say_auto "$(say_id ${taskId}) blocked"`.

Poi suggerisci all'utente di invocare `/loom-works:checkpoint-task` per il checkpoint (commit + aggiornamento epic).

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici ("domanda per te").

## Doc Impact (append libero durante l'esecuzione)

Se durante run-task emergono nozioni documentali (decisioni di design, pattern non-ovvi, gotcha, conoscenza che merita doc), **appendile direttamente** alla sezione `## Doc Impact` del task file. Format: bullet con **nozione** + **ancora primaria** (tag/keyword/comando/pattern).

Non decidere il target doc qui: il checkpoint porta la voce in `{docs_root}/inbox/` e la marca, e dove atterri lo decide `drain-doc` in differita.

**Trattenere una nozione il cui referente non è ancora materializzato**: appendi `⏳ <evento di sblocco>` in coda alla voce (`⏳ publish`, `⏳ deploy`, `⏳ F7`). È l'unico marker che puoi scrivere — `→ ✔️ inbox` e `→ ✖️ <parola>` sono del checkpoint, e scriverli qui significa che nessuno ripassa più sulla voce. `⏳` non è terminale: ogni checkpoint la riprende finché l'evento non arriva, e quello di chiusura la forza comunque a decisione.

### Sentinelle di drift — prima di chiudere

`run-task` è l'unica delle tre skill produttrici in cui i file toccati esistono davvero, quindi è l'unica dove il rilevamento è **meccanico**. Passa allo script i path che hai modificato — la lista la conosci tu, non gliela far dedurre da un `git diff`: in detached il working tree porta anche i file delle altre sessioni.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/drift-candidates.sh" <path1> <path2> ...
```

Ritorna i file doc che **citano** i path toccati, con `strong` (la doc nomina il modulo per intero) o `weak` (nomina solo il basename, che può appartenere a un altro file omonimo). Exit sempre 0: è una misura, il verdetto è tuo.

Per ogni candidato, apri il punto e chiediti: *quella pagina adesso dice il falso?* Solo se sì, appendi alla voce corrispondente in `## Doc Impact`:

```markdown
  🚨 drift: {docs_root}/reference/<file>.md
```

Il checkpoint la propaga sul file inbox, e `drain-doc` smaltisce quel file **per primo, anche sotto il tetto di 8**.

**Il grep non chiude il caso, lo apre.** Un candidato che a leggerlo è ancora vero non porta sentinella — la lista è di path citati, non di pagine false. E all'opposto, **un comportamento cambiato senza che nessun nome cambi non produce nessun candidato**: è precisamente il caso per cui la sentinella si mette anche a mano, senza che nessuno script l'abbia suggerita.
