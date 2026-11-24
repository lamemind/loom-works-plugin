---
name: checkpoint-mandate
description: Checkpoint di un perimetro — un'epica (`Size: Epic`) o un mandato (`Size: Mandate`). Riallinea il task file del perimetro a ciò che i membri hanno fatto e scoperto dall'ultimo avanzamento — legge membri e stato, il diff dei loro task file e i fatti del perimetro che l'orchestrator ha raccolto nel suo stato su disco, porta nella prosa del perimetro bloccanti, collegate, decisioni aperte e regole cambiate, riverifica l'analisi del perimetro e la riscrive se un membro l'ha smentita, toglie le copie di stato e di cifre. Poi aggiorna la Prog e committa il solo file del perimetro con `tasks.md`. Nessuna fase doc, nessuna domanda, nessun task file dei membri toccato. La lancia `checkpoint-task` quando la task è un'epica o un mandato; si invoca anche a mano.
argument-hint: "<epica|mandato> [chiudi]"
allowed-tools: Bash(*), Read, Edit, Grep, Glob, Skill
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

Da qui si leggono due cose: l'**id del perimetro** (`T<numero>`) e la parola **«chiudi»** (§7). Tutto il resto è istruzione libera.

## Il ruolo

Un **perimetro** è il task file di un'epica, che ha per membri le figlie, o di un mandato, che li elenca in `## Membri` (`${CLAUDE_PLUGIN_ROOT}/docs/mandate-format.md`). Il perimetro non ha lavoro proprio: il lavoro e le scoperte stanno nei membri. La sua prosa però parla dei membri — chi blocca chi, quali task fuori dal perimetro contano, quali decisioni restano aperte — e resta indietro appena i membri lavorano.

**Questa skill è l'unico proprietario di quella prosa.** Nessun altro attore la scrive: l'orchestrator per contratto non scrive task file; il checkpoint di un membro aggiorna il proprio task file, la propria riga in `tasks.md` e la propria checkbox nell'Acceptance del padre, e lascia apposta il resto del cappello; la prosa del cappello la scriverebbe solo una sessione sul cappello, e durante un orchestrator non ne gira nessuna.

Confini:

- **I task file dei membri non si toccano mai**, nemmeno per correggere un difetto che il giro trova: il difetto va nelle Segnalazioni, e lo corregge chi lavora su quel membro.
- **Nessuna fase doc.** Un perimetro non rilascia niente, e la doc segue il rilascio dei membri: niente riesame, niente trasloco, niente `drainable`. Le voci del `## Doc Impact` del perimetro restano dove sono e vanno nelle Segnalazioni.
- **Nessuna domanda.** Il comportamento è lo stesso chiunque lanci la skill — l'utente a mano, l'orchestrator a fine giro, il deck —, perché l'unico input oltre all'id è la parola «chiudi», che l'orchestrator non passa mai. Un caso incerto non si chiede: va nelle Segnalazioni.
- **Il commit porta il solo file del perimetro e `tasks.md`**, più il file del padre quando si chiude un'epica che ne ha uno (§7).
- **Nessuna copia di stato o di cifre** nel file del perimetro (`mandate-format.md` §Nessuna copia): il giro le toglie, non le aggiorna.

## 0. Avvio

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" ${taskId}
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

`${taskId}` = l'id delle Note utente; senza, la cascata `$LOOM_TASK → symlink` risolve da sé. Exit non-zero → nessun perimetro risolto: dillo e fermati.

`Read` di `TASK_FILE` per intero. Il `Size` dell'header decide:

- `Epic` o `Mandate` → avanti.
- qualunque altro → stampa `T<id> non è un perimetro: il checkpoint lo fa /loom-works:checkpoint-task T<id>` e fermati. Non invocarla da qui: `checkpoint-task` passa i perimetri a questa skill, e un rimando automatico all'indietro diventa un ciclo al primo `Size` letto male.

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo e fermati: senza Python `mandate.py tree` non gira, e lo stato dei membri e la metà meccanica dell'analisi non si leggono. Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (`PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator`, e lancia ogni script Python con `"PY" -B -I "R/<script>"`.

**Il file del perimetro è pulito:**

```bash
git status --short -- "<TASK_FILE>"
```

Output vuoto → avanti. Altrimenti fermati e dillo: il file ha modifiche non committate, e il commit del giro le porterebbe con sé. Chi le ha scritte le committa o le scarta, poi si rilancia.

`TASK_SRC` non cambia niente: in linked come in detached il giro committa con una pathspec esplicita, perché i file che scrive sono due e li conosce.

## 1. I membri e il loro stato

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <id> --members
"PY" -B -I "R/mandate.py" tree <id> --children <membri, nell'ordine del lettore>
```

I membri vengono dal lettore — le figlie di un'epica, la lista di un mandato —, mai da una lettura a mano. `TASK_MEMBER_MISSING=<id>` è un membro dichiarato senza task file: va nel report come tale, e la lista non si corregge da qui (in un mandato è di `prepare-mandate`, in un'epica del `Parent Task` della figlia).

Da `tree` leggi per ogni membro la Prog (`prog=`), il passo successivo (`next=`), le dipendenze aperte (`blocked=`), le righe `DEPS` e le righe `CONFLICT`. Lo stato viene dalla cella Prog della tabella Tasks Overview, che `tree` legge, **mai dai glifi del grafo**: fra la promozione e il checkpoint i glifi del grafo restano indietro.

Un membro che è a sua volta un'epica o un mandato resta una riga sola: i suoi membri non si leggono qui, è un perimetro a sé col proprio checkpoint.

`TASK_MEMBERS_COUNT=0` non ferma il giro: un mandato appena creato o un'epica senza figlie hanno ancora una prosa e una Prog, e il report lo dice.

## 2. La finestra — cosa è cambiato nei membri

Il giro legge ciò che i membri hanno scritto **dall'ultimo avanzamento del perimetro**:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && partenza=$(lw_task_baseline_sha "<TASK_FILE>") \
  && echo "PARTENZA=${partenza}" \
  && git diff --stat "${partenza}..HEAD" -- <file dei membri>
```

`lw_task_baseline_sha` dà il commit che ha introdotto l'ultimo `### Avanzamento N` del Progress Log del perimetro — l'avanzamento che questa skill scrive (§8) — e, al primo giro, il commit di nascita del file. È l'ancora di ogni task: nessuno sha scritto nel file, nessun marcatore da tenere allineato. Exit non-zero (file mai committato) → dillo e fermati: committa il file del perimetro, poi rilancia.

Per ogni membro che lo `--stat` nomina leggi il suo diff (`git diff <partenza>..HEAD -- <file>`), o il file intero quando è nato dentro la finestra. **Tutto il diff, non solo il Progress Log**: un blocco o una decisione aperta stanno anche in `## Decisions`, nella Description, in `## Dependencies`, nei DLV. Il diff legge `HEAD`: le modifiche non committate di un membro sono il lavoro in corso di un'altra sessione, non ancora un fatto.

**Un fatto del perimetro** è ciò che un membro ha scritto e che riguarda il perimetro intero o un altro membro:

- un **blocco** — il membro non può proseguire finché una task, dentro o fuori dal perimetro, non chiude; una task che blocca i deploy o un rilascio;
- una **collegata** — una task fuori dal perimetro da cui i membri dipendono, o che dipende da loro;
- una **decisione aperta** che tocca più membri, o da prendere prima di un passo del perimetro (un'accensione, un rilascio); e la decisione presa che ne chiude una già scritta nel perimetro;
- una **regola cambiata** — chi può girare in parallelo, in che ordine;
- un **cambio di un membro che smentisce la frase del perimetro che lo descrive**: un DLV tolto, una dipendenza nuova, uno scopo spostato.

Non è un fatto del perimetro il lavoro interno di un membro — DLV spuntati, misure, file toccati —: vive nel membro, e il perimetro al massimo lo punta.

### I fatti dallo stato dell'orchestrator

Un orchestrator sul perimetro raccoglie fatti del perimetro dai report e dai messaggi delle sessioni, e alcuni nessun membro li scrive nel suo task file. Li tiene nel suo stato su disco, in `.claude/loom/orchestrator/T<id>.md` del progetto, fuori da git:

```bash
"PY" -B -I "R/orchestrator_state.py" facts <id>
```

Il path si ricava dall'id del perimetro, non dalla voce 🎬 di `## Materiale`: un perimetro preparato prima che la voce esistesse ha lo stesso uno stato. Lo script legge la testa dello stato — l'identità, `Perimetro: T<id> · Created on <data>`, contro il `Created on` del file del perimetro — e la sola sezione `## Fatti del perimetro`:

| `STATE` | Cosa vuol dire | Cosa fai |
|---|---|---|
| `presente` | lo stato di questo perimetro: una riga `FATTO\|<fatto>` per fatto, poi `FATTI=<n>` | i fatti entrano nel riallineamento (§3) |
| `assente` | nessun orchestrator su questo perimetro, su questa macchina | niente: il giro legge i soli membri |
| `altro` | lo stato di un perimetro passato con lo stesso id: il `Created on` è un altro | niente, e una riga nel report |
| `illeggibile` | il file c'è, la testa non si legge | niente, e una segnalazione |

Un fatto ha la forma `T<n> · <il fatto> · <dove l'ha detto> [· superato: <cosa lo chiude>]`: il membro da cui viene, il fatto, la fonte — report di un run, messaggio, preflight —, e per un fatto chiuso la parola che lo chiude. I fatti dello stato non hanno una finestra: si leggono tutti a ogni giro, aperti e superati, e un fatto già portato si riconosce dal contenuto della prosa (§3).

Lo stato lo scrive solo l'orchestrator, e lo riscrive intero a ogni cambio. **Questa skill non lo scrive mai**, nemmeno per segnare un fatto come portato: una marca la cancellerebbe la riscrittura successiva dell'orchestrator. È un file a un path noto, non un messaggio dell'orchestrator, quindi il giro si comporta uguale chiunque lo lanci. `.claude/loom/` è locale alla macchina: un orchestrator girata su un'altra macchina qui non lascia fatti.

## 3. Il riallineamento della prosa

Il perimetro si riallinea in queste sezioni, e solo in queste:

| Sezione | Cosa ci entra |
|---|---|
| Description | i fatti che toccano il perimetro intero: il paragrafo che descrive un membro, l'ordine delle fasi di un'epica, i bloccanti, le decisioni aperte |
| `## Dependencies` | le collegate fuori dal perimetro da cui dipende il perimetro intero, o che bloccano un suo rilascio |
| `## Preferenze d'ordine` | in un mandato, la regola del giro cambiata: paralleli, ordine |
| `## Analisi del perimetro` | solo col metodo del §4 |
| `## Implementation Notes` | una nota tecnica che vale per tutti i membri |

**Mai** `## Decisions` (la cronaca datata dei preflight del perimetro), `## Membri` (la lista è di `prepare-mandate`), `## Materiale`, `## Doc Impact`, `## Deliverables Checklist`, `## Prod Validation`. In `## Acceptance Criteria` solo le checkbox del §6.

**Un fatto nuovo entra nel paragrafo che tratta il suo tema**; se nessun paragrafo lo tratta, in uno nuovo della Description. Le decisioni aperte stanno in un paragrafo che comincia con `**Decisioni aperte.**`, creato al primo fatto di quel tipo e tolto quando l'ultima esce. Il fatto si scrive al presente, come stato delle cose, col puntatore al membro che lo porta — `T<n> (<maniglia>)` e la sezione dove l'ha scritto — e senza data: chi legge il perimetro ritrova la fonte, e la frase resta vera finché il membro non cambia.

**Una frase che il diff smentisce si riscrive**: la Description dice che un membro dipende da un altro solo, e le sue `## Dependencies` ne nominano tre; una decisione aperta che un membro ha preso esce dal paragrafo delle decisioni aperte. La frase si confronta coi membri cambiati nella finestra: la prosa sugli altri l'ha già riallineata il giro precedente, o l'ha scritta un umano dopo.

**I fatti dallo stato dell'orchestrator** (§2) entrano con le stesse regole, più tre:

- **Un fatto aperto entra se la prosa non lo porta già.** Lo stesso blocco, la stessa decisione aperta, scritti con parole diverse, sono lo stesso fatto e non si riscrivono: è ciò che tiene senza effetti un secondo giro sullo stesso stato. Il puntatore va al membro da cui viene il fatto, e la fonte è quella che la riga dello stato nomina.
- **Un fatto superato chiude e basta.** Se la prosa porta la frase del fatto aperto, la riscrive o la toglie: il blocco caduto esce dal paragrafo che lo porta, la decisione presa esce da `**Decisioni aperte.**`. Se la prosa non la porta, un blocco nato e caduto fra due checkpoint non scrive niente; una decisione presa o una regola cambiata entrano come stato presente, senza dire che prima erano aperte.
- **Un fatto aperto che i file smentiscono vale come superato**: un blocco su una task che `tree` dà ✔️, una decisione che il `## Decisions` del membro ha già congelato. Nel dubbio non entra, e va nelle Segnalazioni.

**Riallineare non vuol dire riassumere.** Il resto della prosa — visione, perimetro, ragioni — resta com'è, parola per parola: il giro tocca le frasi che un fatto smentisce o completa, e nient'altro.

## 4. L'analisi del perimetro

**La sezione `## Analisi del perimetro` non c'è** → non la crei. Il report porta la riga `analisi del perimetro assente: la scrive /loom-works:prepare-mandate <id>`, l'unica skill che la scrive da zero.

**La sezione c'è** → la riverifichi, in due metà:

1. **Meccanica.** Il confronto fra le righe `dichiarata` e `materiale` della tabella e il calcolo di `tree` lo fa lo script, coi membri del §1:

   ```bash
   "PY" -B -I "R/mandate.py" verify <id> --children <membri, nell'ordine del lettore>
   ```

   Ogni riga `DIFF|<tipo>|<coppia>|<dettaglio>` è una divergenza: `manca` (una `CONFLICT` di `tree` senza la sua riga, o un path calcolato che la riga non cita), `in più` (una riga `dichiarata` o `materiale` che `tree` non calcola più), `fuori` (una riga su una task che non è un membro aperto), `forma` (una riga fuori dal formato), `membri` (la `## Membri` di un mandato cambiata dopo il commit dell'analisi). Nessuna riga `DIFF` → la metà meccanica combacia. Una riga con un membro chiuso non è una divergenza: lo script la salta, perché `tree` tace sulle task chiuse e la riga resta scritta. Le righe `CAMBIATO` qui non servono: i membri da rileggere li dà la finestra del §2.
2. **Del modello.** Per ogni membro cambiato nella finestra: le righe `modello` che lo nominano reggono ancora — il suo task file nomina ancora quel file, quel simbolo, quel comportamento? E le sue coppie con gli altri membri aperti hanno una collisione nuova? Il metodo è `${CLAUDE_PLUGIN_ROOT}/docs/mandate-analysis.md` §La metà del modello. I membri non cambiati nella finestra non si rileggono: le loro coppie le ha già viste chi ha scritto la sezione.

Nessuna divergenza → la sezione resta intatta, e il report dice `analisi confermata`.

Una divergenza → la sezione si **riscrive intera** col metodo di `mandate-analysis.md` §La rianalisi, lo stesso di `prepare-mandate`: leggi il documento per intero prima di riscrivere. Nessuna conferma da chiedere: la differenza riga per riga (`=` `+` `-` `~`) va nel report, con le note che il metodo manda alla conferma — dipendenze aperte verso task fuori dal perimetro, punti ciechi. Una dipendenza non dichiarata è un difetto del task file di un membro, e va nelle Segnalazioni.

## 5. Le copie

Leggi il file del perimetro intero a ogni giro, anche con la finestra vuota, e cerca nelle sezioni del §3:

- **stato dei membri** — una colonna o una cella di stato, un glifo di Prog (🔵 🟢 🟡 ✔️ 🔒) accanto a un id, «chiusa», «in corso», «fatta» detto di un membro;
- **cifre ricopiate da un membro** — DLV contati, misure, conteggi, percentuali, stime sommate;
- **schemi** — alberi, liste, diagrammi — che segnano un componente come chiuso o aperto.

Una copia **si toglie, non si aggiorna**: aggiornata resterebbe indietro alla prima modifica del membro, chiunque fosse il suo proprietario. Dove la copia portava un'informazione che serve resta il puntatore: l'id con la maniglia, «la misura sta nel Progress Log di T<n> (<maniglia>)». Lo stato lo dà `tasks.md`, le cifre `recap-status-epic`.

Non sono copie: le checkbox per figlia nell'Acceptance di un'epica (hanno un custode, §6), il Progress Log del perimetro (è la sua storia), `## Decisions` (cronaca datata, non si tocca), l'analisi del perimetro (descrive relazioni fra membri, non il loro stato).

Una copia in una sezione che il giro non scrive — un glifo in `## Membri`, una checkbox per membro in un mandato — resta com'è e va nelle Segnalazioni.

## 6. Le checkbox dell'epica

**Solo in un'epica.** Ogni riga dell'Acceptance che nomina una figlia con Prog ✔️ (da `tree`) e porta ancora `[ ]` passa a `[x]`: il checkpoint della figlia doveva spuntarla e non l'ha fatto. Matcha sull'id, il primo `T<numero>` della riga, e riscrivi solo il box, lasciando maniglia e testo intatti.

Una riga `[x]` su una figlia che non è ✔️ — una figlia riaperta — resta com'è, e va nelle Segnalazioni.

**In un mandato nessuna checkbox si tocca**: il formato non ne vuole, perché il checkpoint di un membro spunta solo la checkbox del proprio `Parent Task` e nessuno terrebbe le altre allineate. Se il mandato ne porta, sono copie fuori dal §3: Segnalazioni.

## 7. La Prog e la chiusura

**Il perimetro si chiude** — Prog ✔️ — in casi diversi per le due forme:

| Forma | Si chiude quando |
|---|---|
| epica | tutta `## Acceptance Criteria` è `[x]` dopo il §6, oppure le Note utente portano «chiudi» |
| mandato | solo quando le Note utente portano «chiudi», anche con tutti i membri ✔️ |

`## Prod Validation` non conta. Un mandato non si chiude da sé perché la sua chiusura non deriva dai membri: dice che il giro per cui è nato è finito, e lo decide chi l'ha aperto. L'orchestrator non passa parole al checkpoint, quindi non chiude mai un perimetro.

La cella Prog si legge e si scrive con le primitive di `lib.sh`, che trovano la colonna dall'header della Tasks Overview e non toccano le tabelle sotto:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" && lw_tasks_md_prog_get "{docs_root}/tasks.md" <id>
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" && lw_tasks_md_prog_set "{docs_root}/tasks.md" <id> <glifo>
```

`lw_tasks_md_prog_get` vuoto → la riga del perimetro non c'è: `tasks.md` non si tocca, e il report lo dice.

**Alla chiusura**, in quest'ordine:

1. Header del file: `- **Progress**: ✔️ Done`. La data la aggiunge lo script del commit (§9), che riscrive la riga in `✔️ Done at <data>`.
2. Prog ✔️ in `tasks.md`; se il perimetro compare nel grafo dell'Execution Plan, allinea l'emoji davanti al suo id.
3. Se il symlink `{docs_root}/current-task.md` risolve a questo file, eliminalo (`rm`). Se punta altrove, o non esiste, non toccarlo: è il binding di un'altra task.
4. Se l'header porta `**Parent Task**: T<n>`, nel file del padre la checkbox della riga che porta l'id del perimetro passa a `[x]` — matcha sull'id, riscrivi solo il box — e il file del padre entra nella pathspec del §9. È la stessa regola di `checkpoint-task`: alla chiusura di una task il suo checkpoint spunta la riga del padre. Nessuna riga con l'id → un avviso nel report, nessun blocco.

**Senza chiusura**, la Prog dice se il lavoro del perimetro è cominciato:

- Prog 🔵 o 🟢 e almeno un membro 🟡 o ✔️ → 🟡 in `tasks.md` e nel grafo, `- **Progress**: 🟡 In Progress` nell'header.
- Prog 🔵 o 🟢 e nessun membro avviato → resta com'è.
- Prog 🟡 → resta.
- Prog ✔️ → resta. Un perimetro chiuso non si riapre dal checkpoint: se la condizione di chiusura non vale più — un'epica con una figlia nuova e la sua checkbox `[ ]` — il report lo dice, e la riapertura la decide l'umano.

## 8. L'avanzamento

Se il giro ha cambiato il file del perimetro, **o** la finestra del §2 non era vuota, appendi al Progress Log del perimetro (crea `## Progress Log` in coda al file se non c'è):

```markdown
### Avanzamento <N>
- Descrizione: <cosa il giro ha portato nel file — fatti nuovi col membro da cui vengono e la fonte (diff del membro o stato dell'orchestrator), frasi riscritte, copie tolte, checkbox spuntate, analisi confermata o riscritta, Prog — oppure «nessun fatto del perimetro» sulla finestra letta>
```

`<N>` = il massimo dei `### Avanzamento` esistenti più uno. L'header non è cosmetico: è l'ancora della finestra del giro dopo (§2), e scritto in un'altra forma la riporta alla nascita del file.

L'avanzamento si scrive anche quando la finestra non porta fatti del perimetro: sposta la partenza in avanti, così il giro dopo non rilegge lo stesso diff.

**Finestra vuota e file intatto → nessun avanzamento e nessun commit.** Il giro non ha letto niente di nuovo e non ha cambiato niente: è il secondo giro sullo stesso perimetro senza lavoro dei membri in mezzo, e deve restare un no-op, chiunque lo lanci. I fatti dello stato dell'orchestrator che la prosa porta già non cambiano il file; un fatto nuovo dallo stato, con la finestra vuota, lo cambia, e l'avanzamento si scrive.

## 9. Commit e push

Gira se il giro ha cambiato il file del perimetro. La pathspec la componi tu, e nomina **sempre** il file del perimetro:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh" --task <id> "checkpoint(<id>): <sintesi del giro>" \
  -- "<TASK_FILE>" ["{docs_root}/tasks.md"] [<file del padre>]
```

- **Il file del perimetro va scritto dopo `--` anche se `--task` lo aggiunge da sé.** Con una pathspec vuota lo script cade nel regime linked e fa `git add -A`, che porterebbe nel commit tutto il worktree (in detached esce in errore).
- **`tasks.md` entra solo se il giro ne ha riscritto la cella** (§7). È un file condiviso: nominato senza averlo toccato, porterebbe nel commit le modifiche non committate di un'altra sessione.
- **Il file del padre** entra solo alla chiusura di un perimetro con `Parent Task` (§7).
- **`--task`** è obbligatorio anche in linked: alla chiusura il symlink può essere sparito.
- Nessun `--doc-message`: il giro non scrive file doc, e lo script fa un commit solo.

Lo script committa e pusha, e stampa `-> commit 1 (codice+tracking, …): <sha>`. Exit non-zero → commit o push falliti: niente hook, ping `failed`, e il report lo dice.

**Hook `taskDone`** — solo se il §7 ha chiuso il perimetro in questo giro, dopo il push riuscito:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" hooks taskDone --task <id> --sha <sha>
```

Un progetto che lega una skill alla chiusura di una task la riceve anche per un perimetro. `deliverableDone` non parte mai: un perimetro non ha DLV.

- **Nessuna riga, exit 0** → il progetto non dichiara hook su `taskDone`.
- **Righe `HOOK|<i>|<skill>` e una riga `ARGS=<argomenti>`** → per ogni `HOOK`, nell'ordine di `<i>`, invoca il tool `Skill` con `skill` = `<skill>` e `args` = il valore di `ARGS` copiato tale e quale, una skill alla volta.
- **Exit non-zero** → nessuna skill: il messaggio nomina il guasto (blocco `hooks` invalido, jq assente, task o sha non risolvibili).

Un hook non riapre niente: commit e push sono già avvenuti. Una skill che non esiste, che dà errore o che dichiara un fallimento produce un avviso in linea — `⚠ hook <skill> fallito su taskDone: <motivo>` — e una segnalazione (`hook <skill> fallito su taskDone: <motivo>`, o `hook taskDone non invocati: <messaggio dello script>`); le skill successive girano comunque, e nessuna si ritenta: un hook fallito a metà può aver già scritto fuori dal repo. Ciò che la skill hook fa resta suo, e nessun suo file entra nel commit del giro.

## Il report

In quest'ordine:

- `🧭 Perimetro: <id> — epica|mandato, <n> membri`, i membri senza task file se ci sono, la finestra (`<partenza corta>..HEAD`) e i membri cambiati dentro;
- lo **stato dell'orchestrator**: `presente, <n> fatti` · `assente` · `altro (Created on <data>)` · `illeggibile`;
- i **fatti portati nel file**, uno per riga: il fatto, il membro da cui viene, la fonte (diff del membro o stato dell'orchestrator), la sezione dove è entrato;
- le **frasi riscritte** e le **copie tolte**;
- l'**analisi**: confermata, riscritta (la differenza riga per riga e le note del metodo), o assente col rimando;
- le **checkbox** spuntate, in un'epica;
- la **Prog**, da → a, e se il perimetro si è chiuso; gli hook `taskDone` invocati, col loro esito;
- il **commit**, o `nessun commit: niente di nuovo dall'avanzamento <N>`;
- la sezione `🚦 Segnalazioni`, sempre.

Poi il ping:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "checkpoint $(say_id <id>) done"
```

In caso di errore nel commit o nel push: `say_auto "checkpoint $(say_id <id>) failed"`.

## 🚦 Segnalazioni

La sezione chiude il report sempre, anche vuota: a zero segnalazioni è la riga `**🚦 Segnalazioni** — nessuna`. Altrimenti:

```
**🚦 Segnalazioni**

**S{N}** — <la segnalazione, su una riga>
  subito · task · scarto · ignora
```

Il contratto completo — forma, sede degli scenari, risposta, uscite, uscita in un altro progetto — è `${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md`. Qui le regole per stampare la sezione:

- `S{N}` numera da 1 dentro questo report; il testo dopo `— ` è quello che lo scenario cita byte per byte.
- **Prima di stampare interroga il registro ADR** su ogni segnalazione (`adr.sh cerca`, regola in contesto): exit `0` vuol dire già scartata con un motivo, e non la riporti.
- **Tu non scarti e non ignori**: ogni segnalazione esce con le quattro uscite.
- **Ogni voce di `## Doc Impact` del perimetro è una segnalazione**, una per voce: `**S{N}** — voce di Doc Impact del perimetro, «<la nozione in breve>»: la rilascia T<n> (<maniglia>)`. Il membro che la rilascia è quello il cui lavoro rende vero il fatto: lo trovi confrontando l'ancora della voce coi DLV e col `## Materiale` dei membri. Se nessun membro la rilascia, la riga dice `nessun membro la rilascia`. La voce resta nel file: spostarla è una decisione dell'umano.
- Sono segnalazioni anche: un caso incerto che il giro non ha deciso (un fatto che non sai dove scrivere, una frase che non sai se il diff smentisce, un fatto dello stato dell'orchestrator che i file forse smentiscono); uno stato dell'orchestrator `illeggibile`; un difetto nel task file di un membro (una dipendenza non dichiarata, una copia di stato); una copia o una checkbox in una sezione che il giro non scrive; una figlia `[x]` non chiusa; un hook `taskDone` fallito (§9).
- Il giro non corregge niente di sua iniziativa fuori dalle sezioni che possiede, quindi non stampa righe `☑ subito (agente)`.

**La risposta dell'umano** è prosa libera, e la leggi nel turno dopo. Prima di scrivere il primo scenario apri `triage-format.md` per intero: le regole della risposta — nessun default, l'approfondimento alla lettera, «subito» e «task» operativi, lo scarto col perché, l'ignora con l'ancora, l'uscita in un altro progetto — sono quelle, identiche a `run-task` e `checkpoint-task`. Ogni scenario:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano \
  --momento flusso --skill checkpoint-mandate [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'umano su quella segnalazione>
SCENARIO
```

**Una risposta firmata «decise dall'orchestrator di T<perimetro> su delega dell'utente»** porta sotto la firma le parole con cui l'umano ha delegato l'orchestrator, alla lettera: ogni scenario si scrive con `--chi delega` e quelle parole intere in `--delega`, con le regole dell'umano per il resto (`triage-format.md` §La decisione su delega). Firma senza le parole → nessuno scenario, e lo dici nel testo finale: non ripieghi su `umano` né su `agente`.

```bash
DELEGA="$(cat <<'DELEGA'
<le parole della delega, dalla riga sotto la firma, intere>
DELEGA
)"
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi delega \
  --delega "$DELEGA" --momento flusso --skill checkpoint-mandate [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'orchestrator su quella segnalazione>
SCENARIO
```

Poi un commit solo per tutti, coi path che lo script stampa:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && lw_git_add_n_commit "triage(<id>): <N> scenari" <path>... \
  && lw_git_push "$(lw_current_branch)"
```

Un'uscita decisa dall'umano si esegue come dicono le sue parole, anche fuori dai confini del giro: «subito, spostala in T<n>» sposta la voce nella sede delle nozioni della figlia, con un commit a sé. Il confine «i task file dei membri non si toccano» vale per il flusso del checkpoint, non per un'azione che l'umano ordina.
