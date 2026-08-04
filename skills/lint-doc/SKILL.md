---
name: lint-doc
description: Misura la doc di progetto contro il contratto editoriale — file sopra soglia, TLDR-riassunto, residui storici, costo online, coordinate opache. Misure numeriche via doc-metrics.sh, giudizio via doc-auditor read-only, patch via doc-writer sulle voci approvate.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: sonnet
---

Confronta la doc di progetto col **contratto editoriale** (`${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md`) e trova le **violazioni**.

Input utente (perimetro doc: file, cartella, oppure vuoto = tutta la doc):
~~~human
$ARGUMENTS
~~~

## Cosa NON fa

**Non apre i sorgenti del progetto.** Mai. Per sapere che un file da 47.000 char è sopra soglia, che un TLDR racconta invece di agganciare, o che una sezione dice «prima era X, ora Y», il codice non serve.

È il taglio con la gemella `align-doc`, che misura la stessa doc contro il **codice** e deve aprirli tutti. Fondere le due farebbe leggere decine di KB di sorgenti a un agent che deve contare caratteri e riconoscere un changelog travestito.

## Numeri prima, giudizio dopo

Le soglie sono **numeri nel contratto**, non valutazioni: due esecuzioni sullo stesso albero devono dare lo stesso esito. Quindi il conteggio lo fa uno script, e all'agent resta solo ciò che un numero non cattura — se un TLDR *aggancia*, se una sezione è cronologia, dove passa il taglio di uno split.

### 1. Passo numerico

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/doc-metrics.sh" --docs-root "${user_config.doc_folder_name}" --online
```

Restituisce per ogni file: char, char del TLDR, flag (`SPLIT`, `TLDR>600`, `NOTLDR`, `ONLINE`, `GEN`) e il **footprint per-sessione** — `@-import` di `CLAUDE.md` **più** le entry hook `SessionStart`. Le due voci vanno lette insieme: gli `@-import` da soli sono circa il 70% del costo reale, e ottimizzare solo quelli lascia un terzo del problema sul tavolo.

Con `--format tsv` l'output è passabile tale e quale agli auditor: sono misure già fatte, non vanno ricontate.

Registra il totale **prima** dell'intervento: senza baseline il "dopo" non dice niente.

### 2. Fan-out doc-auditor

Un `Task` con `subagent_type: doc-auditor` per **gruppo di file** (per cartella, o i file grossi uno per uno), tutti nello stesso messaggio → parallelo. Read-only ⇒ nessun conflitto sul working tree. Massimo 4 auditor per esecuzione.

```
Perimetro:
- Doc: <file o cartella>

Fonte di verità: contratto

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}
Contratto doc: ${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md — leggilo per primo.
Criteri di selezione: ${CLAUDE_PLUGIN_ROOT}/docs/doc-criteria.md — otto test e sette tipologie offline, da leggere quando la collocazione non è ovvia.
Prefisso ID: <sigla corta, es. LINT-DECK>

Misure pre-calcolate (fidati di queste, non ricontare):
<righe TSV di doc-metrics.sh per i file di questo perimetro>

Non aprire i sorgenti del progetto. Cerca: residui storici, TLDR-riassunto,
file sopra soglia (col taglio proposto), layer sbagliato, motivazioni finite online,
costo online ingiustificato, coordinate opache, formato. Ritorna solo il registro.

Bloccanti: TLDR oltre il cap e TLDR-riassunto sono SEVERITY: alta per definizione,
mai media o bassa — non sono giudizi di gusto. Marcali `BLOCKING: si`.
```

### 3. Consolida il registro

Un unico file ordinato per severità. Colloca:

- task attiva con `**Folder**:` popolato → `<task folder>/lint-doc-findings.md`;
- altrimenti `AskUserQuestion`: nuova scratch folder (`/loom-works:scratch-new`) oppure registro solo in chat.

Mai dentro `{docs_root}/`: è materiale di lavoro, non doc di progetto.

In chat va la **sintesi** — una riga per finding (`ID · severità · file · violazione · verdetto proposto`) — più il footprint misurato. Il dettaglio resta nel file.

### 4. Gate dei verdetti — in blocco

Come in `align-doc`: i verdetti si raccolgono **una volta sola sul registro completo**. `AskUserQuestion` (prima il ping TTS) con: conferma tutti · conferma tranne alcuni ID · solo severità alta · nessuno.

Annota il verdetto finale su ogni voce del registro.

**Le voci `BLOCKING: si` non si declassano.** Un TLDR oltre il cap o che riassume invece di agganciare è un numero e una forma, non una preferenza: entra sempre nel gruppo applicato, anche sotto l'opzione «solo severità alta». L'utente resta libero di scegliere «nessuno» e non applicare niente — ma allora il report finale (§7) dichiara la doc **non conforme**, con l'elenco delle voci residue. Il gate decide *quando* si bonifica, mai *se* la violazione esiste.

### 5. Applica

Raggruppa per **file doc target**, un `doc-writer` per gruppo. Gruppi che **non condividono nessun file target** vanno in **parallelo**, nello stesso messaggio: il vincolo è «mai due writer sullo stesso file», non «mai due writer». Sequenziali solo dove i gruppi si sovrappongono — e se si sovrappongono, di norma erano un gruppo solo.

Con più writer in volo il gate two-phase dello split (§6) va **risolto prima**: nessuno può fermarsi a chiedere conferma dell'outline mentre gli altri scrivono, o N domande si aprono sullo stesso schermo. L'outline la approva il gate dei verdetti (§4); passala già validata nel prompt e dichiaralo, così il writer va dritto alla scrittura.

Dai a ogni writer il perimetro dei file che può toccare e l'istruzione di **segnalare invece di editare** ciò che sta fuori: uno split rompe puntatori anche in file assegnati a un altro gruppo, e due writer che si contendono lo stesso puntatore lo riscrivono a vicenda. Lo sweep lo fa il chiamante, a valle (§6).

Le violazioni non-split (residui storici, TLDR da riscrivere, motivazioni da spostare offline, formato) passano come una normale nozione → patch.

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
```

### 6. Split e merge — i fix che non sono "nozione → patch"

Split e merge riscrivono la topologia della doc, non una sezione. Quattro vincoli:

- **Riduzioni prima del taglio.** Eco, cronaca e inventari si tolgono *prima* di decidere dove tagliare: sono spesso migliaia di char, e un frammento dimensionato su peso che sta per sparire nasce a ridosso della soglia — cioè già candidato al prossimo split.
- **Taglio per perimetro, mai per byte.** Frammenti da 7.500 char ottenuti tagliando a metà sono peggio dell'originale: nessuno dei due è cercabile.
- **Ogni frammento nasce col proprio TLDR-ancora.** Un file splittato in N perde l'unica ancora che aveva: senza un TLDR per frammento lo split *peggiora* la reperibilità invece di migliorarla.
- **Outline validata prima della scrittura.** Il `doc-writer` ha il gate two-phase (§3.5 del suo contratto): con **un solo** writer in volo, passa lo split con `NEW file con ≥3 H2` e lascia che chieda conferma via `AskUserQuestion`. Con più writer in parallelo l'outline va approvata al gate dei verdetti (§4) e passata già validata — vedi §5.

**Il merge è l'operazione inversa, e va usata.** Un file sotto il pavimento del contratto non si fonde d'ufficio: si riesamina il suo perimetro di ricerca. Se è distinto, sopravvive e lo si dichiara nel registro; se è un residuo, confluisce nel vicino di perimetro e l'INDEX perde una voce. Senza questo ramo lo split è a senso unico: la doc si frammenta a ogni passata e nessuno nota il file che si è svuotato.

Dopo uno split o un merge, **i riferimenti al file vecchio restano appesi**. Prima di chiudere:

```bash
grep -rn "<vecchio-path>" --include='*.md' <PROJECT_ROOT> | grep -v "<task folder>"
```

Aggiorna quelli che trovi: altri file doc, `CLAUDE.md` (se il file era `ONLINE`, l'`@-import` va sostituito con quelli dei frammenti che restano online), e i `SKILL.md` del plugin che citano il path. Un riferimento a un file che non esiste più è un drift creato dalla bonifica.

### 7. Chiudi

- Rigenera l'indice (uno split o un TLDR riscritto lo richiedono sempre):
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
  ```
  **Exit 2 è il verdetto dello script**, non un comando fallito: l'indice è scritto, ma i TLDR elencati su stderr restano oltre il cap. È la stessa misura del §1 letta a valle — se esce 2 dopo una bonifica che doveva chiudere quelle voci, la bonifica non ha fatto il suo lavoro e va detto nel report. Exit 1 = indice non scritto, quello è un errore da risolvere.
- **Rimisura**: rilancia `doc-metrics.sh --online` e dichiara il delta prima/dopo. È l'unica verifica che la bonifica abbia prodotto l'effetto che si proponeva.
- **Non stampare i diff** in chat. Solo la lista file dal contratto `APPLIED:`.
- **Stage, mai commit**: `git add -- <file>...`.
- Report finale: violazioni per verdetto, file toccati, footprint prima → dopo, voci non applicate. Se restano voci `BLOCKING: si` non applicate, la riga di chiusura è **`doc NON conforme: <n> violazioni bloccanti`** con i file elencati — non un riepilogo neutro.

## Convenzione TTS

Prima di ogni `AskUserQuestion`:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

## Note

- **Bonifica ≠ prevenzione.** Questa skill è una campagna retroattiva. Le regole che valgono anche al momento della scrittura stanno già altrove: il cap TLDR dentro `build-index.sh` (exit 2 a ogni rigenerazione), l'as-is dentro il contratto che `doc-writer` legge a ogni invocazione. Se una violazione si ripresenta a ogni esecuzione, il fix non è rilanciare `lint-doc` — è spostare quella regola in un punto di enforcement.
- **La soglia non si negozia a runtime.** Se un file ci passa per pochi caratteri, resta sopra soglia: il numero sta nel contratto, e uno scostamento discusso caso per caso rende le due esecuzioni successive incoerenti.
- **`GEN` non si splitta a mano.** `INDEX.md` è un artefatto: se è troppo grande, la causa sono i TLDR dei file indicizzati, e il fix sta là.
