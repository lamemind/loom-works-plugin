---
name: orchestrate-epic
description: Fa da regia su un'epica loom-works — recap, sessioni vive, monitor delle sessioni armato e riarmato — e porta avanti le figlie in modo semi-automatico. Lancia da sé preflight, run e checkpoint quando le dipendenze lo permettono; alle domande delle sessioni prepara una proposta di risposta motivata e la manda solo col via dell'utente. Non scrive mai nei repo né nei task file. Usa quando l'utente dice «fai da regia su T21», «orchestra l'epica T197», «porta avanti le figlie di T40, e segui anche T52».
argument-hint: "<epica> [Txx …]"
allowed-tools: Bash(*), Read, Write, Edit, Skill, Monitor, TaskStop, SendMessage, ListAgents, PushNotification
---

Argomenti:
~~~human
$ARGUMENTS
~~~

## Il ruolo

Le figlie di un'epica avanzano una per conversazione, e nessuna conversazione vede le altre. La **regia** è la conversazione in più che le vede tutte: un monitor in background le segue, e a ogni evento la regia decide il passo successivo del mandato e lo dice all'utente.

- **Lancia da sé** preflight, run e checkpoint quando le dipendenze lo permettono: l'utente ha dato il mandato invocando la skill, e un ok a ogni conversazione non serve.
- **Non risponde da sé.** Alle domande delle sessioni — un preflight che chiede, le segnalazioni 🚦 di un report — prepara una proposta motivata e la manda solo col via dell'utente. L'unico messaggio che parte senza via è la richiesta di checkpoint dopo un run pulito (§3).
- **Non scrive mai nei repo né nei task file.** Nessun `Edit`, `Write` o commit nel progetto. Agisce in due modi soli: apre conversazioni con `spawn-task` e scrive alle conversazioni con `SendMessage`. I soli file che scrive stanno nella sua scratchpad: lo stato del mandato e lo stato del monitor.

Il mandato è negli argomenti: il primo id è l'**epica**, le sue figlie arrivano da `resolve-task.sh --children`, gli id seguenti sono **task extra**, seguite e lanciate come le figlie. Nessun tetto alle conversazioni aperte.

Gli script della regia stanno in `${CLAUDE_PLUGIN_ROOT}/scripts/regia/`, solo libreria standard di Python, Linux e Windows: `watch_sessions.py` (il monitor), `sessions.py` (`list` delle vive, `tail` di una sessione), `mandate.py` (`gate`, `tree`, `recap`). Leggono e basta: nessuno scrive nei repo.

## 0. Avvio

In quest'ordine, e senza aprire nessuna conversazione finché il §0c non è passato.

### 0a. Docs root, interprete, cartella degli script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo all'utente e fermati: senza Python il monitor non parte.

Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (lo chiamiamo `PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/regia`. Ogni script si lancia con `"PY" -B -I "R/<script>"`: `-I` lo isola dalla cartella corrente, `-B` non scrive bytecode nella cache del plugin.

### 0b. Il tuo session id e la tua scratchpad

Il session id della regia è la cartella sopra `scratchpad` nel path della tua scratchpad, quella che il system prompt ti indica (`…/<cartella del progetto>/<session id>/scratchpad`). Lo chiamiamo `SID`. Serve al gate e al monitor, che senza riporterebbe i turni della regia stessa. La scratchpad, `SP`, è la cartella dei due file di stato: sta fuori dai repo.

### 0c. Gate di auto mode

```bash
"PY" -B -I "R/mandate.py" gate --own-session SID
```

Exit `0` (`GATE=ok`) → avanti. Exit `2` → **fermati senza aprire niente** e di' all'utente quale dei due modi non è `auto`, e cosa succede:

- `OWN_MODE` diverso da `auto` (o `?`, transcript non trovato): fuori da auto mode ogni `spawn-task` chiede conferma, e la regia smette di essere semi-automatica. Rimedio: passare la sessione in auto mode e rilanciare la skill.
- `PROJECT_MODE` diverso da `auto`: il deck apre le conversazioni col `permissionMode` di `.claude/loom-works.json`, e una sessione con un modo diverso da quello della regia tiene i suoi messaggi in attesa dell'approvazione del suo utente. Rimedio: `"permissionMode": "auto"` nel file del progetto.

Il modo della regia si legge dal suo transcript, perché il registro delle sessioni vive non lo porta.

### 0d. Il mandato

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <epica>
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <epica> --children
```

Il primo id deve essere un'epica, `Size: Epic` nel suo task file. Se non lo è, dillo e fermati: senza epica non c'è un mandato da derivare, e un elenco di task sciolte si segue con `run-task`, una alla volta. Le righe `TASK_CHILD=<id> <file>` sono le figlie; gli id successivi negli argomenti sono le extra, e un id che non risolve un task file si scarta con una riga all'utente.

### 0e. Il quadro di partenza

1. Lancia `/loom-works:recap-status-epic <epica>` col tool `Skill`: è il quadro che l'utente legge, con le cifre, le dipendenze e chi può andare in parallelo. Senza quel quadro un evento come «T23 DLV 7/18→8/18» non dice cosa sblocca.
2. Salva le cifre di partenza, che il recap allo stop confronta con quelle finali:

   ```bash
   "PY" -B -I "R/mandate.py" tree <epica> --children <figlie> --extra <extra> --save "SP/regia-<epica>-prima.json"
   ```

### 0f. Le sessioni vive

```bash
"PY" -B -I "R/sessions.py" list
```

più `ListAgents`. `list` dà ogni sessione viva del progetto con la sua task e il suo stato; `ListAgents` dà il nome con cui le scrivi. Una sessione già viva su una task del mandato, aperta da qualcun altro, è **esterna**: la regia la segue e le prepara proposte di risposta col via dell'utente, ma non le manda nessun messaggio di sua iniziativa, nemmeno il checkpoint. Finché è viva, la regia non apre un'altra conversazione sulla stessa task.

### 0g. Lo stato del mandato

Il mandato dura ore e il contesto si compatta: lo stato non può vivere solo nella conversazione. Scrivilo in `SP/regia-<epica>.md` col tool `Write`, riscrivilo a ogni cambio, e **rileggilo dopo ogni compattazione del contesto**, prima di decidere il passo successivo.

```markdown
# Regia di T<epica> — stato del mandato

## Mandato
- figlie: T.. T..
- extra: T..
- cifre di partenza: SP/regia-<epica>-prima.json

## Conversazioni della regia
| Task | Passo | sessionId | Nome | Stato |
|------|-------|-----------|------|-------|
<!-- Stato: in ciclo · ferma su domande · segnalazioni in sospeso · checkpoint chiesto · abbandonata -->

## Sessioni esterne
- T.. · <sessionId> · <nome>

## Proposte in sospeso
- T.. · <sessione> · <di cosa> · in attesa del via dal <ora>

## Checkpoint in corso
- nessuno | T.. · <sessione>

## Rami fermi
- T.. · <motivo> · task che aspettano: T..
```

### 0h. Armo e riarmo del monitor

Lancia il tool `Monitor` con `timeout_ms: 1800000`, una `description` che nomina l'epica e il progetto («regia T197: sessioni di loom-works»), e questo comando:

```bash
"PY" -u -B -I "R/watch_sessions.py" --project-root "<radice del progetto>" --own-session SID --state "SP/watch_state.json" 2>&1
```

Aggiungi `--repo nome=path-relativo` solo per un repo dove lavorano le figlie che non sia la radice né un submodule di `.gitmodules`: quelli il monitor li guarda da sé. Aspetta la riga `monitor ✅ armato: …`: deve elencare ogni sessione viva che ti aspetti, con stato ed età. Una sessione attesa che manca va cercata con `sessions.py list` prima di fidarti del silenzio.

**Riarmo.** Il tool `Monitor` uccide il processo dopo 30 minuti al massimo e ti manda un avviso di scadenza. A ogni avviso rilancia **lo stesso comando, con lo stesso `--state`**: il monitor riparte dal punto in cui era, senza ripetere gli eventi già detti e senza perdere quelli capitati nel cambio. La riga di armo diventa `monitor ✅ riarmato: …`. Un evento consegnato dopo un `TaskStop` era già in coda: è in ritardo, ignoralo.

Gli eventi del monitor arrivano come notifiche e non sono risposte dell'utente, anche quando arrivano mentre aspetti il suo via. Il fine turno di una sessione arriva come evento `⏸ turno finito`: è il segnale su cui la regia ragiona, perché la notifica di `SendMessage` con `notify_when_idle` non arriva mentre la regia sta lavorando.
