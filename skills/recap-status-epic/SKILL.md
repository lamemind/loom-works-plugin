---
name: recap-status-epic
description: Recap di una task cappello — stato dell'epica a zoom alto, poi le figlie con cifre DLV/AC e stato del preflight, interdipendenze, e un punto d'ingresso a due livelli (quale figlia, quale voce).
allowed-tools: Bash(*), Read, Glob
model: opus
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

Recap di una **task cappello** e delle sue figlie, per rientrare in un lavoro a più fasi sapendo da quale ripartire. **Read-only**: non scrive né modifica nessun file.

## Grado di competenza — `K1` sull'epica e sulle figlie

Chi chiede un recap dichiara, con l'atto stesso, di non avere la bussola della situazione. Scrivi quindi a **`K1`** su un perimetro dichiarato:

- **cosa** — l'epica intera e le sue figlie: cosa vuole ottenere il cappello, dove è arrivata ogni fase
- **dove** — il dominio dell'epica (il sottosistema che rifà, il perimetro su cui interviene)

`K1` significa: termini comuni nudi, termini specialistici glossati alla prima occorrenza, implicazioni sempre esplicitate, nessuna ancora al mondo di tutti i giorni. La scala `K0`-`K3` non la ridefinisci — vive nell'output style; qui dichiari solo a che grado leggerla dentro il perimetro.

**Fuori dal perimetro vale il grado dichiarato normalmente**: un recap di epica non abbassa `java`, `sql` o qualunque altra materia — il vuoto che un recap presume riguarda lo stato di un lavoro, non il possesso di un vocabolario.

**Un `[Kx]` inline vince secco** sul settore che nomina: è la dichiarazione cosciente di quanto l'utente ricorda adesso, e correggerla significherebbe non credergli. I settori che l'override non nomina restano a `K1` dentro il perimetro.

**Le coordinate opache restano opache a ogni grado.** Con N figlie il testo è fatto di id, ed è precisamente il punto in cui una riga come «catena bloccante: T06 → T15 → T16» smette di essere leggibile. Ogni id porta la sua maniglia verbo+oggetto a **ogni** citazione — `T107 (fusione delle sezioni doc)` — salvo quelli che l'utente ha nominato lui nel prompt.

## 1. Risolvi il cappello e le figlie

Se le Note utente nominano un ID (`/loom-works:recap-status-epic T74`), passalo come argomento; altrimenti omettilo e lascia lavorare la cascata.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId} --children
```

Cascata di famiglia `arg → $LOOM_TASK → symlink {docs_root}/current-task.md`, più una riga `TASK_CHILD=<id> <path>` per figlia e il conteggio. Il word boundary sull'id vive dentro lo script: non riscrivere il grep a mano, `T7` matcherebbe `T74`.

Fai `Read` di `TASK_FILE` per intero, e poi di ogni task file figlio.

**Casi fuori competenza — dichiara e procedi**, non fallire:

- `TASK_CHILDREN_COUNT=0` → nessuna figlia. Può essere un'epica appena aperta, oppure una task normale su cui questa skill è stata invocata a mano. Dillo in una riga, indica `/loom-works:recap-status-task ${TASK_ID}`, e fai comunque il recap del solo file risolto.
- la task risolta **non** ha `Size: Epic` ma ha figlie → è un cappello che non si è ancora dichiarato tale. Segnalalo come incongruenza da correggere nel file, e procedi normalmente.

## 2. Raccogli il contesto reale

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/recap-git-status.sh
```

Più `{docs_root}/tasks.md` per la Prog di ogni figlia e per l'Execution Plan, se l'epica sta su una lane.

**La Prog di `tasks.md` non basta** a dire dove sta una figlia: separa tre stati che il recap deve invece distinguere, e li appiattisce tutti su `🔵 Todo`.

## 3. Il recap — in quest'ordine

L'ordine non è cosmetico: una proposta emessa prima delle dipendenze non ha i dati per essere quella giusta.

**Apri con la sostanza.** Docs-root risolta, cascata che ha risolto il cappello, conteggio delle figlie, nome degli script girati: sono passi di lavoro tuoi, non contenuto per chi legge. Niente riga di intestazione tecnica prima del quadro — se un dato di risoluzione conta davvero (figlie zero, cappello senza `Size: Epic`), dillo dentro il blocco dove pesa.

**3a. Il cappello, a zoom alto.** Cosa vuole ottenere l'epica, dove è arrivata nel suo insieme, cosa resta. Prima le figlie non si nominano nemmeno: chi legge deve avere il quadro, non ricostruirlo da un elenco.

Distingui lo **stato del cappello** da quello delle figlie: i DLV e gli AC propri del cappello (compresa la checkbox per figlia in Acceptance) sono cose sue, e possono essere aperti mentre le figlie corrono.

**3b. La catena delle fasi.** Le figlie in ordine, con la loro Prog, come catena leggibile — non una tabella di id nudi.

**3c. Le figlie, una per una, con una cifra.** «In corso» da solo non dice se una figlia è a un passo dalla chiusura o appena aperta. Per ognuna:

- quanti **DLV** spuntati su quanti, quanti **AC** spuntati su quanti
- quale dei **tre stati di avanzamento** è: lavoro in corso · **solo il preflight fatto** (sezione `## Decisions` popolata, design congelato, zero codice) · intatta

Il preflight fatto è un investimento già pagato, ed è il discriminante che più pesa sulla scelta di dove ripartire.

**3d. Interdipendenze.** Fra le figlie: chi blocca chi, cosa è già sbloccato, cosa resta appeso a una fase non chiusa. Fonte: `## Dependencies` delle figlie, l'Execution Plan di `tasks.md`, e ciò che il testo del cappello dichiara sull'ordine delle fasi. Senza questo blocco il punto d'ingresso è indistinguibile da una scelta arbitraria fra le figlie percorribili.

**3e. Il punto d'ingresso — blocco terminale, due livelli.** Chiudi nella forma «**riprendi da T{N}** *(maniglia)*, e lì fai il **DLV {X}**»: prima quale figlia, poi quale voce dentro quella figlia. Non è leggibile da nessun campo — si ricava incrociando la Prog delle figlie, l'ordine delle fasi e le dipendenze appena scritte, e la ragione dell'incrocio va detta in una riga.

Resta una proposta, non un verdetto: se due figlie sono percorribili in parallelo dillo, ma indica comunque da quale conviene entrare.
