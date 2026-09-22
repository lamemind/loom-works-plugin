# Il registro ADR — formato del record e sede

Contratto per chi **scrive e interroga** il registro delle decisioni: la sede su disco, i campi di un record, la regola di immutabilità e la forma della supersessione.

Il registro sta **fuori dal sistema documentale**. La doc è as-is — stato corrente, niente date, niente cronaca — e una decisione è per costruzione datata e motivata: nei quattro layer non ha un posto. Il registro non è un quinto layer: è stato di task, e nessun attore del sistema doc lo legge, lo misura o lo instrada.

Oggi il registro riceve **un solo tipo di record**: lo scarto motivato di una segnalazione. Le voci `D{N}` e `P{N}` che `preflight-task` scrive in `## Decisions` **non entrano**: vivono nel task file finché la task vive e, dopo `clean-tasks`, solo in git history, recuperabili dal commit di purge (`git show <commit>~1 -- <path>`).

## La sede

`{docs_root}/adr/`, sorella di `tasks/`. Un file per record, nessuna sottocartella, nessun indice.

Sta sotto la docs-root perché è stato di task, come `tasks/`, e perché la docs-root è per-progetto: un progetto che tiene la doc in `runtime/` ha il registro in `runtime/adr/`. Chi risolve il path non lo cabla — lo chiede a `lw_docs_root`.

**Un file per record, mai un file unico.** In detached più sessioni committano nello stesso worktree: un file unico entrerebbe intero nel commit della prima sessione che lo tocca, record altrui compresi. `tasks.md` mostra ogni giorno cosa costa un file condiviso fra lane.

**Il nome del file è l'id del record**: `YYYY-MM-DD-HHMM-<slug>.md`. La data in testa fa ordinare `ls` in cronologia senza bisogno di un indice. Lo slug lo dà chi scrive (`--slug`, come `inbox.sh new`): uno slug derivato dal testo libero non sarebbe prevedibile per chi deve citarlo in `Supera`.

## Struttura di un record

```markdown
# Il deck ricalcola la gerarchia epiche a ogni tick invece che sul cambio di HEAD

- **Tipo**: scarto
- **Data**: 2026-09-22 16:40
- **Chi**: umano
- **Ancore**: loom-deck/src/epic-hierarchy.ts, loom-deck/src/hooks.ts
- **Supera**: 2026-08-10-0900-poll-deck, 2026-09-01-1140-cache-fredda#D3

## Perché

Misurato 16,16 ms su 106 task file, dentro il budget del tick da 1,5 s. Il gate su HEAD
esiste già per la passata di `git log` e coprirebbe anche questa, ma il costo che
eviterebbe è sotto la soglia di percezione: si rivaluta se il repo supera le 300 task.
```

- **Riga 1 è la segnalazione**, per esteso e su una riga: è ciò che l'agente confronta con quello che sta per risollevare.
- **L'header è a campi**, nell'ordine canonico `Tipo` · `Data` · `Chi` · `Ancore` · `Supera`. Solo `Supera` è facoltativo.
- **Il corpo è `## Perché`**, prosa libera e non vuota. Sta dopo l'header perché la query stampa l'header e lascia il corpo a chi apre il file.

| Campo | Dominio | Regola |
|---|---|---|
| `Tipo` | `scarto` | vocabolario chiuso |
| `Data` | `YYYY-MM-DD HH:MM` | la scrive il comando |
| `Chi` | `umano` \| `agente` | obbligatorio, **senza default** |
| `Ancore` | path relativi alla project root, separati da `, ` | almeno uno, ognuno deve esistere |
| `Supera` | `<id>[#<voce>]`, separati da `, ` | facoltativo, ogni `<id>` deve esistere in `adr/` |

`Tipo` ha oggi un valore solo. Il vocabolario è chiuso e non aperto a testo libero perché un tipo inventato da chi scrive non sarebbe interrogabile da chi legge; chi ne aggiunge uno lo dichiara qui nello stesso commit.

**`Chi` non ha default**, ed è la scelta che rende il registro campionabile: lo scarto deciso da un agente è esattamente ciò che l'umano vuole poter rileggere a campione. Un default lo renderebbe indistinguibile da uno deciso da una persona.

**`Ancore` porta solo path**, verificati sul filesystem con `test -e`. Keyword e id task non hanno un campo proprio: la query fa match testuale sul record intero, e stanno già nella segnalazione e nel perché. Un campo tipizzato in più sarebbe una seconda sorgente per la stessa ricerca, e le due divergerebbero. Il path si verifica sul filesystem e non su `git ls-files` perché è ciò che un futuro rilevatore «path modificato dopo la data del record» leggerà, accoppiando `test -e` a `git log --since`.

## Immutabilità

**Un record scritto non si modifica e non si cancella.** Il comando di scrittura rifiuta un path che esiste già (exit 2): è tutta l'implementazione dell'invariante, e non richiede né un lock né un hash.

Una decisione superata si marca con un **record nuovo** che nomina il vecchio in `Supera`. Il vecchio resta leggibile dov'è: chi cerca capisce cosa si era deciso *e* cosa lo ha sostituito, che è più di quanto direbbe un record riscritto.

`Supera` accetta **N valori** e sa indirizzare la **singola voce** con `<id>#<voce>`. Le due cose stanno nel formato dal primo record, non perché servano subito, ma perché dopo il primo record non si correggono più: allargare un campo a valore singolo significa avere già su disco record che il parser nuovo legge in un modo e il vecchio in un altro.

- Un `<id>` che non esiste in `adr/` è un rifiuto (exit 1): un refuso in `Supera` nasconderebbe niente per sempre, in silenzio.
- **Il frammento dopo `#` non si valida.** Il registro oggi non ha un parser di voci — i record con voci arriveranno col filtro in ingresso — e un vincolo scritto adesso sulla loro forma sarebbe una premessa non misurata.

## Cosa la query mostra e cosa nasconde

`adr.sh cerca <ancora>` fa **match testuale sul record intero**: la segnalazione, l'header e il perché. Copre quindi path, keyword e id task con una sola regola. Un id task si cerca **a parola intera** — `T16` non trova `T161`, come in `resolve-task.sh --children`.

I record superati **non compaiono senza `--superate`**, e la regola distingue i due indirizzi:

- **nominato intero** (`Supera: 2026-08-10-0900-poll-deck`) → il record è superato, sparisce dalla query.
- **nominato con frammento** (`Supera: 2026-09-01-1140-cache-fredda#D3`) → il record **resta visibile**, con l'annotazione dei frammenti superati da altri. Nascondere un record intero perché un altro ne supera una voce sola sarebbe nascondere ciò che è ancora vivo.

L'annotazione stampa i frammenti trovati nei `Supera` altrui, non il testo della voce: non richiede un parser di voci, e resterà vera quando i record con voci arriveranno.

## Il comando

Un solo script, `scripts/task/adr.sh`, con due sottocomandi. Il dettaglio d'uso e gli exit code stanno nel suo header; qui il contratto di forma.

```bash
adr.sh scarta --slug <slug> --chi umano|agente --segnalazione <testo> \
              --ancora <path> [--ancora <path>]... \
              [--supera <id>[#<voce>]]... [--perche <testo>] [--no-commit]

adr.sh cerca <ancora> [--superate]
```

**`scarta` committa da sé** il solo file del record, con pathspec e senza push. Il chiamante tipico è il modello in chat, in una sessione detached dove nessun altro commit nominerà quel file: un record non committato è uno scarto che può ancora sparire. Chi batcha — una skill che chiude con un commit suo — passa `--no-commit`.

## Il registro non entra nel sistema doc

Due esclusioni, entrambe su `adr/`, e nessun'altra:

- `doc_excluded` in `lib-doc.sh` — la usa `doc-metrics.sh`, che percorre la docs-root intera. Senza, ogni record sotto i 3.000 caratteri prenderebbe `MERGE?` e il registro diventerebbe una coda di lavoro per `rebalance-doc`.
- il `case` del perimetro in `check-doc-links.sh` — senza, ogni path citato in `Ancore` diventerebbe `DANGLING` per sempre su un file che per contratto non si può riscrivere.

`md-wrap.py` non ha un canale di esclusione e non gli serve: i record li scrive uno script, a paragrafi su una riga.
