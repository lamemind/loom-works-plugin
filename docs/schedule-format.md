# Il piano di un perimetro — `schedule.md`

Contratto per chi **scrive e legge** il piano di un perimetro, epica o mandato: `prepare-mandate` lo scrive prima del giro, l'orchestrator lo riscrive durante, lo script del flusso lo esegue. Il piano porta l'analisi del perimetro e le decisioni d'ordine che ne discendono, in un file solo.

## Dove sta e chi lo scrive

- **Sede**: `schedule.md` nella task folder del perimetro, il campo `**Folder**` del suo task file. Il file è tracciato da git. Un perimetro senza task folder non ha piano, e `verify` si ferma.
- **Scrittori**: `prepare-mandate` prima del giro; l'orchestrator durante il giro, quando scopre una collisione o deve cambiare un ordine. Chi scrive committa il solo `schedule.md`, con la propria pathspec. Nessun altro lo tocca, e nessuno lo copia altrove.
- **Lettori**: lo script del flusso (`scripts/orchestrator/flow.py`), che lo rilegge quando cambia; `scripts/orchestrator/schedule.py verify`, che lo confronta coi file del progetto; chi legge il perimetro, nella prosa.
- **Nel task file del perimetro** il piano ha la sua voce in `## Materiale`: `` - 🔬 `📁/schedule.md` — eseguire il giro: analisi del perimetro e piano dello script ``. La scrive `prepare-mandate`, una volta sola.

## La forma

Prosa per chi legge, e **un solo blocco** ```` ```json ```` che è la verità per lo script. Nessun dato del blocco si ricava dalla prosa, e lo script non legge la prosa.

````markdown
# Piano di T230 — convention e orchestrator insieme

## Analisi del perimetro

- T61 dipende da T52: il gate legge il formato che T52 scrive (Dependencies di T61).
- T52 e T64 toccano tutte e due `scripts/utils/lib.sh` (Materiale dei due).
- T61 e T64 riscrivono tutte e due il poll del deck: nessun campo lo dichiara.

## Ordine

- L'utente vuole le convention prima: T64 parte dopo T52 e T61.
- T52 e T64 pubblicano il plugin: risorsa `publish-plugin`.

## Piano

```json
{
  "perimetro": "T230",
  "membri": [
    {"id": "T52", "passo": "run", "risorse": ["publish-plugin", "scripts/utils/lib.sh"]},
    {"id": "T61", "passo": "preflight", "dopo": ["T52"], "risorse": ["poll del deck"]},
    {"id": "T64", "passo": "preflight", "dopo": ["*"], "risorse": ["publish-plugin", "scripts/utils/lib.sh", "poll del deck"]}
  ]
}
```
````

**La prosa** porta tre cose: le relazioni fra i membri e da dove vengono (una dipendenza dichiarata in `## Dependencies` o nel grafo di `tasks.md`, un path in comune nei `## Materiale`, una collisione che nessun campo dichiara e che si trova leggendo i membri), le preferenze d'ordine dell'utente per questo giro, e il perché di ogni risorsa. Il metodo con cui si trovano le relazioni è `mandate-analysis.md`.

**Il blocco** porta le decisioni che ne discendono: chi aspetta chi, chi non gira insieme a chi, da quale passo parte ogni membro. Una relazione della prosa che non diventa un campo del blocco non esiste per lo script.

## Il blocco JSON

Un oggetto con due chiavi, `perimetro` e `membri`. Una chiave ignota, un tipo sbagliato o un valore fuori dominio rendono il piano non valido: nessun default copre un campo scritto male, perché un campo letto col significato sbagliato lascia partire un membro troppo presto senza nessun errore.

| Chiave | Tipo | Cosa dice |
|---|---|---|
| `perimetro` | `"T<n>"` | l'id del perimetro, epica o mandato |
| `membri` | lista | una voce per membro, nell'ordine in cui lo script li preferisce a parità di condizioni |

Una voce di `membri`:

| Chiave | Tipo | Default | Cosa dice |
|---|---|---|---|
| `id` | `"T<n>"` | — | il membro |
| `passo` | `preflight` · `run` · `checkpoint` | quello dei file | il passo da cui il membro parte in questo giro |
| `dopo` | lista di stringhe | `[]` | le task che il membro aspetta, per ogni suo passo |
| `risorse` | lista di stringhe | `[]` | ciò che il ciclo di lavoro del membro occupa |
| `dlv` | `"1,3-5"` | tutti gli aperti | i DLV del prossimo run del membro |
| `umano` | `true` · `false` | `false` | il membro lo segue l'umano |

### `passo`

Il primo passo del membro nel giro. Vale finché il membro non ha fatto un passo nel giro, e finché i file lo permettono: un `preflight` su un membro che il preflight l'ha già fatto, o un `run` su un membro senza DLV aperti, cedono al passo che i file dicono, cioè il `next` di `mandate.py tree`. Assente, vale quello dei file dall'inizio.

Serve dove il piano decide diversamente dai file: `run` su una task S o M ancora 🔵 salta il preflight, che a quelle Size non è obbligatorio; `checkpoint` chiude in una conversazione nuova un ciclo che si è fermato prima del checkpoint. Un `run` su una task L senza preflight, o con un preflight a premessa decaduta, `run-task` lo rifiuta: `verify` lo ferma.

### `dopo`

Le task che il membro aspetta prima di **ogni** suo passo, preflight compreso. Tre forme:

- `"T21"` — dopo la chiusura di T21: la sua Prog è ✔️.
- `"T21:2,4"` — dopo i DLV 2 e 4 di T21, spuntati e **chiusi a ciclo finito**: se T21 è un membro, il ciclo che li ha chiusi deve aver finito il checkpoint e le risposte alle sue segnalazioni. Una task con segnalazioni in sospeso non fa da base a nessuna.
- `"*"` — dopo la chiusura di tutti gli altri membri, compresi quelli seguiti dall'umano.

Una voce può nominare una task fuori dal perimetro. Una dipendenza aperta che un membro dichiara verso una task fuori dal perimetro ferma il membro anche se il `dopo` non la nomina: lo script la legge da `tree` (`blocked=`). Una voce `T<n>:<dlv>` su quella task la sostituisce: il membro parte quando quei DLV sono spuntati, perché il ciclo di una task fuori dal perimetro lo script non lo vede.

### `risorse`

Nomi liberi di ciò che un ciclo di lavoro occupa: un publish del plugin, una release o una build del deck, un file che due membri scrivono, un comportamento che due membri riscrivono. **Due membri con una risorsa in comune non hanno mai due cicli di lavoro aperti insieme.** Un ciclo occupa le sue risorse dall'apertura del run alla chiusura del ciclo, checkpoint e risposte comprese. Un preflight non occupa risorse.

Una collisione della prosa diventa una risorsa in comune, o un `dopo` fra i due membri. Le risorse sono il modo di dire «non insieme» senza dire chi prima.

### `dlv`

Il perimetro del prossimo run del membro, nella grammatica di `run-task`: lista `1,2,6`, intervallo `3-8`, combinabili. Si usa quando un altro membro aspetta un DLV preciso (`"dopo": ["T21:2"]`): il primo ciclo fa solo quel DLV, e il dipendente parte prima della fine del membro.

Lo script fa il run sui DLV del campo ancora aperti. Quando sono tutti chiusi il campo è consumato, e i run successivi vanno su tutti i DLV aperti finché l'orchestrator non scrive un perimetro nuovo.

### `umano`

Il membro lo segue l'umano: lo script non apre passi su di lui, i suoi eventi non svegliano l'orchestrator, e un passo dello script ancora aperto su di lui si lascia andare. Gli altri membri possono aspettarlo nel `dopo`, e `"*"` lo aspetta.

## Cosa il piano non porta

- **Nessuno stato e nessuna cifra dei membri**: la Prog sta in `tasks.md`, i DLV nel task file del membro. Lo stato del giro sta nel flusso dello script, fuori da git.
- **Nessun sessionId**: il piano descrive i membri, non le conversazioni. Un membro che l'orchestrator non deve toccare si marca `umano`.
- **Nessuna dipendenza che il piano solo conosce**: una dipendenza vera va in `## Dependencies` del membro, dove la vede anche chi lavora sulla task fuori dal perimetro. Il `dopo` la ripete per lo script, e `verify` controlla che la ripeta. Una dipendenza che l'analisi trova e che il membro non dichiara entra subito nel `dopo`, perché lo script legge l'ordine solo dal piano; la prosa la dice non dichiarata, e chi scrive il piano chiede a chi lavora sul membro di dichiararla.

## `verify` — il piano contro i file

```bash
"PY" -B -I "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator/schedule.py" verify <perimetro>
```

I membri li legge da sé col lettore unico, `resolve-task.sh <perimetro> --members`. I controlli, tutti insieme:

1. **Il blocco**: uno solo, JSON valido, ogni campo nel suo dominio.
2. **Il perimetro**: `perimetro` è l'id chiesto.
3. **I membri**: le voci del piano sono i membri del lettore, né uno in più né uno in meno. Un membro dichiarato senza task file (`TASK_MEMBER_MISSING`) conta fra i membri.
4. **Il `dopo`**: ogni task nominata esiste; un perimetro di DLV non supera il numero dei DLV della task; ogni dipendenza dichiarata da un membro aperto verso un altro membro aperto — `## Dependencies` o grafo di `tasks.md`, le righe `DEPS` di `mandate.py tree` — sta nel suo `dopo`, con la task o con `*`. Lo script legge l'ordine solo dal piano: una dipendenza aggiunta in un task file dopo la stesura farebbe partire il membro troppo presto.
5. **Le risorse**: due membri aperti con un path in comune che almeno uno dei due scrive — le righe `CONFLICT … materiale` di `mandate.py tree` — hanno una risorsa in comune o un `dopo` fra loro.
6. **Il `dlv`** di un membro non supera il numero dei suoi DLV.
7. **Il `passo`**: un `run` che `run-task` rifiuterebbe, o un `checkpoint` su un membro senza preflight valido, fermano; un passo che i file hanno superato è un avviso.
8. **Il commit**: il piano è committato, e il file nel working tree è quello del commit.

Le righe:

| Riga | Cosa dice |
|---|---|
| `PERIMETRO=<id>\|epica\|mandato` · `PLAN=<path>\|assente` · `MEMBRI=<n>` | il perimetro, il piano, quanti membri |
| `ERRORE\|<motivo>` | il piano non si legge: assente, senza folder, blocco mancante o doppio, JSON o campo non validi |
| `PLAN_COMMIT=<sha>\|? (<motivo>)` | il commit del piano, o perché non c'è |
| `DIFF\|<tipo>\|<chi>\|<dettaglio>` | un controllo che non passa: `perimetro`, `membri`, `dopo`, `risorse`, `dlv`, `passo` |
| `AVVISO\|passo\|<id>\|<dettaglio>` | un passo di partenza che i file hanno superato |
| `CAMBIATO\|<id>\|modificato\|nuovo` | un membro aperto il cui task file è cambiato dopo il commit del piano, o è nato dopo: chi parte lo rilegge, per una collisione che il piano non ha visto |
| `VERIFY=ok\|riesame\|stop` | `stop` con un `ERRORE`, un `DIFF` o un piano non committato; `riesame` con un `CAMBIATO`; `ok` altrimenti |

Exit `0` su `ok` e `riesame`, `2` su `stop`, `1` su un id malformato, un task file del perimetro mancante o un lettore dei membri che non risponde.

**`verify <perimetro> --bozza`** è il controllo di chi ha appena scritto il piano e non l'ha ancora committato: `prepare-mandate` prima della conferma, l'orchestrator prima del commit di una riscrittura. Fa i controlli da 1 a 7 sui file come sono sul disco — il task file del perimetro compreso, anche non committato — e salta l'8: niente `PLAN_COMMIT` e niente `CAMBIATO`. `VERIFY=ok` senza `ERRORE` e senza `DIFF`, `stop` altrimenti.

**A giro avviato lo script rilancia lo stesso controllo** quando cambia il piano o il task file di un membro, senza la storia: i membri cambiano di continuo, e il piano lo committa l'orchestrator. Un `ERRORE` o un `DIFF` mettono in pausa i passi nuovi e svegliano l'orchestrator; i passi già aperti finiscono.

`show <perimetro>` stampa il piano letto, una riga `MEMBRO|<id>|passo=…|dopo=…|risorse=…|dlv=…|umano=sì|no` per membro, con i default scritti per esteso.
