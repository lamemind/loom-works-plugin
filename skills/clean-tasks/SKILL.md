---
name: clean-tasks
description: Clean tasks on demand — by ID (T15), range (T15-T20 / T15-20), or age ("older than N days"). Removes task file, dot-prefixed folder, and tasks.md row, one commit per task. A task whose folder holds material marked 💎 in ## Materiale is refused and stays whole.
allowed-tools: Bash(*), Read, AskUserQuestion
model: sonnet
---

Pota task su indicazione diretta. Operazione distruttiva ma recuperabile via git history.

Tutto il lavoro lo fa lo script: per ogni task elimina il task file, la folder dot-prefixed e la riga della Tasks Overview in `tasks.md` (l'Execution Plan non lo tocca: è design scritto a mano), e fa **un commit atomico per task**. Il tuo compito è solo interpretare l'input, lanciare il dry-run, chiedere conferma quando serve, eseguire `--apply`. Non fare git/rm a mano e non aggiungere commit tuoi: lo script possiede l'intero flusso, range inclusi.

Input utente:
~~~human
$ARGUMENTS
~~~

## Modi

Interpreta `$ARGUMENTS` e scegli **uno** dei modi:

| Modo | Trigger | Front-end | Conferma |
|------|---------|-----------|----------|
| **A — ID/range** | token `Tnn`, `Tnn-Tmm`, `Tnn-mm` (virgola/spazio) | `clean-tasks.sh` | solo se ci sono NON-Done |
| **B — età** | linguaggio naturale su anzianità Done | `cleanup-done-tasks.sh` | sempre |
| **C — vuoto/ambiguo** | nessun token riconoscibile | — | chiedi cosa pulire |

**Modo C** → chiedi inline (no AskUserQuestion): «Quali task? ID/range (es. `T15-20`) o età (es. "più vecchie di 30 giorni")».

In Modo B estrai `DAYS` dal linguaggio naturale (default `60`).

## Conferma già raccolta dal chiamante — token `yolo`

Se `$ARGUMENTS` contiene **`yolo`** (o **"no domande"**, **"senza domande"** — stesso rilevamento di `create-task`), il chiamante dichiara di aver **già raccolto la conferma**: salta **ogni** `AskUserQuestion` di questa skill — quella sui target NON-Done (§2) e quella sul gate `--ignored-files` (§3b) — e vai diretto all'apply. Il token non cambia nient'altro: il dry-run si esegue e si mostra lo stesso, l'esito si verifica lo stesso.

Il canale esiste perché **una skill che chiede conferma con `AskUserQuestion` non è invocabile da un consumer headless**: in `claude -p` non c'è nessuno che risponda, la sessione resta appesa finché non la si uccide, e per chi la osserva dall'esterno (evento `result` che non arriva mai) è indistinguibile da un'operazione lenta. Un consumer che vuole tenere la conferma dalla propria parte — come il modale `CANC` di loom-deck — deve poterlo **dire** alla skill, o la conferma resta doppia e la seconda blocca.

Col token, se il gate `--ignored-files` scatta (§3b) e il chiamante non ha passato `keep|purge`, **non chiedere**: riporta il blocco `ERROR` con folder e file superstiti. Scegliere al posto di chi non ha risposto significherebbe decidere in silenzio se dei file si perdono. Una task rifiutata per il materiale 💎 (§3c) non si chiede mai, col token o senza.

In entrambi i casi — gate senza direttiva, task rifiutate per il 💎 — la **prima riga** della risposta finale deve nominare le task NON rimosse, in chiaro e per ID, col perché prima dei path: `non rimosse: T07 — materiale 💎 nella folder (.26-01-01-x/tool.py)`. Il deck ne mostra i primi caratteri accanto agli ID che restano. Un consumer headless legge quel testo (`{type:"result"}`) e non ha altro modo di sapere *quali* sono sopravvissute. `is_error` non basta e non va usato come segnale — una spiegazione ben scritta di un blocco chiude comunque `is_error: false`, cioè un successo dichiarato su zero rimozioni.

Chiamante headless che passa già la direttiva: `--ignored-files keep` o `--ignored-files purge` compaiono in `$ARGUMENTS` accanto agli ID → inoltrali tali e quali al comando di apply, senza chiedere.

## Flusso — dry-run → conferma → apply

Passa l'intero SPEC/range in **una sola invocazione**: lo script espande i range da solo (gli ID inesistenti finiscono `[missing]`, non bloccano).

### 1. Dry-run

**Modo A:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    <SPEC...>
```

**Modo B:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --days ${DAYS}
```

Mostra l'output. Lo script elenca i target con tag `[Done]` / `[NOT Done]` / `[orphan row]` / `[missing]`, e marca `[⚠ N ignored/untracked]` le folder che conterrebbero file non rimossi da `git rm` (vedi §3b). Una folder che **resta** sul disco e in git mentre la sua task parte si legge `· folder <nome> resta (<motivo>)` al posto di `+ folder <nome>` — i due motivi in §Note, «Folder che resta». Una task **protetta** dal materiale 💎 si legge `· protetta: 💎 <path>[, <path>…]`: con `--apply` resta intera (§3c). Il Modo A chiude con una riga riassuntiva:

```
SUMMARY candidates=A non_done=B orphans=C missing=D protected=E
```

`protected` conta le task che l'apply rifiuterà; `candidates` le comprende.

Nessun candidato e nessuna riga orfana → niente da rimuovere, chiudi.

### 2. Conferma

- **Modo A**: salta la conferma se `non_done == 0` (tutti Done) e vai diretto all'apply. Se `non_done > 0`, conferma obbligatoria.
- **Modo B**: conferma sempre, se ci sono candidati.
- **Token `yolo`**: conferma già raccolta dal chiamante → salta in entrambi i modi.

Quando serve, TTS ping poi `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "conferma pulizia task <topic 3-7 parole>"
```

Nell'`AskUserQuestion`: elenca i target dal dry-run (in Modo A evidenzia le NON-Done, eliminazione forzata; le protette le nomini come task che restano, non come target), ricorda il restore `git checkout <commit>~1 -- <path>`, opzioni **Procedi** / **Annulla**.

### 3. Apply

Stesso comando con `--apply`. Lo script cicla i target e committa uno per uno.

**Modo A:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --apply \
    <SPEC...>
```

**Modo B:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/cleanup-done-tasks.sh \
    --days ${DAYS} \
    --apply
```

### 3b. Gate — task folder con file ignored/untracked

Se una task folder contiene file che `git rm` **non** rimuove (ignorati da un `.gitignore` locale o del root, oppure untracked), rimuovere solo i tracked lascerebbe quei file orfani su disco. Lo script **fallisce con exit 2** prima di toccare qualsiasi cosa, stampando la folder + l'elenco dei file superstiti:

```
ERROR: task folder con file che 'git rm' non rimuove (ignored/untracked):
  .26-06-16-cat/
    - .26-06-16-cat/build/out.bin
    - .26-06-16-cat/notes.local.md
```

Il dry-run le anticipa marcando il candidato con `[⚠ N ignored/untracked]`. Una folder che resta (§Note) è fuori dal gate e da `--ignored-files`: non parte, quindi non lascia niente sul disco da decidere.

Quando l'apply esce con quel blocco `ERROR`, sei tu (chiamante) a decidere — **salvo token `yolo` senza `--ignored-files`**, dove riporti il blocco e chiudi non-zero. TTS ping + `AskUserQuestion`, elenca folder e file, chiedi **come gestirli**. In **entrambi** i casi la folder sparisce dal disco locale — la scelta riguarda solo se preservarli in git:

- **Preserva (keep)** → commit-snapshot dedicato che salva quei file in git **prima** del purge; poi la folder viene comunque rimossa dal disco (i file restano recuperabili da quel commit).
- **Elimina (purge)** → nessuno snapshot; `rm` secco della folder (path assoluto, guardato dentro project root — nessun disastro). File persi.

Poi rilancia lo **stesso** comando `--apply` aggiungendo `--ignored-files keep` **oppure** `--ignored-files purge`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/clean-tasks.sh \
    --apply --ignored-files <keep|purge> \
    <SPEC...>
```

(Modo B: stesso flag su `cleanup-done-tasks.sh`.)

**Direttiva globale al run**: `--ignored-files` vale per *tutte* le folder con superstiti nella stessa invocazione. Se task diverse richiedono scelte diverse (una keep, una purge), lanciale separatamente.

### 3c. Task protetta — materiale 💎 nella folder

Task folder e task file sono temporanei: la potatura li elimina. Una voce di `## Materiale` che porta 💎 accanto al glifo di ruolo (``- 📤💎 `📁/report.xlsx` — …``) marca un oggetto da non eliminare. Se l'oggetto esiste, sta nella task folder e la folder partirebbe in questa invocazione, lo script **rifiuta la task**: task file, folder e riga di `tasks.md` restano, le altre task dello stesso giro partono. Una folder condivisa con una task rifiutata resta anche per le task che partono (`· folder <nome> resta (condivisa con T…)`). Una task rifiutata è fuori dal gate `--ignored-files` (§3b): non parte, e non lascia niente da decidere.

L'apply la nomina in `--- rifiuto <id> ---` e chiude con `-> rifiutate: <id>, … — materiale 💎 nella folder` ed **exit 3**: 0 vuol dire tutte eliminate, 2 è il gate `--ignored-files`. A un 3 non si rilancia niente — `--ignored-files` non sblocca una task protetta, e non esiste un flag che forzi l'eliminazione.

**Non chiedere e non sbloccare tu**, col token `yolo` o senza: non spostare l'oggetto, non togliere 💎 dal task file. La task si sblocca in due modi, e la scelta è di chi ha marcato l'oggetto: spostarlo fuori dalla folder, o togliere 💎 dalla sua voce. Riportali nella risposta, dopo la prima riga che nomina le task non rimosse (§Conferma già raccolta dal chiamante).

### 4. Esito

Mostra l'output dello script. Atteso: un commit `chore(tasks): purge …` per ogni task rimossa (più eventuali `reconcile orphan …`), e nessun commit unico che ripulisce `tasks.md` in blocco. Exit 3: le task rifiutate per il 💎 restano, le altre sono rimosse — è un esito parziale, e la risposta lo dice in prima riga (§3c). Se l'esito diverge, segnalalo invece di dichiarare successo.

Se almeno un commit è andato a buon fine:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "task cleanup done"
```

## Note

- **Dry-run di default**: sicuro da invocare per sola ispezione.
- **Restore granulare**: ogni commit include file + folder + riga della stessa task → `git checkout <commit>~1 -- <path>`.
- **Modo A ignora stato ed età**: rimuove anche task non-Done (con conferma) e non guarda la soglia giorni; il Modo B pota solo Done oltre `--days`.
- **Righe orfane**: ID con riga in `tasks.md` ma file già assente → riconciliate con commit dedicato.
- **Folder ignored/untracked**: `git rm` non tocca i file ignorati/untracked di una task folder → gate exit 2, decidi keep/purge (§3b). `--ignored-files` obbligatorio solo se ci sono superstiti.
- **Folder condivisa fra task che partono insieme**: la prima la rimuove, le altre la trovano già sparita e saltano pulito.
- **Folder che resta**: task file e riga partono, la folder resta sul disco e in git, e il commit lo scrive in `Folder kept:`. Due motivi:
  - `condivisa con T…` — un'altra task, fuori da questa invocazione, dichiara la stessa folder nel campo `Folder`;
  - `non ha la forma .YY-MM-DD-slug` — il campo `Folder` non nomina una task folder in project root (es. `Folder: .` sarebbe la project root intera).
- **Folder senza file tracciati** (vuota, o con soli file non tracciati sotto `purge`): parte come le altre. Se dopo la rimozione restano file che git non elenca (il contenuto di una `.git`), la folder resta sul disco con un avviso `⚠ folder rimasta sul disco`: va guardata a mano.
- **Materiale 💎**: la task che porta nella folder un oggetto marcato non parte, le altre sì, exit 3 (§3c). Un oggetto marcato fuori dalla folder, o già spostato, non ferma niente: la potatura non lo eliminerebbe.
- **Push**: nessun push automatico; manuale o via `checkpoint-task`.
