---
name: drive-task
description: Fa avanzare una task di un passo, guidato dalla conversazione che lo chiede — lancia un preflight headless, senza tab, col contesto che la conversazione ha costruito con l'utente, aspetta la fine del turno, porta in chat le domande del preflight e gli manda le risposte, col via dell'utente o da sé sotto una delega che l'utente dà («con delega»). Un passo su una task, non un perimetro. Tiene chi guida il passo in `.claude/loom/drive/` del progetto, ignorata da git, e lo riprende al rilancio. Non scrive mai nei task file né in un file tracciato. Usa quando l'utente dice «lancia il preflight di T66 e rispondi tu», «drive-task T66 preflight», «fai il preflight di T220 con delega».
argument-hint: "<TaskID> preflight [con delega]"
allowed-tools: Bash(*), Read, Write, PushNotification
---

Argomenti:
~~~human
$ARGUMENTS
~~~

## Il ruolo

Una conversazione che ha ragionato con l'utente su un tema ha in mano un contesto che una task può usare: le decisioni già prese, le parole dell'utente, i rimandi ai file giusti. `drive-task` usa quel contesto per far avanzare la task di **un passo**: lo lancia **headless** — un processo `claude -p` senza tab, con `loom-deck-headless` —, aspetta che il turno finisca e porta qui le domande del passo, invece che in una tab che nessuno guarda. Le risposte partono da qui.

- **Un passo, una task.** In questa versione il passo è uno solo: `preflight`. Un perimetro di più task, un'epica o un mandato, si porta avanti con `orchestrate-mandate`.
- **Non risponde da sé**, salvo delega: prepara la risposta e la manda col via dell'utente (§5). Con la delega manda da sé le risposte che le parole dell'utente coprono, e scala le altre.
- **Non scrive mai nei task file né in un file tracciato.** Il preflight scrive le decisioni nel task file e committa; questa conversazione scrive solo il proprio stato, in `.claude/loom/drive/T<id>.md`, ignorata da git (§Lo stato su disco).

Le regole su firma, delega e azioni che restano all'utente sono quelle della regia (`${CLAUDE_PLUGIN_ROOT}/skills/orchestrate-mandate/SKILL.md` §3), applicate a un passo solo: niente monitor, niente perimetro, niente checkpoint.

## 0. Gli argomenti

- **`<TaskID>`** — `T` più il numero.
- **`<passo>`** — `preflight`. Un altro passo (`run`, `checkpoint`, `recap`) → dillo e fermati: questa versione porta solo il preflight, e per gli altri c'è `run-task` nella conversazione stessa, o `spawn-task` in una tab.
- **`con delega`** — le due parole accendono la delega per questo passo (§5, La delega). Le **parole della delega** sono allora la riga di invocazione intera: `/loom-works:drive-task $ARGUMENTS`.
- **Il resto** — parole dell'utente sul passo: entrano nel contesto (§2) come sue, alla lettera.

Senza `<TaskID>` → riporta cosa manca ed esci, senza lanciare niente. Senza `<passo>` la skill vale solo per riprendere un passo già aperto (§La ripresa): se il controllo dà un passo nuovo (`ROUND=nuovo`), riporta che manca il passo ed esci.

## 1. I controlli d'ingresso

L'interprete è il primo fra `python3` e `python` che risponde con Python 3 (su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde):

```bash
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

Nessuno dei due → dillo e fermati. Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (`PY`). Poi, dalla root del progetto:

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/regia/drive_state.py" check <TaskID>
```

Il `sessionId` di questa conversazione lo legge lo script da `CLAUDE_CODE_SESSION_ID`. Le righe:

| Riga | Cosa dice |
|---|---|
| `PROJECT_ROOT=` · `OWN_SESSION=` | la root, da passare a ogni `loom-deck-headless` con `--root`, e il tuo `sessionId` (lo chiamiamo `SID`) |
| `TASK\|<id>\|prog=…\|size=…\|preflight=…\|title=…` | la task: Prog, Size, se ha già un preflight (`ok`, `decaduta`, `none`) |
| `DEP\|<id>\|<prog>\|<fonte>` · `DEPS_OPEN=<n>` | le dipendenze ancora aperte, da `## Dependencies` e dal grafo |
| `HEADLESS=` · `HEADLESS_CONTEXT=` · `PROJECT_MODE=` | il comando del deck, se conosce `--context`, il permission mode del progetto |
| `STATE_FILE=` · `CREATED_ON=` · `IGNORED=` | lo stato su disco del passo e la sua identità, e se git lo ignora |
| `STATE=` · `STATE_HOLDER=` · `STEP_SESSION=` · `STEP_KIND=` · `STEP_LIVE=` | il verdetto sullo stato (§Lo stato su disco) e, in una ripresa, il passo aperto |
| `VIVA\|<sessionId>\|tab\|headless\|<stato>` | un'altra conversazione viva sulla task |
| `REGIA_PASSO\|<sessionId>\|<perimetro>\|<stato>` | un turno headless su questa task aperto da una regia che non è ferma |
| `REGIA\|<sessionId>\|<perimetro>\|<etichetta>` | un'altra regia viva sul progetto, da confrontare coi membri (sotto) |
| `ROUND=nuovo\|ripresa` · `STOP\|<motivo>` · `CHECK=ok\|stop` | il giro, una riga per ogni ragione di fermarsi, il verdetto |

**`CHECK=stop`** (exit `2`) → **fermati senza lanciare niente**, e di' all'utente ogni riga `STOP` col suo rimedio:

- `loom-deck-headless` assente, o senza `--context` → `npm install -g @lamemind/loom-deck@latest`, poi rilancia la skill;
- `permissionMode` del progetto diverso da `auto` → il turno headless non ha nessuno che approva, e il preflight si vedrebbe negare la scrittura del task file e il commit: `"permissionMode": "auto"` in `.claude/loom-works.json`;
- git non ignora `.claude/loom/` → la riga di `IGNORE_RULE` nel `.gitignore` del progetto;
- passo tenuto da un'altra conversazione viva (`STATE=vivo`) → nominala (`STATE_HOLDER`): il passo lo guida lei. Si libera chiedendole, nella sua chat, di lasciare il passo (§6), o chiudendola;
- stato illeggibile → il path: lo corregge o lo toglie l'utente;
- conversazione viva sulla task (`VIVA`) → nominala: due conversazioni sulla stessa task lavorano sugli stessi file. Si rilancia quando è chiusa;
- passo aperto in una tab (`STEP_LIVE=tab`) → l'utente ha ripreso il passo dal deck: si risponde in quella tab, e la skill si rilancia quando la tab è chiusa;
- turno aperto da una regia (`REGIA_PASSO`) → nomina la regia e la conversazione: la task è in mano a quella regia finché non è ferma. Si sblocca fermando la regia, nella sua chat. Una regia morta e mai fermata tiene la task finché non viene rilanciata e fermata, o finché lo stato headless del suo turno (`.claude/loom/headless/<sessionId>.json`) non viene tolto: lo dici con queste parole.

Exit `1` → il motivo da stderr (task file mancante, registro delle sessioni illeggibile), e fermati.

**Le regie vive.** Con `CHECK=ok`, per ogni riga `REGIA` leggi i membri del suo perimetro col lettore unico:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <perimetro> --members
```

Se la task è fra le righe `TASK_MEMBER=` o è il perimetro stesso, **fermati**: la regia `<sessionId corto>` di `<perimetro>` la porterebbe avanti accanto a te. Si sblocca fermando quella regia.

**Avvisi, non rifiuti.** Il passo lo chiede l'utente, per nome: quello che segue si dice in una riga e si lancia lo stesso.

- `DEPS_OPEN` maggiore di zero → le dipendenze aperte, ognuna con la Prog;
- `preflight=ok` → la task ha già un preflight, e questo ne aggiunge un altro;
- `preflight=decaduta` → l'ultimo preflight si è fermato su una premessa smentita: questo la riesamina.

Una task ✔️ è chiusa: dillo e fermati.

## 2. Il contesto del passo

Il passo nasce in una conversazione nuova, che di questa non sa niente. Il contesto gli arriva con `--context`: un testo in coda al prompt dell'azione, che il preflight legge fra le sue **Note utente**. Le Note utente valgono come istruzione, e da qui discende cosa ci va e come.

Il testo porta tre cose, e nient'altro:

1. **le decisioni già prese con l'utente**, con le sue parole, citate alla lettera;
2. **i rimandi a ciò che sta su disco**: task file, sezione, path, decisioni congelate altrove («le decisioni da cui nasce T66 stanno in T57 §Decisions D18–D43»);
3. **chi risponde e come**: «Le domande le legge la conversazione `<SID corto>`, che ha lanciato il passo: scrivile in chat a fine turno, nel blocco finale del preflight. Risponde col via dell'utente» — oppure «risponde da sé su delega dell'utente, e scala all'utente ciò che la delega non copre».

**Una conclusione di questa conversazione che l'utente non ha detto entra marcata**: «conclusione di questa conversazione, non dell'utente». Senza la marca il preflight la prenderebbe per una decisione dell'utente, non porrebbe la domanda e congelerebbe una scelta che nessuno ha preso. Nessun riassunto della conversazione: il resto lo trova il preflight nei file.

**Mostra il testo in chat prima di `open`**, intero: è ciò che il passo riceverà come istruzione, e l'utente lo legge mentre il turno parte.

## 3. Aprire il passo

```bash
loom-deck-headless open <TaskID> preflight --context - --root "<PROJECT_ROOT>" <<'CONTESTO'
<il testo del §2>
CONTESTO
```

L'heredoc fra apici tiene backtick, apici e `$` come testo. `open` compone titolo, modello e binding come il tasto del deck, scrive il binding nel sidecar prima del processo — la conversazione compare nel deck sotto la sua task — e toglie da sé l'ambiente di questa conversazione.

- **Uscita `0`** → le righe portano `sessionId:` e `titolo:`. Scrivi subito lo stato (§Lo stato su disco), con la testa `Stato: aperto · SID`, poi aspetta la fine del turno (§4).
- **Uscita `1`** → rifiuto, col motivo su stderr: riportalo e fermati, senza ritentare.
- **Uscita `2`** → riga composta male: riportala e fermati.

## 4. Aspettare la fine del turno

`open` e `reply` tornano subito, a turno appena lanciato. Dopo ognuno lancia un comando Bash **in background** (`run_in_background: true`, timeout `3700000` ms), che esce quando il turno finisce, o dopo un'ora:

```bash
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do loom-deck-headless status <sessionId> --wait 300 --root "<PROJECT_ROOT>" >/dev/null; [ "$?" -ne 3 ] && break; done; loom-deck-headless status <sessionId> --root "<PROJECT_ROOT>"
```

La fine del comando risveglia questa conversazione: nessun monitor, nessun polling. Intanto chiudi il turno con una riga all'utente — il passo è partito, il nome della conversazione, e che riprendi quando il turno finisce. L'utente può continuare a scrivere qui: rispondigli, e non lanciare un secondo comando d'attesa sullo stesso turno.

Un'ora di turno ancora `in corso` (uscita `3`) → una riga all'utente, e rilancia lo stesso comando.

## 5. L'esito, le domande, le risposte

L'uscita del comando d'attesa è quella di `status`, e il suo stdout porta l'esito:

| Uscita | Classe | Cosa fai |
|---|---|---|
| `0` | `turno chiuso` | leggi il **testo finale**: le domande del preflight, o la sua chiusura |
| `3` | `in corso` | un'ora passata: una riga, e riarmi l'attesa (§4) |
| `4` | `permesso negato` | il passo si ferma, sotto |
| `1` | `errore` | il motivo (`motivo:`): riportalo, nessun ritento |
| `2` | — | sessione ignota o riga sbagliata: riportala, nessun ritento |

**`turno chiuso` non dice che il passo è finito.** In `claude -p` lo strumento `AskUserQuestion` non esiste: il preflight scrive domande e proposte nel testo finale e chiude il turno, con l'esito di ogni altro turno. Il testo finale si legge sempre.

**`permesso negato` ferma il passo, anche se il testo finale dice che il lavoro è fatto**: un lavoro chiuso dopo un rifiuto è passato per una via che nessuno ha approvato. Di' all'utente strumento e input di ogni chiamata negata, come li stampa `status`, e la via: riprendere la conversazione in una tab dal deck con ⏎, dove l'utente approva. Nessun `reply` che riformuli la richiesta, nemmeno sotto delega.

### Le domande in chat

A turno chiuso con domande, scrivi in chat:

- **le domande che scalano**, intere: la domanda, le strade che il preflight vede, e il pezzo di recap che serve a deciderle;
- **le domande coperte**, con la risposta che proponi — o che hai mandato, sotto delega — e il perché;
- **le proposte `P{N}` del preflight**, tutte, una riga l'una con la scelta.

Il resto del recap non si ricopia: sta nella conversazione del passo, che l'utente apre dal deck con ⏎. Il silenzio accetta una proposta solo se chi può smentirla l'ha vista, e l'output di `status` lo legge questa conversazione, non l'utente: per questo le proposte arrivano in chat tutte.

Scrivi le domande in sospeso nello stato (`## Domande in sospeso`), e aggiorna la riga `turno:` del passo.

## 6. La fine del passo, e lasciarlo

Il preflight è finito quando il testo finale dice che le decisioni sono congelate e committate, e non chiede altro. Rileggi il blocco nuovo di `## Decisions` nel task file e il suo commit (`git log -1 --format='%h %s' -- <task file>`), e di' all'utente in una riga: il commit, quante decisioni e quante proposte. Poi la testa dello stato diventa `Stato: chiuso · SID`. La conversazione del passo resta nel deck sotto la sua task: è headless, non c'è niente da chiudere.

**Lasciare il passo.** L'utente può chiedere di lasciarlo — «lascia il passo», «lo prendo da un'altra conversazione»: la testa diventa `Stato: lasciato · SID`, e la conversazione che rilancia la skill sulla stessa task lo riprende (§La ripresa). Da qui non mandi più niente al passo.

## Lo stato su disco

Un file per task: `STATE_FILE` di `drive_state.py`, `.claude/loom/drive/T<id>.md`. Sta sotto `.claude/loom/`, che git ignora, perché sopravviva a una compattazione e a una chiusura senza finire in un commit. Lo scrivi col tool `Write`, intero a ogni cambio, e lo **rileggi dopo ogni compattazione del contesto**, prima di decidere il passo successivo: delega e domande in sospeso stanno lì.

```markdown
Stato: aperto · <SID>
Task: T<id> · Created on <CREATED_ON>

# drive-task T<id> — stato

## Passo
- passo: preflight
- sessionId: <sessionId del passo>
- titolo: <titolo>
- turno: <n> · in corso | domande in sospeso | risposte mandate | chiuso
- aperto alle: <ora>

## Delega
- no | sì dal <ora>: «<le parole della delega>»

## Domande in sospeso
- nessuna | D<n> · <di cosa> · all'utente dal <ora>

## Risposte mandate
- nessuna | turno <n> · D<n>, D<n> · approvate dall'utente | su delega
```

Le due righe di testa le legge `drive_state.py check` a ogni lancio. `Stato:` dice chi tiene il passo — `aperto`, `lasciato`, `chiuso` più il `sessionId` di chi lo guida —, `Task:` l'identità: l'id di una task purgata può tornare a una task nuova, e uno stato con un altro `Created on` vale come assente. Il titolare serve perché una headless ferma su domande non ha un processo, e fra due turni `reply` non rifiuta nessuno: senza, una seconda conversazione risponderebbe allo stesso preflight mentre la prima aspetta ancora.

### La ripresa

| `STATE` | Cosa trovi | Cosa fai |
|---|---|---|
| `assente` · `altro` · `chiuso` | nessun passo aperto | passo nuovo (§2), lo stato si sovrascrive |
| `mio` | il passo che questa conversazione tiene | ripresa di tutto, delega compresa |
| `lasciato` | un passo che il titolare ha lasciato | ripresa senza la delega: diventi titolare |
| `morto` | un passo aperto da una conversazione non più viva | ripresa senza la delega: diventi titolare |
| `vivo` · `illeggibile` | — | stop (§1) |

In una ripresa leggi lo stato con `Read`, riscrivi la testa `Stato: aperto · SID`, e su `lasciato` e `morto` la delega torna `no`: vale solo nella chat dove l'utente l'ha data, e la ridà qui se la vuole. Dillo in una riga, col titolare di prima. Poi rileggi il turno del passo (`STEP_SESSION`) una volta, senza `--wait`:

```bash
loom-deck-headless status <STEP_SESSION> --root "<PROJECT_ROOT>"
```

`in corso` → l'attesa (§4); `turno chiuso` → il testo finale, da §5: domande da portare in chat, o la chiusura (§6); `errore` e `permesso negato` come in §5. Il passo di una ripresa è quello dello stato (`STEP_KIND`), anche quando la skill è rilanciata col solo `<TaskID>`.
