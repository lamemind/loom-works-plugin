---
name: checkpoint-perimeter
description: Checkpoint di un perimetro orchestrabile — un'epica (`Size: Epic`) o una lista custom (`Size: Custom`). Riallinea il task file del perimetro orchestrabile a ciò che i membri hanno fatto e scoperto dall'ultimo avanzamento — legge membri e stato, il diff dei loro task file e i fatti del perimetro orchestrabile che l'orchestrator ha raccolto nel suo stato su disco, porta nella prosa di quel file bloccanti, collegate, decisioni aperte e regole cambiate, toglie le copie di stato e di cifre, e dice se il piano (`orchestration-schedule.md`) vale ancora, senza riscriverlo. Poi aggiorna la Prog e committa il solo file del perimetro orchestrabile con `tasks.md`. Nessuna fase doc, nessuna domanda, nessun task file dei membri toccato. La lancia `checkpoint-task` quando la task è un'epica o una lista custom; si invoca anche a mano.
argument-hint: "<epica|lista custom> [chiudi]"
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

Da qui si leggono due cose: l'**id del perimetro orchestrabile** (`T<numero>`) e la parola **«chiudi»** (§7). Tutto il resto è istruzione libera.

## Il ruolo

Un **perimetro orchestrabile** è il task file di un'epica, che ha per membri le figlie, o di una lista custom, che li elenca in `## Membri` (`${CLAUDE_PLUGIN_ROOT}/docs/perimeter-format.md`). Non ha lavoro proprio: il lavoro e le scoperte stanno nei membri. La sua prosa però parla dei membri — chi blocca chi, quali task fuori dal perimetro orchestrabile contano, quali decisioni restano aperte — e resta indietro appena i membri lavorano.

**Questa skill è l'unico proprietario di quella prosa.** Nessun altro attore la scrive: l'orchestrator per contratto non scrive task file; il checkpoint di un membro aggiorna il proprio task file, la propria riga in `tasks.md` e la propria checkbox nell'Acceptance del padre, e lascia apposta il resto del cappello; la prosa del cappello la scriverebbe solo una sessione sul cappello, e durante un orchestrator non ne gira nessuna.

Confini:

- **I task file dei membri non si toccano mai**, nemmeno per correggere un difetto che il giro trova: il difetto va nelle Segnalazioni, e lo corregge chi lavora su quel membro.
- **Nessuna fase doc.** Un perimetro orchestrabile non rilascia niente, e la doc segue il rilascio dei membri: niente riesame, niente trasloco, niente `drainable`. Le voci del suo `## Doc Impact` restano dove sono e vanno nelle Segnalazioni.
- **Nessuna domanda.** Il comportamento è lo stesso chiunque lanci la skill — l'utente a mano, l'orchestrator a fine giro, il deck —, perché l'unico input oltre all'id è la parola «chiudi», che l'orchestrator non passa mai. Un caso incerto non si chiede: va nelle Segnalazioni.
- **Il commit porta il solo file del perimetro orchestrabile e `tasks.md`**, più il file del padre quando si chiude un'epica che ne ha uno (§7).
- **Nessuna copia di stato o di cifre** nel file del perimetro orchestrabile (`perimeter-format.md` §Nessuna copia): il giro le toglie, non le aggiorna.

## 0. Avvio

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" ${taskId}
for candidate in python3 python; do "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' 2>/dev/null && { command -v "$candidate"; break; }; done
```

`${taskId}` = l'id delle Note utente; senza, la cascata `$LOOM_TASK → symlink` risolve da sé. Exit non-zero → nessun perimetro orchestrabile risolto: dillo e fermati.

`Read` di `TASK_FILE` per intero. Il `Size` dell'header decide:

- `Epic`, `Custom` o `Mandate` (il nome di prima di `Custom`) → avanti.
- qualunque altro → stampa `T<id> non è un perimetro orchestrabile: il checkpoint lo fa /loom-works:checkpoint-task T<id>` e fermati. Non invocarla da qui: `checkpoint-task` passa i perimetri orchestrabili a questa skill, e un rimando automatico all'indietro diventa un ciclo al primo `Size` letto male.

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo e fermati: senza Python `perimeter.py tree` e `orchestration_schedule.py verify` non girano, e lo stato dei membri e il piano non si leggono. Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (`PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator`, e lancia ogni script Python con `"PY" -B -I "R/<script>"`.

**Il file del perimetro orchestrabile è pulito:**

```bash
git status --short -- "<TASK_FILE>"
```

Output vuoto → avanti. Altrimenti fermati e dillo: il file ha modifiche non committate, e il commit del giro le porterebbe con sé. Chi le ha scritte le committa o le scarta, poi si rilancia.

`TASK_SRC` non cambia niente: in linked come in detached il giro committa con una pathspec esplicita, perché i file che scrive sono due e li conosce.

## 1. I membri e il loro stato

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh" <id> --members
"PY" -B -I "R/perimeter.py" tree <id> --children <membri, nell'ordine del lettore>
```

I membri vengono dal lettore — le figlie di un'epica, quelli elencati da una lista custom —, mai da una lettura a mano. `TASK_MEMBER_MISSING=<id>` è un membro dichiarato senza task file: va nel report come tale, e la lista non si corregge da qui (in una lista custom è di `prepare-perimeter`, in un'epica del `Parent Task` della figlia).

Da `tree` leggi per ogni membro la Prog (`prog=`), il passo successivo (`next=`), le dipendenze aperte (`blocked=`), le righe `DEPS` e le righe `CONFLICT`. Lo stato viene dalla cella Prog della tabella Tasks Overview, che `tree` legge, **mai dai glifi del grafo**: `promote-ready`, `promote-wip` e `checkpoint-task` riscrivono il glifo del grafo insieme alla cella, ma il grafo resta una copia, che manca per una task assente dal grafo e resta indietro su un nodo in una forma che `lw_tasks_md_graph_set` non riconosce.

Un membro che è a sua volta un'epica o una lista custom resta una riga sola: i suoi membri non si leggono qui, è un perimetro orchestrabile a sé col proprio checkpoint.

`TASK_MEMBERS_COUNT=0` non ferma il giro: una lista custom appena creata o un'epica senza figlie hanno ancora una prosa e una Prog, e il report lo dice.

## 2. La finestra — cosa è cambiato nei membri

Il giro legge ciò che i membri hanno scritto **dall'ultimo avanzamento del perimetro orchestrabile**:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && partenza=$(lw_task_baseline_sha "<TASK_FILE>") \
  && echo "PARTENZA=${partenza}" \
  && git diff --stat "${partenza}..HEAD" -- <file dei membri>
```

`lw_task_baseline_sha` dà il commit che ha introdotto l'ultimo `### Avanzamento N` del Progress Log del perimetro orchestrabile — l'avanzamento che questa skill scrive (§8) — e, al primo giro, il commit di nascita del file. È l'ancora di ogni task: nessuno sha scritto nel file, nessun marcatore da tenere allineato. Exit non-zero (file mai committato) → dillo e fermati: committa il file del perimetro orchestrabile, poi rilancia.

Per ogni membro che lo `--stat` nomina leggi il suo diff (`git diff <partenza>..HEAD -- <file>`), o il file intero quando è nato dentro la finestra. **Tutto il diff, non solo il Progress Log**: un blocco o una decisione aperta stanno anche in `## Decisions`, nella Description, in `## Dependencies`, nei DLV. Il diff legge `HEAD`: le modifiche non committate di un membro sono il lavoro in corso di un'altra sessione, non ancora un fatto.

**Un fatto del perimetro orchestrabile** è ciò che un membro ha scritto e che riguarda il perimetro orchestrabile intero o un altro membro:

- un **blocco** — il membro non può proseguire finché una task, dentro o fuori dal perimetro orchestrabile, non chiude; una task che blocca i deploy o un rilascio;
- una **collegata** — una task fuori dal perimetro orchestrabile da cui i membri dipendono, o che dipende da loro;
- una **decisione aperta** che tocca più membri, o da prendere prima di un passo del perimetro orchestrabile (un'accensione, un rilascio); e la decisione presa che ne chiude una già scritta nella prosa del perimetro orchestrabile;
- una **regola cambiata** — chi può girare in parallelo, in che ordine;
- un **cambio di un membro che smentisce la frase del perimetro orchestrabile che lo descrive**: un DLV tolto, una dipendenza nuova, uno scopo spostato.

Non è un fatto del perimetro orchestrabile il lavoro interno di un membro — DLV spuntati, misure, file toccati —: vive nel membro, e il perimetro orchestrabile al massimo lo punta.

### I fatti dallo stato dell'orchestrator

Un orchestrator raccoglie fatti del perimetro orchestrabile dai report dei turni dei membri e dai loro messaggi, e alcuni nessun membro li scrive nel suo task file. Li tiene nella sua memoria su disco, in `.claude/loom/orchestrator/T<id>.md` del progetto, fuori da git:

```bash
"PY" -B -I "R/orchestrator_state.py" facts <id>
```

Il path si ricava dall'id del perimetro orchestrabile, non dalla voce 🎬 di `## Materiale`: un perimetro orchestrabile preparato prima che la voce esistesse ha lo stesso uno stato. Lo script legge la testa dello stato — l'identità, `Perimetro: T<id> · Created on <data>`, contro il `Created on` del file del perimetro orchestrabile — e la sola sezione `## Fatti del perimetro`:

| `STATE` | Cosa vuol dire | Cosa fai |
|---|---|---|
| `presente` | lo stato di questo perimetro orchestrabile: una riga `FATTO\|<fatto>` per fatto, poi `FATTI=<n>` | i fatti entrano nel riallineamento (§3) |
| `assente` | nessun orchestrator su questo perimetro orchestrabile, su questa macchina | niente: il giro legge i soli membri |
| `altro` | lo stato di un perimetro orchestrabile passato con lo stesso id: il `Created on` è un altro | niente, e una riga nel report |
| `illeggibile` | il file c'è, la testa non si legge | niente, e una segnalazione |

Un fatto ha la forma `T<n> · <il fatto> · <dove l'ha detto> [· superato: <cosa lo chiude>]`: il membro da cui viene, il fatto, la fonte — report di un run, messaggio, preflight —, e per un fatto chiuso la parola che lo chiude. I fatti dello stato non hanno una finestra: si leggono tutti a ogni giro, aperti e superati, e un fatto già portato si riconosce dal contenuto della prosa (§3).

Lo stato lo scrive solo l'orchestrator, e lo riscrive intero a ogni cambio. **Questa skill non lo scrive mai**, nemmeno per segnare un fatto come portato: una marca la cancellerebbe la riscrittura successiva dell'orchestrator. È un file a un path noto, non un messaggio dell'orchestrator, quindi il giro si comporta uguale chiunque lo lanci. `.claude/loom/` è locale alla macchina: un orchestrator girato su un'altra macchina qui non lascia fatti.

## 3. Il riallineamento della prosa

Il perimetro orchestrabile si riallinea in queste sezioni, e solo in queste:

| Sezione | Cosa ci entra |
|---|---|
| Description | i fatti che toccano il perimetro orchestrabile intero: il paragrafo che descrive un membro, l'ordine delle fasi di un'epica, i bloccanti, le decisioni aperte |
| `## Dependencies` | le collegate da cui dipende il perimetro orchestrabile intero, o che bloccano un suo rilascio |
| `## Implementation Notes` | una nota tecnica che vale per tutti i membri |

**Mai** `## Decisions` (la cronaca datata dei preflight del perimetro orchestrabile), `## Membri` (la lista è di `prepare-perimeter`), `## Materiale`, `## Doc Impact`, `## Deliverables Checklist`, `## Prod Validation`. In `## Acceptance Criteria` solo le checkbox del §6. **Mai il piano**, `orchestration-schedule.md` nella task folder, o `schedule.md` in un perimetro orchestrabile preparato prima del rename: lo scrivono `prepare-perimeter` prima del giro e l'orchestrator durante, e una regola d'ordine cambiata va lì, non nella prosa del perimetro orchestrabile. **Mai** le sezioni `## Analisi del perimetro` e `## Preferenze d'ordine` di un perimetro orchestrabile preparato prima del piano: il loro posto è il piano, e le sposta `prepare-perimeter` (§4).

Una **regola cambiata** — chi gira in parallelo, in che ordine — non entra nella prosa: la porta il piano, e una seconda copia resterebbe indietro alla prima riscrittura del piano. Se il piano non la porta ancora, va nelle Segnalazioni, col membro da cui viene e il rimando a `/loom-works:prepare-perimeter <id>`.

**Un fatto nuovo entra nel paragrafo che tratta il suo tema**; se nessun paragrafo lo tratta, in uno nuovo della Description. Le decisioni aperte stanno in un paragrafo che comincia con `**Decisioni aperte.**`, creato al primo fatto di quel tipo e tolto quando l'ultima esce. Il fatto si scrive al presente, come stato delle cose, col puntatore al membro che lo porta — `T<n> (<maniglia>)` e la sezione dove l'ha scritto — e senza data: chi legge il perimetro orchestrabile ritrova la fonte, e la frase resta vera finché il membro non cambia.

**Una frase che il diff smentisce si riscrive**: la Description dice che un membro dipende da un altro solo, e le sue `## Dependencies` ne nominano tre; una decisione aperta che un membro ha preso esce dal paragrafo delle decisioni aperte. La frase si confronta coi membri cambiati nella finestra: la prosa sugli altri l'ha già riallineata il giro precedente, o l'ha scritta un umano dopo.

**I fatti dallo stato dell'orchestrator** (§2) entrano con le stesse regole, più tre:

- **Un fatto aperto entra se la prosa non lo porta già.** Lo stesso blocco, la stessa decisione aperta, scritti con parole diverse, sono lo stesso fatto e non si riscrivono: è ciò che tiene senza effetti un secondo giro sullo stesso stato. Il puntatore va al membro da cui viene il fatto, e la fonte è quella che la riga dello stato nomina.
- **Un fatto superato chiude e basta.** Se la prosa porta la frase del fatto aperto, la riscrive o la toglie: il blocco caduto esce dal paragrafo che lo porta, la decisione presa esce da `**Decisioni aperte.**`. Se la prosa non la porta, un blocco nato e caduto fra due checkpoint non scrive niente; una decisione presa entra come stato presente, senza dire che prima era aperta.
- **Un fatto aperto che i file smentiscono vale come superato**: un blocco su una task che `tree` dà ✔️, una decisione che il `## Decisions` del membro ha già congelato. Nel dubbio non entra, e va nelle Segnalazioni.

**Riallineare non vuol dire riassumere.** Il resto della prosa — visione, perimetro, ragioni — resta com'è, parola per parola: il giro tocca le frasi che un fatto smentisce o completa, e nient'altro.

## 4. Il piano

Il piano del perimetro orchestrabile — `orchestration-schedule.md` nella task folder, l'analisi delle relazioni fra i membri e l'ordine del giro (`${CLAUDE_PLUGIN_ROOT}/docs/orchestration-schedule-format.md`) — non lo scrive questa skill: lo scrive `prepare-perimeter` prima del giro, e l'orchestrator lo riscrive durante. Il giro dice solo se vale ancora, perché chi lancia il prossimo orchestrator lo sappia dal report:

```bash
"PY" -B -I "R/orchestration_schedule.py" verify <id>
```

| `VERIFY` | Cosa vuol dire | Nel report |
|---|---|---|
| `ok` | il piano combacia coi file, e nessun membro aperto è cambiato dopo il suo commit | `piano: ok` |
| `riesame` | combacia, e dei membri aperti sono cambiati dopo il commit: chi lancia il giro li rilegge | `piano: riesame`, coi membri delle righe `CAMBIATO` |
| `stop` | il piano manca, non si legge, non è committato o non copre una relazione fra i membri | `piano: stop`, le righe `ERRORE` e `DIFF` per esteso, e il rimedio `/loom-works:prepare-perimeter <id>` |

Le righe `AVVISO` vanno nel report come sono. Un'uscita `1` — il lettore dei membri che non risponde — va nel report col messaggio dello script: il giro prosegue, perché il piano non entra in nessuna sezione che il giro scrive.

**Un perimetro orchestrabile preparato prima del piano** porta ancora nel task file `## Analisi del perimetro` o `## Preferenze d'ordine`. Il giro non le tocca e non le riscrive: il report dice `sezioni fuori formato: le sposta nel piano /loom-works:prepare-perimeter <id>`.

## 5. Le copie

Leggi il file del perimetro orchestrabile intero a ogni giro, anche con la finestra vuota, e cerca nelle sezioni del §3:

- **stato dei membri** — una colonna o una cella di stato, un glifo di Prog (🔵 🟢 🟡 ✔️ 🔒) accanto a un id, «chiusa», «in corso», «fatta» detto di un membro;
- **cifre ricopiate da un membro** — DLV contati, misure, conteggi, percentuali, stime sommate;
- **schemi** — alberi, liste, diagrammi — che segnano un componente come chiuso o aperto.

Una copia **si toglie, non si aggiorna**: aggiornata resterebbe indietro alla prima modifica del membro, chiunque fosse il suo proprietario. Dove la copia portava un'informazione che serve resta il puntatore: l'id con la maniglia, «la misura sta nel Progress Log di T<n> (<maniglia>)». Lo stato lo dà `tasks.md`, le cifre `recap-status-epic`.

Non sono copie: le checkbox per figlia nell'Acceptance di un'epica (hanno un custode, §6), il Progress Log del perimetro orchestrabile (è la sua storia), `## Decisions` (cronaca datata, non si tocca).

Una copia in una sezione che il giro non scrive — un glifo in `## Membri`, una checkbox per membro in una lista custom — resta com'è e va nelle Segnalazioni.

## 6. Le checkbox dell'epica

**Solo in un'epica.** Ogni riga dell'Acceptance che nomina una figlia con Prog ✔️ (da `tree`) e porta ancora `[ ]` passa a `[x]`: il checkpoint della figlia doveva spuntarla e non l'ha fatto. Matcha sull'id, il primo `T<numero>` della riga, e riscrivi solo il box, lasciando maniglia e testo intatti.

Una riga `[x]` su una figlia che non è ✔️ — una figlia riaperta — resta com'è, e va nelle Segnalazioni.

**In una lista custom nessuna checkbox si tocca**: il formato non ne vuole, perché il checkpoint di un membro spunta solo la checkbox del proprio `Parent Task` e nessuno terrebbe le altre allineate. Se la lista custom ne porta, sono copie fuori dal §3: Segnalazioni.

## 7. La Prog e la chiusura

**Il perimetro orchestrabile si chiude** — Prog ✔️ — in casi diversi per le due forme:

| Forma | Si chiude quando |
|---|---|
| epica | tutta `## Acceptance Criteria` è `[x]` dopo il §6, oppure le Note utente portano «chiudi» |
| lista custom | solo quando le Note utente portano «chiudi», anche con tutti i membri ✔️ |

`## Prod Validation` non conta. Una lista custom non si chiude da sé perché la sua chiusura non deriva dai membri: dice che il giro per cui è nata è finito, e lo decide chi l'ha aperta. L'orchestrator non passa parole al checkpoint, quindi non chiude mai un perimetro orchestrabile.

La cella Prog si legge e si scrive con le primitive di `lib.sh`, che trovano la colonna dall'header della Tasks Overview e non toccano le tabelle sotto:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" && lw_tasks_md_prog_get "{docs_root}/tasks.md" <id>
```

`lw_tasks_md_prog_get` vuoto → la riga del perimetro orchestrabile non c'è: `tasks.md` non si tocca, e il report lo dice.

Cella Prog e glifo dei nodi nel grafo dell'Execution Plan li scrivono le stesse due funzioni di `checkpoint-task`, mai tu a mano. `G` è il glifo di arrivo, `✔️` alla chiusura e `🟡` quando il lavoro comincia:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
G="✔️"   # 🟡 quando il perimetro orchestrabile non si chiude ma il lavoro è cominciato
if lw_tasks_md_prog_set "{docs_root}/tasks.md" "<id>" "$G"; then
    echo "-> tasks.md aggiornato: <id> $G"
else
    echo "WARN: nessuna riga <id> sotto un header con colonna Prog — Prog NON aggiornata" >&2
fi
lw_tasks_md_graph_set "{docs_root}/tasks.md" "<id>" "$G"
```

`lw_tasks_md_graph_set` stampa da sé i nodi riscritti, e un `WARN` per ogni riga che porta l'id con un altro glifo in una posizione che non riconosce come nodo. Exit 1 senza nessuna riga è il perimetro orchestrabile assente dal grafo, il caso normale. Ogni `WARN` dei due comandi va nel report: non correggi il grafo a mano.

**Alla chiusura**, in quest'ordine:

1. Header del file: `- **Progress**: ✔️ Done`. La data la aggiunge lo script del commit (§9), che riscrive la riga in `✔️ Done at <data>`.
2. Prog ✔️ in `tasks.md` e nel grafo dell'Execution Plan: lo snippet sopra con `G="✔️"`.
3. Se il symlink `{docs_root}/current-task.md` risolve a questo file, eliminalo (`rm`). Se punta altrove, o non esiste, non toccarlo: è il binding di un'altra task.
4. Se l'header porta `**Parent Task**: T<n>`, nel file del padre la checkbox della riga che porta l'id del perimetro orchestrabile passa a `[x]` — matcha sull'id, riscrivi solo il box — e il file del padre entra nella pathspec del §9. È la stessa regola di `checkpoint-task`: alla chiusura di una task il suo checkpoint spunta la riga del padre. Nessuna riga con l'id → un avviso nel report, nessun blocco.

**Senza chiusura**, la Prog dice se il lavoro del perimetro orchestrabile è cominciato:

- Prog 🔵 o 🟢 e almeno un membro 🟡 o ✔️ → 🟡 in `tasks.md` e nel grafo con lo snippet sopra (`G="🟡"`), `- **Progress**: 🟡 In Progress` nell'header.
- Prog 🔵 o 🟢 e nessun membro avviato → resta com'è.
- Prog 🟡 → resta.
- Prog ✔️ → resta. Un perimetro orchestrabile chiuso non si riapre dal checkpoint: se la condizione di chiusura non vale più — un'epica con una figlia nuova e la sua checkbox `[ ]` — il report lo dice, e la riapertura la decide l'umano.

## 8. L'avanzamento

Se il giro ha cambiato il file del perimetro orchestrabile, **o** la finestra del §2 non era vuota, appendi al suo Progress Log (crea `## Progress Log` in coda al file se non c'è):

```markdown
### Avanzamento <N>
- Descrizione: <cosa il giro ha portato nel file — fatti nuovi col membro da cui vengono e la fonte (diff del membro o memoria dell'orchestrator), frasi riscritte, copie tolte, checkbox spuntate, Prog — oppure «nessun fatto del perimetro orchestrabile» sulla finestra letta>
```

`<N>` = il massimo dei `### Avanzamento` esistenti più uno. L'header non è cosmetico: è l'ancora della finestra del giro dopo (§2), e scritto in un'altra forma la riporta alla nascita del file.

L'avanzamento si scrive anche quando la finestra non porta fatti del perimetro orchestrabile: sposta la partenza in avanti, così il giro dopo non rilegge lo stesso diff.

**Finestra vuota e file intatto → nessun avanzamento e nessun commit.** Il giro non ha letto niente di nuovo e non ha cambiato niente: è il secondo giro sullo stesso perimetro orchestrabile senza lavoro dei membri in mezzo, e deve restare un no-op, chiunque lo lanci. I fatti dello stato dell'orchestrator che la prosa porta già non cambiano il file; un fatto nuovo dallo stato, con la finestra vuota, lo cambia, e l'avanzamento si scrive.

## 9. Commit e push

Gira se il giro ha cambiato il file del perimetro orchestrabile. La pathspec la componi tu, e lo nomina **sempre**:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/checkpoint-task-commit.sh" --task <id> "checkpoint(<id>): <sintesi del giro>" \
  -- "<TASK_FILE>" ["{docs_root}/tasks.md"] [<file del padre>]
```

- **Il file del perimetro orchestrabile va scritto dopo `--` anche se `--task` lo aggiunge da sé.** Con una pathspec vuota lo script cade nel regime linked e fa `git add -A`, che porterebbe nel commit tutto il worktree (in detached esce in errore).
- **`tasks.md` entra solo se il giro ne ha riscritto la cella** (§7). È un file condiviso: nominato senza averlo toccato, porterebbe nel commit le modifiche non committate di un'altra sessione.
- **Il file del padre** entra solo alla chiusura di un perimetro orchestrabile con `Parent Task` (§7).
- **`--task`** è obbligatorio anche in linked: alla chiusura il symlink può essere sparito.
- Nessun `--doc-message`: il giro non scrive file doc, e lo script fa un commit solo.

Lo script committa e pusha, e stampa `-> commit 1 (codice+tracking, …): <sha>`. Exit non-zero → commit o push falliti: niente hook, ping `failed`, e il report lo dice.

**Hook `taskDone`** — solo se il §7 ha chiuso il perimetro orchestrabile in questo giro, dopo il push riuscito:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/config/project-config.sh" hooks taskDone --task <id> --sha <sha>
```

Un progetto che lega una skill alla chiusura di una task la riceve anche per un perimetro orchestrabile. `deliverableDone` non parte mai: un perimetro orchestrabile non ha DLV.

- **Nessuna riga, exit 0** → il progetto non dichiara hook su `taskDone`.
- **Righe `HOOK|<i>|<skill>` e una riga `ARGS=<argomenti>`** → per ogni `HOOK`, nell'ordine di `<i>`, invoca il tool `Skill` con `skill` = `<skill>` e `args` = il valore di `ARGS` copiato tale e quale, una skill alla volta.
- **Exit non-zero** → nessuna skill: il messaggio nomina il guasto (blocco `hooks` invalido, jq assente, task o sha non risolvibili).

Un hook non riapre niente: commit e push sono già avvenuti. Una skill che non esiste, che dà errore o che dichiara un fallimento produce un avviso in linea — `⚠ hook <skill> fallito su taskDone: <motivo>` — e una segnalazione (`hook <skill> fallito su taskDone: <motivo>`, o `hook taskDone non invocati: <messaggio dello script>`); le skill successive girano comunque, e nessuna si ritenta: un hook fallito a metà può aver già scritto fuori dal repo. Ciò che la skill hook fa resta suo, e nessun suo file entra nel commit del giro.

## Il report

In quest'ordine:

- `🧭 Perimetro orchestrabile: <id> — epica|lista custom, <n> membri`, i membri senza task file se ci sono, la finestra (`<partenza corta>..HEAD`) e i membri cambiati dentro;
- lo **stato dell'orchestrator**: `presente, <n> fatti` · `assente` · `altro (Created on <data>)` · `illeggibile`;
- i **fatti portati nel file**, uno per riga: il fatto, il membro da cui viene, la fonte (diff del membro o stato dell'orchestrator), la sezione dove è entrato;
- le **frasi riscritte** e le **copie tolte**;
- il **piano**: il verdetto del §4, con le righe che lo motivano e il rimedio; le sezioni fuori formato, se ci sono;
- le **checkbox** spuntate, in un'epica;
- la **Prog**, da → a, e se il perimetro orchestrabile si è chiuso; gli hook `taskDone` invocati, col loro esito;
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
- **Ogni voce di `## Doc Impact` del perimetro orchestrabile è una segnalazione**, una per voce: `**S{N}** — voce di Doc Impact del perimetro orchestrabile, «<la nozione in breve>»: la rilascia T<n> (<maniglia>)`. Il membro che la rilascia è quello il cui lavoro rende vero il fatto: lo trovi confrontando l'ancora della voce coi DLV e col `## Materiale` dei membri. Se nessun membro la rilascia, la riga dice `nessun membro la rilascia`. La voce resta nel file: spostarla è una decisione dell'umano.
- Sono segnalazioni anche: un caso incerto che il giro non ha deciso (un fatto che non sai dove scrivere, una frase che non sai se il diff smentisce, un fatto dello stato dell'orchestrator che i file forse smentiscono); uno stato dell'orchestrator `illeggibile`; una regola d'ordine cambiata che il piano non porta (§3); un difetto nel task file di un membro (una dipendenza non dichiarata, una copia di stato); una copia o una checkbox in una sezione che il giro non scrive; una figlia `[x]` non chiusa; un hook `taskDone` fallito (§9).
- Il giro non corregge niente di sua iniziativa fuori dalle sezioni che possiede, quindi non stampa righe `☑ subito (agente)`.

**La risposta dell'umano** è prosa libera, e la leggi nel turno dopo. Prima di scrivere il primo scenario apri `triage-format.md` per intero: le regole della risposta — nessun default, l'approfondimento alla lettera, «subito» e «task» operativi, lo scarto col perché, l'ignora con l'ancora, l'uscita in un altro progetto — sono quelle, identiche a `run-task` e `checkpoint-task`. Ogni scenario:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano \
  --momento flusso --skill checkpoint-perimeter [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'umano su quella segnalazione>
SCENARIO
```

**Una risposta firmata «decise dall'orchestrator di T<id del perimetro orchestrabile> su delega dell'utente»** porta sotto la firma le parole con cui l'umano ha delegato l'orchestrator, alla lettera: ogni scenario si scrive con `--chi delega` e quelle parole intere in `--delega`, con le regole dell'umano per il resto (`triage-format.md` §La decisione su delega). Firma senza le parole → nessuno scenario, e lo dici nel testo finale: non ripieghi su `umano` né su `agente`.

```bash
DELEGA="$(cat <<'DELEGA'
<le parole della delega, dalla riga sotto la firma, intere>
DELEGA
)"
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi delega \
  --delega "$DELEGA" --momento flusso --skill checkpoint-perimeter [--ancora <path>]... --no-commit <<'SCENARIO'
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
