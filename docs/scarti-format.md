# Il registro degli scarti — formato del record e sede

Contratto per chi **scrive e interroga** il registro degli scarti: la sede su disco, i campi di un record, la regola di immutabilità, la forma della supersessione e la migrazione dalla sede di prima.

Il registro sta **fuori dal sistema documentale**. La doc è as-is — stato corrente, niente date, niente cronaca — e uno scarto è per costruzione datato e motivato: nei quattro layer non ha un posto. Il registro non è un quinto layer: è stato di task, e nessun attore del sistema doc lo legge, lo misura o lo instrada.

Il registro riceve **un solo tipo di record**: lo scarto motivato di una segnalazione. Le voci `D{N}` e `P{N}` che `preflight-task` scrive in `## Decisions` **non entrano**: vivono nel task file finché la task vive e, dopo `clean-tasks`, solo in git history, recuperabili dal commit di purge (`git show <commit>~1 -- <path>`).

## La sede

`{docs_root}/scarti/`, sorella di `tasks/`. Un file per record, nessuna sottocartella, nessun indice.

Sta sotto la docs-root perché è stato di task, come `tasks/`, e perché la docs-root è per-progetto: un progetto che tiene la doc in `runtime/` ha il registro in `runtime/scarti/`. Chi risolve il path non lo cabla — lo chiede a `lw_docs_root`.

**Il registro non sta in `adr/`.** Quella cartella è delle decisioni che confermano o cambiano un disegno, e l'hook di sessione fa tacere l'agente su ogni record che `cerca` trova. Una decisione positiva letta come scarto silenzierebbe una segnalazione che nessuno ha scartato.

**Un file per record, mai un file unico.** In detached più sessioni committano nello stesso worktree: un file unico entrerebbe intero nel commit della prima sessione che lo tocca, record altrui compresi. `tasks.md` mostra ogni giorno cosa costa un file condiviso fra sessioni.

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
- **L'header è a campi**, nell'ordine canonico `Tipo` · `Data` · `Chi` · `Delega` · `Ancore` · `Supera`. `Delega` compare solo con `Chi: delega`, `Supera` solo quando il record ne supera un altro; gli altri ci sono sempre.
- **Il corpo è `## Perché`**, prosa libera e non vuota. Sta dopo l'header perché la query stampa l'header e lascia il corpo a chi apre il file.

| Campo | Dominio | Regola |
|---|---|---|
| `Tipo` | `scarto` | un valore solo, sempre presente |
| `Data` | `YYYY-MM-DD HH:MM` | la scrive il comando |
| `Chi` | `umano` \| `agente` \| `delega` | obbligatorio, **senza default** |
| `Delega` | testo libero, una riga | le parole con cui l'utente ha dato la delega, alla lettera; obbligatorio con `Chi: delega`, un rifiuto con gli altri autori |
| `Ancore` | path relativi alla project root, separati da `, ` | almeno uno, ognuno deve esistere |
| `Supera` | `<id>[#<voce>]`, separati da `, ` | facoltativo, ogni `<id>` deve esistere in `scarti/` |

**`Tipo` vale sempre `scarto`, e resta** perché è ciò che distingue uno scarto da ogni altro file dentro `adr/`: lo leggono `scarti.sh migra` e l'avviso di registro non migrato (§La sede di prima). Un record lo porta dalla nascita, e i record già scritti non si riscrivono: toglierlo dai record nuovi lascerebbe sul disco due forme dello stesso record.

**`Chi` non ha default**, ed è la scelta che rende il registro campionabile: lo scarto deciso da un agente è esattamente ciò che l'umano vuole poter rileggere a campione. Un default lo renderebbe indistinguibile da uno deciso da una persona.

**`delega` è lo scarto che l'orchestrator di un perimetro orchestrabile decide su una delega dell'utente**, data nella chat dell'orchestrator. Non è dell'umano, che non ha letto la segnalazione, né dell'agente che decide da sé, e scritto come uno dei due falserebbe chi campiona l'uno o l'altro. Il record porta in `Delega` le parole con cui l'utente ha dato la delega, e senza è un rifiuto: sono ciò che riconduce lo scarto all'umano che l'ha affidato. Le porta il record e non solo lo scenario di triage dello stesso scarto, perché `scarti.sh scarta` si chiama anche da solo, senza scenario, e un record non si riscrive — il campo che manca alla nascita non si aggiunge più. Su un altro autore `Delega` è un rifiuto, perché il record non ha dove scriverlo.

**`Ancore` porta solo path**, verificati sul filesystem con `test -e`. Keyword e id task non hanno un campo proprio: la query fa match testuale sul record intero, e stanno già nella segnalazione e nel perché. Un campo tipizzato in più sarebbe una seconda sorgente per la stessa ricerca, e le due divergerebbero. Il path si verifica sul filesystem e non su `git ls-files` perché è ciò che un futuro rilevatore «path modificato dopo la data del record» leggerà, accoppiando `test -e` a `git log --since`.

## Immutabilità

**Un record scritto non si modifica e non si cancella.** Il comando di scrittura rifiuta un path che esiste già (exit 2): è tutta l'implementazione dell'invariante, e non richiede né un lock né un hash. Lo spostamento di `migra` non lo viola: il file cambia cartella, non contenuto, e l'id resta lo stesso.

Uno scarto superato si marca con un **record nuovo** che nomina il vecchio in `Supera`. Il vecchio resta leggibile dov'è: chi cerca capisce cosa si era deciso *e* cosa lo ha sostituito, che è più di quanto direbbe un record riscritto.

`Supera` accetta **N valori** e sa indirizzare la **singola voce** con `<id>#<voce>`. Le due cose stanno nel formato dal primo record, non perché servano subito, ma perché dopo il primo record non si correggono più: allargare un campo a valore singolo significa avere già su disco record che il parser nuovo legge in un modo e il vecchio in un altro.

- Un `<id>` che non esiste in `scarti/` è un rifiuto (exit 1): un refuso in `Supera` nasconderebbe niente per sempre, in silenzio.
- **Il frammento dopo `#` non si valida.** Il registro oggi non ha un parser di voci — i record con voci arriveranno col filtro in ingresso — e un vincolo scritto adesso sulla loro forma sarebbe una premessa non misurata.

## Cosa la query mostra e cosa nasconde

`scarti.sh cerca <ancora>` fa **match testuale sul record intero**: la segnalazione, l'header e il perché. Copre quindi path, keyword e id task con una sola regola. Un id task si cerca **a parola intera** — `T16` non trova `T161`, come in `resolve-task.sh --children`.

I record superati **non compaiono senza `--superate`**, e la regola distingue i due indirizzi:

- **nominato intero** (`Supera: 2026-08-10-0900-poll-deck`) → il record è superato, sparisce dalla query.
- **nominato con frammento** (`Supera: 2026-09-01-1140-cache-fredda#D3`) → il record **resta visibile**, con l'annotazione dei frammenti superati da altri. Nascondere un record intero perché un altro ne supera una voce sola sarebbe nascondere ciò che è ancora vivo.

L'annotazione stampa i frammenti trovati nei `Supera` altrui, non il testo della voce: non richiede un parser di voci, e resterà vera quando i record con voci arriveranno.

## Il comando

Un solo script, `scripts/task/scarti.sh`, con tre sottocomandi. Il dettaglio d'uso e gli exit code stanno nel suo header; qui il contratto di forma.

```bash
scarti.sh scarta --slug <slug> --chi umano|agente|delega --segnalazione <testo> \
                 --ancora <path> [--ancora <path>]... [--delega <testo>] \
                 [--supera <id>[#<voce>]]... [--perche <testo>] [--no-commit]

scarti.sh cerca <ancora> [--superate]

scarti.sh migra
```

**`cerca` stampa l'autore** di ogni record trovato, nella riga `<id> · <chi> · <data>`: uno scarto su delega si riconosce senza aprire il file, e `scarti.sh cerca delega` trova anche un record che nomina la delega solo nel perché.

**`scarta` committa da sé** il solo file del record, con pathspec e senza push. Il chiamante tipico è il modello in chat, in una sessione detached dove nessun altro commit nominerà quel file: un record non committato è uno scarto che può ancora sparire. Chi batcha — una skill che chiude con un commit suo — passa `--no-commit`.

**`adr.sh`, nella stessa cartella, è il nome di prima** e inoltra a `scarti.sh` argomenti, stdin ed exit. Resta perché l'orchestrator lo chiama per nome: senza, la sua ricerca fallirebbe senza un errore visibile, e l'orchestrator riporterebbe segnalazioni già scartate.

## La sede di prima e la migrazione

Un progetto nato prima di questo registro tiene i suoi scarti in `adr/` della docs-root, dove `cerca` non guarda: la ricerca risponde «nessun record» come su un registro vuoto vero, e l'agente risolleva le segnalazioni già scartate.

**`cerca` e `scarta` lo dicono.** Contano i file di `adr/` che portano `- **Tipo**: scarto` e, se ce ne sono, scrivono su stderr quanti sono e il comando che li sposta. L'exit code non cambia, perché è il contratto che i chiamanti leggono. L'avviso scatta anche su un progetto già migrato, quando una sessione rimasta su una versione precedente del plugin scrive un record nuovo in `adr/`.

**`migra` sposta gli scarti nel registro**, sul solo progetto della cartella corrente:

- sposta con `git mv` i soli file di primo livello di `adr/` che portano `- **Tipo**: scarto`; ogni altro file resta in `adr/` ed è elencato nell'output. Il filtro esiste perché `adr/` è delle decisioni delle figure: un `migra` lanciato su un progetto migrato in ritardo non deve portarne una nel registro che fa tacere l'agente;
- è **tutto o niente**: un id già presente in `scarti/`, un record non tracciato da git o con modifiche non committate sono un rifiuto prima del primo spostamento, e un errore a metà rimette a posto i record già spostati;
- toglie `adr/` solo se è rimasta vuota. Git non traccia le cartelle: su ogni altro clone sparisce da sola al pull;
- committa i soli file spostati, ai due path, e **non pusha**: un push pubblicherebbe tutti i commit che il ramo locale ha in più del remote, non il solo commit della migrazione;
- non riscrive i file che citano un record per path (`adr/<id>.md`), e li elenca: un task file racconta un momento passato, e in un progetto vivo altre sessioni possono averli aperti. L'id — il nome del file — resta lo stesso: `adr/<id>.md` si ritrova in `scarti/<id>.md`. `cerca` confronta il testo del record e non il nome del file, quindi l'id non è una query che lo trova.

Exit: `0` almeno un record spostato, `2` niente da migrare (`adr/` assente, vuota o senza scarti), `1` errore senza nessun record spostato. Un secondo giro sullo stesso progetto esce `2`.

Il comando non percorre il registry dei progetti: è un fatto di una macchina, e `migra` deve girare anche dove il registry è un altro. Un giro su più progetti è un ciclo fuori dallo script, un progetto alla volta.

## Il registro non entra nel sistema doc

Nessuno script del sistema doc percorre `scarti/`: `build-index.sh` indicizza `reference/` e la cartella inbox, e nessuno misura la docs-root intera. Il registro non ha quindi bisogno di un'esclusione.
