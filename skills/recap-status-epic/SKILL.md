---
name: recap-status-epic
description: Recap di un'epica o di un mandato — stato del perimetro a zoom alto, poi i membri (le figlie di un'epica, la lista di un mandato) con cifre DLV/AC e stato del preflight, interdipendenze, e un punto d'ingresso a due livelli (quale membro, quale voce).
allowed-tools: Bash(*), Read, Glob
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

Recap di un **perimetro di lavoro** — una task cappello (`Size: Epic`) e le sue figlie, oppure un mandato (`Size: Mandate`) e i membri che elenca — per rientrare in un lavoro a più fasi sapendo da quale ripartire. **Read-only**: non scrive né modifica nessun file.

Epica e mandato differiscono solo nel punto da cui si leggono i membri: le figlie da `Parent Task`, oppure la lista `## Membri` del mandato. Formato del mandato: `${CLAUDE_PLUGIN_ROOT}/docs/mandate-format.md`. Sotto, **membri** vale per entrambi; dove il caso cambia, il testo lo dice.

## Grado di competenza — `K1` sul perimetro e sui membri

Chi chiede un recap dichiara, con l'atto stesso, di non avere la bussola della situazione. Scrivi quindi a **`K1`** su un perimetro dichiarato:

- **cosa** — il perimetro intero e i suoi membri: cosa vuole ottenere l'epica o il mandato, dove è arrivato ogni membro
- **dove** — il dominio dell'epica (il sottosistema che rifà, il perimetro su cui interviene)

`K1` significa: termini comuni nudi, termini specialistici glossati alla prima occorrenza, implicazioni sempre esplicitate, nessuna ancora al mondo di tutti i giorni. La scala `K0`-`K3` non la ridefinisci — vive nell'output style; qui dichiari solo a che grado leggerla dentro il perimetro.

**Fuori dal perimetro vale il grado dichiarato normalmente**: un recap di epica non abbassa `java`, `sql` o qualunque altra materia — il vuoto che un recap presume riguarda lo stato di un lavoro, non il possesso di un vocabolario.

**Un `[Kx]` inline vince secco** sul settore che nomina: è la dichiarazione cosciente di quanto l'utente ricorda adesso, e correggerla significherebbe non credergli. I settori che l'override non nomina restano a `K1` dentro il perimetro.

**Le coordinate opache restano opache a ogni grado.** Con N membri il testo è fatto di id, ed è precisamente il punto in cui una riga come «catena bloccante: T06 → T15 → T16» smette di essere leggibile. Ogni id porta la sua maniglia verbo+oggetto a **ogni** citazione — `T107 (fusione delle sezioni doc)` — salvo quelli che l'utente ha nominato lui nel prompt.

## 1. Risolvi il perimetro e i membri

Se le Note utente nominano un ID (`/loom-works:recap-status-epic T74`), passalo come argomento; altrimenti omettilo e lascia lavorare la cascata.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId} --members
```

Cascata di famiglia `arg → $LOOM_TASK → symlink {docs_root}/current-task.md`, poi il lettore unico dei membri:

- `TASK_MEMBERS_SRC=parent` — un'epica, o una task qualunque: i membri sono le figlie, in ordine numerico
- `TASK_MEMBERS_SRC=list` — un mandato: i membri sono la lista `## Membri`, nell'ordine del file
- `TASK_MEMBERS_COUNT=<n>` e una riga `TASK_MEMBER=<id> <path>` per membro
- `TASK_MEMBER_MISSING=<id>` — un membro dichiarato dal mandato senza task file, fuori dal conteggio

Non riscrivere la lettura a mano: il word boundary sull'id e le regole della lista vivono nello script, e `T7` matcherebbe `T74`.

Fai `Read` di `TASK_FILE` per intero, e poi di ogni task file membro.

**Casi fuori competenza — dichiara e procedi**, non fallire:

- `TASK_MEMBERS_SRC=parent` e `TASK_MEMBERS_COUNT=0` → nessuna figlia. Può essere un'epica appena aperta, oppure una task normale su cui questa skill è stata invocata a mano. Dillo in una riga, indica `/loom-works:recap-status-task ${TASK_ID}`, e fai comunque il recap del solo file risolto.
- `TASK_MEMBERS_SRC=list` e `TASK_MEMBERS_COUNT=0` → un mandato che non dichiara ancora membri. Dillo in una riga e fai il recap del solo file.
- la task risolta **non** ha `Size: Epic` ma ha figlie → è un cappello che non si è ancora dichiarato tale. Segnalalo come incongruenza da correggere nel file, e procedi normalmente.
- `TASK_MEMBER_MISSING=<id>` → il mandato elenca una task che non ha più un task file: purgata da `clean-tasks` dopo la chiusura, o mai creata. Mostrala fra i membri come tale, con la riga di `tasks.md` se c'è ancora, e procedi.
- un membro `Size: Epic` o `Size: Mandate` → è un perimetro a sé, e il lettore non lo espande. Mostralo come una riga, con la sua Prog, e indica il suo recap (`/loom-works:recap-status-epic T{N}`): i suoi membri non entrano in questo recap.

## 2. Raccogli il contesto reale

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/recap-git-status.sh
```

Più `{docs_root}/tasks.md` per la Prog di ogni membro e per l'Execution Plan, se il perimetro vi ha una catena.

**Lo stato dei membri si legge da `tasks.md` e dai loro task file, mai dal file del perimetro.** Un'epica o un mandato che porta una colonna di stato o una cifra ricopiata da un membro viola il formato (`mandate-format.md` §Nessuna copia): la copia resta indietro alla prima modifica. Se ne trovi una, segnala la divergenza come incongruenza da correggere nel file, e scrivi il recap col dato vero.

**La Prog di `tasks.md` non basta** a dire dove sta un membro. Il glifo `🟢 Ready` distingue ormai il preflight fatto dall'intatta, ma lo scrive solo `preflight-task`, e solo dalle esecuzioni successive al suo rilascio: una figlia preflightata prima resta `🔵` senza che niente lo segnali. Il verdetto sullo stato lo dà quindi il task file — blocco `### Preflight` in `## Decisions` — con la Prog come conferma, non come fonte.

## 3. Il recap — in quest'ordine

L'ordine non è cosmetico: una proposta emessa prima delle dipendenze non ha i dati per essere quella giusta.

**Apri con la sostanza.** Docs-root risolta, cascata che ha risolto il perimetro, conteggio dei membri, nome degli script girati: sono passi di lavoro tuoi, non contenuto per chi legge. Niente riga di intestazione tecnica prima del quadro — se un dato di risoluzione conta davvero (membri zero, cappello senza `Size: Epic`, membro senza task file), dillo dentro il blocco dove pesa.

**3a. Il perimetro, a zoom alto.** Cosa vuole ottenere l'epica o il mandato, dove è arrivato nel suo insieme, cosa resta. Prima i membri non si nominano nemmeno: chi legge deve avere il quadro, non ricostruirlo da un elenco.

Distingui lo **stato del perimetro** da quello dei membri: i DLV e gli AC propri del file (compresa la checkbox per figlia nell'Acceptance di un'epica) sono cose sue, e possono essere aperti mentre i membri corrono. Un mandato può non averne affatto: il formato non li prescrive.

**3b. La catena delle fasi — o, per un mandato, il perimetro dichiarato.**

- **Epica**: le figlie in ordine, con la loro Prog, come catena leggibile — non una tabella di id nudi.
- **Mandato**: al posto della catena, tre blocchi dal file del mandato. I **membri**, nell'ordine della lista, ognuno con la sua maniglia, la sua Prog da `tasks.md` e l'epica a cui appartiene (`Parent Task`) o «orfana». Le **preferenze d'ordine** (`## Preferenze d'ordine`), dette come valgono: solo per questo perimetro. L'**analisi del perimetro** (`## Analisi del perimetro`), riga per riga, con la sua `Fonte`: le righe `modello` vengono da una lettura dei DLV, e se un membro è cambiato dopo possono essere vecchie. Una sezione assente si dichiara in una riga.

**3c. I membri, uno per uno, con una cifra.** «In corso» da solo non dice se un membro è a un passo dalla chiusura o appena aperto. Per ognuno:

- quanti **DLV** spuntati su quanti, quanti **AC** spuntati su quanti
- quale dei **tre stati di avanzamento** è: lavoro in corso · **solo il preflight fatto** (sezione `## Decisions` popolata, design congelato, zero codice — Prog `🟢` se promossa) · intatta

Il preflight fatto è un investimento già pagato, ed è il discriminante che più pesa sulla scelta di dove ripartire.

**3d. Interdipendenze.** Fra i membri: chi blocca chi, cosa è già sbloccato, cosa resta appeso a una fase non chiusa. Fonte: `## Dependencies` dei membri, l'Execution Plan di `tasks.md`, e ciò che il testo del cappello dichiara sull'ordine delle fasi; per un mandato anche `## Analisi del perimetro` e `## Preferenze d'ordine`, che però valgono meno delle dipendenze dichiarate dai membri quando le contraddicono. Senza questo blocco il punto d'ingresso è indistinguibile da una scelta arbitraria fra i membri percorribili.

**3e. Il punto d'ingresso — blocco terminale, due livelli.** Chiudi nella forma «**riprendi da T{N}** *(maniglia)*, e lì fai il **DLV {X}**»: prima quale membro, poi quale voce dentro quel membro. Non è leggibile da nessun campo — si ricava incrociando la Prog dei membri, l'ordine delle fasi (o le preferenze d'ordine del mandato) e le dipendenze appena scritte, e la ragione dell'incrocio va detta in una riga.

Resta una proposta, non un verdetto: se due membri sono percorribili in parallelo dillo, ma indica comunque da quale conviene entrare.
