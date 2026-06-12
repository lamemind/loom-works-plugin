---
name: run-task
description: Execute a task following an adaptive workflow based on size (S/M/L).
allowed-tools: Bash(*), Task, Read, Edit, Glob, AskUserQuestion, TodoWrite
model: sonnet
---

## Note utente
~~~human
$ARGUMENTS
~~~

## 0. Presenta la task

Risolvi il file task con questa precedenza:

1. Se l'utente ha specificato un task ID nelle Note utente (es. `T310`), cercalo con Glob `${user_config.doc_folder_name}/tasks/${taskId}-*.md` e caricalo attivamente. Esecuzione **on-the-fly** o **detached** (start-task fatto con `detach`): il file non è in contesto, va letto.
2. Altrimenti leggi il symlink `${user_config.doc_folder_name}/current-task.md` (modalità linked).

Il workflow operativo è identico nei due casi: l'unica differenza è il punto di caricamento del file.

In modalità detached il taskId è obbligatorio: niente symlink fallback. Se il symlink non esiste e non è stato passato un taskId, chiedi all'utente quale task eseguire.

Stampa SEMPRE un riassunto compatto prima di qualsiasi altra azione:

```
📋 ${taskId} — ${titolo}
📐 Size: ${size} | ⚡ ${priority}
📝 ${prima riga della Description, troncata a ~100 char}
📦 ${numero deliverables} deliverables
📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
```

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
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "$(say_id ${taskId}) completata"
```
In caso di blocco reale: `say_auto "$(say_id ${taskId}) bloccata"`.

Poi suggerisci all'utente di invocare `/loom-works:checkpoint-task` per il checkpoint (commit + aggiornamento epic).

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici ("domanda per te").

## Doc Impact (append libero durante l'esecuzione)

Se durante run-task emergono nozioni documentali (decisioni di design, pattern non-ovvi, gotcha, conoscenza che merita doc), **appendile direttamente** alla sezione `## Doc Impact` del task file. Format: bullet con **nozione** + **ancora primaria** (tag/keyword/comando/pattern).

Non decidere il target doc qui — lo gestisce il gate al `checkpoint-task` (capture inline / D-task / skip).
