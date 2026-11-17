---
name: checkpoint-mandate
description: Checkpoint di un perimetro — un'epica (`Size: Epic`) o un mandato (`Size: Mandate`). Riallinea il task file del perimetro a ciò che i membri hanno fatto e scoperto dall'ultimo avanzamento — legge membri e stato, il diff dei loro task file, porta nella prosa del perimetro bloccanti, collegate, decisioni aperte e regole cambiate, riverifica l'analisi del perimetro e la riscrive se un membro l'ha smentita, toglie le copie di stato e di cifre. Poi aggiorna la Prog e committa il solo file del perimetro con `tasks.md`. Nessuna fase doc, nessuna domanda, nessun task file dei membri toccato. La lancia `checkpoint-task` quando la task è un'epica o un mandato; si invoca anche a mano.
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

**Questa skill è l'unico proprietario di quella prosa.** Nessun altro attore la scrive: la regia per contratto non scrive task file; il checkpoint di un membro aggiorna il proprio task file, la propria riga in `tasks.md` e la propria checkbox nell'Acceptance del padre, e lascia apposta il resto del cappello; la prosa del cappello la scriverebbe solo una sessione sul cappello, e durante una regia non ne gira nessuna.

Confini:

- **I task file dei membri non si toccano mai**, nemmeno per correggere un difetto che il giro trova: il difetto va nelle Segnalazioni, e lo corregge chi lavora su quel membro.
- **Nessuna fase doc.** Un perimetro non rilascia niente, e la doc segue il rilascio dei membri: niente riesame, niente trasloco, niente `drainable`. Le voci del `## Doc Impact` del perimetro restano dove sono e vanno nelle Segnalazioni.
- **Nessuna domanda.** Il comportamento è lo stesso chiunque lanci la skill — l'utente a mano, la regia a fine giro, il deck —, perché l'unico input oltre all'id è la parola «chiudi», che la regia non passa mai. Un caso incerto non si chiede: va nelle Segnalazioni.
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

L'interprete è il primo fra `python3` e `python` che risponde con Python 3: su Windows `python3` può essere l'alias del Microsoft Store, che esiste ma non risponde. Nessuno dei due → dillo e fermati: senza Python `mandate.py tree` non gira, e lo stato dei membri e la metà meccanica dell'analisi non si leggono. Lo stato della shell non passa da una chiamata Bash all'altra: d'ora in poi scrivi per esteso il path dell'interprete (`PY`) e la cartella `R` = `${CLAUDE_PLUGIN_ROOT}/scripts/regia`, e lancia ogni script Python con `"PY" -B -I "R/<script>"`.

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

**Riallineare non vuol dire riassumere.** Il resto della prosa — visione, perimetro, ragioni — resta com'è, parola per parola: il giro tocca le frasi che un fatto smentisce o completa, e nient'altro.

## 4. L'analisi del perimetro

**La sezione `## Analisi del perimetro` non c'è** → non la crei. Il report porta la riga `analisi del perimetro assente: la scrive /loom-works:prepare-mandate <id>`, l'unica skill che la scrive da zero.

**La sezione c'è** → la riverifichi, in due metà:

1. **Meccanica.** Le righe `CONFLICT` di `tree` (§1) contro le righe `dichiarata` e `materiale` della tabella. È una divergenza una `CONFLICT` senza la sua riga, o una riga `dichiarata` o `materiale` fra due membri aperti che `tree` non stampa più. Una riga con un membro chiuso non è una divergenza: `tree` tace sulle task chiuse, e la riga resta scritta.
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

## 8. L'avanzamento

Se il giro ha cambiato il file del perimetro, **o** la finestra del §2 non era vuota, appendi al Progress Log del perimetro (crea `## Progress Log` in coda al file se non c'è):

```markdown
### Avanzamento <N>
- Descrizione: <cosa il giro ha portato nel file — fatti nuovi col membro da cui vengono, frasi riscritte, copie tolte, checkbox spuntate, analisi confermata o riscritta, Prog — oppure «nessun fatto del perimetro» sulla finestra letta>
```

`<N>` = il massimo dei `### Avanzamento` esistenti più uno. L'header non è cosmetico: è l'ancora della finestra del giro dopo (§2), e scritto in un'altra forma la riporta alla nascita del file.

L'avanzamento si scrive anche quando la finestra non porta fatti del perimetro: sposta la partenza in avanti, così il giro dopo non rilegge lo stesso diff.

**Finestra vuota e file intatto → nessun avanzamento e nessun commit.** Il giro non ha letto niente di nuovo e non ha cambiato niente: è il secondo giro sullo stesso perimetro senza lavoro dei membri in mezzo, e deve restare un no-op, chiunque lo lanci.

## Il report

In quest'ordine:

- `🧭 Perimetro: <id> — epica|mandato, <n> membri`, i membri senza task file se ci sono, la finestra (`<partenza corta>..HEAD`) e i membri cambiati dentro;
- i **fatti portati nel file**, uno per riga: il fatto, il membro da cui viene, la sezione dove è entrato;
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
- Sono segnalazioni anche: un caso incerto che il giro non ha deciso (un fatto che non sai dove scrivere, una frase che non sai se il diff smentisce); un difetto nel task file di un membro (una dipendenza non dichiarata, una copia di stato); una copia o una checkbox in una sezione che il giro non scrive; una figlia `[x]` non chiusa; un hook `taskDone` fallito (§9).
- Il giro non corregge niente di sua iniziativa fuori dalle sezioni che possiede, quindi non stampa righe `☑ subito (agente)`.

**La risposta dell'umano** è prosa libera, e la leggi nel turno dopo. Prima di scrivere il primo scenario apri `triage-format.md` per intero: le regole della risposta — nessun default, l'approfondimento alla lettera, «subito» e «task» operativi, lo scarto col perché, l'ignora con l'ancora, l'uscita in un altro progetto — sono quelle, identiche a `run-task` e `checkpoint-task`. Ogni scenario:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano \
  --momento flusso --skill checkpoint-mandate [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'umano su quella segnalazione>
SCENARIO
```

Poi un commit solo per tutti, coi path che lo script stampa:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && lw_git_add_n_commit "triage(<id>): <N> scenari" <path>... \
  && lw_git_push "$(lw_current_branch)"
```

Un'uscita decisa dall'umano si esegue come dicono le sue parole, anche fuori dai confini del giro: «subito, spostala in T<n>» sposta la voce nella sede delle nozioni della figlia, con un commit a sé. Il confine «i task file dei membri non si toccano» vale per il flusso del checkpoint, non per un'azione che l'umano ordina.
