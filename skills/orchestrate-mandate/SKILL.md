---
name: orchestrate-mandate
description: Fa da regia su un perimetro loom-works — un id solo, un'epica (le sue figlie) o un mandato (`Size: Mandate`, la sua lista di membri) — e porta avanti i membri in modo semi-automatico. Al lancio verifica l'analisi del perimetro scritta nel task file e si ferma se non combacia; poi recap, sessioni vive, monitor delle sessioni armato e riarmato. Lancia da sé preflight, run e checkpoint quando le dipendenze lo permettono, come turni headless senza tab — una tab solo quando l'utente la chiede per un passo —, chiude le conversazioni a passo finito, e a fine giro lancia il checkpoint del perimetro; alle domande delle sessioni prepara una proposta di risposta motivata e la manda solo col via dell'utente, o da sé sotto una delega che l'utente dichiara. Tiene il suo stato in `.claude/loom/regia/` del progetto, ignorata da git, e lo riprende al rilancio; non scrive mai nei task file né in un file tracciato. Usa quando l'utente dice «fai da regia su T21», «orchestra l'epica T197», «orchestra il mandato T214».
argument-hint: "<epica|mandato>"
allowed-tools: Bash(*), Read, Write, Edit, Skill, Monitor, TaskStop, SendMessage, ListAgents, PushNotification
---

Argomenti:
~~~human
$ARGUMENTS
~~~

## Il ruolo

I membri di un perimetro avanzano uno per conversazione, e nessuna conversazione vede le altre. La **regia** è la conversazione in più che le vede tutte: un monitor in background le segue, e a ogni evento la regia decide il passo successivo del perimetro e lo dice all'utente.

- **Lancia da sé** preflight, run e checkpoint quando le dipendenze lo permettono: l'utente ha dato il mandato invocando la skill, e un ok a ogni conversazione non serve.
- **Non risponde da sé**, salvo delega. Alle domande delle sessioni — un preflight che chiede, le segnalazioni 🚦 di un report — prepara una proposta motivata e la manda solo col via dell'utente. L'unico messaggio che parte senza via è la richiesta di checkpoint dopo un run pulito (§2). Con una delega che l'utente dichiara nella chat della regia, manda da sé anche le risposte, entro i limiti del §3.
- **Non scrive mai nei task file né in un file tracciato.** Nessun `Edit`, `Write` o commit su un file che git segue. Agisce sulle conversazioni e basta: le apre e le porta avanti come turni headless con `loom-deck-headless` (§2); apre una tab con `spawn-task` solo quando l'utente la chiede per un passo; scrive a una tab viva con `SendMessage`, e chiude con `close-session` le tab che ha aperto, a passo finito. I soli file che scrive stanno in `.claude/loom/regia/` del progetto, che git ignora: lo stato della regia, le cifre di partenza e lo stato del monitor (§0f, Lo stato su disco).

Il **perimetro** è un id solo negli argomenti: un'**epica** (`Size: Epic`), i cui membri sono le figlie, o un **mandato** (`Size: Mandate`), che elenca i membri nel proprio file (`${CLAUDE_PLUGIN_ROOT}/docs/mandate-format.md`). La regia li tratta allo stesso modo: i membri arrivano dal lettore unico, `resolve-task.sh <id> --members`, e il perimetro con tutti i suoi membri è ciò che la regia porta avanti. Un perimetro più largo — un'epica e qualche task in più, task di epiche diverse — si costruisce prima del lancio con `/loom-works:prepare-mandate`, mai negli argomenti. Nessun tetto alle conversazioni aperte.

Gli script della regia stanno in `${CLAUDE_PLUGIN_ROOT}/scripts/regia/`, solo libreria standard di Python, Linux e Windows: `watch_sessions.py` (il monitor), `sessions.py` (`list` delle vive, `tail` di una sessione, `regie` delle altre regie vive), `mandate.py` (`gate`, `tree`, `verify`, `recap`), `regia_state.py` (`check` dello stato su disco al lancio, `facts` per `checkpoint-mandate`). Nessuno scrive un file tracciato: scrivono solo sotto `.claude/loom/regia/`.

## 0. Avvio

In quest'ordine, e senza aprire nessuna conversazione finché i controlli d'ingresso (§0c, §0d, §0e, §0f) non sono passati.

### 0a. Docs root, interprete, cartella degli script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo all'utente e fermati: senza Python il monitor non parte.

Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (lo chiamiamo `PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/regia`. Ogni script si lancia con `"PY" -B -I "R/<script>"`: `-I` lo isola dalla cartella corrente, `-B` non scrive bytecode nella cache del plugin.

### 0b. Il tuo session id

Il session id della regia è la cartella sopra `scratchpad` nel path della tua scratchpad, quella che il system prompt ti indica (`…/<cartella del progetto>/<session id>/scratchpad`). Lo chiamiamo `SID`. Serve al gate, al monitor, che senza riporterebbe i turni della regia stessa, e allo stato su disco, che lo porta nella riga di testa (§0i).

La scratchpad non tiene niente della regia: sta nella temp di sistema, e un reboot o una pulizia la svuotano a giro aperto. I file della regia stanno nel progetto (§0f, Lo stato su disco).

### 0c. Gate di auto mode

```bash
"PY" -B -I "R/mandate.py" gate --own-session SID
```

Exit `0` (`GATE=ok`) → avanti. Exit `2` → **fermati senza aprire niente** e di' all'utente quale dei due modi non è `auto`, e cosa succede:

- `OWN_MODE` diverso da `auto` (o `?`, transcript non trovato): fuori da auto mode ogni comando `loom-deck-headless` e ogni `spawn-task` chiede conferma, e la regia smette di essere semi-automatica. Rimedio: passare la sessione in auto mode e rilanciare la skill.
- `PROJECT_MODE` diverso da `auto`: le conversazioni nascono col `permissionMode` di `.claude/loom-works.json`, headless o in una tab. Un turno headless non ha nessuno che approva: in `manual` `loom-deck-headless open` rifiuta run e checkpoint, e in ogni modo diverso da `auto` il turno si vede negare ciò che il modo non concede da sé. Una tab con un modo diverso da quello della regia tiene i suoi messaggi in attesa dell'approvazione del suo utente. Rimedio: `"permissionMode": "auto"` nel file del progetto.

Il modo della regia si legge dal suo transcript, perché il registro delle sessioni vive non lo porta.

### 0d. Il perimetro e i membri

Gli argomenti portano **un id solo**. Con un id dopo il primo fermati prima di aprire qualsiasi cosa, e di' all'utente che il perimetro è un id solo, un'epica o un mandato, e che per seguire insieme task in più si prepara un mandato con `/loom-works:prepare-mandate <id…>`. Non proseguire sul primo id: le conversazioni partirebbero su un perimetro diverso da quello che l'utente ha scritto.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <perimetro>
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <perimetro> --members
```

Il `Size` del task file del perimetro deve essere `Epic` o `Mandate`. Se non lo è, dillo e fermati: una task normale si esegue con `run-task`, e un elenco di task sciolte diventa un perimetro con `prepare-mandate`.

Le righe `TASK_MEMBER=<id> <file>` sono i membri, nell'ordine del lettore: le figlie per un'epica (`TASK_MEMBERS_SRC=parent`), la lista `## Membri` per un mandato (`TASK_MEMBERS_SRC=list`). Una riga `TASK_MEMBER_MISSING=<id>` è un membro dichiarato senza task file: una riga all'utente, e resta fuori. `TASK_MEMBERS_COUNT=0` → dillo e fermati: non c'è niente da portare avanti.

I membri si leggono **solo** dal lettore, mai a mano dal task file, e si rileggono a ogni quadro (§1).

### 0e. La verifica al lancio

Il perimetro porta nel suo task file la sezione `## Analisi del perimetro`: quali coppie di membri non possono girare insieme, e su cosa (`${CLAUDE_PLUGIN_ROOT}/docs/mandate-format.md`). Prima della prima conversazione la regia controlla che l'analisi scritta valga ancora:

```bash
"PY" -B -I "R/mandate.py" verify <perimetro> --children <membri>
```

Le righe:

| Riga | Cosa dice |
|---|---|
| `PERIMETRO=<id>\|epica\|mandato` · `ANALYSIS=presente\|assente` · `ROWS=<n>` | il perimetro, e se la sezione c'è |
| `ANALYSIS_COMMIT=<sha>` · `ANALYSIS_FROM=sezione\|avanzamento` | il commit da cui l'analisi vale: il più recente fra l'ultimo che ha cambiato le righe della sezione e l'ultimo `### Avanzamento` del perimetro, cioè l'ultimo giro di `checkpoint-mandate`, che riverifica l'analisi. `ANALYSIS_COMMIT=? (<motivo>)`: file o sezione non committati |
| `DIFF\|<tipo>\|<coppia>\|<dettaglio>` | una differenza della metà meccanica: `manca` (una riga `CONFLICT` di `tree` senza la sua riga, o un path che la riga non cita), `in più` (una riga `dichiarata` o `materiale` che `tree` non calcola), `fuori` (una riga su una task che non è un membro aperto), `forma` (una riga fuori dal formato), `membri` (la lista di un mandato cambiata dopo l'analisi) |
| `MODELLO\|<a>\|<b>\|<su cosa>` | una collisione della metà del modello fra due membri aperti |
| `CAMBIATO\|<id>\|modificato\|nuovo` | un membro aperto il cui task file è cambiato dopo il commit dell'analisi, o è nato dopo |
| `VERIFY=ok\|riesame\|stop` | il verdetto |

Una riga che nomina un membro chiuso non è una differenza: `tree` tace sulle task chiuse, e la riga resta scritta.

- **`VERIFY=stop`** (exit `2`) → **fermati senza aprire niente**. Di' all'utente perché, riga per riga — analisi assente, non committata, ogni `DIFF` —, e il rimedio: `/loom-works:prepare-mandate <perimetro>`, che riscrive l'analisi di un'epica o di un mandato. La regia non scrive nei task file e non può correggere da sé. Un'epica che non ha mai avuto l'analisi si ferma allo stesso modo.
- **`VERIFY=riesame`** (exit `0`) → la metà meccanica combacia, e i membri `CAMBIATO` vanno riletti prima di partire: leggi il loro task file per intero e, col metodo di `${CLAUDE_PLUGIN_ROOT}/docs/mandate-analysis.md` §La metà del modello, controlla due cose. Le righe `MODELLO` che li nominano reggono ancora: il task file nomina ancora quel file, quel simbolo, quel comportamento? E le loro coppie con gli altri membri aperti hanno una collisione nuova, che la tabella non porta? Un membro `nuovo` passa da zero: tutte le sue coppie. I membri non cambiati non si rileggono: le loro coppie le ha già viste chi ha scritto la sezione, ed è per questo che la verifica costa meno dell'analisi. Una riga che non regge o una collisione nuova → fermati come sullo stop, nominando membro, coppia e oggetto. Nessuna delle due → avanti.
- **`VERIFY=ok`** (exit `0`) → avanti.

Le righe `MODELLO` che hanno passato la verifica vanno nello stato, in `## Collisioni del modello` (§0i): su quelle coppie `tree` tace, e senza la regia le lancerebbe in parallelo (§1, Le regole di partenza). Si ricaricano rilanciando `verify` dopo un commit che cambia il file del perimetro durante il giro — l'evento `git` di un commit `task(T<perimetro>): …` o `checkpoint(T<perimetro>): …`: `verify` legge la storia, e un file cambiato ma non ancora committato non vale ancora. Uno stop a giro avviato non ferma la regia, ma va detto all'utente con il rimando a `prepare-mandate`, e le righe `MODELLO` nuove sostituiscono le vecchie.

### 0f. Le altre regie vive e lo stato su disco

Due regie su due perimetri che hanno un membro aperto in comune lancerebbero tutte e due la stessa task: la regola «un passo alla volta» vede una sessione esterna solo quando è già viva, e la coda dei checkpoint vale dentro una regia sola. Prima di aprire niente controlla le altre regie vive sul progetto:

```bash
"PY" -B -I "R/sessions.py" regie --own-session SID
```

Una riga `REGIA|<sessionId>|<perimetro>|<etichetta>` per ogni altra sessione viva che ha lanciato una regia e non l'ha fermata, poi `REGIE=<n>`. Per ognuna leggi i membri del suo perimetro col lettore unico:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <perimetro dell'altra regia> --members
```

Un membro è **in comune** se compare fra i tuoi membri aperti — le righe `TASK` di `"PY" -B -I "R/mandate.py" tree <perimetro> --children <membri>` con `next` diverso da `chiusa` ed `epica` — e fra i membri dell'altra regia; lo è anche il tuo stesso perimetro, se l'altra regia porta avanti quello. Un membro in comune → **fermati senza aprire niente**, e di' all'utente quale regia (sessionId corto, perimetro con la maniglia), quali membri in comune, e le due strade: fermare l'altra regia — chiederle lo stop nella sua chat, o chiuderne la conversazione —, o togliere i membri in comune da uno dei due perimetri con `prepare-mandate`. Nessun membro in comune → avanti.

**Il controllo vede solo questa macchina.** Il registro delle sessioni vive e i transcript sono locali: una regia lanciata da un'altra macchina sullo stesso repo — una su Windows, una su Linux — non compare, e nessun meccanismo la vede, nemmeno un lock su file. Per quel caso vale una regola, a carico dell'utente: **non lanciare due regie su perimetri con una task aperta in comune, su nessuna macchina.** Dillo all'utente in una riga a ogni avvio in cui il controllo passa.

#### Lo stato su disco

La regia tiene tre file in `.claude/loom/regia/` del progetto, col nome ricavato dall'id del perimetro: `T<perimetro>.md`, lo stato (§0i); `T<perimetro>-prima.json`, le cifre di partenza (§0g); `T<perimetro>-watch.json`, il punto da cui riparte il monitor (§0j). Stanno nel progetto perché sopravvivano a un reboot, e sotto `.claude/loom/` perché git la ignora: nella task folder del perimetro, che è tracciata, il `git add -A` di un `checkpoint-task` linked committerebbe lo stato a metà giro. Nessuno li cancella: il giro dopo eredita i fatti del perimetro, e `checkpoint-mandate` li legge da lì.

```bash
"PY" -B -I "R/regia_state.py" check <perimetro> --own-session SID
```

`STATE_FILE`, `BEFORE_FILE` e `WATCH_FILE` sono i tre path: da qui in poi li scrivi per esteso, come `PY` e `R`. `CREATED_ON` è il `Created on` del task file del perimetro, che entra nella testa dello stato (§0i). Lo script crea la cartella.

**`IGNORED=no`** (exit `2`, `CHECK=stop`) → **fermati senza aprire niente**: git non ignora `.claude/loom/`, e lo stato finirebbe nel commit del primo `checkpoint-task` linked. Di' all'utente la riga da aggiungere al `.gitignore` del progetto, quella di `IGNORE_RULE`, e di rilanciare la regia. `IGNORED=fuori da git` va avanti; `IGNORED=?` — git non risponde — va avanti con una riga all'utente.

La riga `STATE=` dice cosa hai trovato:

| `STATE` | Cosa trovi | Cosa fai |
|---|---|---|
| `assente` | nessuno stato | giro nuovo |
| `altro` | lo stato di un perimetro passato con lo stesso id: il `Created on` non è quello del task file | giro nuovo, lo stato vecchio si sovrascrive |
| `ferma` | lo stato di una regia fermata allo stop (§5) | giro nuovo che eredita i soli fatti del perimetro |
| `mia` | `attiva`, scritta da questa sessione | ripresa di tutto |
| `morta` | `attiva` o `passata a` di una sessione che non è più viva: la regia si è chiusa senza stop | ripresa di tutto tranne la delega |
| `viva` | `attiva` o `passata a` di un'altra sessione viva | fermati, exit `2` |
| `passata` | `passata a` questa sessione | fermati, exit `2` |
| `illeggibile` | il file c'è, la testa no | fermati, exit `2` |

- **Giro nuovo** (`ROUND=nuovo`). Lo script ha già tolto lo stato del monitor (`WATCH=tolto`): riarmato su un file vecchio, il monitor darebbe come eventi tutto ciò che è cambiato dal giro prima. Le cifre di partenza si riscrivono (§0g). Su `ferma` leggi lo stato vecchio con `Read` prima di riscriverlo, e porta nello stato nuovo la sezione `## Fatti del perimetro` intera, aperti e superati: lo stop non lancia il checkpoint del perimetro, e quei fatti possono stare solo lì. Li riesamini al primo quadro (§1): un fatto aperto che i membri hanno chiuso nel frattempo diventa superato. Conversazioni, proposte, rami fermi, collisioni e delega ripartono da zero.
- **Ripresa** (`ROUND=ripresa`). Leggi lo stato con `Read` e riparti da lì. Lo stato del monitor resta, e il monitor riarmato riparte dal punto in cui era (§0j). Le cifre di partenza restano quelle salvate all'avvio del giro (`BEFORE=tieni`), e si riscrivono solo se il file manca (`BEFORE=scrivi`). Su `morta` la regia di prima si è chiusa senza stop — un crash, una tab chiusa, un reboot: adotti conversazioni, proposte in sospeso, rami fermi e fatti; le conversazioni della tabella che `sessions.py list` non dà più vive (§0h) diventano `abbandonata (non più viva alla ripresa)`, e un `## Checkpoint in corso` su una di loro si libera; la **delega torna `no`**, perché vale solo nella chat dove l'utente l'ha data, e l'utente la ridichiara qui se la vuole. Scrivi in chat cosa hai trovato: conversazioni adottate e abbandonate, proposte in sospeso, rami fermi, fatti aperti, delega tolta.
- **`viva`** → **fermati senza aprire niente**: un'altra regia viva tiene lo stato di questo perimetro, la sessione di `STATE_HOLDER`. Le strade sono quelle della guardia sopra: fermarla nella sua chat, o chiuderne la conversazione.
- **`passata`** → **fermati senza aprire niente**: un'altra regia ha passato le consegne a questa sessione, e la ripresa di chi riceve le consegne non c'è ancora. Di' all'utente il path dello stato.
- **`illeggibile`** → **fermati senza aprire niente**, e di' all'utente il path: lo stato lo corregge o lo toglie lui. La regia non sovrascrive un file che non sa leggere, perché può portare i fatti di un giro.

Exit `1` — task file del perimetro mancante, registro delle sessioni illeggibile → dillo e fermati.

### 0g. Il quadro di partenza

1. Lancia `/loom-works:recap-status-epic <perimetro>` col tool `Skill`, che vale per un'epica e per un mandato: è il quadro che l'utente legge, con le cifre, le dipendenze e chi può andare in parallelo. Senza quel quadro un evento come «T23 DLV 7/18→8/18» non dice cosa sblocca.
2. Con `BEFORE=scrivi` (§0f) salva le cifre di partenza, che il recap allo stop confronta con quelle finali:

   ```bash
   "PY" -B -I "R/mandate.py" tree <perimetro> --children <membri> --save "<BEFORE_FILE>"
   ```

   Con `BEFORE=tieni` restano quelle del giro che riprendi: il recap allo stop confronta con l'avvio del giro, non con la ripresa.

### 0h. Le sessioni vive

```bash
"PY" -B -I "R/sessions.py" list
```

più `ListAgents`. `list` dà ogni sessione viva del progetto con la sua task e il suo stato; `ListAgents` dà il nome con cui le scrivi. Una sessione già viva su un membro del perimetro, aperta da qualcun altro, è **esterna**: la regia la segue e le prepara proposte di risposta col via dell'utente, ma non le manda nessun messaggio di sua iniziativa, nemmeno il checkpoint. Finché è viva, la regia non apre un'altra conversazione sulla stessa task.

Una sessione viva su una task fuori dal perimetro, o senza task, non è esterna: è fuori dal perimetro, e la regia la ignora (§1, Il riporto).

### 0i. Lo stato della regia

Il giro dura ore e il contesto si compatta: lo stato non può vivere solo nella conversazione. Scrivilo in `STATE_FILE` (§0f) col tool `Write`, riscrivilo intero a ogni cambio, e **rileggilo dopo ogni compattazione del contesto**, prima di decidere il passo successivo.

Le due righe di testa stanno prima di ogni heading, e `regia_state.py check` le legge al lancio di una regia dopo questa:

- **`Stato:`** — `Stato: attiva · SID` dalla prima scrittura del giro, anche in una ripresa; `Stato: ferma · SID` allo stop (§5). Una regia che passa le consegne a un'altra sessione scrive `Stato: passata a <sessionId>`. La riga dice a chi rilancia la regia se trova un giro in corso, un giro chiuso o le consegne di un'altra regia.
- **`Perimetro:`** — `Perimetro: T<perimetro> · Created on <CREATED_ON>`, l'identità. L'id di un perimetro purgato può tornare a una task nuova, e uno stato con un altro `Created on` vale come assente.

```markdown
Stato: attiva · <SID>
Perimetro: T<perimetro> · Created on <CREATED_ON>

# Regia di T<perimetro> — stato

## Perimetro
- T<perimetro> · epica | mandato
- membri: T.. T..
- cifre di partenza: <BEFORE_FILE>

## Conversazioni della regia
| Task | Passo | sessionId | Nome | Stato |
|------|-------|-----------|------|-------|
<!-- Stato: in ciclo · ferma su domande · segnalazioni in sospeso · checkpoint chiesto · chiusa · abbandonata (<motivo>) -->

## Fatti del perimetro
- T.. · <il fatto> · <dove l'ha detto: report del run, messaggio, preflight> [· superato: <cosa lo chiude>]

## Collisioni del modello
- T.. · T.. · <su cosa>   (righe MODELLO di verify, ricaricate a ogni commit del file del perimetro)

## Sessioni esterne
- T.. · <sessionId> · <nome>

## Proposte in sospeso
- T.. · <sessione> · <di cosa> · in attesa del via dal <ora>

## Checkpoint in corso
- nessuno | T.. · <sessione> | T<perimetro> (perimetro) · <sessione>

## Checkpoint del perimetro
- cicli chiusi dall'ultimo: <n> · ultimo: mai | <ora> · <sessione>

## Rami fermi
- T.. · <motivo> · task che aspettano: T..

## Delega
- no | sì dal <ora>: «<le parole dell'utente>»
```

### 0j. Armo e riarmo del monitor

Lancia il tool `Monitor` con `timeout_ms: 1800000`, una `description` che nomina il perimetro e il progetto («regia T197: sessioni di loom-works»), e questo comando:

```bash
"PY" -u -B -I "R/watch_sessions.py" --project-root "<radice del progetto>" --own-session SID --state "<WATCH_FILE>" 2>&1
```

Aggiungi `--repo nome=path-relativo` solo per un repo dove lavorano i membri che non sia la radice né un submodule di `.gitmodules`: quelli il monitor li guarda da sé. Aspetta la riga `monitor ✅ armato: …`: deve elencare ogni sessione viva che ti aspetti, con stato ed età. Una sessione attesa che manca va cercata con `sessions.py list` prima di fidarti del silenzio.

**Riarmo.** Il tool `Monitor` uccide il processo dopo 30 minuti al massimo e ti manda un avviso di scadenza. A ogni avviso rilancia **lo stesso comando, con lo stesso `--state`**: il monitor riparte dal punto in cui era, senza ripetere gli eventi già detti e senza perdere quelli capitati nel cambio. Vale anche per il primo armo di una ripresa (§0f): il file è quello del giro ripreso. La riga di armo diventa `monitor ✅ riarmato: …`. Un evento consegnato dopo un `TaskStop` era già in coda: è in ritardo, ignoralo.

Gli eventi del monitor arrivano come notifiche e non sono risposte dell'utente, anche quando arrivano mentre aspetti il suo via. Il fine turno di una sessione arriva come evento `⏸ turno finito`: è il segnale su cui la regia ragiona, perché la notifica di `SendMessage` con `notify_when_idle` non arriva mentre la regia sta lavorando.

## 1. Il quadro e la scelta del passo

Il passo successivo si decide sul quadro dei file, mai a memoria. Rifai il quadro dopo l'armo e dopo ogni evento che cambia lo stato di una task — un fine turno, un checkpoint finito, una risposta dell'utente. Il quadro sono due letture, sempre insieme e in quest'ordine:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <perimetro> --members
"PY" -B -I "R/mandate.py" tree <perimetro> --children <membri>
```

### I membri, a ogni quadro

I membri si rileggono dal lettore unico a ogni quadro, e i `<membri>` di `tree` sono quelli di **questa** lettura, non quelli dell'avvio: un perimetro cambia durante il giro. In un'epica nasce una figlia nuova, che dichiara il `Parent Task`; in un mandato `prepare-mandate` aggiunge o toglie una riga di `## Membri`. Confronta la lettura con la riga `membri:` dello stato:

- **Un membro nuovo** entra nel mandato della regia da questo quadro, e parte con le sole regole del quadro: le dipendenze e i path in comune che `tree` calcola. Una riga all'utente: `T70 (maniglia) entra nel perimetro: l'analisi scritta non lo copre, e le collisioni che nessun campo dichiara non le vedo — per coprirlo /loom-works:prepare-mandate <perimetro>`. La regia non si ferma: l'analisi non la può scrivere, e un ramo fermo in attesa di un'analisi resterebbe appeso all'utente.
- **Un membro tolto** esce dal mandato della regia: nessuna conversazione nuova su di lui. Un suo ciclo già aperto da questa regia arriva al checkpoint come gli altri, poi la task si lascia andare. Una riga all'utente.
- **Un `TASK_MEMBER_MISSING` nuovo** — un membro purgato da `clean-tasks` durante il giro — esce come un membro tolto.

Riscrivi la riga `membri:` dello stato a ogni cambio. Le cifre di partenza del recap (§5) restano quelle salvate all'avvio: un membro entrato dopo non ha un «prima», e il recap lo dice.

Le righe che legge la regia:

| Riga | Cosa dice |
|---|---|
| `TASK\|<id>\|prog=…\|size=…\|preflight=…\|dlv=a/b\|ac=a/b\|next=…\|blocked=…\|title=…` | stato della task e prossimo passo del suo ciclo |
| `DEPS\|<id>\|T.. ✔ (deps) · T.. 🟡 (grafo)` | da chi dipende, con la Prog e la fonte: `## Dependencies` del task file o frecce e Cross-deps del grafo. Il perimetro non compare: si chiude dopo i membri, e un membro che lo nomina non lo aspetta |
| `MATERIALE\|<id>\|<path> · …` | i path di `## Materiale`, `📁/` sciolto nella task folder; le voci 🎬, lo stato della regia, non entrano |
| `CONFLICT\|<id>\|<id>\|dipendenza` · `…\|materiale: <path>` | due task aperte che non possono girare insieme: una dipendenza fra loro, o un path in comune che almeno una delle due non dichiara come 📖 fonte (due letture non si scontrano) |

Lo stato viene dalla cella Prog della tabella Tasks Overview e dal task file, **mai dai glifi del grafo**: fra la promozione e il checkpoint i glifi del grafo restano indietro. Il grafo dà solo le frecce.

`next` vale:

- `preflight` — nessun preflight valido su una task 🔵: manca il blocco datato in `## Decisions`; oppure, a ogni Prog, l'ultimo blocco è una «premessa decaduta». Una task 🟢 o 🟡 senza blocco è già partita senza preflight, che per una S o una M non è obbligatorio: va a `run` o a `checkpoint`. Una Size L senza blocco va a `preflight` a ogni Prog: `run-task` su una L senza preflight si rifiuta di partire. Il primo caso lo lanci; il secondo no: la ricostruzione delle premesse è dell'utente, e la task diventa un ramo fermo (§4).
- `run` — preflight fatto, o task già partita, e DLV aperti.
- `checkpoint` — tutti i DLV spuntati, Prog non ancora ✔️: il ciclo si è interrotto prima del checkpoint. Non lo lanci in una conversazione nuova, che non avrebbe il contesto del run (§2): scala all'utente.
- `chiusa` — Prog ✔️, niente da fare.
- `epica` — un'epica o un mandato fra i membri non si esegue: è un perimetro a sé, e si orchestra con una regia a parte.
- `assente` — nessun task file: scartala con una riga all'utente.

### Le regole di partenza

Una conversazione nuova parte solo se valgono tutte:

1. **Un passo alla volta dentro una task.** Il ciclo è preflight → run → checkpoint, e la regia non apre una conversazione su una task che ne ha già una in ciclo — sua o esterna (§0h).
2. **Dipendenze soddisfatte**, per ogni passo, preflight compreso: le decisioni di una task poggiano su ciò che la dipendenza ha fatto davvero. Una dipendenza è soddisfatta quando è ✔️, oppure quando la sua voce in `## Dependencies` nomina dei DLV precisi («serve il DLV2 di T21») e quei DLV sono **chiusi a ciclo finito**. Le voci le leggi tu nel task file: `blocked=` conta solo le task, non i DLV.
3. **Un DLV conta come chiuso solo a ciclo finito.** `run-task` spunta e committa ogni DLV appena chiuso, prima del checkpoint e prima delle risposte alle segnalazioni del suo report. Per la regia il DLV diventa una base solo dopo il checkpoint del suo ciclo e le risposte alle segnalazioni. Una task con segnalazioni in sospeso non fa da base a nessuna: si fermano le sue dipendenti, i rami indipendenti continuano.
4. **Parallelo solo senza conflitti.** Due task vanno insieme solo se nessuna riga `CONFLICT` le accoppia — né una dipendenza fra loro, né un path in comune nei loro `## Materiale` che almeno una delle due scrive — e nessuna riga di `## Collisioni del modello` nello stato (§0e): una collisione che nessun campo dichiara ferma il parallelo come una `CONFLICT`. Vale per ogni passo, preflight compreso, e vale anche contro una sessione esterna in ciclo.
5. **Un checkpoint alla volta in tutto il mandato.** Il checkpoint riscrive il task file e `tasks.md`, e due `checkpoint-task` insieme fanno race su `tasks.md` e su git. Prima di chiederne uno guarda `## Checkpoint in corso` nello stato: se è occupato, il ciclo aspetta in coda, e lo dici in una riga.

Fra i membri pronti, parte prima quello che sblocca più membri: conta le righe `DEPS` che lo nominano.

### Il perimetro del run

Un ciclo di lavoro è una sola chiamata `run`. Prima del lancio guarda le voci `## Dependencies` degli altri membri: se una nomina un DLV preciso di questa task, il primo ciclo fa **solo quei DLV** (perimetro `2`, `1,3`), e il resto va in un ciclo successivo, in un'altra conversazione. Le dipendenze vivono spesso al livello del singolo DLV, e un run su tutti i DLV terrebbe ferma la dipendente fino alla fine. Senza DLV nominati, il perimetro è tutti i DLV aperti: `run` senza perimetro.

### Il riporto

Il monitor segue tutte le sessioni vive del progetto, non solo quelle del perimetro. Il **mandato** della regia è il perimetro e i suoi membri dell'ultima lettura (§I membri, a ogni quadro), e l'etichetta in testa a un evento dice a quale task appartiene. Prima di riportare, guarda l'etichetta:

- **Task del mandato** → l'evento si riporta, come nella tabella sotto.
- **Task fuori dal mandato** — una sessione legata a un'altra task, il task file di un'altra task, la sua cella Prog in `tasks.md` → la regia ignora l'evento del tutto: nessuna riga in chat, nessuna proposta (§3), nessun messaggio, nessuna chiusura, nessuna scalata (§4), niente nello stato. Vale anche per gli eventi che dentro il mandato chiedono una mossa: una domanda, un permesso in attesa, `🧊 ferma da N min`. Quella sessione risponde al suo utente, non al mandato: una proposta o un messaggio della regia sarebbero un'azione che l'utente non le ha chiesto.
- **Sessione senza task** — etichetta `?` più l'inizio del sessionId → fuori dal mandato, finché un evento non la lega a una task del mandato.
- **Cambio di legame** — `🏷 legata a`, `🔀 staccata da`, `🔀 riassegnata` → conta se la task vecchia o la nuova è del mandato: una riga, e da lì la sessione è dentro o fuori secondo la nuova. Una conversazione della regia in ciclo che esce dal mandato ha il ciclo interrotto: è un'anomalia (§4).
- **Eventi `git`** → non portano un'etichetta di task, la riga del commit di norma sì (`run(T23): …`, `checkpoint(T23): …`): un commit che nomina solo task fuori dal mandato si ignora. Unica eccezione, il commit di creazione di una task, `task(T<n>): create …`: rifai il quadro prima di ignorarlo, perché è così che si presenta una figlia nuova dell'epica — il monitor non riporta un task file appena nato, e la sua etichetta è fuori dal mandato finché il lettore non la conta. Se il quadro non la porta fra i membri, l'evento resta ignorato.
- **Eventi `monitor`** → si guardano sempre: parlano del monitor, non di una task.

A ogni evento del mandato scrivi all'utente cosa vuol dire per il mandato:

| Evento | Riporto |
|---|---|
| ciclo chiuso che sblocca un'altra task | cosa si sblocca e cosa lanci adesso |
| sessione ferma su domande o segnalazioni | chi aspetta, per cosa, e la proposta (§3) |
| commit, push, fase doc di un checkpoint | una riga: cosa registra, «per il parallelo non cambia niente» |
| sessione nuova | quale task segue; se la task ha già una conversazione in ciclo, l'avviso di non farle lavorare insieme |
| risposta dell'utente in una tab che rischia un danno | cosa sparisce e cosa resta, per esteso |

- Ogni id di task porta la sua maniglia, sempre: `T32 (campione Naviga su dev)`.
- Un evento minore prende una riga; non riempire il silenzio.
- L'evento è un fatto, la deduzione si dice come tale («molto probabilmente è il DLV3»).
- Quando la notifica non basta, apri il transcript prima di scrivere: `"PY" -B -I "R/sessions.py" tail <prefisso del sessionId> --chars 6000`.
- Il monitor etichetta una sessione con la sua task: due conversazioni sulla stessa task portano la stessa etichetta. Quale delle due ha parlato lo dice `sessions.py list`, con stato ed età di ognuna.

### I fatti del perimetro

Un report o un messaggio di una sessione può portare un fatto che riguarda il perimetro intero o un altro membro, non il lavoro interno della task che lo scrive. La definizione è quella di `checkpoint-mandate` (`${CLAUDE_PLUGIN_ROOT}/skills/checkpoint-mandate/SKILL.md` §2, «Un fatto del perimetro»):

- un **blocco** — il membro non può proseguire finché una task, dentro o fuori dal perimetro, non chiude;
- una **collegata** — una task fuori dal perimetro da cui i membri dipendono, o che dipende da loro;
- una **decisione aperta** che tocca più membri, o da prendere prima di un passo del perimetro; e la decisione presa che ne chiude una già scritta;
- una **regola cambiata** — chi può girare in parallelo, in che ordine;
- un **cambio di un membro** che smentisce ciò che la regia sa di lui: un DLV tolto, una dipendenza nuova, uno scopo spostato.

Non lo è il lavoro interno di un membro — DLV spuntati, misure, file toccati —: vive nel suo task file.

Lo riconosci tu, leggendo: nessuna sessione lo etichetta. Scrivilo subito in `## Fatti del perimetro` dello stato (§0i), una riga per fatto col membro da cui viene e dove l'ha detto, e una riga all'utente nel riporto. Da lì il fatto pesa sulle decisioni della regia: un blocco nuovo ferma il membro bloccato e le sue dipendenti, una regola d'ordine cambiata vale dal quadro successivo, una decisione aperta su un passo del perimetro si scala all'utente (§4). Un fatto superato — il blocco è caduto, la decisione è presa — resta nella sezione con la parola che lo chiude.

I fatti stanno nello stato perché la conversazione si compatta: rileggendo lo stato dopo una compattazione (§0i) la regia li ritrova, anche quelli che nessun membro ha scritto nel suo task file. Dallo stato arrivano al file del perimetro: `checkpoint-mandate` legge `## Fatti del perimetro` dal file su disco, al path che ricava dall'id del perimetro (`regia_state.py facts`), e li porta nella prosa del perimetro, che è committata. Lo spawn non porta note, e il checkpoint si comporta uguale chiunque lo lanci: legge un file a un path noto, non un messaggio della regia. Per questo un fatto si scrive per esteso, col membro e la fonte: chi lo porta nella prosa non ha questa conversazione. Il recap allo stop li elenca (§5), e il giro dopo sullo stesso perimetro li eredita (§0f).

## 2. Lanciare e scrivere alle conversazioni

Una conversazione fa **un solo passo**, poi si chiude: il contesto di una sessione riusata per più passi arriva al tetto, e la qualità cala a ogni passo.

- **preflight** → una conversazione headless, kind `preflight`.
- **ciclo di lavoro** → una conversazione headless, kind `run` e il perimetro di §1. Nella **stessa** conversazione, dopo il run, le risposte alle segnalazioni e poi il checkpoint, ognuno un turno nuovo (§Scrivere): in una sessione aperta dal deck `checkpoint-task` ricava i DLV fatti e i file da committare dal contesto della conversazione, e una conversazione nuova non lo avrebbe.
- **checkpoint del perimetro** → una conversazione headless, kind `checkpoint`, sull'id del perimetro, a fine giro (§Il checkpoint del perimetro).

Finito il passo la regia non scrive più a quella conversazione, e la chiude (§Chiudere).

### Headless, e la tab solo su richiesta

Ogni passo che la regia decide parte **headless**: un processo `claude -p` staccato, senza tab, che esegue un turno e finisce da solo. Una regia lavora in momenti che l'utente non sceglie: una tab aperta da lei prende la tastiera dell'utente, e sul deck Linux lo spawn in una tab viene rifiutato ogni volta che la finestra in focus non è del progetto. Un turno headless non apre tab, non sposta il focus e non cambia desktop. La conversazione compare nel deck sotto la sua task, e l'utente la apre in una tab con ⏎ quando vuole guardarla.

Una **tab** nasce solo quando l'utente la chiede per **quel** passo, nella chat della regia: «apri il run di T23 in una tab». Si apre con `spawn-task` (§Aprire una tab), e la richiesta vale per quel passo soltanto: nessuna preferenza che dura, e nessun criterio con cui la regia sceglie la tab da sé.

### Aprire

Una chiamata Bash per conversazione:

```bash
loom-deck-headless open <TaskID> preflight --root "<radice del progetto>"
loom-deck-headless open <TaskID> run [perimetro] --root "<radice del progetto>"
loom-deck-headless open <perimetro> checkpoint --root "<radice del progetto>"
```

`open` compone titolo, modello e binding come il tasto del deck, con gli override di progetto, e scrive il binding nel sidecar prima di lanciare il processo: la conversazione compare nel deck sotto la sua task. Toglie da sé l'ambiente di questa conversazione — `LOOM_TASK`, `PTYXIS_PROFILE`, le variabili di sessione di Claude Code —: nessun `env -u` davanti. Non serve il deck acceso.

Con uscita `0` le righe portano `sessionId:` e `titolo:`; scrivi subito la conversazione nello stato, con `Stato: in ciclo`, poi leggi l'esito del turno (§L'esito di un turno headless). Il **nome** della conversazione è la riga `titolo:`, il titolo che il deck le darebbe col tasto. Uscita `1` è un rifiuto, col motivo su stderr — task assente, DLV chiusi o fuori range, run su un mandato, `permissionMode` `manual` —; uscita `2` una riga composta male. Tutte e due sono un'anomalia (§4): non ritentare.

### L'esito di un turno headless

`open` e `reply` (§Scrivere) tornano subito, a turno appena lanciato. L'esito lo dà un comando solo, e lo stato su disco del turno ne è la fonte:

```bash
loom-deck-headless status <sessionId> --root "<radice del progetto>"
```

| Uscita | Classe | Cosa fai |
|---|---|---|
| `3` | `in corso` | il turno lavora: aspetti, nessun messaggio |
| `0` | `turno chiuso` | leggi il **testo finale**, che `status` stampa per intero: è il report del passo, o una domanda (§3) |
| `4` | `permesso negato` | ramo fermo, sotto |
| `1` | `errore` | anomalia (§4): l'errore dell'API o la coda dello stderr, che `status` stampa in `motivo:` |
| `2` | — | sessione ignota o riga sbagliata: anomalia (§4) |

**`turno chiuso` non dice che il passo è finito.** In `claude -p` lo strumento `AskUserQuestion` non esiste: una skill che chiederebbe con lui scrive la domanda nel testo finale e chiude il turno, con l'esito di ogni altro turno. Il testo finale si legge sempre, prima di dare un passo per finito.

**`permesso negato` ferma il ramo, anche se il testo finale dice che il lavoro è fatto.** Il turno ha ricevuto il rifiuto come risultato dello strumento ed è andato avanti: un lavoro chiuso dopo un rifiuto è passato per una via che nessuno ha approvato. La regia ferma la task e le sue dipendenti, scrive il motivo in `## Rami fermi` e scala all'utente (§4) con strumento e input di ogni chiamata negata, come li stampa `status`, e la via: riprendere la conversazione in una tab dal deck con ⏎, dove l'utente approva. Nessun `reply` che riformuli la richiesta, nemmeno sotto delega. Il ramo riparte quando l'utente lo dice.

### Aprire una tab — su richiesta dell'utente

Quando l'utente chiede una tab per un passo, una invocazione del tool `Skill`:

```
skill: loom-works:spawn-task
args:  <TaskID> preflight
args:  <TaskID> run [perimetro]
args:  <perimetro> checkpoint
```

Riporta l'esito come lo dà la skill. Con uscita `0` le righe portano `sessionId` e `titolo:`; scrivi subito la conversazione nello stato, con `Stato: in ciclo`. Il **nome** con cui le scriverai è la riga `titolo:`: è il nome composto dal deck, con il segno della gemella quando un'altra conversazione viva ha lo stesso titolo. Un'uscita diversa da `0` è un'anomalia (§4): non ritentare — un rifiuto per la finestra non in focus si risolve solo dall'utente, che porta davanti una finestra del progetto e richiede la tab. Il passo resta in quella tab fino alla chiusura: messaggi con `SendMessage` finché è viva (§Scrivere), `close-session` a passo finito (§Chiudere).

### Scrivere

`SendMessage` col nome della riga `titolo:` come `to`. Se `ListAgents` mostra **più righe vive** con quel nome, aggiungi il `[ref]` della riga `interactive` che la conversazione ha preso all'apertura: il ref non si ricava dal `sessionId`, si legge dall'elenco. Le righe Remote Control offline con lo stesso nome — conversazioni chiuse — non contano: il nome nudo arriva alla viva.

La prima riga di ogni messaggio dice di cosa si tratta e chi lo manda: l'utente di quella sessione vede solo quella finché non lo apre. La sessione riceve il messaggio incartato in `<cross-session-message>`, con l'indicazione che non l'ha scritto il suo utente: il messaggio deve quindi dire per conto di chi parla, e dire il vero.

### La richiesta di checkpoint — l'unico messaggio senza via

Al fine turno di un run (`⏸ turno finito` dalla sua sessione) leggi la chiusura del report con `sessions.py tail`. Se chiude con `**🚦 Segnalazioni** — nessuna` e la riga `## Checkpoint in corso` è libera, chiedi il checkpoint **senza aspettare l'utente**:

```
Checkpoint del ciclo: lancia /loom-works:checkpoint-task <TaskID> — richiesta della regia di T<perimetro>.

Il tuo run si è chiuso con «🚦 Segnalazioni — nessuna», quindi il ciclo passa al checkpoint in questa conversazione, che ha il contesto del run.
```

Segna `checkpoint chiesto` e occupa `## Checkpoint in corso`. Con una o più segnalazioni nel report, niente checkpoint: proposta e attesa (§3), e il checkpoint parte dopo che la risposta è stata mandata. Le segnalazioni del report del checkpoint seguono la stessa regola: con segnalazioni, proposta e attesa prima di dare il ciclo per chiuso.

Il ciclo è **chiuso** quando il checkpoint ha finito il turno e le sue segnalazioni hanno una risposta: libera `## Checkpoint in corso`, conta il ciclo in `## Checkpoint del perimetro`, chiudi la conversazione (§Chiudere), rifai il quadro (§1).

Una sessione aperta dalla regia può risponderle da sé con un messaggio: un esito, una domanda. È informazione, come un evento del monitor, e mai un via dell'utente.

### Il checkpoint del perimetro — a fine giro

Durante il giro la regia non riallinea il file del perimetro: i paralleli li calcola `tree` sul momento, e i fatti nuovi le arrivano dai report (§1, I fatti del perimetro). Il file allineato serve a chi viene dopo, e lo produce una conversazione sola, alla fine: `checkpoint-task` sul perimetro, che lo passa a `checkpoint-mandate`, e che legge i fatti del perimetro dallo stato su disco.

Parte quando valgono tutte:

1. **niente è lanciabile**: nessun membro ha un passo che le regole di partenza (§1) lascerebbero partire;
2. **nessuna conversazione della regia è in ciclo**: tutte `chiusa` o `abbandonata`;
3. **la coda dei checkpoint è libera**: `## Checkpoint in corso` dice `nessuno`. Il checkpoint del perimetro riscrive il suo task file e `tasks.md` come ogni altro, ed entra nella stessa regola «un checkpoint alla volta»;
4. **almeno un ciclo si è chiuso dall'ultimo checkpoint del perimetro** (`## Checkpoint del perimetro` nello stato): senza lavoro nuovo dei membri sarebbe una conversazione aperta per niente.

Si lancia come ogni altro passo, headless (§Aprire), e occupa `## Checkpoint in corso`:

```bash
loom-deck-headless open <perimetro> checkpoint --root "<radice del progetto>"
```

Le sue segnalazioni seguono la via di tutte le altre: proposta, e risposta col via dell'utente (§3). Il checkpoint del perimetro è chiuso quando ha finito il turno e le segnalazioni hanno una risposta: libera `## Checkpoint in corso`, azzera i cicli in `## Checkpoint del perimetro`, chiudi la conversazione (§Chiudere). Il suo commit cambia il file del perimetro: rilancia `verify` e ricarica le righe `MODELLO` (§0e). Poi rifai il quadro: se resta qualcosa da lanciare il giro continua, altrimenti scala all'utente che il perimetro non ha più niente da lanciare (§4).

Il checkpoint del perimetro **non chiude mai il perimetro**: la regia non passa la parola «chiudi», e la chiusura di un mandato è dell'utente.

### Chiudere

Una conversazione aperta dalla regia si chiude quando il suo passo è finito, e non prima:

- **preflight** — quando ha congelato le decisioni: il turno finito dopo le risposte mandate, senza domande aperte;
- **ciclo di lavoro** — quando il ciclo è chiuso, cioè dopo il checkpoint e le risposte alle sue segnalazioni (§La richiesta di checkpoint);
- **checkpoint del perimetro** — quando ha finito il turno e le sue segnalazioni hanno una risposta.

Una invocazione del tool `Skill` per conversazione, col `sessionId` che `spawn-task` ha restituito all'apertura e che sta nello stato:

```
skill: loom-works:close-session
args:  <sessionId>
```

- **Uscita `0`** → segna la conversazione `chiusa` nello stato. L'evento `✖ sessione chiusa` che il monitor riporta subito dopo è l'effetto della chiusura, non un'anomalia: una riga nel riporto, o nessuna.
- **Uscita diversa da `0`** → la conversazione resta aperta: segna `abbandonata` nello stato col motivo che la skill riporta (al lavoro, non nata dall'endpoint, deck spento, deck senza chiusura), una riga nel riporto, e **nessun ritento**: un secondo tentativo su un rifiuto ripete il rifiuto, e su un processo che non è finito in tempo può colpire una conversazione ripartita nel frattempo. Non è un'anomalia (§4): il mandato prosegue, e l'utente la chiude quando vuole.

Una sessione esterna (§0h) non si chiude mai: non l'ha aperta la regia, e il deck la rifiuterebbe comunque se non è nata da una richiesta di spawn.

### Le sessioni esterne

A una sessione che la regia non ha aperto (§0h) non parte nessun messaggio di iniziativa della regia, nemmeno il checkpoint: solo le risposte che l'utente ha approvato (§3). Quando il suo ciclo si chiude, la task torna libera per la regia, e il ciclo conta in `## Checkpoint del perimetro` come uno della regia.

## 3. Proposte di risposta

Una sessione ferma su una domanda aspetta l'utente, non la regia. La regia accorcia l'attesa: legge cosa chiede, prepara la risposta col perché di ogni scelta, e la manda **solo col via dell'utente** — o da sé, se l'utente le ha delegato le risposte (§La delega dell'utente).

**Quando.** Un evento `⏸ turno finito` di una sessione del mandato (§1, Il riporto) che chiude su domande — il blocco finale di un preflight (`D{N}`), la sezione `🚦 Segnalazioni` di un report con almeno una `S{N}` — oppure un evento `❓ domanda all'utente` o `⏳ aspetta un permesso`. Leggi la sessione per intero prima di proporre: `"PY" -B -I "R/sessions.py" tail <prefisso> --chars 6000`.

**Cosa proponi.**

- **Preflight** — una risposta per ogni `D{N}`: la strada (`D2.B`, o una nuova in prosa) e il perché, ricavato dal quadro del mandato e dalle decisioni già congelate nelle altre task. Sulle proposte `P{N}` del preflight **taci**: il silenzio le accetta, e smentirle è dell'utente. Unica eccezione, una `P{N}` che contraddice una decisione già congelata in un'altra task del mandato: la nomini, con le due decisioni a confronto.
- **Segnalazioni** — per ogni `S{N}` un'uscita, `subito` · `task` · `scarto` · `ignora`, col perché; per `scarto` anche il motivo che finirà nel registro ADR.
- **`AskUserQuestion` e permessi** — la proposta c'è, ma la risposta si dà **nella tab**: un messaggio di un'altra sessione non risponde a un `AskUserQuestion` aperto e non approva un permesso, per costruzione di Claude Code. Di' all'utente quale tab aprire e cosa scegliere.

**Una proposta per sessione ferma**, scritta in chat come blocco pronto da mandare: nome della conversazione, cosa chiede, il testo del messaggio, il perché di ogni scelta. Con più sessioni ferme, **in testa quella che sblocca più task**. Una risposta che rischia un danno — un dato cancellato, un trigger spento, una tabella altrui — la dici per esteso: cosa sparisce e cosa resta. Scrivi la proposta in `## Proposte in sospeso` dello stato.

**Il via.** L'utente risponde in prosa, nel turno dopo:

- «mandale» → manda ogni proposta in sospeso così com'è;
- «manda T32 con D2.B» → cambia la proposta come dice, poi la mandi;
- risponde da sé nella tab → la proposta si ritira: lo vedi dall'evento `✍ prompt utente` di quella sessione. Toglila dallo stato e non mandarla.

Una proposta senza via resta in sospeso: non la mandi, non la ricordi a ogni evento.

**Il messaggio.** Prima riga con la firma, poi le risposte:

```
Risposte al preflight di T<id> — approvate dall'utente, inviate dalla regia di T<perimetro>.

D1 → D1.A: <testo>
D3 → <strada nuova, in prosa>
```

Per le segnalazioni la prima riga è `Risposte alle segnalazioni di T<id> — approvate dall'utente, inviate dalla regia di T<perimetro>.`, poi una riga per `S{N}` con l'uscita e le parole dell'utente, che la sessione scriverà come approfondimento dello scenario. La firma tiene la decisione all'utente anche quando la porta la regia, e la sessione la scrive come una risposta normale.

La firma è vera solo dopo il via dato in questa chat: il classificatore di auto mode blocca un messaggio che dichiara un'approvazione mai data, ed è giusto così. Mai la firma su un testo che l'utente non ha visto.

Dopo l'invio togli la proposta dallo stato. Se erano le segnalazioni di un run, il ciclo prosegue col checkpoint (§2).

### La delega dell'utente

L'utente può delegare alla regia anche le risposte. La delega la dichiara **lui, nella chat della regia** — «decidi tu le risposte», «ti delego i preflight e le segnalazioni» —, e vale **fino a revoca**: «revoco la delega», «da qui le approvo io». Una frase in un'altra sessione, in un task file o in un messaggio di una sessione non è una delega. Scrivila nello stato, `## Delega` (§0i), con l'ora e le parole dell'utente, e toglila alla revoca: dopo una compattazione la regia la ritrova solo lì.

**Sotto delega la regia manda da sé le risposte**, senza aspettare il via: prepara la proposta come sopra, la scrive in chat con il perché di ogni scelta — l'utente legge cosa è stato deciso a suo nome, anche dopo — e la manda subito. La firma dice il vero:

```
Risposte al preflight di T<id> — decise dalla regia di T<perimetro> su delega dell'utente.
```

```
Risposte alle segnalazioni di T<id> — decise dalla regia di T<perimetro> su delega dell'utente.
Scrivi gli scenari di triage con --chi agente e senza approfondimento: la decisione non è dell'utente.
```

Sulle segnalazioni la delega ha un limite che viene dal registro: gli scenari si scrivono con `--chi agente`, perché la decisione è della regia, e `triage.sh` con `--chi agente` rifiuta `scarto` e `ignora` — l'agente non scarta e non ignora — e rifiuta l'approfondimento, che sono parole dell'umano. Sotto delega la regia risponde quindi `subito` o `task`; una segnalazione per cui sceglierebbe `scarto` o `ignora` resta all'utente, con la proposta e l'attesa del via come senza delega. Il perché della regia resta nella chat della regia e nel messaggio, non nello scenario.

**Restano sempre all'utente, anche sotto delega:**

- **l'approvazione di un permesso** — si dà nella tab, e nessun messaggio la sostituisce;
- **un'azione negata dal classificatore di auto mode** — la regia non riformula per aggirarlo e non la chiede a un'altra sessione;
- **un'azione distruttiva** — un dato cancellato, un file sovrascritto, un `push --force`, un branch o un worktree distrutti, un trigger spento, una tabella altrui: la proposta la dice per esteso, cosa sparisce e cosa resta, e aspetta il via.

Su questi casi si scala come sempre (§4). Una risposta mandata sotto delega si toglie dallo stato come una approvata.

## 4. Scalare all'utente

Una regia che aspetta l'utente chiude il turno, e compass la mostra `done`, non `ask`: il badge non avvisa nessuno. Quando la regia ha bisogno dell'utente lo avvisa da sé, su **tre canali insieme**:

1. **una riga in chat** in testa al riporto: chi aspetta, per cosa, con la maniglia di ogni task;
2. **`PushNotification`**: una riga sotto i 200 caratteri, in testa ciò su cui agire («T32 (campione Naviga) aspetta il via su 3 risposte di preflight»);
3. **`say.sh`**:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "regia $(say_id T<perimetro>) <argomento in 3-7 parole>"
   ```

**Si scala per**: proposte nuove in attesa di via (§3); una risposta da dare nella tab (`AskUserQuestion`, permessi); un permesso negato in un turno headless (§2, L'esito di un turno headless); una task con preflight decaduto o col ciclo interrotto prima del checkpoint (§1); un'anomalia; un perimetro che non ha più niente da lanciare, dopo il suo checkpoint o quando non ce n'è bisogno (§2, Il checkpoint del perimetro).

**Non si scala** per gli eventi di routine — commit, push, un DLV spuntato, un checkpoint andato liscio: bastano le righe del riporto. Una notifica che non serviva si somma alle altre e insegna a ignorarle.

### Le anomalie: ramo fermo, nessun ritento

- `loom-deck-headless open` o `spawn-task` esce con un codice diverso da `0`;
- un turno headless finisce in `errore` (§2, L'esito di un turno headless); un `permesso negato` ferma il ramo allo stesso modo, con strumento e input delle chiamate negate nella scalata;
- una tab in ciclo si chiude a metà (`✖ sessione chiusa` prima del checkpoint);
- un run chiude il turno senza aver chiuso nessun DLV del suo perimetro;
- un evento `🧊 ferma da N min` su una conversazione in ciclo.

La regia ferma la task e le sue dipendenti, scrive il motivo in `## Rami fermi`, scala all'utente e **non rilancia**: un secondo tentativo su una causa non capita ripete il guasto, e può ripetere anche quello che il primo ha già scritto. I rami indipendenti continuano. Il ramo riparte quando l'utente lo dice.

## 5. Stop

La regia si ferma quando l'utente lo chiede. Prima di fermarti, se una richiesta di checkpoint è in corso, dillo: il checkpoint finisce da sé, ma nessuno lo seguirà più. Allo stop chiesto dall'utente il checkpoint del perimetro **non parte**: la regia non seguirebbe una conversazione dopo aver fermato il monitor.

1. **`TaskStop` sul monitor.** Un evento che arriva dopo è in ritardo: ignoralo.
2. **La riga di testa dello stato** diventa `Stato: ferma · SID`, e il resto del file resta com'è. Una regia lanciata dopo sullo stesso perimetro trova un giro chiuso, e ne eredita i soli fatti (§0f).
3. **Le cifre finali**, accanto a quelle salvate all'avvio del giro:

   ```bash
   "PY" -B -I "R/mandate.py" recap --before "<BEFORE_FILE>"
   ```

   Una riga `RECAP|<id>|prog=prima→dopo|dlv=a/b→c/d|ac=a/b→c/d|title=…` per il perimetro e per ogni membro letto all'avvio. Un membro entrato durante il giro non ha una riga: le sue cifre di oggi stanno nell'ultimo quadro. Questo `recap` è anche il segno con cui le altre regie sanno che questa è ferma (§0f): una regia fermata senza lanciarlo resta viva per loro finché la sua conversazione è aperta.
4. **Il recap**, in chat:
   - la tabella delle task con le cifre prima → dopo: Prog, DLV, AC, ogni id con la sua maniglia; i membri entrati o usciti durante il giro, con una parola che lo dice;
   - i progressi in lista, una riga per ciclo chiuso;
   - le **conversazioni rimaste aperte**, dalla tabella dello stato — quelle `abbandonata`, col motivo, e quelle ancora in ciclo: task, passo, nome, `sessionId`. L'utente le chiude quando vuole. Le `chiusa` non si elencano;
   - quello che resta in sospeso: proposte senza via, rami fermi col loro motivo, task che aspettano una dipendenza;
   - se `## Checkpoint del perimetro` conta cicli chiusi dall'ultimo, la riga `il file del perimetro non è allineato ai membri: /loom-works:checkpoint-task <perimetro>`;
   - i **fatti del perimetro** dello stato, aperti e superati, col membro da cui vengono: sono quelli che chi legge il file del perimetro dopo deve trovare, e alcuni nessun membro li ha scritti nel suo task file. Il prossimo `checkpoint-task` sul perimetro li porta nel file, chiunque lo lanci.

Lo stato non si cancella, né allo stop né dopo: i fatti servono al giro dopo sullo stesso perimetro (§0f) e a un `checkpoint-mandate` lanciato a mano. I tre file restano in `.claude/loom/regia/`, fuori da git.
