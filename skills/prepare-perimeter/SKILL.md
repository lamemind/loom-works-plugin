---
name: prepare-perimeter
description: Prepara il perimetro orchestrabile di un orchestrator prima che parta — crea una lista custom (task `Size: Custom`) da una lista di id o da una descrizione, la modifica aggiungendo o togliendo membri, oppure prepara un'epica — e ne scrive il piano, `orchestration-schedule.md` nella sua task folder, assegnata se manca. Il piano porta l'analisi delle dipendenze e delle collisioni fra i membri, con una metà meccanica (`perimeter.py tree`) e una del modello, che legge i task file dei membri, e le decisioni d'ordine per lo script del flusso — chi aspetta chi, chi non gira insieme a chi, i membri che segue l'utente. Presidiata — lista e piano li conferma l'utente prima del commit — e non tocca mai i task file dei membri. Usa quando l'utente dice «prepara una lista custom con T52, T61 e T64», «fammi una lista custom con tutte le task di front-end», «aggiungi T70 alla lista custom T230, togli T52», «scrivi il piano di T40», «rifai il piano di T256».
argument-hint: "<Txx Tyy …> | <descrizione> | <lista custom> [aggiungi Txx] [togli Tyy] | <epica>"
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

Un **perimetro orchestrabile** è l'insieme di task che un orchestrator porta avanti insieme: le figlie di un'epica, oppure i membri di una **lista custom**, cioè una task `Size: Custom` che elenca nel proprio file task di epiche diverse e orfane. Il formato del task file è `${CLAUDE_PLUGIN_ROOT}/docs/perimeter-format.md`, quello del piano `${CLAUDE_PLUGIN_ROOT}/docs/orchestration-schedule-format.md`: leggili per intero prima di scrivere qualunque file.

Questa skill costruisce il perimetro orchestrabile **prima** che l'orchestrator parta, e ne scrive il **piano**: `orchestration-schedule.md` nella sua task folder, con l'analisi delle relazioni fra i membri in prosa e le decisioni d'ordine in un blocco JSON, che lo script del flusso esegue. Senza un piano valido e committato l'orchestrator non parte. Tre modi:

| Modo | Cosa scrive | Chi committa |
|---|---|---|
| creazione (§2) | un task file nuovo `Size: Custom` con la sua task folder, la sua riga in `tasks.md`, e il piano | `create-task.sh` il task file; la skill il piano |
| modifica (§4) | `## Membri` di una lista custom che esiste, la Description se chiesta, e il piano riscritto | la skill, il file della lista custom e il piano insieme |
| epica (§5) | il piano di un'epica | la skill, il piano e il file dell'epica se cambia |

In ogni modo la skill porta anche il task file del perimetro orchestrabile in regola col formato: la task folder se manca (§7), le due voci di `## Materiale` (§7), e via le sezioni `## Analisi del perimetro` e `## Preferenze d'ordine` di un perimetro orchestrabile preparato prima del piano, che passano nel piano (`orchestration-schedule-analysis.md` §La rianalisi).

Confini, in ogni modo:

- **I task file dei membri non si toccano mai**, nemmeno per correggere un difetto che l'analisi trova — una dipendenza non dichiarata, un `## Materiale` incompleto. Il difetto si dice all'utente alla conferma, e lo corregge chi lavora su quel membro.
- **Nessun commit senza la conferma dell'utente**, chiesta con `AskUserQuestion` (§3). Una conferma chiesta in chat è testo: niente fermerebbe il commit prima della risposta, mentre il tool sospende l'esecuzione finché l'utente non sceglie.
- **Nessuna copia di stato o di cifre**, né nel file del perimetro orchestrabile né nel piano (`perimeter-format.md` §Nessuna copia): niente Prog dei membri, niente DLV contati, niente stime sommate. Tutto questo vive altrove e resterebbe indietro alla prima modifica.
- **Un piano, un orchestrator.** Durante il giro il piano lo riscrive il suo orchestrator: con un orchestrator vivo sul perimetro orchestrabile la skill non scrive (§0).

## 0. Avvio

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo all'utente e fermati: senza Python l'analisi e il controllo del piano non girano.

Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (lo chiamiamo `PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator`. Ogni script si lancia con `"PY" -B -I "R/<script>"`: `-I` lo isola dalla cartella corrente, `-B` non scrive bytecode nella cache del plugin.

**Gli orchestrator vivi**, nei modi modifica ed epica, prima di scrivere qualunque file:

```bash
"PY" -B -I "R/sessions.py" orchestrators
```

Una riga `ORCHESTRATOR|<sessionId>|<id del perimetro orchestrabile>|…` con l'id di questa invocazione → fermati senza scrivere: quell'orchestrator riscrive il piano durante il giro, e due scrittori sullo stesso file si rubano le modifiche al commit. Di' all'utente quale sessione, e le due strade: fermare l'orchestrator nella sua chat e rilanciare la skill, o chiedere a lui la modifica.

## 1. Il modo

Dalle Note utente leggi gli id (`T<numero>`) e il resto, che è una descrizione oppure dei **verbi sulla lista** («aggiungi T64», «togli T52»). Di ogni id leggi il task file con `resolve-task.sh <id>` (`Size` nell'header) e la Prog dalla tabella Tasks Overview di `{docs_root}/tasks.md`.

Il modo lo decidono il primo id e quello che lo segue:

| Note utente | Modo |
|---|---|
| il primo id è `Size: Custom` (o `Size: Mandate`, il nome di prima, che vale uguale), da solo o seguito da verbi sulla lista — gli id dopo il primo sono gli oggetti dei verbi | modifica (§4) |
| un solo id, `Size: Epic`, e nient'altro | epica (§5) |
| due o più id senza verbi, oppure una descrizione, con o senza id | creazione (§2) |
| un solo id di una task normale, e nient'altro | errore |
| niente | errore |

È il dispatch per marcatore di `recap-status` e `run-task`: il `Size` del primo id decide.

**Errore** → stampa l'uso e fermati, senza scrivere niente:

```
/loom-works:prepare-perimeter T52 T61 T64            crea una lista custom da una lista di id
/loom-works:prepare-perimeter le task di front-end   crea una lista custom da una descrizione
/loom-works:prepare-perimeter T230 aggiungi T70      modifica la lista custom T230 (anche: togli T52)
/loom-works:prepare-perimeter T40                    scrive il piano dell'epica T40
```

**Lettura dubbia** → dichiara il modo che hai letto e chiedilo con `AskUserQuestion` prima di scrivere qualunque file. Tre casi tipici: «le figlie di T40» da solo (il piano dell'epica T40, oppure una lista custom nuova con le sue figlie aperte?); una lista custom seguita da altri id senza verbi (aggiungerli alla lista custom, oppure una lista custom nuova che la contiene come riga sola?); una lista custom seguita da parole che non sono verbi sulla lista né preferenze d'ordine.

Prima di proseguire dichiara il modo in una riga: `🧭 Modo: creazione da lista — 3 id`.

**Le preferenze d'ordine** stanno nelle stesse Note utente, in ogni modo: «prima le convention», «T255 per ultima», «T245 lo seguo io». Valgono per questo giro e vanno nel piano (`orchestration-schedule-analysis.md` §Le preferenze dell'utente), mai nel task file.

## 2. Creazione

### 2a. La lista — da id

Per ogni id nominato, nell'ordine in cui l'utente lo nomina:

- **Nessun task file** (`resolve-task.sh` esce non-zero) → resta fuori dalla lista. Lo dici alla conferma: un id sbagliato non deve diventare un membro senza file.
- **Prog ✔️** → entra, con un avviso alla conferma: una task chiusa non dà lavoro all'orchestrator.
- **`Size: Epic` o `Size: Custom`** → entra come riga sola (`perimeter-format.md` §Membri: il lettore non la espande). La conferma dice che l'orchestrator non lancerà i suoi membri: la tratterà come un perimetro orchestrabile da seguire a parte.
- **«le figlie di T40»** → le leggi da `resolve-task.sh T40 --members` e scrivi le aperte (Prog diversa da ✔️) una per una, nell'ordine del lettore. Una figlia nata dopo non entra da sola: lo dici alla conferma.

Da una lista di id non c'è una fermata qui: la lista la conferma l'utente insieme alla bozza e al piano, in una fermata sola (§3).

### 2b. La lista — da una descrizione

La proposta si costruisce in due passi:

1. **I titoli delle aperte.** Le righe della tabella Tasks Overview di `{docs_root}/tasks.md` con Prog 🔵, 🟢 o 🟡 — solo quella tabella: le tabelle che la seguono (cross-deps) hanno righe della stessa forma. Dai titoli scegli i candidati e i dubbi.
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

Poi la **prima fermata**: `AskUserQuestion` con la domanda «Confermi i membri della lista custom?» e tre opzioni — confermo · correggo (scrivi cosa aggiungere o togliere) · annulla. Una correzione rifà la proposta e la richiede; annulla chiude la skill senza scrivere niente.

### 2c. Il file su disco, prima del piano

Il task file della lista custom si scrive **prima** del piano e **non si committa** fino alla conferma. Tre ragioni: `perimeter.py tree` vuole in testa un id il cui task file esiste su disco, e senza esce 1; il piano sta nella task folder che il campo `**Folder**` del file dichiara, e `verify` legge i membri dalla `## Membri` del file; e `get-next-task-id.sh` conta i file oltre alle righe di `tasks.md`, quindi il file non committato riserva l'id contro una sessione parallela che crea una task durante l'attesa della conferma.

1. L'id:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/utils/get-next-task-id.sh"
   ```

2. I campi di progetto:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" fields
   ```

   Ogni riga `FIELD|<key>|…` diventa una riga vuota `- **<key>**:` dopo `Folder`, nell'ordine dichiarato, senza domande: una lista custom non ha lavoro proprio, e il campo si riempie a mano se serve. Nessuna riga → nessuna riga nell'header. Exit non-zero → header senza campi, e lo dici alla conferma.

3. Il file, col tool `Write`, in `{docs_root}/tasks/<id>-lista-custom-<slug>.md`:

   ```markdown
   # Task: Lista custom: <tema>

   - **ID**: <id>
   - **Created on**: <YYYY-MM-DD HH:mm>
   - **Priority**: Med
   - **Estimated Time**:
   - **Size**: Custom
   - **Parent Task**:
   - **Branch**:
   - **Folder**:
   - **Progress**: 🔵 Todo

   ## Description

   <perché questa lista custom esiste e cosa vuole ottenere>

   ## Membri

   - T52 (lettore delle convention del deck)
   - T61 (gate del deck sulle convention)

   ## Materiale
   *📖 fonte · 🔬 analisi · 📤 prodotto · 🎬 stato dell'orchestrator · 💎 da non eliminare, accanto al glifo di ruolo (📤💎); 📁/ = task folder. Solo materiale di alto rilievo, non l'inventario della folder.*

   - 🔬 `📁/orchestration-schedule.md` — eseguire il giro: analisi del perimetro e piano dello script
   - 🎬 `.claude/loom/orchestrator/<id>.md` — seguire il giro dell'orchestrator: fatti del perimetro, proposte in sospeso, delega (fuori da git)
   ```

4. La task folder (§7):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh" <id>
   ```

   Lo script scrive il campo `**Folder**` e mette il file in stage: resta tuo, e non è ancora committato.

Le regole del file:

- **Titolo** «Lista custom: <tema>», col tema dalle parole dell'utente; da soli id, il tema che i membri hanno in comune. **Slug**: il tema in kebab-case, senza accenti, con il prefisso `lista-custom-`.
- **Priority** Med se l'utente non la dice (High, Med, Low).
- **Estimated Time** vuoto: la stima di una lista custom sarebbe la somma dei membri, cioè una copia.
- **Description**: dalle parole dell'utente. Da soli id, un paragrafo corto sul tema comune, che l'utente corregge alla conferma. Niente sullo stato dei membri, niente ordine del giro: l'ordine sta nel piano.
- **Membri**: `- T<id> (maniglia)`, con la maniglia verbo+oggetto ricavata dal titolo del membro. Niente Prog, niente checkbox, niente epica di provenienza: la parentela vive nel `Parent Task` del membro.
- **Materiale**: le due voci del §7, e nient'altro.
- Niente `## Acceptance Criteria` e niente `## Deliverables Checklist`: una lista custom non ha lavoro proprio (`perimeter-format.md` §Acceptance e Deliverables).

### 2d. Il piano

Scrivi `orchestration-schedule.md` nella task folder col metodo del §6, con l'id della lista custom in testa, i membri della lista e le preferenze delle Note utente. Poi la conferma (§3).

## 3. La conferma e il commit della creazione

In chat, prima della domanda:

- la **bozza** del task file intero, e il **piano** intero;
- le **note** che l'utente deve leggere prima di dire sì: gli id rimasti fuori senza task file, i membri ✔️, i membri epica o lista custom, le dipendenze aperte verso task fuori dal perimetro orchestrabile con l'offerta di aggiungerle (§6), le dipendenze non dichiarate che l'analisi ha trovato e che il piano ripete nel `dopo`, i cicli di dipendenze, i punti ciechi dell'analisi (§6).

Poi la fermata: `AskUserQuestion` con la domanda «Scrivo la lista custom <id>?» e tre opzioni — scrivi · correggo (lista, descrizione, ordine) · annulla. Le preferenze d'ordine l'utente le aggiunge qui, nella risposta.

- **Scrivi** → se la risposta porta delle preferenze, portale nel piano col metodo del §6 e rilancia `verify --bozza`. Poi i due commit, nell'ordine:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/task/create-task.sh" <id> lista-custom-<slug> "Lista custom: <tema>" <Priority>
  ```

  Lo script aggiunge la riga a `tasks.md`, committa il task file e `tasks.md` con una pathspec esplicita, e pusha. Poi il piano:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
    && lw_git_add_n_commit "task(<id>): piano del perimetro orchestrabile" "<path del piano>" \
    && lw_git_push "$(lw_current_branch)"
  ```

  E il controllo finale (§8).
- **Correggo** → applica la correzione. Se cambia la lista dei membri, riscrivi `## Membri` e rifai il piano (§2d). Mostra di nuovo bozza, piano e note, e richiedi.
- **Annulla** → cancella quello che hai scritto: `git status --short -- <task file>` deve stampare `A ` o `??`, cioè un file mai committato, che è il tuo — togli lo stage con `git rm -q --cached -- <task file>`, poi cancella il task file, il piano e la task folder se resta vuota. L'id torna libero. Se `git status` stampa altro, il file non è più solo tuo: non cancellarlo, e dillo.

Chiudi con il path del task file e del piano, l'id, il numero di membri, le relazioni del piano per fonte e il verdetto del controllo finale.

## 4. Modifica di una lista custom

Una lista custom che esiste si rilancia per aggiungere o togliere membri, cambiare descrizione o ordine, o solo per rifare il piano. Il piano si rifà **intero** a ogni rilancio, anche quando la lista non cambia.

### 4a. I file sono puliti

```bash
git status --short -- <file della lista custom> <path del piano nei due nomi, orchestration-schedule.md e schedule.md, se il campo Folder c'è>
```

Output vuoto → avanti. Altrimenti fermati e dillo: un file ha modifiche non committate, e il commit di questa skill le porterebbe con sé. Chi le ha scritte le committa o le scarta, poi si rilancia.

### 4b. La lista nuova

I membri di oggi si leggono col lettore unico, mai a mano:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <lista custom> --members
```

Poi si applicano le parole dell'utente:

- **«aggiungi T64»** → una riga nuova in fondo a `## Membri`, o nel punto che l'utente dice, con le regole del §2a: task file assente → fuori, ✔️ → avviso, epica o lista custom → riga sola. La lista custom non aggiunge sé stessa, e un id già in lista non si ripete.
- **«togli T52»** → la riga di T52 sparisce. Un id che non è in lista si dice alla conferma, senza toccare niente.
- **«le figlie di T40»** → come al §2a, le aperte una per una.
- **descrizione, una maniglia** → si riscrive quello che le parole dicono, e nient'altro.
- **preferenze d'ordine** → vanno nel piano, non nel file.
- **nessun verbo** → la lista resta com'è, e si rifà il solo piano.

Un `TASK_MEMBER_MISSING=<id>` — un membro senza task file, per esempio una task chiusa e purgata — resta in lista finché l'utente non dice di toglierlo: lo mostri alla conferma come tale.

### 4c. Il file e il piano, su disco

Il file della lista custom si scrive **prima** della conferma, perché `verify` legge i membri dalla sua `## Membri`; i file erano puliti (§4a), quindi un annulla li riporta al commit. Col tool `Edit`:

- `## Membri` con la lista nuova; la Description se l'utente l'ha chiesto;
- la task folder, se il campo `**Folder**` è vuoto (§7);
- via `## Analisi del perimetro` e `## Preferenze d'ordine`, se ci sono: il loro contenuto è l'ingresso della rianalisi (`orchestration-schedule-analysis.md` §La rianalisi);
- le voci di `## Materiale` che mancano (§7);
- `Size: Mandate` e il piano `schedule.md`, se ci sono: qui scatta la migrazione del §7, «I nomi di prima».

Poi il piano col metodo del §6, §La rianalisi: il piano vecchio, o le sezioni tolte, in ingresso; `tree` con l'id della lista custom in testa e la **lista nuova** dopo `--children`; le relazioni meccaniche ricalcolate; ogni collisione del modello vecchia confermata, riscritta o tolta con la ragione; le coppie dei membri aggiunti analizzate da zero.

### 4d. La conferma e il commit

In chat, prima della domanda:

- la differenza di `## Membri`: `+ T64 (maniglia)`, `− T52 (maniglia)`;
- la descrizione nuova, se cambia;
- la differenza del piano riga per riga (`=` `+` `-` `~`, §6), o il piano intero se prima non c'era;
- le sezioni tolte dal task file, la task folder assegnata e le voci di `## Materiale` aggiunte, se ci sono;
- le note del §3: avvisi sui membri, dipendenze aperte fuori dal perimetro orchestrabile, dipendenze non dichiarate, cicli, punti ciechi.

Poi la fermata: `AskUserQuestion` con la domanda «Aggiorno la lista custom <id>?» e tre opzioni — aggiorna · correggo · annulla.

- **Aggiorna** → il commit del file della lista custom e del piano, insieme:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
    && lw_git_add_n_commit "task(<id>): lista custom — <+T64 −T52 | piano rifatto>" "<file della lista custom>" "<path del piano>" \
    && lw_git_push "$(lw_current_branch)"
  ```

  `tasks.md` non si tocca: la riga della lista custom non cambia. Poi il controllo finale (§8).
- **Correggo** → applica, rifai il piano se cambia la lista, mostra e richiedi.
- **Annulla** → riporta il file della lista custom al commit (`git restore --staged --worktree -- <file della lista custom>`) e il piano al suo commit, o cancellalo se non era tracciato.

## 5. Il piano di un'epica

Un'epica ha già i suoi membri — le figlie, che dichiarano `**Parent Task**` — e non ha una lista da costruire. Le manca, finché nessuno lo scrive, il piano: lo stesso file di una lista custom, con la stessa forma. In questo modo la skill scrive **solo** il piano e, nel file dell'epica, la task folder, le voci di `## Materiale` e la rimozione di `## Analisi del perimetro` (§7): le figlie, la loro checkbox nell'Acceptance dell'epica, la Prog e `tasks.md` non si toccano.

1. **I file sono puliti** — la guardia del §4a, sul file dell'epica e sul piano nei due nomi.
2. **Le figlie** — dal lettore unico:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <epica> --members
   ```

   `TASK_MEMBERS_COUNT=0` → dillo e fermati: un'epica senza figlie non ha un giro da pianificare.
3. **Il file dell'epica** — la task folder se manca, via `## Analisi del perimetro` se c'è, le voci di `## Materiale` che mancano (§7). Un piano `schedule.md` nella folder fa scattare qui la migrazione del §7, «I nomi di prima».
4. **Il piano** — col metodo del §6, con l'epica in testa e le figlie dopo `--children`, nell'ordine del lettore, e le preferenze delle Note utente. Un piano o un'analisi che c'erano già sono l'ingresso della rianalisi.
5. **La conferma** — in chat il piano nuovo, o la differenza riga per riga se c'era, le modifiche al file dell'epica, e le note del §3. Una dipendenza aperta verso una task che non è figlia non si può aggiungere ai membri da qui, perché le figlie le decide il `Parent Task` della figlia: la nota dice che per seguirla insieme all'epica serve una lista custom. Poi `AskUserQuestion` con la domanda «Scrivo il piano dell'epica <id>?» e tre opzioni — scrivi · correggo · annulla. L'annulla riporta i file al commit, come al §4d.
6. **Il commit** — il piano, e il file dell'epica se è cambiato:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
     && lw_git_add_n_commit "task(<epica>): piano del perimetro orchestrabile" "<path del piano>" ["<file dell'epica>"] \
     && lw_git_push "$(lw_current_branch)"
   ```

   Poi il controllo finale (§8).

## 6. Il piano

Il metodo è `${CLAUDE_PLUGIN_ROOT}/docs/orchestration-schedule-analysis.md`: leggilo per intero prima del primo piano della conversazione. Vale per i tre modi, ed è lo stesso che usa l'orchestrator quando riscrive il piano a metà giro.

In breve:

1. **Le relazioni, metà meccanica** — `tree` con la testa e i membri, e la trascrizione delle sue righe `CONFLICT` in prosa e in campi del blocco:

   ```bash
   "PY" -B -I "R/perimeter.py" tree <testa> --children <membri…>
   ```

   La testa è la lista custom o l'epica: il suo task file deve esistere su disco, ed è per questo che la creazione lo scrive prima (§2c). I membri si passano nell'ordine della lista. `tree` legge e basta, nessun file del repo cambia.
2. **Le relazioni, metà del modello** — il task file intero di ogni membro aperto, e `git grep` sui soli path e simboli che due membri nominano, per sapere se cadono sullo stesso file.
3. **Le risorse del ciclo di lavoro** — un publish del plugin, una release o una build del deck, dai DLV dei membri.
4. **Le preferenze dell'utente** — ordine, membri che segue lui, perimetri eseguibili, passi di partenza.
5. **Il file** — `orchestration-schedule.md` nella task folder, col tool `Write`, poi il controllo:

   ```bash
   "PY" -B -I "R/orchestration_schedule.py" verify <testa> --bozza
   ```

   `VERIFY=ok` → la conferma. Un `ERRORE` o un `DIFF` → correggi il piano e rilancia, prima di mostrarlo: un `DIFF` è una relazione che non è diventata un campo. Un `AVVISO` su un `passo` → togli il campo.

Le note che l'analisi produce oltre al piano vanno alla conferma, mai nel file: le dipendenze aperte verso task fuori dal perimetro orchestrabile, le dipendenze non dichiarate, i cicli, i punti ciechi.

## 7. La task folder e le voci di `## Materiale`

**La task folder.** Il piano ci sta dentro, e un perimetro orchestrabile senza folder non ha piano. Se il suo campo `**Folder**` è vuoto la assegna lo script, che sceglie il nome canonico `.YY-MM-DD-<slug>` in project root e mette il task file in stage:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/set-task-folder.sh" <id>
```

La cartella nasce col piano, che il tool `Write` crea con le cartelle intermedie. Un campo già popolato non si riscrive.

**I nomi di prima.** Un perimetro orchestrabile preparato prima del rename porta due nomi vecchi, e questa skill li migra quando ci passa, nei modi modifica ed epica, nello stesso commit del piano:

- **`Size: Mandate`** nell'header → `Size: Custom`, col tool `Edit` sulla sola riga `**Size**`. I lettori trattano i due valori allo stesso modo, quindi la riga cambia nome e non membri.
- **`📁/schedule.md`** → `📁/orchestration-schedule.md`. Se nella task folder c'è il piano col nome di prima e non quello nuovo, spostalo prima della rianalisi, così la storia del file lo segue:

  ```bash
  git mv "<folder>/schedule.md" "<folder>/orchestration-schedule.md"
  ```

  Il piano rifatto (§6) si scrive sul nome nuovo, e il commit porta i due path. Se i due file ci sono entrambi, vale quello nuovo: `schedule.md` si toglie con `git rm` nello stesso commit, e lo dici alla conferma.
- **La voce 🔬 di `## Materiale`** che punta a `📁/schedule.md` si riscrive su `📁/orchestration-schedule.md`: è la sola voce che questa skill riscrive, perché punterebbe a un file che non c'è più.

Si migra solo qui, perché la preparazione è l'unico momento in cui nessun orchestrator è vivo sul file (§0): lo script del flusso di un giro vivo legge col lettore della versione del plugin da cui è partito, e una versione di prima del rename non conosce né `Size: Custom` né `orchestration-schedule.md`. Le migrazioni fatte si dicono alla conferma, una riga ciascuna.

**Le due voci.** Il perimetro orchestrabile porta in `## Materiale` una voce per il piano e una per lo stato dell'orchestrator:

```markdown
- 🔬 `📁/orchestration-schedule.md` — eseguire il giro: analisi del perimetro e piano dello script
- 🎬 `.claude/loom/orchestrator/<id>.md` — seguire il giro dell'orchestrator: fatti del perimetro, proposte in sospeso, delega (fuori da git)
```

- **Sono puntatori per chi legge il task file**, e nient'altro. Lo script del flusso, `verify` e `checkpoint-perimeter` ricavano i path dal campo `**Folder**` e dall'id del perimetro orchestrabile, e non leggono le voci. Lo stato dell'orchestrator può non esserci ancora — l'orchestrator lo crea al primo lancio — e la voce resta valida.
- **Le scrive questa skill**, l'unica che prepara il perimetro orchestrabile: l'orchestrator non scrive nei task file.
- **Una sola volta.** Una voce già presente non si riscrive e non si ripete; una voce 🎬 con una maniglia di prima resta com'è.
- **Dove.** In una lista custom nuova `## Materiale` sta in coda, dopo `## Membri` (§2c). In un file che la sezione non la porta — una lista custom preparata prima, un'epica senza `## Materiale` — la crei con la legenda del template, prima del primo heading fra `## Decisions`, `## Implementation Notes`, `## Testing Notes`, `## Doc Impact`, `## Prod Validation` e `## Progress Log`; in coda se il file non ne porta nessuno. È il punto in cui il task template mette `## Materiale`.
- **Non sono collisioni.** `perimeter.py tree` salta le voci 🎬, e il piano sta nella folder del perimetro orchestrabile, che nessun membro scrive.

## 8. Il controllo finale

Dopo il commit, sul piano committato:

```bash
"PY" -B -I "R/orchestration_schedule.py" verify <testa>
```

`VERIFY=ok` → il piano è pronto per l'orchestrator, e lo dici nella chiusura. `VERIFY=riesame` → un membro è cambiato fra la lettura e il commit, perché un'altra sessione ci lavora: dillo, con i membri `CAMBIATO`, e l'orchestrator li rileggerà al lancio. `VERIFY=stop` dopo un `--bozza` verde vuol dire che il commit non ha preso il piano o il task file: dillo con le righe dello script, senza correggere da qui.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

A lavoro finito, dopo il commit:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "$(say_id <id>) ready"
```
