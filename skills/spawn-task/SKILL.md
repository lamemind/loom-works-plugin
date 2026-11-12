---
name: spawn-task
description: Chiede al deck acceso sul progetto di aprire una conversazione nuova su una task — preflight, run di tutti i DLV o di un perimetro, recap, checkpoint — come se l'utente premesse il tasto nel deck. Una task per invocazione, nessuna domanda e nessuna conferma. Usa quando una conversazione ha un piano già approvato da lanciare, per esempio quella di un'epica: «lancia il preflight di T12», «apri il run dei DLV 1-3 di T14».
argument-hint: "<TaskID> <kind> [perimetro] [--model <alias>] [--note <testo>]"
---

Argomenti:
~~~human
$ARGUMENTS
~~~

## Cosa fa, e cosa non fa

Lo spawn resta del **deck**: la skill è un client. Il deck acceso sul progetto ascolta un endpoint locale — named pipe su Windows, socket Unix su Linux, un indirizzo per progetto — e apre la conversazione col percorso del tasto: binding della task nel sidecar prima della tab, `--session-id` pinnato, titolo, modello con l'override di progetto. Senza un deck acceso sul progetto non si apre niente.

**Un'invocazione, uno spawn.** Più spawn sono più invocazioni, una dopo l'altra. La skill non pone domande, non chiede conferme e non fa piani: la conferma è già avvenuta nella conversazione che la invoca. Quali task possono girare in parallelo sullo stesso branch, e in che ordine, lo decide chi orchestra, a monte — la skill non lo controlla.

## 1. Componi la riga

Dagli argomenti ricavi, nell'ordine:

- **`<TaskID>`** — `T` più il numero.
- **`<kind>`** — uno di `preflight` · `run` · `recap` · `recap-task` · `recap-epic` · `checkpoint` · `none` (`none` apre la task senza prompt).
- **`[perimetro]`** — solo con `run`: i DLV nella grammatica di `run-task`, **un token solo** senza spazi (`2`, `1,3-5`). Assente = tutti i DLV aperti. «DLV da 1 a 3» diventa `1-3`.
- **`--model <alias>`** — `fable` · `opus` · `sonnet` · `haiku`, solo se l'utente lo nomina. Assente = il modello che il deck userebbe col tasto.
- **`--note <testo>`** — la nota del titolo della tab, solo se l'utente la detta. Assente = il titolo dell'azione.

Argomenti che non si traducono in questa forma (un kind fuori elenco, un perimetro con un kind diverso da `run`, un prompt libero) → riporta cosa manca ed esci, senza invocare niente: la skill non ha un prompt libero, e un'interpretazione tua aprirebbe una conversazione diversa da quella chiesta.

## 2. Chiedi lo spawn

Dalla project root, una chiamata sola:

```bash
loom-deck-spawn <TaskID> <kind> [perimetro] [--model <alias>] [--note '<testo>']
```

La nota fra apici singoli. Nessuna regola di permesso accompagna il comando: fuori da auto mode Claude Code chiede conferma a ogni spawn, ed è voluto — lo spawn apre una sessione col `permissionMode` del progetto e col prompt del catalogo, `run` compreso.

## 3. Riporta l'esito

Secondo l'uscita del comando, senza ritentare:

| Uscita | Esito | Cosa scrivi |
|---|---|---|
| `0` | tab aperta | le righe di stdout così come sono: `sessionId`, task, kind e modello, prompt, titolo, comando in-tab |
| `1` | il deck ha rifiutato o non ha risposto | il motivo da stderr (task assente, DLV chiusi o fuori range, spawn spento sulla piattaforma) |
| `2` | errore d'uso | il messaggio da stderr: la riga composta al passo 1 era sbagliata |
| `3` | nessun deck in ascolto sul progetto | che serve il deck acceso sul progetto, o aggiornato: l'endpoint c'è da `loom-deck` 0.87.0 |
| `127` | `loom-deck-spawn` non trovato | che il deck installato è più vecchio dell'endpoint: `npm install -g @lamemind/loom-deck@latest` |

Una riga `⚠ spawn inerte` in testa allo stdout vuol dire che il deck gira col freno dei test (`LOOM_DECK_NO_SPAWN`): il binding è scritto, la tab no. Riportalo com'è.

La tab nasce nella finestra di terminale attiva (Ptyxis) o usata per ultima (Windows Terminal), come col tasto del deck: di norma quella da cui l'utente scrive alla conversazione.
