# Lo script del flusso — `flow.py`

Contratto per chi **lancia, legge e comanda** lo script del flusso di un giro: l'orchestrator, che lo lancia staccato e si sveglia sulle sue righe di risveglio, e chi rilegge un giro dopo. Lo script porta il flusso meccanico del piano (`orchestration-schedule-format.md`) — apre i passi, legge gli esiti, chiede i checkpoint, lancia il checkpoint del perimetro orchestrabile — e sveglia l'orchestrator solo quando serve un giudizio.

Il costo di un turno dell'orchestrator dipende dalla dimensione del suo contesto, non dal lavoro che fa: ogni risveglio rilegge tutto il contesto dalla cache. Lo script esiste per togliere i risvegli che non chiedono un giudizio.

## Il processo e i file

Un processo per perimetro orchestrabile, staccato dalla conversazione che lo lancia: sopravvive alla chiamata Bash, e non gira sotto il tool `Monitor`, che lo ucciderebbe entro trenta minuti. Un lock impedisce un secondo processo sullo stesso perimetro orchestrabile.

I file stanno in `.claude/loom/orchestrator/` del progetto, che git ignora. Ognuno ha un solo scrittore:

| File | Scrittore | Cosa porta |
|---|---|---|
| `T<id>-flow.jsonl` | il processo del flusso | il giro: righe solo in coda, ognuna col suo `seq` |
| `T<id>-ordini.jsonl` | l'orchestrator, con `flow.py <ordine>` | gli ordini allo script, numerati |
| `T<id>-watch.json` | il processo del flusso | il punto di lettura degli scanner del monitor: transcript, task file, Prog, ref git |
| `T<id>-flow.lock` · `T<id>-flow.log` | il processo del flusso | il lock, e lo stderr del processo |
| `T<id>.md` | l'orchestrator | la sua memoria; lo script ne legge solo la testa, per sapere chi è l'orchestrator |

Lo stato del giro non sta in nessun file: si ricava rileggendo il flusso dall'inizio. È così che lo script riparte dopo un crash, e che `recap` e `wait` leggono il giro senza parlare col processo.

## I comandi

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/flow.py" <comando> <id del perimetro orchestrabile> …
```

| Comando | Cosa fa | Uscite |
|---|---|---|
| `start [--nuovo] [--context-threshold <token>] [--poll-seconds <s>]` | lancia il processo staccato e aspetta la sua riga `avvio`; se è già vivo lo dice e non ne lancia un altro. Riprende il flusso che trova; `--nuovo` archivia flusso e ordini del giro prima (`T<id>-flow.<ora>.jsonl`) e riparte da zero | `0` avviato o già vivo · `1` non partito, con le ultime righe del log · `2` `--nuovo` su un processo vivo |
| `status` | se il processo è vivo: pid e ora d'avvio dal flusso, controllati sul processo vero | `0` vivo · `3` morto o assente |
| `wait --dopo <seq>` | aspetta la prima riga `risveglio` oltre `<seq>` e stampa il recap da lì; esce subito se c'è già. Esce anche quando il processo muore | `0` risveglio · `3` processo morto · `2` flusso assente |
| `recap [--dal <seq>] [--testi]` | lo stato del giro; con `--dal` anche le righe dopo quel `seq`, raccolte per membro; con `--testi` il testo finale di ogni turno letto | `0` |
| `stop` | ferma il processo; la riga `fine` lo registra | `0` |
| `prosegui` · `abbandona` · `tieni` `<membro>` | un ordine allo script (§Gli ordini) | `0` · `1` membro malformato |

`wait` è il Bash in background dell'orchestrator: non ha scadenza, e alla sua fine la notifica sveglia la conversazione. Un risveglio arrivato mentre l'orchestrator lavorava non si perde: `wait` col `seq` già letto esce subito.

### Le righe di `recap`

```
FLOW=vivo · pid 4242 · avviato 2026-11-24T14:00:00.000Z
SEQ=187
PIANO=valido · 87149e9c6a6c
CHECKPOINT=libero | T71 00000003
CICLI=3 chiusi · 1 dall'ultimo checkpoint del perimetro orchestrabile
MEMBRO|T71|run attesa|dlv=2|sessione=00000003|titolo=…
MEMBRO|T74|nessun passo|fermo=premessa decaduta
RISVEGLIO|183|segnalazioni|T71|00000003|<prima riga del testo finale>
--- T71
181 T71 turno 1 run · turno chiuso · segnalazioni · .claude/loom/headless/<sessionId>.out.json
182 T71 passo run → attesa · 00000003
--- -
179 git root ● main: run(T71): DLV2 …
```

`MEMBRO` dice il passo corrente di ogni membro — passo e fase — e se è fermo. Le righe dopo `--dal` sono gli eventi del monitor (task file, Prog, commit, sessioni), i passi, gli esiti dei turni e gli ordini, sotto il membro a cui appartengono. Il testo finale di un turno sta nel flusso: il file d'esito del deck tiene solo l'ultimo turno della conversazione.

## Il giro dello script

A ogni giro, ogni `--poll-seconds` (15 di default):

1. **L'orchestrator.** La testa di `T<id>.md` dice chi è: `Stato: attiva · <sid>`, `in passaggio · <sid>`, `passata a <sid>`. Il registro dei vivi dice se è vivo. `Stato: ferma` chiude il processo.
2. **Il piano**, riletto quando il file cambia, e verificato come fa `orchestration_schedule.py verify`, senza la storia: un `ERRORE` o un `DIFF` mettono in pausa i passi nuovi e svegliano l'orchestrator. La verifica riparte anche quando cambia il task file del perimetro orchestrabile o di un membro.
3. **Gli scanner del monitor** (`watch_sessions.py`): ogni evento del perimetro orchestrabile e dei suoi membri diventa una riga `evento`. Nessun evento sveglia l'orchestrator da solo, tranne quelli di §I risvegli.
4. **Gli ordini** nuovi dell'orchestrator.
5. **I passi aperti**: l'esito di ogni turno headless finito, letto da `loom-deck-headless status`, e la sua classificazione (§La lettura di un turno).
6. **I passi nuovi**, poi la fine del giro.
7. **Il keep-alive** della cache dell'orchestrator.

### Quando un passo parte

Niente parte senza un piano valido e un orchestrator vivo. Un membro riceve un passo nuovo solo se valgono tutte:

- non lo segue l'umano, non è fermo, non ha un passo aperto, e nessuna conversazione viva — tab o turno headless — è legata alla sua task;
- il suo `dopo` è soddisfatto, e nessuna sua dipendenza aperta verso una task fuori dal perimetro orchestrabile lo ferma;
- per un ciclo di lavoro, nessuna delle sue risorse è occupata da un altro ciclo aperto;
- per un checkpoint, nessun altro checkpoint è in corso nel perimetro orchestrabile.

Fra i membri pronti parte prima quello che più membri nominano nel loro `dopo`, poi l'ordine del piano. **Il passo** è il `passo` del piano se il membro non ne ha ancora fatto uno nel giro e i file lo permettono, altrimenti quello dei file (`next` di `perimeter.py tree`). Un preflight a premessa decaduta non parte mai da solo: il membro si ferma e l'orchestrator si sveglia. Lo stesso per un membro coi DLV tutti spuntati e la Prog non ✔️: il checkpoint in una conversazione nuova non ha il contesto del run.

Ogni passo è una conversazione headless (`loom-deck-headless open … --orchestrator <id del perimetro orchestrabile>`), con la sessione dell'orchestrator di adesso nel sidecar. Un run usa i DLV del campo `dlv` ancora aperti; senza, tutti gli aperti.

**Il ciclo di lavoro** è run → checkpoint nella stessa conversazione. A run pulito lo script manda da sé la richiesta di checkpoint, l'unico messaggio che parte senza l'orchestrator, e la sua prima riga dice chi lo manda. Il ciclo è chiuso quando il checkpoint è pulito.

**Il checkpoint del perimetro orchestrabile** parte quando niente è lanciabile, nessun passo è aperto, nessun checkpoint è in corso e almeno un ciclo si è chiuso dall'ultimo. Lo si legge come ogni checkpoint, sul task file del perimetro orchestrabile.

**A giro chiuso** — niente aperto, niente lanciabile, nessun ciclo da portare nel perimetro orchestrabile — lo script sveglia l'orchestrator: `fine giro` se i membri sono chiusi, `fermo` coi membri che restano e perché. Una volta per stato.

### Senza orchestrator, e col giro in chiusura

- **Orchestrator non vivo**: nessun passo nuovo e nessun messaggio. I turni in corso finiscono, il loro esito si scrive, e i risvegli aspettano l'orchestrator che si riattacca: il successore di un passaggio di consegne riscrive la testa di `T<id>.md`, e lo script lo segue.
- **Giro in chiusura** — il contesto dell'orchestrator di adesso ha passato il 100% di `--context-threshold`: nessun passo nuovo, ma i cicli aperti arrivano al checkpoint e il checkpoint del perimetro orchestrabile parte a fine giro.

## La lettura di un turno

**Lista bianca.** Un passo è chiuso solo su due prove insieme: una riga fissa nel testo finale e lo stato atteso su disco. Tutto il resto sveglia l'orchestrator. Un testo riconosciuto per esclusione sbaglia in silenzio alla prima skill che cambia forma; uno riconosciuto per inclusione, nel caso peggiore, sveglia l'orchestrator una volta di troppo.

| Passo | Chiuso quando | Prova su disco |
|---|---|---|
| preflight | `✅ Preflight completato` o `🛫 Nessuna ambiguità rilevata` | un blocco datato in `## Decisions`, non a premessa decaduta |
| run | `🚦 Segnalazioni — nessuna` → lo script chiede il checkpoint | tutti i DLV del perimetro eseguibile del run spuntati |
| checkpoint | `🚦 Segnalazioni — nessuna` | un `### Avanzamento` in più dal checkpoint chiesto |

Le due righe che la riga dell'organigramma chiede a ogni conversazione aperta dall'orchestrator:

- `❓ Domanda per l'orchestrator` — il turno chiede qualcosa. Vince su ogni altra riga, anche sulla riga fissa di un report.
- `✅ Risposte registrate` — il turno ha scritto gli scenari delle risposte dell'orchestrator alle segnalazioni. Su un run vale come il run pulito (checkpoint, coi DLV spuntati); su un checkpoint lo chiude.

**Il genere di un turno** lo dice il suo prompt: il primo turno ha l'azione con cui `open` l'ha aperto; un turno dopo è un checkpoint, un preflight o un run se il prompt porta `/loom-works:checkpoint-task`, `/loom-works:preflight-task` o `/loom-works:run-task`, altrimenti è una **risposta**. Una risposta si legge come il passo che segue: dopo un preflight è un preflight, dopo un checkpoint un checkpoint, dopo un run un run. Ne discende che **un messaggio dell'orchestrator che nomina una skill è un turno di quella skill**: le risposte alle domande non nominano `checkpoint-task`, e la richiesta di checkpoint lo nomina.

Un turno ripreso dall'utente in una tab dal deck non lo legge nessuno: lo script aspetta che la tab si chiuda.

## I risvegli

Una riga `risveglio` porta il motivo, il membro, la sessione e la prima riga del testo che l'ha prodotta. Il passo del membro resta fermo finché l'orchestrator non lo muove: rispondendo alla conversazione — un turno nuovo, che lo script legge come ogni altro — o con un ordine.

| Motivo | Cosa è successo | Il membro |
|---|---|---|
| `domande` · `proposte` | un preflight chiude con delle `D{N}`, o con sole `P{N}` | passo in attesa |
| `segnalazioni` | un report chiude con delle `S{N}` | passo in attesa; un checkpoint con segnalazioni tiene il posto del checkpoint |
| `domanda` | la riga `❓ Domanda per l'orchestrator` | passo in attesa |
| `dlv aperti` | un run chiude con la riga fissa e un DLV del suo perimetro eseguibile aperto | passo in attesa |
| `non classificato` | nessuna riga fissa, o la riga senza la prova su disco | passo in attesa |
| `errore` · `permesso negato` | l'esito del turno | passo in attesa |
| `premessa decaduta` | il membro ha un preflight a premessa decaduta | fermo |
| `ciclo interrotto` · `non chiusa` | DLV tutti spuntati e Prog non ✔️, prima del primo passo del giro o dopo un ciclo | fermo |
| `rifiuto` | `open` o `reply` rifiutati dal deck: lo script non ritenta | fermo, o passo in attesa |
| `stallo` | il turno headless di un passo è fermo da dieci minuti | passo aperto |
| `piano` | il piano non si legge o non combacia coi file | i passi nuovi in pausa |
| `tab` | fine turno, domanda, permesso, chiusura o stallo di una tab aperta dall'orchestrator | — |
| `contesto` | il contesto dell'orchestrator al 100% o al 120% della soglia | il giro si chiude |
| `fermo` · `fine giro` | niente da lanciare (§Quando un passo parte) | — |
| `keep-alive` | §Il keep-alive | — |

## Gli ordini

L'orchestrator comanda lo script con un ordine per membro, quando la risposta a una conversazione non basta:

- **`prosegui <membro>`** — l'ultimo turno del passo in attesa vale come pulito: un run passa al checkpoint, un preflight o un checkpoint si chiudono. Su un membro fermo, lo libera: il primo passo dopo l'ordine scavalca il motivo che l'aveva fermato, per esempio un preflight su una premessa decaduta ricostruita, o il checkpoint in una conversazione nuova.
- **`abbandona <membro>`** — lascia il passo aperto, senza toccare la conversazione, e libera il membro: il passo dopo parte in una conversazione nuova.
- **`tieni <membro>`** — ferma il membro: nessun passo nuovo finché un `prosegui` o un `abbandona` non lo liberano. Serve prima di aprire una tab su un membro, che lo script non vedrebbe finché la tab non nasce.

## Il keep-alive

La cache della conversazione dell'orchestrator dura un'ora, e ogni lettura ne fa ripartire il timer; un risveglio dopo un'ora di silenzio riscrive tutto il contesto. Lo script sveglia l'orchestrator dopo 55 minuti di silenzio (`--keepalive-minutes`), a tre condizioni: l'ultima scrittura in cache dell'orchestrator è a un'ora (in consumo extra Claude Code scende a cinque minuti, e un keep-alive non terrebbe niente); ogni risveglio è già stato letto; e non sono già partiti 25 keep-alive di fila. Il silenzio si misura dall'ultima risposta del modello nel transcript dell'orchestrator, e la fila si azzera con un altro risveglio o con un prompt dell'utente.

## La ripresa

Un processo rilanciato rilegge il flusso e riparte dal suo stato, senza ripetere e senza perdere passi:

- un turno finito mentre il processo era morto si legge al primo giro: l'esito sta nello stato del deck;
- prima di ogni `open` lo script scrive il passo `in apertura`. Se il processo muore prima di registrarne il sessionId, alla ripresa cerca fra gli stati headless del deck una conversazione aperta su quella task, con quell'azione e dall'orchestrator del perimetro orchestrabile dopo quella riga: se c'è la adotta, altrimenti l'apertura non è avvenuta e il passo riparte;
- una richiesta di checkpoint registra il numero del turno che attende. Il deck numera i turni prima di lanciarli: un numero più basso alla ripresa vuol dire che la richiesta non è partita, e si manda.

## Le righe del flusso

Una riga per evento, JSON, con `seq`, `ts` e `tipo`. Il passo corrente di un membro è la sua ultima riga `passo`, che porta la fotografia intera del passo.

| `tipo` | Campi |
|---|---|
| `avvio` · `fine` | pid e ora d'avvio del processo · il motivo della fine |
| `prima` | le cifre dei membri al primo avvio del giro: Prog, DLV, AC, titolo |
| `piano` | `valido` con impronta e membri, o `non valido` col motivo |
| `evento` | genere, testo, task |
| `passo` | membro, passo, fase (`in apertura`, `turno`, `attesa`, `coda`, `checkpoint`, `chiuso`, `abbandonato`), sessione, titolo, DLV del run, ultimo turno letto, genere dell'ultimo turno, avanzamenti di partenza |
| `turno` | membro, sessione, numero, genere, esito, verdetto, testo finale, file d'esito del deck |
| `risveglio` | motivo, membro, sessione, dettaglio |
| `fermo` · `libero` | membro, motivo |
| `ordine` | numero, ordine, membro, esito |
| `guasto` | la fonte che si è rotta e l'errore: il processo continua |
