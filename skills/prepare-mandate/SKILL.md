---
name: prepare-mandate
description: Prepara il perimetro di una regia prima che parta — crea un mandato (task `Size: Mandate`) da una lista di id o da una descrizione, lo modifica aggiungendo o togliendo membri, oppure scrive l'analisi del perimetro dentro un'epica. L'analisi delle dipendenze e delle collisioni fra i membri ha una metà meccanica (`mandate.py tree`) e una del modello, che legge i task file dei membri. Presidiata — lista e analisi le conferma l'utente prima del commit — e non tocca mai i task file dei membri. Usa quando l'utente dice «prepara un mandato con T52, T61 e T64», «fammi un mandato con tutte le task di front-end», «aggiungi T70 al mandato T230, togli T52», «scrivi l'analisi del perimetro di T40».
argument-hint: "<Txx Tyy …> | <descrizione> | <mandato> [aggiungi Txx] [togli Tyy] | <epica>"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, AskUserQuestion
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

## Il ruolo

Un **perimetro** è l'insieme di task che una regia porta avanti insieme: le figlie di un'epica, oppure i membri di un **mandato**, cioè una task `Size: Mandate` che elenca nel proprio file task di epiche diverse e orfane. Il formato del task file è `${CLAUDE_PLUGIN_ROOT}/docs/mandate-format.md`: leggilo per intero prima di scrivere qualunque file.

Questa skill costruisce il perimetro **prima** che la regia parta, e ne scrive l'analisi: quali coppie di membri non possono girare insieme, e su cosa. Tre modi:

| Modo | Cosa scrive | Chi committa |
|---|---|---|
| creazione (§2) | un task file nuovo `Size: Mandate`, e la sua riga in `tasks.md` | `create-task.sh` |
| modifica (§4) | `## Membri`, `## Preferenze d'ordine` e `## Analisi del perimetro` di un mandato che esiste, la Description se chiesta, la voce 🎬 se manca | la skill, il solo file del mandato |
| epica (§5) | `## Analisi del perimetro` di un'epica, e la voce 🎬 se manca | la skill, il solo file dell'epica |

In tutti e tre i modi il perimetro porta in `## Materiale` la voce 🎬, il puntatore allo stato della regia (§7).

Confini, in ogni modo:

- **I task file dei membri non si toccano mai**, nemmeno per correggere un difetto che l'analisi trova — una dipendenza non dichiarata, un `## Materiale` incompleto. Il difetto si dice all'utente alla conferma, e lo corregge chi lavora su quel membro.
- **Nessun commit senza la conferma dell'utente**, chiesta con `AskUserQuestion` (§3). Una conferma chiesta in chat è testo: niente fermerebbe il commit prima della risposta, mentre il tool sospende l'esecuzione finché l'utente non sceglie.
- **Nessuna copia di stato o di cifre** nel file del perimetro (`mandate-format.md` §Nessuna copia): niente Prog dei membri, niente DLV contati, niente stime sommate. Tutto questo vive altrove e resterebbe indietro alla prima modifica.

## 0. Avvio

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo all'utente e fermati: senza Python la metà meccanica dell'analisi non si calcola.

Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (lo chiamiamo `PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/regia`. Ogni script si lancia con `"PY" -B -I "R/<script>"`: `-I` lo isola dalla cartella corrente, `-B` non scrive bytecode nella cache del plugin.

## 1. Il modo

Dalle Note utente leggi gli id (`T<numero>`) e il resto, che è una descrizione oppure dei **verbi sulla lista** («aggiungi T64», «togli T52»). Di ogni id leggi il task file con `resolve-task.sh <id>` (`Size` nell'header) e la Prog dalla tabella Tasks Overview di `{docs_root}/tasks.md`.

Il modo lo decidono il primo id e quello che lo segue:

| Note utente | Modo |
|---|---|
| il primo id è `Size: Mandate`, da solo o seguito da verbi sulla lista — gli id dopo il primo sono gli oggetti dei verbi | modifica (§4) |
| un solo id, `Size: Epic`, e nient'altro | epica (§5) |
| due o più id senza verbi, oppure una descrizione, con o senza id | creazione (§2) |
| un solo id di una task normale, e nient'altro | errore |
| niente | errore |

È il dispatch per marcatore di `recap-status` e `run-task`: il `Size` del primo id decide.

**Errore** → stampa l'uso e fermati, senza scrivere niente:

```
/loom-works:prepare-mandate T52 T61 T64              crea un mandato da una lista di id
/loom-works:prepare-mandate le task di front-end     crea un mandato da una descrizione
/loom-works:prepare-mandate T230 aggiungi T70        modifica il mandato T230 (anche: togli T52)
/loom-works:prepare-mandate T40                      scrive l'analisi del perimetro nell'epica T40
```

**Lettura dubbia** → dichiara il modo che hai letto e chiedilo con `AskUserQuestion` prima di scrivere qualunque file. Tre casi tipici: «le figlie di T40» da solo (l'analisi nell'epica T40, oppure un mandato nuovo con le sue figlie aperte?); un mandato seguito da altri id senza verbi (aggiungerli al mandato, oppure un mandato nuovo che lo contiene come riga sola?); un mandato seguito da parole che non sono verbi sulla lista.

Prima di proseguire dichiara il modo in una riga: `🧭 Modo: creazione da lista — 3 id`.

## 2. Creazione

### 2a. La lista — da id

Per ogni id nominato, nell'ordine in cui l'utente lo nomina:

- **Nessun task file** (`resolve-task.sh` esce non-zero) → resta fuori dalla lista. Lo dici alla conferma: un id sbagliato non deve diventare un membro senza file.
- **Prog ✔️** → entra, con un avviso alla conferma: una task chiusa non dà lavoro alla regia.
- **`Size: Epic` o `Size: Mandate`** → entra come riga sola (`mandate-format.md` §Membri: il lettore non la espande). La conferma dice che la regia non lancerà i suoi membri: la tratterà come un perimetro da orchestrare a parte.
- **«le figlie di T40»** → le leggi da `resolve-task.sh T40 --members` e scrivi le aperte (Prog diversa da ✔️) una per una, nell'ordine del lettore. Una figlia nata dopo non entra da sola: lo dici alla conferma.

Da una lista di id non c'è una fermata qui: la lista la conferma l'utente insieme alla bozza e all'analisi, in una fermata sola (§3).

### 2b. La lista — da una descrizione

La proposta si costruisce in due passi:

1. **I titoli delle aperte.** Le righe della tabella Tasks Overview di `{docs_root}/tasks.md` con Prog 🔵, 🟢 o 🟡 — solo quella tabella: le tabelle che la seguono (lane attive, cross-deps) hanno righe della stessa forma. Dai titoli scegli i candidati e i dubbi.
2. **I task file dei candidati e dei dubbi**, letti per Description, Deliverables e `## Materiale`. Il titolo da solo non basta: è troncato a 100 caratteri, e dà falsi positivi.

Le task ✔️ non entrano nella proposta. Un id nominato dall'utente accanto alla descrizione entra con le regole del §2a.

La proposta in chat porta una ragione per membro e l'elenco corto dei vicini esclusi — le task che un lettore si aspetterebbe di trovare, con il perché non ci sono:

```
📋 Proposta — «tutte le task di front-end»
   T52 (lettore delle convention del deck) — riscrive il parser della tabella task
   T61 (gate del deck sulle convention) — legge il formato di T52 nel deck
   esclusi:
   T58 (doc delle convention) — tocca solo reference/, nessun file del deck
```

Poi la **prima fermata**: `AskUserQuestion` con la domanda «Confermi i membri del mandato?» e tre opzioni — confermo · correggo (scrivi cosa aggiungere o togliere) · annulla. Una correzione rifà la proposta e la richiede; annulla chiude la skill senza scrivere niente.

### 2c. Il file su disco, prima dell'analisi

Il task file del mandato si scrive **prima** dell'analisi e **non si committa** fino alla conferma. Due ragioni: `mandate.py tree` vuole in testa un id il cui task file esiste su disco, e senza esce 1; e `get-next-task-id.sh` conta i file oltre alle righe di `tasks.md`, quindi il file non committato riserva l'id contro una sessione parallela che crea una task durante l'attesa della conferma.

1. L'id:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/utils/get-next-task-id.sh"
   ```

2. I campi di progetto:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" fields
   ```

   Ogni riga `FIELD|<key>|…` diventa una riga vuota `- **<key>**:` dopo `Folder`, nell'ordine dichiarato, senza domande: un mandato non ha lavoro proprio, e il campo si riempie a mano se serve. Nessuna riga → nessuna riga nell'header. Exit non-zero → header senza campi, e lo dici alla conferma.

3. Il file, col tool `Write`, in `{docs_root}/tasks/<id>-mandato-<slug>.md`:

   ```markdown
   # Task: Mandato: <tema>

   - **ID**: <id>
   - **Created on**: <YYYY-MM-DD HH:mm>
   - **Priority**: Med
   - **Estimated Time**:
   - **Size**: Mandate
   - **Lane**: nessuna (task spot)
   - **Parent Task**:
   - **Branch**:
   - **Folder**:
   - **Progress**: 🔵 Todo

   ## Description

   <perché questo perimetro esiste e cosa vuole ottenere>

   ## Membri

   - T52 (lettore delle convention del deck)
   - T61 (gate del deck sulle convention)

   ## Preferenze d'ordine

   - In questo giro prima le convention: T52 prima di T61.

   ## Analisi del perimetro

   <scritta al §2d>

   ## Materiale
   *📖 fonte · 🔬 analisi · 📤 prodotto · 🎬 stato della regia; 📁/ = task folder. Solo materiale di alto rilievo, non l'inventario della folder.*

   - 🎬 `.claude/loom/regia/<id>.md` — seguire il giro della regia: conversazioni, fatti del perimetro, proposte in sospeso (fuori da git)
   ```

Le regole del file:

- **Titolo** «Mandato: <tema>», col tema dalle parole dell'utente; da soli id, il tema che i membri hanno in comune. **Slug**: il tema in kebab-case, senza accenti, con il prefisso `mandato-`.
- **Priority** Med se l'utente non la dice (High, Med, Low).
- **Estimated Time** vuoto: la stima di un mandato sarebbe la somma dei membri, cioè una copia.
- **Description**: dalle parole dell'utente. Da soli id, un paragrafo corto sul tema comune, che l'utente corregge alla conferma. Niente sullo stato dei membri.
- **Membri**: `- T<id> (maniglia)`, con la maniglia verbo+oggetto ricavata dal titolo del membro. Niente Prog, niente checkbox, niente epica di provenienza: la parentela vive nel `Parent Task` del membro.
- **Preferenze d'ordine**: solo se l'utente ha detto un ordine per questo giro; altrimenti la sezione non c'è. Una dipendenza vera non è una preferenza: se l'utente dice «T61 ha bisogno del formato di T52», quella va in `## Dependencies` di T61, che questa skill non scrive — lo dici alla conferma.
- **Materiale**: la sola voce 🎬 (§7).
- Niente `## Acceptance Criteria` e niente `## Deliverables Checklist`: un mandato non ha lavoro proprio (`mandate-format.md` §Acceptance e Deliverables).

### 2d. L'analisi

Scrivi `## Analisi del perimetro` nel file su disco col metodo del §6, con l'id del mandato in testa e i membri della lista. Poi la conferma (§3).

## 3. La conferma e il commit della creazione

In chat, prima della domanda:

- la **bozza** del file intero;
- le **note** che l'utente deve leggere prima di dire sì: gli id rimasti fuori senza task file, i membri ✔️, i membri epica o mandato, le dipendenze aperte verso task fuori dal perimetro con l'offerta di aggiungerle (§6), i punti ciechi dell'analisi (§6), le dipendenze non dichiarate che l'analisi ha trovato.

Poi la fermata: `AskUserQuestion` con la domanda «Scrivo il mandato <id>?» e tre opzioni — scrivi · correggo (lista, descrizione, preferenze) · annulla. Le preferenze d'ordine l'utente le aggiunge qui, nella risposta.

- **Scrivi** → se la risposta porta delle preferenze, scrivile in `## Preferenze d'ordine`. Poi:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/task/create-task.sh" <id> mandato-<slug> "Mandato: <tema>" <Priority>
  ```

  Lo script aggiunge la riga a `tasks.md`, committa il task file e `tasks.md` con una pathspec esplicita, e pusha.
- **Correggo** → applica la correzione. Se cambia la lista dei membri, rifai l'analisi (§2d). Mostra di nuovo bozza e note, e richiedi.
- **Annulla** → cancella il file: `git status --short -- <file>` deve stampare `??`, cioè un file mai committato, che è il tuo. L'id torna libero. Se stampa altro, il file non è più solo tuo: non cancellarlo, e dillo.

Chiudi con il path del file, l'id, il numero di membri e le righe dell'analisi per fonte.

## 4. Modifica di un mandato

Un mandato che esiste si rilancia per aggiungere o togliere membri, cambiare descrizione o preferenze d'ordine, o solo per rifare l'analisi. L'analisi si rifà **intera** a ogni rilancio, anche quando la lista non cambia.

### 4a. Il file è pulito

```bash
git status --short -- <file del mandato>
```

Output vuoto → avanti. Altrimenti fermati e dillo: il file ha modifiche non committate, e il commit di questa skill le porterebbe con sé. Chi le ha scritte le committa o le scarta, poi si rilancia.

### 4b. La lista nuova

I membri di oggi si leggono col lettore unico, mai a mano:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <mandato> --members
```

Poi si applicano le parole dell'utente:

- **«aggiungi T64»** → una riga nuova in fondo a `## Membri`, o nel punto che l'utente dice, con le regole del §2a: task file assente → fuori, ✔️ → avviso, epica o mandato → riga sola. Il mandato non aggiunge sé stesso, e un id già in lista non si ripete.
- **«togli T52»** → la riga di T52 sparisce. Un id che non è in lista si dice alla conferma, senza toccare niente.
- **«le figlie di T40»** → come al §2a, le aperte una per una.
- **descrizione, preferenze d'ordine, una maniglia** → si riscrive quello che le parole dicono, e nient'altro.
- **nessun verbo** → la lista resta com'è, e si rifà la sola analisi.

Un `TASK_MEMBER_MISSING=<id>` — un membro senza task file, per esempio una task chiusa e purgata — resta in lista finché l'utente non dice di toglierlo: lo mostri alla conferma come tale.

### 4c. La rianalisi

Col metodo del §6, §La rianalisi: `tree` con l'id del mandato in testa e la **lista nuova** dopo `--children`, le righe `dichiarata` e `materiale` ricalcolate, ogni riga `modello` vecchia confermata, riscritta o tolta con la ragione, le coppie dei membri aggiunti analizzate da zero. Il file su disco non cambia ancora: `tree` riceve i membri dagli argomenti, e la sezione `## Membri` del file non la legge.

### 4d. La conferma e il commit

In chat, prima della domanda:

- la differenza di `## Membri`: `+ T64 (maniglia)`, `− T52 (maniglia)`;
- le preferenze d'ordine e la descrizione nuove, se cambiano;
- la differenza dell'analisi riga per riga (`=` `+` `-` `~`, §6);
- la voce 🎬, se il mandato non la porta (§7);
- le note del §3: avvisi sui membri, dipendenze aperte fuori dal perimetro, dipendenze non dichiarate, punti ciechi.

Poi la fermata: `AskUserQuestion` con la domanda «Aggiorno il mandato <id>?» e tre opzioni — aggiorna · correggo · annulla.

- **Aggiorna** → scrivi col tool `Edit` le sole sezioni che cambiano: `## Membri`, `## Preferenze d'ordine` (creata se prima non c'era, tolta se l'utente la svuota), `## Analisi del perimetro` sostituita intera, la Description se l'utente l'ha chiesto, e la voce 🎬 se manca (§7). Poi il commit del **solo** file del mandato:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
    && lw_git_add_n_commit "task(<id>): mandato — <+T64 −T52 | analisi rifatta>" "<file del mandato>" \
    && lw_git_push "$(lw_current_branch)"
  ```

  `tasks.md` non si tocca: la riga del mandato non cambia.
- **Correggo** → applica, rifai la rianalisi se cambia la lista, mostra e richiedi.
- **Annulla** → niente da cancellare: il file non è cambiato.

## 5. L'analisi in un'epica

Un'epica ha già i suoi membri — le figlie, che dichiarano `**Parent Task**` — e non ha una lista da costruire. Le manca, finché nessuno la scrive, l'analisi: la stessa sezione di un mandato, con lo stesso nome e la stessa forma, così chi la cerca la cerca con un nome solo. In questo modo la skill scrive **solo** quella sezione e la voce 🎬 (§7): le figlie, la loro checkbox nell'Acceptance dell'epica, la Prog e `tasks.md` non si toccano.

1. **Il file è pulito** — la guardia del §4a, sul file dell'epica.
2. **Le figlie** — dal lettore unico:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <epica> --members
   ```

   `TASK_MEMBERS_COUNT=0` → dillo e fermati: un'epica senza figlie non ha coppie da analizzare.
3. **L'analisi** — col metodo del §6, con l'epica in testa e le figlie dopo `--children`, nell'ordine del lettore. Se `## Analisi del perimetro` esiste già, è una rianalisi, con la tabella vecchia in ingresso; altrimenti si parte da zero.
4. **La conferma** — in chat la sezione nuova, o la differenza riga per riga se c'era, la voce 🎬 se l'epica non la porta (§7), e le note del §3. Una dipendenza aperta verso una task che non è figlia non si può aggiungere ai membri da qui, perché le figlie le decide il `Parent Task` della figlia: la nota dice che per seguirla insieme all'epica serve un mandato. Poi `AskUserQuestion` con la domanda «Scrivo l'analisi del perimetro nell'epica <id>?» e tre opzioni — scrivi · correggo · annulla.
5. **La scrittura** — col tool `Edit`. Se la sezione esiste, si sostituisce intera dove sta. Se non esiste, entra subito dopo `## Description`, prima del primo heading `## ` che la segue: nel mandato la sezione sta nello stesso punto, dopo la Description e le sezioni proprie. Poi la voce 🎬, se manca (§7).
6. **Il commit** — il solo file dell'epica:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
     && lw_git_add_n_commit "task(<epica>): analisi del perimetro" "<file dell'epica>" \
     && lw_git_push "$(lw_current_branch)"
   ```

## 6. L'analisi del perimetro

Il metodo è `${CLAUDE_PLUGIN_ROOT}/docs/mandate-analysis.md`: leggilo per intero prima della prima analisi della conversazione. Vale per i tre modi, ed è lo stesso che usa chi riscrive un'analisi smentita da un membro.

In breve, le due metà:

1. **Meccanica** — `tree` con la testa e i membri, e la trascrizione delle sue righe `CONFLICT`:

   ```bash
   "PY" -B -I "R/mandate.py" tree <testa> --children <membri…>
   ```

   La testa è il mandato o l'epica: il suo task file deve esistere su disco, ed è per questo che la creazione lo scrive prima (§2c). I membri si passano nell'ordine della lista: è l'ordine delle coppie in tabella. `tree` legge e basta, nessun file del repo cambia.
2. **Del modello** — il task file intero di ogni membro aperto, e `git grep` sui soli path e simboli che due membri nominano, per sapere se cadono sullo stesso file.

Le note che l'analisi produce oltre alla tabella vanno alla conferma, mai nel file: le dipendenze aperte verso task fuori dal perimetro, le dipendenze non dichiarate, i punti ciechi.

## 7. La voce 🎬 — il puntatore allo stato della regia

La regia di un perimetro tiene il suo stato in `.claude/loom/regia/<id>.md` del progetto, ignorata da git: conversazioni, fatti del perimetro, proposte in sospeso (`${CLAUDE_PLUGIN_ROOT}/skills/orchestrate-mandate/SKILL.md` §0f). Il perimetro lo punta da `## Materiale` con una voce sola:

```markdown
- 🎬 `.claude/loom/regia/<id>.md` — seguire il giro della regia: conversazioni, fatti del perimetro, proposte in sospeso (fuori da git)
```

- **È un puntatore per chi legge il task file**, e nient'altro. La regia e `checkpoint-mandate` ricavano il path dall'id del perimetro e non leggono la voce: un perimetro preparato prima che la voce esistesse viene seguito lo stesso. Il file può non esserci ancora — la regia lo crea al primo lancio — e la voce resta valida.
- **La scrive questa skill**, l'unica che prepara il perimetro: la regia non scrive nei task file.
- **Una sola volta.** Una voce 🎬 già presente in `## Materiale` non si riscrive e non si ripete.
- **Dove.** In un mandato nuovo la sezione `## Materiale` sta in coda, dopo `## Analisi del perimetro` (§2c). In un file che la sezione non la porta — un mandato preparato prima, un'epica senza `## Materiale` — la crei con la legenda del template, prima del primo heading fra `## Decisions`, `## Implementation Notes`, `## Testing Notes`, `## Doc Impact`, `## Prod Validation` e `## Progress Log`; in coda se il file non ne porta nessuno. È il punto in cui il task template mette `## Materiale`.
- **Non è una collisione.** `mandate.py tree` salta le voci 🎬: nessun membro scrive lo stato della regia.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

A lavoro finito, dopo il commit:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "$(say_id <id>) ready"
```
