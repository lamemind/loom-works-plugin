---
name: drain-doc
description: Svuota l'inbox doc — inventario deterministico, un doc-router per file inbox, raggruppamento per file target, un doc-writer per gruppo, guardiani, collaudo doc-verifier, commit. Paga i criteri dipendenti una volta per batch invece di una per nozione. Token `plan`: inventario e piano delle invocazioni, senza scrivere niente.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task
model: sonnet
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `${DOCS_ROOT}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Porta le nozioni di `${DOCS_ROOT}/inbox/` nei quattro layer: verdetto, file target, patch, collaudo, commit.

Input utente (perimetro: nomi di file inbox, un numero, `tutto`, `urgenti` · più il token `plan`):
~~~human
$ARGUMENTS
~~~

## Perché esisti separata da `lint-doc` e `align-doc`

Quelle due misurano doc **già collocata** — contro il contratto la prima, contro la fonte nativa la seconda. Qui la doc non è ancora collocata, e l'operazione è un **routing**, non una misura.

Il tuo mestiere sono i criteri **dipendenti**: *eco*, *sorpresa* e *sopravvive al refactor* dipendono dal codice, *inventario* e *calco* dalla fonte viva, *fonte unica* e *quale file* dal resto della doc. Il checkpoint che ha scritto il file inbox ha pagato solo gli indipendenti, ed è il motivo per cui costava zero. Qui si paga il resto, **una volta per batch**.

## Non presidiata — nessuna domanda

`AskUserQuestion` non è nel toolset, e non è una dimenticanza: giri anche di notte, dentro una GitHub Action, dove non c'è nessuno a rispondere. Il collaudo lo fa `doc-verifier`, non un umano.

**La valvola di sicurezza è che il rifiuto è una non-azione.** Se il collaudo boccia, il file inbox *resta in coda*: nessun dato si perde e nessuno va svegliato. È questo che rende licenziabile l'umano dal ciclo — non la fiducia nel giudice, la reversibilità dello scarto.

### `plan` — inventario e fermati

Col token la skill esegue §1 e §2, stampa il piano e **si ferma lì**: niente router, niente writer, niente commit. Il costo sono due chiamate bash e nessun subagent.

Stampa la coda con char, età e priorità, quanti file la presa in carico raccoglierebbe, e le righe di comando dei router che partirebbero. **Non stampa i gruppi**: il raggruppamento per target è calcolabile solo *dopo* il routing, che è l'unico passo che sa dove ogni nozione va a finire.

## Mai staged fino al commit

Lo stage git è uno **per worktree, non per sessione**: un file lasciato nell'indice viene raccolto dal `git add -A` di qualunque altra sessione che committi nel frattempo, e finisce in un commit che parla d'altro.

Da cui tre regole, che valgono per l'intera run:

- **Guardia in ingresso.** Se `git diff --cached --quiet` esce non-zero, l'indice è già popolato da qualcun altro: **fermati** e dillo. Un commit con pathspec porterebbe via lavoro non tuo.
- **La patch vive solo nel working tree.** Guardiani e `doc-verifier` leggono `git diff` **non-staged**. Nessun `git add` prima del momento del commit.
- **Il commit è una catena sola**, con pathspec esplicita del gruppo: `git add -- <path...>` immediatamente seguito da `git commit -m "..." -- <path...>`. La finestra scende a millisecondi, e non esiste mai un indice popolato in attesa di un giudizio.

Il rollback è `git checkout -- <path>` sui `MOD` e `rm -- <path>` sui `NEW`, che non sono in HEAD e quindi `git checkout` non li toglie.

## 1. Inventario — deterministico, zero giudizio

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --inbox --format tsv
```

Ritorna la coda **già ordinata e già triata**: i file con sentinella di drift in testa, poi il più vecchio per primo dentro ogni classe. Colonne `PRIO` (`urgente` | `normale`) e `DRIFT` (i file doc che quella nozione dovrebbe correggere). L'età viene dal commit che ha aggiunto il file, non dall'mtime.

**L'ordine lo decide lo script, non tu.** Due lettori della stessa coda devono vederla nello stesso ordine, e la riga `> **PRIORITY**: 🚨` sulla riga 4 di un file inbox è un dato che il produttore ha scritto — non si rivaluta qui. Un file senza quella riga vale priorità normale: è il caso di maggioranza, e i file nati prima che le sentinelle esistessero non vanno ritoccati.

Servono altre due misure, e vanno prese **adesso** perché sono baseline:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --format tsv
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
```

- La prima è la misura per-file di tutta la doc: la passi ai router, che così non ricontano e possono rispettare la regola del target sopra soglia.
- La seconda è il baseline dei riferimenti appesi. **Senza, il collaudo non sa distinguere un `DANGLING` introdotto dalla patch da uno che c'era già** — e il secondo non è colpa di nessuno. Exit 2 all'ingresso non è un blocco: è il numero da cui si misura il delta.

## 2. Presa in carico

Dal perimetro nell'input:

- **vuoto o `tutto`** → l'intera coda
- **`urgenti`** → i soli file con `PRIO: urgente`
- **un numero** (`3`) → i primi N della coda, che sono gli urgenti se ce ne sono e i più vecchi altrimenti
- **uno o più nomi** → quei file, nell'ordine della coda

Coda vuota è un esito normale e va detto in una riga: nessun file inbox, niente da smaltire, stop. Non è un fallimento e non va cercato altrove il lavoro. Lo stesso vale per `urgenti` su una coda senza sentinelle: dillo e fermati, non ripiegare sulla coda intera — chi ha chiesto gli urgenti sta pagando un giro corto apposta.

**Un lotto urgente gira sotto il tetto, ed è il punto.** Il cap di 8 file dice quando lo smaltimento non è più *opzionale*; non dice quando è *permesso*. Una nozione con la sentinella sta curando una pagina già falsa, e farla aspettare la soglia tiene in piedi la bugia per tutto il tempo dell'attesa.

## 3. Routing — un `doc-router` per file inbox, in parallelo

Un `Task` con `subagent_type: doc-router` per file preso in carico, **tutti nello stesso messaggio**. Read-only ⇒ nessun conflitto sul working tree, ed è l'unico passo che parallelizza.

```
Nozioni non collocate — dal file inbox <path del file>:

<il contenuto del file inbox, dalla riga dopo il TLDR in giù>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — i criteri dipendenti sono il tuo mestiere.
Prefisso ID: INBOX<n>
Sentinella di drift: <i path della colonna DRIFT, se il file ne porta — altrimenti ometti la riga>
  Sono le pagine che chi ha catturato la nozione ritiene già FALSE. Aprile: se la nozione le corregge, sono il target naturale. Non è un ordine — un candidato ancora vero non le rende tali.

Misure pre-calcolate (fidati di queste, non ricontare):
<le righe PATH / CHAR / TLDR / FLAGS di doc-metrics.sh>

Ritorna solo il registro.
```

Il **prefisso è diverso per ogni router** (`INBOX1`, `INBOX2`, …): girano in parallelo e senza prefissi distinti gli ID delle rotte collidono, che è il modo in cui due nozioni diverse finiscono per sembrare la stessa nel referto.

**Tieni la corrispondenza rotta → file inbox di provenienza.** È l'unica informazione che dice quale file si può rimuovere alla fine (§8), e nessuno dei due agenti a valle la porta con sé.

## 4. Raggruppamento per target — codice, non giudizio

Questo passo non è un agente e non è una valutazione: è una regola meccanica sui registri che hai in mano.

- **Chiave di gruppo = il path del `TARGET:`**, normalizzato — via il `§Sezione`, via il prefisso `NEW `. `foo.md §A` e `NEW foo.md` sono lo **stesso** gruppo.
- **Solo `online` e `offline` formano gruppi.** Le rotte `→ codice`, `→ fonte viva` e `drop` hanno `TARGET: —`: non atterrano da nessuna parte, non vanno a nessun writer, e le riporti tu nel corpo del commit e nel referto.
- **Rotte da file inbox diversi con lo stesso target finiscono nello stesso gruppo.** È la ragione per cui questo passo esiste: due writer sullo stesso file si sovrascrivono a vicenda, e il sintomo è una nozione persa senza nessun errore.
- **Nessun cap alla taglia del gruppo**, ma la taglia si misura: quante nozioni e quanti char di materiale, nel referto accanto all'esito del collaudo.

Zero gruppi con rotte non vuote è un esito legittimo — un lotto interamente `drop` è il filtro che funziona. Salta a §8: i file inbox si rimuovono lo stesso, il verdetto è nel commit.

## 5. Il ciclo per gruppo è sequenziale

Dal writer in poi si lavora **un gruppo alla volta**, ciclo intero: scrittura → guardiani → collaudo → commit o rollback. Poi il gruppo dopo.

Non è prudenza, sono due vincoli concreti:

- **Il rollback deve essere sicuro.** `git checkout -- <path>` su un working tree dove un altro writer sta scrivendo porta via anche il suo lavoro.
- **Due file sono condivisi da tutti i gruppi**: `INDEX.md`, che ogni rebuild riscrive, e `CLAUDE.md`, che due rotte `online` in gruppi diversi toccano entrambe. Nessuno dei due si può assegnare a un gruppo solo.

Il parallelismo di questa skill sta tutto al passo 3, dove nessuno scrive.

### 5a. Scrittura — un `doc-writer` per gruppo

`Task` con `subagent_type: doc-writer`. Verdetto e target sono **già decisi**: il writer non li rivaluta.

```
Rotte da applicare — verdetto e target sono già decisi e vincolanti, non rivalutarli:

<le voci del registro per questo target: NOTION / VERDICT / TARGET / TLDR / POINTER / WRITE>

Contesto:
<il testo integrale delle nozioni dai file inbox di provenienza>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo, ha la parola finale su convenzioni e soglie.
Formule TLDR: ${CLAUDE_PLUGIN_ROOT}/docs/tldr-formats.md

Applica le patch direttamente (Write/Edit), incluso l'eventuale patch a CLAUDE.md; non committare, non rigenerare l'indice, non stagiare niente. Ritorna il contratto APPLIED: (marker NEW/MOD/DEL per ogni file) + SPLIT_MAP: se sposti contenuto + INDEX_REBUILD_NEEDED.
```

Un `APPLIED:` vuoto col razionale è un esito previsto — il writer non ha trovato materiale sufficiente per scrivere qualcosa di vero. Non è un rollback: non c'è niente da annullare. Il file inbox resta in coda, e il motivo va nel referto.

### 5b. Guardiani deterministici

Nell'ordine, sul working tree così com'è:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"      # solo se INDEX_REBUILD_NEEDED: yes
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/check-doc-links.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh"
```

**Exit 2 è un verdetto, non un comando fallito** — su `build-index.sh` significa indice scritto ma TLDR oltre il cap, su `check-doc-links.sh` riferimenti appesi. Su `doc-metrics.sh` l'exit è sempre 0: è una misura, e il flag `SPLIT` o `MERGE?` che compare va letto, non trattato come errore.

Sui riferimenti appesi conta solo il **delta contro il baseline del §1**: quelli che c'erano già non li ha causati questa patch.

Non riparare niente qui. Gli esiti si passano al collaudo, che decide se sono rollback o coda.

### 5c. Collaudo — `doc-verifier` sul diff

`Task` con `subagent_type: doc-verifier`, una volta per gruppo.

```
Patch da collaudare — gruppo <target>.

File toccati (dal contratto APPLIED: del writer):
<la lista coi marker NEW / MOD / DEL>

Registro delle rotte che hanno ordinato questa patch:
<le voci del registro del router per questo gruppo>

Docs root: <PROJECT_ROOT>/${DOCS_ROOT}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.

Esiti dei guardiani (fatti deterministici, non ricontarli):
- build-index.sh: exit <n> <+ i TLDR oltre cap che ha elencato, se ce ne sono>
- check-doc-links.sh: exit <n> — riferimenti appesi NUOVI rispetto al baseline: <la lista, o «nessuno»>
- doc-metrics.sh: <le righe dei soli file toccati, con i flag>

La patch non è staged: leggila con `git diff` sul working tree.
Ritorna solo il referto.
```

Passagli **il delta** dei riferimenti appesi, non l'output grezzo dello script: la distinzione fra introdotto e preesistente è già stata calcolata al §5b, e rifarla dentro l'agente significa affidarla a un giudizio invece che a due liste.

### 5d. Commit o rollback

Il referto porta `OUTCOME: pass | rollback`. Una `LABEL: accodato` **non** boccia: è topologia che la patch ha rivelato, non causato — il file esce col flag `SPLIT` alla prossima misura e `lint-doc` lo raccoglie da sé, senza bisogno di un registro. La misura è lo stato.

**`pass` → commit**, catena unica con pathspec esplicita:

```bash
git add -- <path...> && git commit -m "docs(drain): <target>" -m "<corpo>" -- <path...>
```

- La pathspec sono **tutti** i file di `APPLIED:` più `INDEX.md` se il rebuild l'ha toccato. Su un `DEL` serve `git add -A -- <path>`, o la cancellazione non entra nell'indice e il commit fa rinascere il file.
- Il **corpo** porta le rotte non atterrate di questo lotto — i `drop` col motivo e il custode, i `→ codice` e `→ fonte viva` col puntatore. È lì che il verdetto resta greppabile, coerente col principio che la cronaca sta in git e non nella doc.

**`rollback` → annulla il gruppo**, per file secondo il marker: `MOD` → `git checkout -- <path>` · `NEW` → `rm -- <path>` · `DEL` → `git checkout -- <path>`. Poi **rigenera l'indice**: il rebuild del §5b ha già scritto la voce di un file che adesso non esiste più, e lasciarla lì è drift prodotto dal rollback stesso.

I file inbox di provenienza di quel gruppo **restano in coda**, interi. Il motivo — la `RULE:` della violazione, non «bocciato» — va nel referto.

## 6. Il gruppo dopo

Torna al §5a. Se un gruppo ha fatto rollback, i successivi girano lo stesso: sono target diversi e non hanno niente a che vedere.

## 7. Un file inbox si rimuove solo quando è smaltito **per intero**

Le nozioni di un file inbox possono finire in gruppi diversi, e un gruppo può essere bocciato mentre gli altri passano. In quel caso **il file resta intero in coda**, nozioni già committate comprese.

Al giro successivo il router ripaga il routing su tutte, e scarta come «già scritto altrove» quelle che sono atterrate — è un criterio dipendente, cioè esattamente il suo mestiere. Costa un re-routing sprecato, non perde niente, e non muta il file: **un file inbox è immutabile, o si rimuove o resta com'è.**

Un file è rimovibile quando nessuna delle sue rotte appartiene a un gruppo bocciato. Le rotte senza target (`drop`, `→ codice`, `→ fonte viva`) non bloccano: il loro verdetto è già entrato in un commit.

## 8. Chiudi

```bash
git rm -- <file inbox interamente smaltiti>
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh"
git add -- ${DOCS_ROOT}/reference/INDEX.md
git commit -m "docs(drain): smaltiti <n> file inbox" -- <file inbox rimossi> ${DOCS_ROOT}/reference/INDEX.md
```

Il rebuild finale toglie dall'INDEX la sezione inbox — che `build-index.sh` emette solo se la cartella ha almeno un file indicizzabile, quindi su inbox svuotata sparisce da sola, e con essa la riga di precedenza.

Poi `check-doc-links.sh` deve uscire **0**: se esce 2 con voci nuove rispetto al baseline, elencale nel referto — non si chiude in silenzio.

**`git push`** una volta, a fine run. Se fallisce (branch dietro, remote assente) riportalo e fermati lì: i commit sono locali e nessuno li perde. Non forzare niente.

## 9. Referto

Su disco, non in chat — il contesto dell'orchestratore è l'unica risorsa che può far fallire il ciclo, e ri-echeggiare ciò che sta già su un file lo consuma per niente. Dove atterra lo risolve uno script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/resolve-registry-path.sh" --name drain-doc-referto.md
```

Cosa contiene, una riga per voce:

- **coda in ingresso**: file, char, età, priorità
- **un blocco per gruppo**: target · quante nozioni · quanti char di materiale · esito del collaudo · le violazioni con etichetta e regola
- **rotte non atterrate**: `drop`, `→ codice`, `→ fonte viva`, col motivo
- **file inbox rimossi** e **file rimasti in coda**, questi ultimi col motivo
- **lavoro accodato**: i file usciti col flag `SPLIT` o `MERGE?`, che `lint-doc` raccoglierà

In chat va solo il consuntivo: quanti file drenati su quanti, quanti gruppi, quanti rollback, cosa resta in coda.

Poi il ping TTS:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "inbox drained"
```

## Note

- **Re-entrante senza bookkeeping.** Se la sessione muore a metà, si rilancia: i file inbox già rimossi non sono più in coda, quelli bocciati ci sono ancora. Non c'è stato da recuperare perché **la misura è lo stato** — la stessa proprietà per cui `lint-doc` non tiene un registro di ciò che ha già fatto.
- **Nessun undo oltre il commit.** Lo smaltimento non conserva copie: un file inbox rimosso vive in git come qualunque altra cosa, e questo basta.
- **Non toccare i file di runtime**: `${DOCS_ROOT}/tasks/`, `${DOCS_ROOT}/current-task.md`. Non sono doc, e nessuna rotta può puntarci.
- **Il primo `build-index.sh` su un progetto con un INDEX scritto a mano lo riscrive per intero**, da tabella a bullet list. Non è un guasto — è il formato che il generatore produce — ma su un progetto terzo quella migrazione arriva dentro un commit di smaltimento che parla d'altro. Dichiaralo nel referto.
