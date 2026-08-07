---
name: lint-doc
description: Misura la doc di progetto contro il contratto editoriale — file sopra soglia, TLDR-riassunto, residui storici, costo online, coordinate opache, cartelle da partizionare. Tre fasi sequenziali (clean, split, regroup), non presidiata, committa da sé col collaudo di doc-verifier. Misure numeriche via doc-metrics.sh, giudizio via doc-auditor read-only, patch via doc-writer, partizione via doc-grouper. Token `plan`: misura e piano delle invocazioni, senza applicare niente.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Confronta la doc di progetto col **contratto editoriale** (`${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md`) e trova le **violazioni**.

Input utente (perimetro doc: file, cartella, vuoto = tutta la doc · più i token `clean` / `split` / `regroup` / `plan`):
~~~human
$ARGUMENTS
~~~

## Cosa NON fa

**Non apre i sorgenti del progetto.** Mai. Per sapere che un file da 47.000 char è sopra soglia, che un TLDR racconta invece di agganciare, o che una sezione dice «prima era X, ora Y», il codice non serve.

È il taglio con la gemella `align-doc`, che misura la stessa doc contro il **codice** e deve aprirli tutti. Fondere le due farebbe leggere decine di KB di sorgenti a un agent che deve contare caratteri e riconoscere un changelog travestito.

## Tre fasi, mai insieme

La bonifica ha **tre fasi disgiunte**, e l'ordine fra loro non è una preferenza:

- **clean** — riduzioni dentro i file esistenti: residui storici, TLDR da riscrivere come ancore, eco e inventari da sostituire con puntatori, motivazioni finite online, formato, coordinate opache. La topologia non cambia: stessi file, stessi path.
- **split** — topologia verticale: taglio dei file sopra soglia, `merge` dei residui sotto il pavimento, sweep dei puntatori che ne consegue. Cambia il numero dei file e i loro path.
- **regroup** — topologia orizzontale: una cartella oltre soglia si spezza in sottocartelle. Non cambia il numero dei file, cambia dove stanno (§9).

**Mai nella stessa passata.** Il contratto impone «riduzioni prima del taglio», quindi un'outline di split calcolata insieme alle riduzioni nasce già stale: è dimensionata su char che quella stessa esecuzione sta per togliere. Peggio, una parte dei file candidati **esce dalla lista da sola** quando le riduzioni atterrano — l'outline prodotta per loro è lavoro interamente perso, non solo da rifare.

**Il `regroup` va ultimo per la stessa ragione, un livello sopra**: una categorizzazione dimensionata su file che stanno per essere spezzati nasce stale, e un file che dopo lo split diventa tre può cambiare cartella di appartenenza.

Il costo si divide in due voci che non vanno confuse: **rilevare** che un file è sopra soglia costa zero (è il flag `SPLIT` che `doc-metrics.sh` ha già calcolato, un confronto fra due numeri), **proporre dove tagliare** costa la lettura integrale del file. In fase clean si fa solo il primo.

### Fase e perimetro dall'input

Dall'input si estraggono due cose indipendenti. I token noti sono `clean`, `split`, `regroup`, `plan`; **tutto il resto è perimetro**.

- nessun token di fase → **tutte e tre**, `clean` poi `split` poi `regroup`, in un'unica invocazione
- `clean` → solo riduzioni; i file sopra soglia restano nel registro come `SPLIT: deferred`
- `split` → solo topologia verticale; presuppone che le riduzioni siano già atterrate
- `regroup` → solo topologia orizzontale; presuppone che i tagli siano già atterrati
- più token di fase (in qualunque forma: `clean + split`, `clean, split`) → esplicitano un sottoinsieme del default, sempre eseguito nell'ordine contrattuale

Esempi:

```
/loom-works:lint-doc docs/reference/engine          → clean, split, regroup
/loom-works:lint-doc docs/reference/engine clean    → solo clean
/loom-works:lint-doc docs/reference/db/dtl-schema.md split
/loom-works:lint-doc regroup                        → solo la partizione delle cartelle
/loom-works:lint-doc                                → tutta la doc, tutte le fasi
/loom-works:lint-doc plan                           → misura + piano, non applica niente
```

### Fin dove arrivare — `plan` è il solo freno

Il default è il **ciclo completo**: piano, tutte le fasi, tutte le ondate, collaudo, commit, pulizia — in una sola invocazione, senza una domanda, senza soste, senza chiedere al chiamante di rilanciare. Non si chiede un token per ciò che è già il comportamento.

| token | applica | committa | si ferma |
| --- | --- | --- | --- |
| `plan` | no | no | dopo la misura (§1-§2) |
| _(nessuno)_ | sì | sì | a bonifica chiusa, registro rimosso |

Il livello intermedio «applica ma non committare» **non esiste**, ed è una rimozione deliberata: lasciare una patch nel working tree o nell'indice in attesa di un giudizio umano è la forma esatta dell'incidente in cui una patch doc è finita dentro il commit di un'altra sessione. Chi collauda è `doc-verifier` (§7), su ogni fase, prima di ogni commit.

#### `plan` — misura e fermati

Col token la skill esegue §1 (misura) e §2 (partizione), stampa il piano e **si ferma lì** — niente fan-out di auditor (§3), niente registro su disco (§4), niente writer, niente commit. Il costo sono due chiamate bash e nessun subagent: è ciò che lo rende consultabile *prima* di decidere se e da dove partire.

Anche i token di fase sono inerti: **il perimetro delle fasi 2 e 3 non è calcolabile ex-ante** — dipende dai char *dopo* le riduzioni (§8), e la partizione di una cartella dipende da quali file esistono dopo i tagli. Il piano elenca quindi sempre le invocazioni `clean` per gruppo e chiude con uno step `split` e uno `regroup` a perimetro da ricalcolare.

Cosa stampa, e nient'altro:

- totale doc e **footprint per-sessione** del §1, con le due voci (`@-import` di `CLAUDE.md` + entry hook) separate;
- le violazioni **già visibili dai soli numeri** — i flag `SPLIT`, `TLDR>600`, `MERGE?` che `doc-metrics.sh` ha calcolato, senza aprire un file, più le cartelle a flag `REGROUP`;
- i gruppi del §2 con char, conteggio file e ragione del raggruppamento;
- le **righe di comando** delle invocazioni successive, nell'ordine imposto dal contratto: prima i `clean`, coi file a flag `SPLIT` in testa (le loro riduzioni possono farli scendere sotto soglia e togliere del tutto la fase 2), poi uno `split`, poi un `regroup`.

**Dichiara sempre che la partizione non è pinnata.** Ogni invocazione successiva con perimetro ristretto ricalcola la propria partizione su quel sottoinsieme (§2): i gruppi del piano sono una *work-list*, non i gruppi che quegli auditor useranno davvero. Senza quella riga il piano si legge come un contratto, e il registro che arriva dopo non torna coi numeri annunciati.

#### Il regime di default — non presidiato

**Guardia in ingresso, prima di qualunque altra cosa.** Se `git diff --cached --quiet` esce non-zero l'indice è già popolato da qualcun altro: **fermati e dillo**. Ogni commit di questa skill ha una pathspec esplicita, e con un indice sporco porterebbe via lavoro non tuo.

**Primo atto, prima di toccare qualunque file** — stampa lo SHA di partenza:

```bash
git rev-parse --short HEAD
```

È **l'unica coordinata di undo dell'intera run**, e va stampata due volte: all'inizio (prima che serva) e nel report finale (quando serve). I commit sono già in cronologia quando qualcuno li guarda, quindi `git checkout` non annulla più niente: l'undo è `git reset --hard <SHA>`, che porta via anche i file **nuovi** di uno split.

**Non pusha, deliberatamente.** Finché i commit restano locali l'undo è una riga; pushati, diventa un force-push su un ramo che altre sessioni possono già aver letto. Il push è una decisione del chiamante, a valle.

**Mai staged fino al commit.** Lo stage git è uno per *worktree*, non per sessione: una patch lasciata nell'indice viene raccolta dal `git add -A` di qualunque altra sessione che committi nel frattempo. Quindi le patch vivono solo nel working tree, il collaudo legge `git diff` non-staged, e il commit è una catena unica con pathspec esplicita — `git add -- <path...> && git commit -- <path...>`.

Sequenza dei commit — il registro entra in cronologia **prima** delle patch che lo eseguono:

| # | dopo | contenuto | messaggio |
| - | --- | --- | --- |
| 1 | §2 | registro col solo piano in testa | `docs(lint): piano bonifica` |
| 2 | §4 | registro coi finding della fase | `docs(lint): registro fase <clean\|split\|regroup>` |
| 3 | §7 | patch dei writer + sweep dei puntatori, **collaudate** | `docs(lint): <riduzioni\|split topologia\|regroup> fase <fase>` |
| 4 | §10 | INDEX rigenerato, registro rimosso | `docs(lint): chiude bonifica` |

I commit 2 e 3 si ripetono per fase eseguita. Il commit 1 esiste perché **il piano non ha un posto suo**: è la testa del registro, e committarlo lì lo rende consultabile a mesi di distanza invece di morire nello scrollback. Coi commit 2 e 3 adiacenti, `git show` sul primo dice *cosa era stato trovato* e il secondo *cosa è stato fatto* — l'unica traccia forense di una bonifica che nessuno ha revisionato.

Il commit 4 rimuove il registro (materiale di lavoro esaurito, la cronologia lo conserva comunque): serve `git add -A -- <path>`, o la cancellazione non entra nell'indice — stessa ragione del §10.

**Se il registro è gitignorato** (in certi progetti le folder dot-prefixed lo sono), i commit 1, 2 e 4 non hanno niente da stagiare e `git commit` esce non-zero: verifica con `git check-ignore -q <REGISTRY_PATH>` prima del commit 1, e se è ignorato salta i tre commit del registro **dichiarandolo nel report**. Le patch (commit 3) restano.

**Re-entrante senza bookkeeping.** Se la sessione muore a metà, si rilancia e riprende — non c'è stato da recuperare, perché **la misura è lo stato**: un file già ripulito è sotto soglia ed esce dalla partizione da solo alla rimisura del §1. È la stessa proprietà per cui la fase split ricalcola il perimetro invece di riusare la lista della fase clean (§8), applicata all'intera run invece che al solo passaggio fra fasi.

**Il contesto dell'orchestratore è la risorsa scarsa** — l'unica che può far fallire il ciclo: auditor e writer hanno contesto proprio e lo buttano, il chiamante accumula per tutta la run. Non si ri-echeggia in chat niente che stia già su disco: né registro, né diff, né elenchi di finding. Una riga per fase, il report solo alla fine.

### Chi collauda — `doc-verifier`, non un umano

La skill **non chiede verdetti** e non lascia niente in attesa di un giudizio. Il controllo di merito sta al §7, fra l'apply e il commit: `doc-verifier` legge il diff prodotto più i verdetti che l'hanno ordinato, e decide se la patch si tiene.

Il gate umano sul diff che stava qui prima è stato **rimosso**: era l'unico collaudo della skill, e i guardiani deterministici che restavano — `build-index.sh`, `check-doc-links.sh` — misurano forma e link, non vedono un TLDR-riassunto né una cronaca infilata in `reference/`. Un collaudo che nessuno esegue perché gira di notte non è un collaudo.

## Numeri prima, giudizio dopo

Le soglie sono **numeri nel contratto**, non valutazioni: due esecuzioni sullo stesso albero devono dare lo stesso esito. Quindi il conteggio lo fa uno script, e all'agent resta solo ciò che un numero non cattura — se un TLDR *aggancia*, se una sezione è cronologia, dove passa il taglio di uno split.

### 1. Passo numerico

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --online
```

Restituisce per ogni file: char, char del TLDR, flag (`SPLIT`, `TLDR>600`, `NOTLDR`, `ONLINE`, `GEN`) e il **footprint per-sessione** — `@-import` di `CLAUDE.md` **più** le entry hook `SessionStart`. Le due voci vanno lette insieme: gli `@-import` da soli sono circa il 70% del costo reale, e ottimizzare solo quelli lascia un terzo del problema sul tavolo.

Con `--format tsv` l'output è passabile tale e quale agli auditor: sono misure già fatte, non vanno ricontate.

Registra il totale **prima** dell'intervento: senza baseline il "dopo" non dice niente.

### 2. Partiziona i perimetri

**Quali** file vanno insieme non è una scelta a runtime: due esecuzioni sullo stesso albero devono produrre gli stessi gruppi, o il registro non è confrontabile col precedente.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-partition.sh" --format tsv
```

Consuma le misure del §1 e ritorna i gruppi già formati, ciascuno col proprio `PREFIX` (il prefisso ID dei finding) e le righe di misura dei suoi file. Il criterio: un file sopra soglia di split fa gruppo da solo, il resto va per cartella, i gruppi-cartella più leggeri si fondono se sforano il cap.

**Due cap, non uno**: `--max-groups` (4) è quanti auditor per *ondata* — oltre, il registro diventa illeggibile; `--max-char` (60.000) è quanta doc legge *un* auditor. Il secondo esiste perché senza di esso «un gruppo per cartella» degenera: una `reference/` da 23 file finisce tutta in un perimetro solo.

Se la colonna `WAVE` porta più di 1, **esegui un'ondata per messaggio** e consolida il registro alla fine. Non tagliare i gruppi in eccesso: quei file resterebbero non auditati senza che nulla lo dica.

**Le ondate girano back-to-back** nella stessa invocazione. La sosta per messaggio esisteva per tenere il registro leggibile a un umano che lo revisionava, e senza quell'umano non regge: `--max-groups` torna a essere solo un limite di **concorrenza** (4 auditor in volo), non un punto di fermata.

In **fase split** la partizione va ricalcolata sul perimetro ristretto (§8), non riusata da quella di clean. La fase `regroup` non usa questa partizione: lavora per cartella e ha un trigger proprio (§9).

### 3. Fan-out doc-auditor

Un `Task` con `subagent_type: doc-auditor` per gruppo dell'ondata corrente, tutti nello stesso messaggio → parallelo. Read-only ⇒ nessun conflitto sul working tree.

```
Perimetro:
- Doc: <i PATH del gruppo>

Fonte di verità: contratto
Fase: <clean | split>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — otto test e sette tipologie offline, da leggere quando la collocazione non è ovvia.
Prefisso ID: <la colonna PREFIX del gruppo>

Misure pre-calcolate (fidati di queste, non ricontare):
<righe del gruppo: PATH / CHAR / TLDR / FLAGS>

<blocco di fase, vedi sotto>

Ritorna solo il registro.
```

**Blocco di fase `clean`:**

```
Non aprire i sorgenti del progetto. Cerca: residui storici, TLDR-riassunto,
layer sbagliato, motivazioni finite online, costo online ingiustificato,
eco e inventari da sostituire con un puntatore, coordinate opache, formato.

NON produrre outline di split e NON proporre merge: sono topologia, li lavora
la fase successiva su un file gia' dimagrito. Per un file col flag SPLIT o
MERGE? emetti una voce sola `SPLIT: deferred` / `MERGE: deferred`, senza aprirlo
per cercare il punto di taglio: il rilevamento e' gia' nel flag.

Bloccanti: TLDR oltre il cap e TLDR-riassunto sono SEVERITY: alta per definizione,
mai media o bassa — non sono giudizi di gusto. Marcali `BLOCKING: si`.
```

**Blocco di fase `split`:**

```
Non aprire i sorgenti del progetto. Il perimetro contiene solo file che restano
fuori soglia DOPO le riduzioni: qui si lavora la topologia e nient'altro.

Per ogni file sopra soglia: outline del taglio, per perimetro e mai per byte
(due trigger di ricerca distinti = due file), ogni frammento col proprio
TLDR-ancora, e la mappa di quali § finiscono in quale frammento.
Per ogni file col flag MERGE?: perimetro di ricerca distinto -> sopravvive e
dillo; residuo -> verdetto merge, e dì in quale file confluisce.

Se trovi riduzioni residue, segnalale ma non bloccarci sopra: la fase clean
e' gia' passata, e una voce nuova qui e' materiale per la prossima esecuzione.
```

### 4. Consolida il registro

Un unico file ordinato per severità, con **una sezione per fase** (`## FASE: clean`, `## FASE: split`, `## FASE: regroup`): ogni fase deve poter leggere cosa ha fatto la precedente, e file separati perdono il collegamento. Dove atterra lo risolve uno script, non una domanda:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/resolve-registry-path.sh" --name lint-doc-findings.md
```

Cascata: task attiva con `**Folder**:` popolato → quella folder · task attiva senza folder → la crea (`set-task-folder.sh`, che riscrive il campo) · nessuna task → scratch `.YY-MM-DD-lint-doc-findings`. Usa la riga `REGISTRY_PATH=` che stampa.

Mai dentro `{docs_root}/`: è materiale di lavoro, non doc di progetto.

**Se il file esiste già** (esecuzione precedente, o più perimetri in parallelo sullo stesso giorno) appendi una sezione nuova invece di sovrascriverlo, intestata col perimetro: il path è lo stesso per ogni invocazione della giornata, e sovrascrivere perde il registro di chi ha girato prima.

In chat **una riga per fase**, e il piano va scritto in testa al registro prima del suo primo commit (§Il regime di default). Ri-echeggiare ciò che è già su disco consuma l'unica risorsa che deve reggere fino in fondo al ciclo.

I verdetti proposti dagli auditor **valgono come approvati**: non c'è un passo che li raccoglie e li fa confermare. Le voci `BLOCKING: si` — TLDR oltre il cap, TLDR-riassunto — non si declassano e non si rimandano: sono un numero e una forma, non una preferenza.

### 5. Applica

Raggruppa per **file doc target**, un `doc-writer` per gruppo. Gruppi che **non condividono nessun file target** vanno in **parallelo**, nello stesso messaggio: il vincolo è «mai due writer sullo stesso file», non «mai due writer». Sequenziali solo dove i gruppi si sovrappongono — e se si sovrappongono, di norma erano un gruppo solo.

Un `merge` accoppia **due** file (chi confluisce e chi assorbe): entrambi vanno nello stesso gruppo, o due writer si contendono la stessa fusione.

L'outline dello split (§6) va **risolta prima** del fan-out dei writer: il writer è muto e non può fermarsi a chiedere conferma su un taglio che non convince. La risolve il registro dell'auditor; passala già validata nel prompt e **dichiaralo**, così il writer va dritto alla scrittura.

Dai a ogni writer il perimetro dei file che può toccare e l'istruzione di **segnalare invece di editare** ciò che sta fuori: uno split rompe puntatori anche in file assegnati a un altro gruppo, e due writer che si contendono lo stesso puntatore lo riscrivono a vicenda. Lo sweep lo fa il chiamante, a valle (§6).

**Ogni voce porta il proprio verdetto e il proprio target**: il writer non giudica e non sceglie dove scrivere. Una violazione passata come descrizione nuda («bonifica questo file») lo lascia a improvvisare la collocazione, che è il mestiere che gli è stato tolto.

```
Rotte da applicare — verdetto e target sono già decisi e vincolanti, non rivalutarli.
Target: <file>

<una voce per violazione del registro:>
NOTION: <la violazione, come sta nel file oggi>
VERDICT: clean | relayer | split | merge | tldr
TARGET: <file>.md §<sezione> | NEW <file>.md
TLDR: <ancora proposta — solo su NEW o su verdetto tldr>
POINTER: <file + simbolo> | <comando + forma della domanda> | —
EVIDENCE: <path:linea | misura di doc-metrics.sh>
WRITE: <cosa deve diventare la sezione>

Contesto:
<le voci del registro per questo file: violazione / evidenza / FIX>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Formule TLDR: ${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md

Applica le patch direttamente (Write/Edit), non committare, non rigenerare l'indice.
Sostituisci la sezione toccata, non stratificare. Ritorna APPLIED: + INDEX_REBUILD_NEEDED.
Se splitti, fondi o cancelli un file, ritorna anche SPLIT_MAP: — serve allo sweep dei puntatori.
```

Su `relayer` il `POINTER:` lo produce **l'auditor**, che ha aperto la fonte per giudicare: il writer lo trascrive senza riaprire niente.

### 6. Split e merge — i fix che non sono "nozione → patch"

Split e merge riscrivono la topologia della doc, non una sezione, e per questo stanno **tutti nella fase 2**. Quattro vincoli:

- **Riduzioni prima del taglio.** È la ragione per cui le fasi sono separate: eco, cronaca e inventari sono spesso migliaia di char, e un frammento dimensionato su peso che sta per sparire nasce a ridosso della soglia — cioè già candidato al prossimo split.
- **Taglio per perimetro, mai per byte.** Frammenti da 7.500 char ottenuti tagliando a metà sono peggio dell'originale: nessuno dei due è cercabile.
- **Ogni frammento nasce col proprio TLDR-ancora.** Un file splittato in N perde l'unica ancora che aveva: senza un TLDR per frammento lo split *peggiora* la reperibilità invece di migliorarla.
- **Outline validata prima della scrittura, sempre.** Il `doc-writer` è muto: non ha `AskUserQuestion` e non può fermarsi a chiedere conferma su un taglio che non convince. L'outline dello split arriva quindi già decisa nel prompt, dal registro dell'auditor. Un writer che riceve un `NEW` senza outline applica la scelta conservativa (una sezione in coda, nessuna sottocartella) e la dichiara in `NOTE:`, che non è lo split che volevi.

**Il merge è l'operazione inversa, e va usata.** Un file sotto il pavimento del contratto non si fonde d'ufficio: si riesamina il suo perimetro di ricerca. Se è distinto, sopravvive e lo si dichiara nel registro; se è un residuo, confluisce nel vicino di perimetro e l'INDEX perde una voce. Senza questo ramo lo split è a senso unico: la doc si frammenta a ogni passata e nessuno nota il file che si è svuotato.

Un merge applicato è **tre patch, non una**: la sezione entra nel file che assorbe (`MOD`), il file svuotato sparisce (`DEL`, che il writer fa solo su verdetto tuo), e i riferimenti al path morto vanno rimappati come dopo uno split.

#### Sweep dei puntatori — lo fa il chiamante, non il writer

Dopo uno split o un merge i riferimenti al file vecchio restano appesi, **anche in file che nessun writer ha toccato**. Enumerarli è meccanico:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
```

Scansiona `{docs_root}/` più `CLAUDE.md`. `--also <file|dir>` (ripetibile) aggiunge perimetri che citano path di progetto senza esserne parte — tipicamente un submodule di plugin/tooling nel repo. Passalo solo se quel perimetro esiste davvero qui.

Due livelli, e il secondo è il motivo per cui un `grep` del path vecchio non basta:

- `DANGLING` — il file puntato non esiste più. Un grep lo trova.
- `NOSECTION` — il file esiste, ma la `§` citata non c'è. Dopo uno split è il caso **normale**: il riferimento è stato riscritto sul frammento giusto e la sezione è finita in un altro. Un grep sul path nuovo risulta pulito, e il drift resta.

**Exit 2 è il verdetto** (ci sono riferimenti appesi), exit 0 pulito, exit 1 errore duro.

Gira **a valle di entrambe le fasi**, non solo dello split: un verdetto `relayer` cancella la copia e lascia il puntatore, quindi la fase clean produce `NOSECTION` per conto proprio.

Il mapping di ogni voce al frammento giusto viene dal blocco `SPLIT_MAP:` che il writer ha ritornato: è l'unico che sa in quale frammento è finita `§X`. Applica le riscritture tu, con `Edit`, e ricontrolla finché lo script non esce 0. Restano a carico tuo anche `CLAUDE.md` (se il file era `ONLINE`, l'`@-import` va sostituito con quelli dei frammenti che restano online) e i `SKILL.md` del plugin che citano il path.

Un riferimento appeso è drift **prodotto dalla bonifica stessa**: nasce con la patch che doveva migliorare la doc, e nessun segnale lo denuncia.

### 7. Collaudo — `doc-verifier`, poi il commit della fase

Una volta per fase, a sweep chiuso e **prima** del commit 3. `Task` con `subagent_type: doc-verifier`.

```
Patch da collaudare — fase <clean | split | regroup>.

File toccati (dai contratti APPLIED: dei writer di questa fase):
<la lista coi marker NEW / MOD / DEL>

Registro dei verdetti che hanno ordinato questa patch:
<le voci del registro della fase: violazione / verdetto / target>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.

Esiti dei guardiani (fatti deterministici, non ricontarli):
- check-doc-links.sh: exit <n>, riferimenti appesi residui: <la lista, o «nessuno»>
- doc-metrics.sh: <le righe dei soli file toccati, coi flag>

La patch non è staged: leggila con `git diff` sul working tree.
Ritorna solo il referto.
```

Il referto porta `OUTCOME: pass | rollback`, e ogni violazione una `LABEL:`.

- **`accodato` non boccia.** Un file che dopo la patch supera la soglia di split o scende sotto il pavimento di merge è topologia che la patch ha *rivelato*, non causato: la misura è lo stato, e la prossima esecuzione lo raccoglie da sé. Riportalo nel registro e prosegui.
- **`rollback` annulla la fase**, per file secondo il marker: `MOD` → `git checkout -- <path>` · `NEW` → `rm -- <path>` · `DEL` → `git checkout -- <path>`. Le voci del registro tornano non applicate, e il motivo — la `RULE:` della violazione — ci va scritto sopra. La fase successiva **gira lo stesso**: lavora su un perimetro rimisurato, e la rimisura vede il rollback.

Su `pass`, il commit 3 della fase, catena unica con pathspec esplicita:

```bash
git add -- <path...> && git commit -- <path...> -m "docs(lint): <fase>"
```

Su un `DEL` serve `git add -A -- <path>`, o la cancellazione non entra nell'indice e il commit fa rinascere il file.

### 8. Passaggio di fase — rimisura, non riuso

Fra una fase e la successiva nella stessa invocazione. **È il passo che rende le fasi sequenziali invece che concorrenti**, e va eseguito per intero prima del fan-out di quella dopo:

1. sweep dei puntatori della fase appena chiusa (§6), fino a exit 0;
2. **rimisura**: `doc-metrics.sh` sul perimetro — le patch sono atterrate, i char sono altri;
3. **ripartizione**: `doc-partition.sh` sui numeri nuovi;
4. il perimetro della fase `split` sono **solo i file ancora `SPLIT` o `MERGE?`** dopo la rimisura — un sottoinsieme ricalcolato, mai la lista della fase 1. Quello della fase `regroup` sono **solo le cartelle ancora a flag `REGROUP`**.

Il punto 4 non è una precauzione formale: una parte dei candidati scende sotto soglia grazie alle sole riduzioni ed esce di scena. Partire dalla lista vecchia significa splittare file che non vanno più splittati.

**Fase con perimetro vuoto = successo.** Se dopo la rimisura nessun file resta sopra soglia né sotto il pavimento, la fase non ha lavoro: dichiaralo (`fase split: nessun file oltre soglia dopo le riduzioni`) e passa alla successiva. Non è un fallimento e non va segnalato come tale.

### 9. Fase `regroup` — la topologia orizzontale

Split e merge sono verticali: cambiano quanti file ci sono. Il regroup è **orizzontale** — cambia dove stanno — e serve perché creare una cartella richiede di guardare *tutto* l'insieme, mentre ogni altra scrittura guarda solo la propria nozione. Senza un attore con quel punto di vista non avviene mai.

**Trigger**: la sezione `CARTELLE` di `doc-metrics.sh`, flag `REGROUP` — **60.000 char di figli diretti**, lo stesso `--max-char` di `doc-partition.sh` e per la stessa ragione: misura quanta doc legge un auditor tutta insieme. Nessuna cartella a flag `REGROUP` → la fase non ha lavoro, e si dichiara.

#### 9a. Proposta — `doc-grouper`

Un `Task` con `subagent_type: doc-grouper` per cartella oltre soglia. Read-only, e **legge i TLDR dall'INDEX, non i corpi**: 25 file valgono ~15.000 char di TLDR contro ~200.000 di corpi, e un TLDR *è* un'ancora di ricerca — cioè esattamente l'informazione su cui si categorizza.

```
Cartella da partizionare: <path>
INDEX: <PROJECT_ROOT>/${DOCS_ROOT}/reference/INDEX.md
Soglia: 60000 char di figli diretti

Misure (fidati di queste, non ricontare):
<le righe PATH / CHAR dei figli diretti + il totale di cartella>

Ritorna solo la proposta.
```

`GROUPS: 0` è un esito valido: una cartella di file tutti di dominio unico non ha una partizione, e inventargliela è il fallimento che il grouper esiste per evitare.

#### 9b. Spostamento — `git mv`, nomi interi

Lo spostamento non passa da un writer: è movimento di file, non scrittura.

```bash
mkdir -p "${DOCS_ROOT}/reference/<categoria>"
git mv "${DOCS_ROOT}/reference/<nome>.md" "${DOCS_ROOT}/reference/<categoria>/<nome>.md"
```

**Il nome del file resta intero** — `loom-deck/loom-deck-spawn.md`, mai `loom-deck/spawn.md`. La ripetizione è brutta da leggere e costa poco; togliere il prefisso rompe un'ancora, e non tutti i riferimenti vivono dentro la doc: ci sono i `SKILL.md` del plugin, i task file, i messaggi di commit — perimetri che `check-doc-links.sh` non scandisce e che quindi nessuno sweep ripara. Vale anche al contrario: non aggiungere un prefisso a un file che non ce l'ha.

`git mv` e non `mv`: il rename resta tale nella cronologia, e `git log --follow` continua a seguire il file.

#### 9c. Sweep — è lo stesso del §6, più grosso

Il post-processing non ha bisogno di infrastruttura nuova. La `SPLIT_MAP` qui la produci **tu**, non un writer: è la lista degli spostamenti che hai appena fatto, `<path vecchio> → <path nuovo>`, con le sezioni invariate.

1. `check-doc-links.sh` — enumera i `DANGLING` in massa;
2. riscrivi i riferimenti con `Edit`, usando la mappa degli spostamenti, finché lo script non esce **0**. A carico tuo anche `CLAUDE.md` e i `SKILL.md` del plugin che citano un path spostato;
3. `build-index.sh` — genera da sé una sezione per sottocartella: l'INDEX passa da una lista piatta a sezioni tematiche senza che nessuno gliele scriva.

Poi il collaudo (§7) e il commit della fase.

#### 9d. Ricorsivo — la profondità emerge

Dopo lo sweep, **rimisura**: una sottocartella appena creata che è a sua volta oltre soglia si ri-triggera, e si rifà il ciclo su quella. Il grouper lo dichiara da sé con `OVER_THRESHOLD: si`.

Si smette quando una passata **non produce nessuno spostamento** — non a una profondità decisa in anticipo. Una cartella che resta sopra soglia perché i suoi file non hanno una partizione è un esito legittimo, non un ciclo da forzare.

### 10. Chiudi

- Rigenera l'indice, **una volta sola in coda a tutte le fasi** (non fra clean e split: l'INDEX non è input della fase 2 — la fase `regroup` è l'eccezione, e il suo rebuild sta nel §9c perché è parte dello sweep):
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
  ```
  **Exit 2 è il verdetto dello script**, non un comando fallito: l'indice è scritto, ma i TLDR elencati su stderr restano oltre il cap. È la stessa misura del §1 letta a valle — se esce 2 dopo una bonifica che doveva chiudere quelle voci, la bonifica non ha fatto il suo lavoro e va detto nel report. Exit 1 = indice non scritto, quello è un errore da risolvere.
- **Rimisura finale**: rilancia `doc-metrics.sh --online` e dichiara il delta prima/dopo. È l'unica verifica che la bonifica abbia prodotto l'effetto che si proponeva.
- **Riverifica i puntatori**: `check-doc-links.sh` (§6) deve uscire **0**. Se esce 2 lo sweep non è finito, e i riferimenti residui vanno nel report — non si chiude in silenzio.
- **Non stampare i diff** in chat. Solo la lista file dal contratto `APPLIED:`.
- **Commit 4**, che rimuove il registro: sequenza e messaggi nel §Il regime di default.
- Report finale, **una sezione per fase eseguita**: violazioni per verdetto, file toccati, footprint prima → dopo, riferimenti appesi risolti, voci non applicate, e le fasi finite in `rollback` col motivo. La riga di reversibilità è lo SHA baseline e `git reset --hard`, che porta via anche i file nuovi di uno split. Se restano voci `BLOCKING: si` non applicate, la riga di chiusura è **`doc NON conforme: <n> violazioni bloccanti`** con i file elencati — non un riepilogo neutro.

## Note

- **Bonifica ≠ prevenzione.** Questa skill è una campagna retroattiva. Le regole che valgono anche al momento della scrittura stanno già altrove: il cap TLDR dentro `build-index.sh` (exit 2 a ogni rigenerazione), l'as-is dentro il contratto che `doc-writer` legge a ogni invocazione. Se una violazione si ripresenta a ogni esecuzione, il fix non è rilanciare `lint-doc` — è spostare quella regola in un punto di enforcement.
- **La soglia non si negozia a runtime.** Se un file ci passa per pochi caratteri, resta sopra soglia: il numero sta nel contratto, e uno scostamento discusso caso per caso rende le due esecuzioni successive incoerenti.
- **`GEN` non si splitta a mano.** `INDEX.md` è un artefatto: se è troppo grande, la causa sono i TLDR dei file indicizzati, e il fix sta là.
- **Una fase, un commit.** La separazione è cablata nella sequenza (§Il regime di default) e non è una scelta del chiamante a valle: senza un chiamante a valle non c'è nessuno che possa farla, e un unico commit che mescola riduzioni, tagli e spostamenti è un diff che nessuno rilegge.
- **Il regroup migliora, non risana.** Sui dati tipici raccoglie i domini densi e lascia in root la coda lunga dei file di dominio unico. Migliora l'INDEX e la partizione del fan-out; finché la maggioranza dei file resta singola, la cartella può restare sopra soglia — ed è un esito, non un lavoro incompiuto.
