---
name: spawn-task
description: Chiede al deck acceso sul progetto di aprire una conversazione nuova su una task — preflight, run di tutti i DLV o di un perimetro, recap, checkpoint — come se l'utente premesse il tasto nel deck. Una task per invocazione, nessuna domanda e nessuna conferma. Usa quando una conversazione ha un piano già approvato da lanciare, per esempio quella di un'epica: «lancia il preflight di T12», «apri il run dei DLV 1-3 di T14».
argument-hint: "<TaskID> <kind> [perimetro] [--model <alias>] [--note <testo>] [--regia <perimetro>]"
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
- **`--regia <perimetro>`** — l'id dell'epica o del mandato della regia che chiede lo spawn, solo quando chi invoca è una regia (`orchestrate-mandate`) e lo dichiara. Assente = nessuna regia.

Argomenti che non si traducono in questa forma (un kind fuori elenco, un perimetro con un kind diverso da `run`, un prompt libero) → riporta cosa manca ed esci, senza invocare niente: la skill non ha un prompt libero, e un'interpretazione tua aprirebbe una conversazione diversa da quella chiesta.

## 2. Chiedi lo spawn

Dalla project root, una chiamata sola:

```bash
loom-deck-spawn <TaskID> <kind> [perimetro] [--model <alias>] [--note '<testo>'] [--regia <perimetro>]
```

La nota fra apici singoli.

**`--regia`** dà alla conversazione la sua posizione nell'organigramma: nasce con `LOOM_REGIA=<perimetro>` nell'ambiente, l'hook `SessionStart` le dice che le domande vanno in chat a fine turno, dove la regia le legge, e un hook `PreToolUse` le nega `AskUserQuestion`, che la regia non può chiudere. Il sidecar del deck registra il perimetro e la sessione della regia: la sessione la legge `loom-deck-spawn` dal proprio ambiente, non si passa. Il deck rifiuta una regia che non è un'epica né un mandato del progetto. Nessuna regola di permesso accompagna il comando: fuori da auto mode Claude Code chiede conferma a ogni spawn, ed è voluto — lo spawn apre una sessione col `permissionMode` del progetto e col prompt del catalogo, `run` compreso.

## 3. Riporta l'esito

Secondo l'uscita del comando, senza ritentare:

| Uscita | Esito | Cosa scrivi |
|---|---|---|
| `0` | tab aperta | le righe di stdout così come sono: `sessionId`, task, kind e modello, prompt, titolo, comando in-tab, la riga `regia:` quando la regia è impostata, e le righe `⚠` quando ci sono |
| `1` | il deck ha rifiutato o non ha risposto | il motivo da stderr così com'è (task assente, DLV chiusi o fuori range, spawn spento sulla piattaforma, finestra del progetto non in focus con un compass senza la coda) |
| `2` | errore d'uso | il messaggio da stderr: la riga composta al passo 1 era sbagliata |
| `3` | nessun deck in ascolto sul progetto | che serve il deck acceso sul progetto, o aggiornato: l'endpoint c'è da `loom-deck` 0.87.0 |
| `4` | in coda: la tab non c'è ancora | le righe di stdout così come sono: `⏳ in coda`, `sessionId`, task, kind e modello, prompt, la riga `regia:` quando la regia è impostata, `scade:`. La conversazione nascerà con quel `sessionId` |
| `127` | `loom-deck-spawn` non trovato | che il deck installato è più vecchio dell'endpoint: `npm install -g @lamemind/loom-deck@latest` |

Una riga `⚠ spawn inerte` in testa allo stdout vuol dire che il deck gira col freno dei test (`LOOM_DECK_NO_SPAWN`): il binding è scritto, la tab no. Riportalo com'è.

**Finestra del progetto non in focus — in coda** (Linux, uscita `4`). Ptyxis apre la tab nella sua finestra attiva, e il deck non sposta il focus per conto proprio: prima di aprire chiede a compass se la finestra in focus è del progetto, e se non lo è mette la richiesta in coda. compass mostra all'utente una notifica dello spawn in attesa col bottone «Vai», e la tab nasce quando una finestra del progetto torna in focus, col `sessionId` già stampato: la finestra la porta davanti l'utente, col bottone o a mano. Non c'è ancora la riga `titolo:`: il titolo lo compone il deck quando la tab nasce. Riporta le righe e che la tab aspetta una finestra del progetto in focus, e **non ritentare**: una seconda richiesta aprirebbe una seconda conversazione sulla stessa task, quando arriva il focus. Una richiesta in coda scade all'ora della riga `scade:` — trenta minuti —, e allora nessuna tab nasce: il deck lo dice all'utente con una notifica, a chi ha chiesto non arriva niente.

**Schermo bloccato — in coda** (Linux, uscita `4`). Con lo schermo bloccato GNOME Shell spegne compass, e nessuno può dire in quale finestra nascerebbe la tab: il deck mette la richiesta in coda allo stesso modo, e la prima riga lo dice — `schermo bloccato`. Allo sblocco vale la regola della coda: se la finestra in focus è del progetto la tab nasce subito, altrimenti compass mostra «Vai» e la richiesta aspetta. La scadenza non cambia, trenta minuti dalla richiesta: un blocco più lungo la fa scadere senza nessuna tab. Riporta le righe e che la tab aspetta lo sblocco, e **non ritentare**, per la stessa ragione.

**Finestra del progetto non in focus — rifiuto** (Linux, uscita `1`). Con un compass che ha il controllo della finestra ma non la coda, il deck rifiuta come prima della coda: il motivo porta l'istruzione per l'utente — portare davanti una finestra del progetto e richiedere lo spawn — e il motivo `compass senza AwaitProjectFocus, da aggiornare`. Riportalo e non ritentare, perché solo l'utente può cambiare la finestra in focus.

**`⚠ LOOM_REGIA non impostata`** in stdout vuol dire che la richiesta dichiarava la regia e il deck acceso è più vecchio: l'ha ignorata, e la tab è aperta senza `LOOM_REGIA` — lì `AskUserQuestion` funziona, e una domanda posta così resta ferma nella tab finché l'utente non ci va. L'uscita è `0` perché la tab esiste già. Riportalo com'è: il rimedio è riavviare il deck.

**`⚠ finestra non verificata`** in stdout vuol dire che il deck non ha potuto chiedere — compass assente, più vecchio del controllo, o che non conosce il progetto — e ha aperto comunque: la tab è nata nella finestra di terminale attiva, che può essere di un altro progetto. Riportalo com'è.

Su Windows il controllo non c'è: la tab nasce nella finestra di Windows Terminal usata per ultima.
