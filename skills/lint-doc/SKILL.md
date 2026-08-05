---
name: lint-doc
description: Misura la doc di progetto contro il contratto editoriale — file sopra soglia, TLDR-riassunto, residui storici, costo online, coordinate opache. Due fasi sequenziali (clean, poi split), auto-apply, misure numeriche via doc-metrics.sh, giudizio via doc-auditor read-only, patch via doc-writer. Token `plan`: misura e piano delle invocazioni, senza applicare niente.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

Confronta la doc di progetto col **contratto editoriale** (`${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md`) e trova le **violazioni**.

Input utente (perimetro doc: file, cartella, vuoto = tutta la doc · più i token `clean` / `split` / `gate` / `plan`):
~~~human
$ARGUMENTS
~~~

## Cosa NON fa

**Non apre i sorgenti del progetto.** Mai. Per sapere che un file da 47.000 char è sopra soglia, che un TLDR racconta invece di agganciare, o che una sezione dice «prima era X, ora Y», il codice non serve.

È il taglio con la gemella `align-doc`, che misura la stessa doc contro il **codice** e deve aprirli tutti. Fondere le due farebbe leggere decine di KB di sorgenti a un agent che deve contare caratteri e riconoscere un changelog travestito.

## Due fasi, mai insieme

La bonifica ha **due fasi disgiunte**, e l'ordine fra loro non è una preferenza:

- **clean** — riduzioni dentro i file esistenti: residui storici, TLDR da riscrivere come ancore, eco e inventari da sostituire con puntatori, motivazioni finite online, formato, coordinate opache. La topologia non cambia: stessi file, stessi path.
- **split** — topologia: taglio dei file sopra soglia, `merge` dei residui sotto il pavimento, sweep dei puntatori che ne consegue. Cambia il numero dei file e i loro path.

**Mai nella stessa passata.** Il contratto impone «riduzioni prima del taglio», quindi un'outline di split calcolata insieme alle riduzioni nasce già stale: è dimensionata su char che quella stessa esecuzione sta per togliere. Peggio, una parte dei file candidati **esce dalla lista da sola** quando le riduzioni atterrano — l'outline prodotta per loro è lavoro interamente perso, non solo da rifare.

Il costo si divide in due voci che non vanno confuse: **rilevare** che un file è sopra soglia costa zero (è il flag `SPLIT` che `doc-metrics.sh` ha già calcolato, un confronto fra due numeri), **proporre dove tagliare** costa la lettura integrale del file. In fase clean si fa solo il primo.

### Fase e perimetro dall'input

Dall'input si estraggono due cose indipendenti. I token noti sono `clean`, `split`, `gate`, `plan`; **tutto il resto è perimetro**.

- nessun token di fase → **entrambe**, `clean` poi `split`, in un'unica invocazione
- `clean` → solo riduzioni; i file sopra soglia restano nel registro come `SPLIT: deferred`
- `split` → solo topologia; presuppone che le riduzioni siano già atterrate
- `clean split` (in qualunque forma: `clean + split`, `clean, split`) → esplicita il default

Esempi:

```
/loom-works:lint-doc docs/reference/engine          → clean, poi split
/loom-works:lint-doc docs/reference/engine clean    → solo clean
/loom-works:lint-doc docs/reference/db/dtl-schema.md split
/loom-works:lint-doc                                → tutta la doc, entrambe le fasi
/loom-works:lint-doc plan                           → misura + piano, non applica niente
```

### `plan` — misura e fermati

`plan` **non è una fase**: le fasi dicono *cosa fare*, `plan` dice **fin dove arrivare**. Col token la skill esegue §1 (misura) e §2 (partizione), stampa il piano e **si ferma lì** — niente fan-out di auditor (§3), niente registro su disco (§4), niente writer, niente stage. Il costo sono due chiamate bash e nessun subagent: è ciò che lo rende consultabile *prima* di decidere se e da dove partire.

Con `plan` gli altri token diventano inerti: `gate` non ha verdetti da raccogliere, e i token di fase non selezionano niente, perché **il perimetro della fase split non è calcolabile ex-ante** — dipende dai char *dopo* le riduzioni (§8). Il piano elenca quindi sempre le invocazioni `clean` per gruppo e chiude con uno step `split` a perimetro da ricalcolare.

Cosa stampa, e nient'altro:

- totale doc e **footprint per-sessione** del §1, con le due voci (`@-import` di `CLAUDE.md` + entry hook) separate;
- le violazioni **già visibili dai soli numeri** — i flag `SPLIT`, `TLDR>600`, `MERGE?` che `doc-metrics.sh` ha calcolato, senza aprire un file;
- i gruppi del §2 con char, conteggio file e ragione del raggruppamento;
- le **righe di comando** delle invocazioni successive, nell'ordine imposto dal contratto: prima i `clean`, coi file a flag `SPLIT` in testa (le loro riduzioni possono farli scendere sotto soglia e togliere del tutto la fase 2), poi un `split` finale.

**Dichiara sempre che la partizione non è pinnata.** Ogni invocazione successiva con perimetro ristretto ricalcola la propria partizione su quel sottoinsieme (§2): i gruppi del piano sono una *work-list*, non i gruppi che quegli auditor useranno davvero. Senza quella riga il piano si legge come un contratto, e il registro che arriva dopo non torna coi numeri annunciati.

### Auto-apply è il default — il gate è il diff

Senza il token `gate` la skill **non chiede verdetti**: applica le patch e stagea. Il controllo di merito si sposta a valle, sul `git diff` dell'utente, ed è la stessa sentenza dell'apply-first del gate doc al checkpoint — patch applicata, mai committata, review dal diff.

Regge perché **niente è irreversibile**: la skill stagea e si ferma, e ogni patch è un `git checkout` di distanza. Unica asimmetria da dichiarare nel report: uno split crea file **nuovi**, che `git checkout -- <path>` non rimuove — annullarlo richiede anche di cancellare i frammenti (`git rm -f`, o `git clean -f` se non erano stati staged).

Con `gate` torna l'`AskUserQuestion` sul registro completo (§5), **una volta per fase**.

## Numeri prima, giudizio dopo

Le soglie sono **numeri nel contratto**, non valutazioni: due esecuzioni sullo stesso albero devono dare lo stesso esito. Quindi il conteggio lo fa uno script, e all'agent resta solo ciò che un numero non cattura — se un TLDR *aggancia*, se una sezione è cronologia, dove passa il taglio di uno split.

### 1. Passo numerico

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "${user_config.doc_folder_name}" --online
```

Restituisce per ogni file: char, char del TLDR, flag (`SPLIT`, `TLDR>600`, `NOTLDR`, `ONLINE`, `GEN`) e il **footprint per-sessione** — `@-import` di `CLAUDE.md` **più** le entry hook `SessionStart`. Le due voci vanno lette insieme: gli `@-import` da soli sono circa il 70% del costo reale, e ottimizzare solo quelli lascia un terzo del problema sul tavolo.

Con `--format tsv` l'output è passabile tale e quale agli auditor: sono misure già fatte, non vanno ricontate.

Registra il totale **prima** dell'intervento: senza baseline il "dopo" non dice niente.

### 2. Partiziona i perimetri

**Quali** file vanno insieme non è una scelta a runtime: due esecuzioni sullo stesso albero devono produrre gli stessi gruppi, o il registro non è confrontabile col precedente.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-partition.sh" --docs-root "${user_config.doc_folder_name}" --format tsv
```

Consuma le misure del §1 e ritorna i gruppi già formati, ciascuno col proprio `PREFIX` (il prefisso ID dei finding) e le righe di misura dei suoi file. Il criterio: un file sopra soglia di split fa gruppo da solo, il resto va per cartella, i gruppi-cartella più leggeri si fondono se sforano il cap.

**Due cap, non uno**: `--max-groups` (4) è quanti auditor per *ondata* — oltre, il registro diventa illeggibile e il gate dei verdetti impraticabile; `--max-char` (60.000) è quanta doc legge *un* auditor. Il secondo esiste perché senza di esso «un gruppo per cartella» degenera: una `reference/` da 23 file finisce tutta in un perimetro solo.

Se la colonna `WAVE` porta più di 1, **esegui un'ondata per messaggio** e consolida il registro alla fine. Non tagliare i gruppi in eccesso: quei file resterebbero non auditati senza che nulla lo dica.

In **fase split** la partizione va ricalcolata sul perimetro ristretto (§8), non riusata da quella di clean.

### 3. Fan-out doc-auditor

Un `Task` con `subagent_type: doc-auditor` per gruppo dell'ondata corrente, tutti nello stesso messaggio → parallelo. Read-only ⇒ nessun conflitto sul working tree.

```
Perimetro:
- Doc: <i PATH del gruppo>

Fonte di verità: contratto
Fase: <clean | split>

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}
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

Un unico file ordinato per severità, con **una sezione per fase** (`## FASE: clean`, `## FASE: split`): la fase 2 deve poter leggere cosa ha fatto la fase 1, e due file separati perdono il collegamento. Dove atterra lo risolve uno script, non una domanda:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/resolve-registry-path.sh" --name lint-doc-findings.md --docs-root "${user_config.doc_folder_name}"
```

Cascata: task attiva con `**Folder**:` popolato → quella folder · task attiva senza folder → la crea (`set-task-folder.sh`, che riscrive il campo) · nessuna task → scratch `.YY-MM-DD-lint-doc-findings`. Usa la riga `REGISTRY_PATH=` che stampa.

Il ramo «task senza folder» prima finiva in `AskUserQuestion`, e la risposta era comunque «creala»: una task che produce un registro ha per definizione materiale da ospitare.

Mai dentro `{docs_root}/`: è materiale di lavoro, non doc di progetto.

**Se il file esiste già** (esecuzione precedente, o più perimetri in parallelo sullo stesso giorno) appendi una sezione nuova invece di sovrascriverlo, intestata col perimetro: il path è lo stesso per ogni invocazione della giornata, e sovrascrivere perde il registro di chi ha girato prima.

In chat va la **sintesi** — una riga per finding (`ID · severità · file · violazione · verdetto proposto`) — più il footprint misurato. Il dettaglio resta nel file.

### 5. Gate dei verdetti — solo col token `gate`

Senza `gate` questo passo **non esiste**: i verdetti proposti dagli auditor valgono come approvati e si passa al §6. Il controllo è il `git diff` finale.

Col token `gate`, i verdetti si raccolgono **una volta sola sul registro completo della fase corrente** — mai finding per finding. `AskUserQuestion` (prima il ping TTS) con: conferma tutti · conferma tranne alcuni ID · solo severità alta · nessuno. Annota il verdetto finale su ogni voce del registro.

**Le voci `BLOCKING: si` non si declassano.** Un TLDR oltre il cap o che riassume invece di agganciare è un numero e una forma, non una preferenza: entra sempre nel gruppo applicato, anche sotto l'opzione «solo severità alta». L'utente resta libero di scegliere «nessuno» e non applicare niente — ma allora il report finale (§9) dichiara la doc **non conforme**, con l'elenco delle voci residue. Il gate decide *quando* si bonifica, mai *se* la violazione esiste.

### 6. Applica

Raggruppa per **file doc target**, un `doc-writer` per gruppo. Gruppi che **non condividono nessun file target** vanno in **parallelo**, nello stesso messaggio: il vincolo è «mai due writer sullo stesso file», non «mai due writer». Sequenziali solo dove i gruppi si sovrappongono — e se si sovrappongono, di norma erano un gruppo solo.

Un `merge` accoppia **due** file (chi confluisce e chi assorbe): entrambi vanno nello stesso gruppo, o due writer si contendono la stessa fusione.

L'outline dello split (§7) va **risolta prima** del fan-out dei writer: nessuno può fermarsi a chiedere conferma mentre gli altri scrivono, o N domande si aprono sullo stesso schermo. In modo auto la risolve il registro dell'auditor; col token `gate` la approva il §5. In entrambi i casi passala già validata nel prompt e **dichiaralo**, così il writer va dritto alla scrittura.

Dai a ogni writer il perimetro dei file che può toccare e l'istruzione di **segnalare invece di editare** ciò che sta fuori: uno split rompe puntatori anche in file assegnati a un altro gruppo, e due writer che si contendono lo stesso puntatore lo riscrivono a vicenda. Lo sweep lo fa il chiamante, a valle (§7).

```
Nozione da documentare:
- **Nozione**: bonifica <file> secondo il contratto doc. Violazioni: <elenco sintetico>.
- **Ancora primaria**: riscrivi il TLDR come ancora se il registro lo segnala

Contesto:
<le voci del registro per questo file: violazione / evidenza / FIX>

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — otto test e sette tipologie offline, da leggere quando la collocazione non è ovvia.

Applica le patch direttamente (Write/Edit), non committare, non rigenerare l'indice.
Sostituisci la sezione toccata, non stratificare. Ritorna APPLIED: + INDEX_REBUILD_NEEDED.
Se splitti, fondi o cancelli un file, ritorna anche SPLIT_MAP: — serve allo sweep dei puntatori.
```

### 7. Split e merge — i fix che non sono "nozione → patch"

Split e merge riscrivono la topologia della doc, non una sezione, e per questo stanno **tutti nella fase 2**. Quattro vincoli:

- **Riduzioni prima del taglio.** È la ragione delle due fasi: eco, cronaca e inventari sono spesso migliaia di char, e un frammento dimensionato su peso che sta per sparire nasce a ridosso della soglia — cioè già candidato al prossimo split.
- **Taglio per perimetro, mai per byte.** Frammenti da 7.500 char ottenuti tagliando a metà sono peggio dell'originale: nessuno dei due è cercabile.
- **Ogni frammento nasce col proprio TLDR-ancora.** Un file splittato in N perde l'unica ancora che aveva: senza un TLDR per frammento lo split *peggiora* la reperibilità invece di migliorarla.
- **Outline validata prima della scrittura.** Il `doc-writer` ha il gate two-phase (§3.5 del suo contratto). Con **un solo** writer in volo e il token `gate`, passa lo split con `NEW file con ≥3 H2` e lascia che chieda conferma via `AskUserQuestion`. In modo auto, o con più writer in parallelo, l'outline arriva già validata dal §6 e il two-phase va disattivato esplicitamente nel prompt.

**Il merge è l'operazione inversa, e va usata.** Un file sotto il pavimento del contratto non si fonde d'ufficio: si riesamina il suo perimetro di ricerca. Se è distinto, sopravvive e lo si dichiara nel registro; se è un residuo, confluisce nel vicino di perimetro e l'INDEX perde una voce. Senza questo ramo lo split è a senso unico: la doc si frammenta a ogni passata e nessuno nota il file che si è svuotato.

Un merge applicato è **tre patch, non una**: la sezione entra nel file che assorbe (`MOD`), il file svuotato sparisce (`DEL`, che il writer fa solo su verdetto tuo), e i riferimenti al path morto vanno rimappati come dopo uno split.

#### Sweep dei puntatori — lo fa il chiamante, non il writer

Dopo uno split o un merge i riferimenti al file vecchio restano appesi, **anche in file che nessun writer ha toccato**. Enumerarli è meccanico:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh" --docs-root "${user_config.doc_folder_name}"
```

Scansiona `{docs_root}/` più `CLAUDE.md`. `--also <file|dir>` (ripetibile) aggiunge perimetri che citano path di progetto senza esserne parte — tipicamente un submodule di plugin/tooling nel repo. Passalo solo se quel perimetro esiste davvero qui.

Due livelli, e il secondo è il motivo per cui un `grep` del path vecchio non basta:

- `DANGLING` — il file puntato non esiste più. Un grep lo trova.
- `NOSECTION` — il file esiste, ma la `§` citata non c'è. Dopo uno split è il caso **normale**: il riferimento è stato riscritto sul frammento giusto e la sezione è finita in un altro. Un grep sul path nuovo risulta pulito, e il drift resta.

**Exit 2 è il verdetto** (ci sono riferimenti appesi), exit 0 pulito, exit 1 errore duro.

Gira **a valle di entrambe le fasi**, non solo dello split: un verdetto `relayer` cancella la copia e lascia il puntatore, quindi la fase clean produce `NOSECTION` per conto proprio.

Il mapping di ogni voce al frammento giusto viene dal blocco `SPLIT_MAP:` che il writer ha ritornato: è l'unico che sa in quale frammento è finita `§X`. Applica le riscritture tu, con `Edit`, e ricontrolla finché lo script non esce 0. Restano a carico tuo anche `CLAUDE.md` (se il file era `ONLINE`, l'`@-import` va sostituito con quelli dei frammenti che restano online) e i `SKILL.md` del plugin che citano il path.

Un riferimento appeso è drift **prodotto dalla bonifica stessa**: nasce con la patch che doveva migliorare la doc, e nessun segnale lo denuncia.

### 8. Passaggio di fase — rimisura, non riuso

Solo quando la fase `split` segue una fase `clean` nella stessa invocazione. **È il passo che rende le due fasi sequenziali invece che concorrenti**, e va eseguito per intero prima di toccare il fan-out della fase 2:

1. sweep dei puntatori della fase clean (§7), fino a exit 0;
2. **rimisura**: `doc-metrics.sh` sul perimetro — le riduzioni sono atterrate, i char sono altri;
3. **ripartizione**: `doc-partition.sh` sui numeri nuovi;
4. il perimetro della fase 2 sono **solo i file ancora `SPLIT` o `MERGE?`** dopo la rimisura — un sottoinsieme ricalcolato, mai la lista della fase 1.

Il punto 4 non è una precauzione formale: una parte dei candidati scende sotto soglia grazie alle sole riduzioni ed esce di scena. Partire dalla lista vecchia significa splittare file che non vanno più splittati.

**Fase split con perimetro vuoto = successo.** Se dopo la rimisura nessun file resta sopra soglia né sotto il pavimento, la fase 2 non ha lavoro: dichiaralo (`fase split: nessun file oltre soglia dopo le riduzioni`) e passa al §9. Non è un fallimento e non va segnalato come tale.

### 9. Chiudi

- Rigenera l'indice, **una volta sola in coda a tutte le fasi** (non fra clean e split: l'INDEX non è input della fase 2):
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
  ```
  **Exit 2 è il verdetto dello script**, non un comando fallito: l'indice è scritto, ma i TLDR elencati su stderr restano oltre il cap. È la stessa misura del §1 letta a valle — se esce 2 dopo una bonifica che doveva chiudere quelle voci, la bonifica non ha fatto il suo lavoro e va detto nel report. Exit 1 = indice non scritto, quello è un errore da risolvere.
- **Rimisura finale**: rilancia `doc-metrics.sh --online` e dichiara il delta prima/dopo. È l'unica verifica che la bonifica abbia prodotto l'effetto che si proponeva.
- **Riverifica i puntatori**: `check-doc-links.sh` (§7) deve uscire **0**. Se esce 2 lo sweep non è finito, e i riferimenti residui vanno nel report — non si chiude in silenzio.
- **Non stampare i diff** in chat. Solo la lista file dal contratto `APPLIED:`.
- **Stage, mai commit**: `git add -- <file>...`. Per un `DEL` il file è già sparito dal working tree, quindi serve `git add -A -- <path>`: senza `-A` la cancellazione non entra nell'indice e il commit del chiamante fa rinascere il file.
- Report finale, **una sezione per fase eseguita**: violazioni per verdetto, file toccati, footprint prima → dopo, riferimenti appesi risolti, voci non applicate. In modo auto aggiungi la riga di reversibilità: i file `NEW` prodotti da uno split non tornano indietro con `git checkout` e vanno rimossi a mano. Se restano voci `BLOCKING: si` non applicate, la riga di chiusura è **`doc NON conforme: <n> violazioni bloccanti`** con i file elencati — non un riepilogo neutro.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Bonifica ≠ prevenzione.** Questa skill è una campagna retroattiva. Le regole che valgono anche al momento della scrittura stanno già altrove: il cap TLDR dentro `build-index.sh` (exit 2 a ogni rigenerazione), l'as-is dentro il contratto che `doc-writer` legge a ogni invocazione. Se una violazione si ripresenta a ogni esecuzione, il fix non è rilanciare `lint-doc` — è spostare quella regola in un punto di enforcement.
- **La soglia non si negozia a runtime.** Se un file ci passa per pochi caratteri, resta sopra soglia: il numero sta nel contratto, e uno scostamento discusso caso per caso rende le due esecuzioni successive incoerenti.
- **`GEN` non si splitta a mano.** `INDEX.md` è un artefatto: se è troppo grande, la causa sono i TLDR dei file indicizzati, e il fix sta là.
- **Due fasi ≠ due commit.** La skill stagea e si ferma in entrambi i casi; separare `docs: riduzioni` da `docs: split topologia` rende il diff molto più leggibile, ma è una scelta del chiamante a valle, non un vincolo di qui.
