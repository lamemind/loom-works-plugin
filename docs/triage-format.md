# Il file degli scenari di triage — formato del record e sede

Contratto per chi **scrive e conta** gli scenari di triage: la sede su disco, i campi di un record, la regola che manda lo scarto nel registro ADR, e l'assenza di ogni default.

Uno **scenario** è la decisione presa su una segnalazione del report di fine skill: la segnalazione citata alla lettera, l'uscita scelta fra `subito` · `task` · `scarto`, e chi l'ha scelta. Il file degli scenari sta **fuori dal sistema documentale**, per la stessa ragione del registro ADR (`adr-format.md`): un record è datato, cita alla lettera e porta chi ha deciso, e nessuno di questi tratti ha posto in una doc as-is. È stato di task, e nessun attore del sistema doc lo legge, lo misura o lo instrada.

## La sede

`{docs_root}/triage/`, sorella di `adr/` e `tasks/`. Un file per record, nessuna sottocartella, nessun indice.

Sta sotto la docs-root perché la docs-root è per-progetto: un progetto che tiene la doc in `runtime/` ha gli scenari in `runtime/triage/`. Chi risolve il path non lo cabla — lo chiede a `lw_docs_root`.

**Un file per record, mai un file unico.** Chi scrive uno scenario è una sessione detached per costruzione — spawnata dal deck con `LOOM_TASK`, o con la task nominata per argomento — e in detached più sessioni committano nello stesso worktree: un file unico entrerebbe intero nel commit della prima sessione che lo tocca, record altrui compresi. Le misure restano comandi, perché le fa `triage.sh conta`.

**Il nome del file è l'id del record**: `YYYY-MM-DD-HHMM-<slug>.md`, la stessa grammatica del registro ADR. Lo slug lo dà chi scrive. Sullo scarto lo stesso id nomina anche il record ADR, quindi la coppia `triage/<id>.md` · `adr/<id>.md` si legge con un `ls`.

## Struttura di un record

```markdown
# `publish-plugin.sh` non verifica che il branch del plugin sia pushato prima del bump

- **Uscita**: scarto
- **Chi**: umano
- **Momento**: flusso
- **Skill**: run-task
- **Progetto**: loom-works
- **Sessione**: 0a0f369d-c827-4fd4-ba34-ddc1b3be56c3
- **Data**: 2026-09-24 18:40
- **ADR**: 2026-09-24-1840-publish-branch-pushato
```

- **Riga 1 è la segnalazione alla lettera**, byte per byte come stampata nel report dopo `**S{N}** — `: backtick, virgolette e spazi restano com'erano. È la chiave con cui una segnalazione ritrovata in un transcript si accoppia al suo scenario. Per questo il record è markdown e non JSON: un escaper fra il testo stampato e il file renderebbe la citazione un'altra stringa.
- **L'header è a campi**, nell'ordine canonico della tabella sotto. `ADR` compare solo sullo scarto.
- **Nessun corpo.** Il perché di uno scarto sta nel record ADR: duplicarlo qui lo farebbe divergere al primo record scritto a mano.

| Campo | Dominio | Regola |
|---|---|---|
| `Uscita` | `subito` \| `task` \| `scarto` | vocabolario chiuso |
| `Chi` | `umano` \| `agente` | obbligatorio, **senza default**; lo scarto con `agente` è un rifiuto |
| `Momento` | `flusso` \| `posteriori` | obbligatorio, **senza default** |
| `Skill` | `[a-z0-9-]+` | token libero: il nome della skill del report |
| `Progetto` | `[A-Za-z0-9._-]+` | l'`id` di `.claude/loom-works.json`, override `--progetto` |
| `Sessione` | `[A-Za-z0-9._:-]+` | `CLAUDE_CODE_SESSION_ID`, override `--sessione` |
| `Data` | `YYYY-MM-DD HH:MM` | la scrive il comando |
| `ADR` | id di un record in `adr/` | solo con `Uscita: scarto`; lo scrive il comando |

**`Uscita` e `Chi` sono chiusi perché si contano.** `Skill` no: dice solo da quale report viene lo scenario, e una skill che adotti la sezione delle segnalazioni non deve richiedere una modifica del comando.

**`Chi` non ha default**, ed è ciò che separa i due usi del file: gli scenari con `umano` sono il corpus su cui si misura un triage delegato, quelli con `agente` sono il campione delle decisioni che l'agente ha già preso da sé.

**`Momento` distingue la decisione che ha avuto effetto da quella che non l'ha avuto.** Nel flusso — l'umano risponde al report nella stessa conversazione — «subito» è operativo, e l'agente lo esegue. A posteriori — una sessione aperta dopo, che rilegge i transcript — la stessa parola è un esito: registra che si sarebbe voluto farlo, e nessuno lo esegue. La data non basta a distinguerli, perché una risposta a posteriori sulla segnalazione di ieri porta la data di oggi. Il campo sta nel formato dal primo record per la stessa ragione di `Supera` nel registro ADR: aggiunto dopo, lascerebbe su disco due generazioni di record che un parser legge in modo diverso.

**Lo scenario registra l'uscita, mai il modo di esecuzione.** «Fallo subito ma in un subagente» resta `subito`: il modo non è un dato di triage, e un campo per registrarlo aprirebbe un dominio che nessuno sa contare.

**`Sessione` e `Progetto` assenti su entrambi i canali sono un rifiuto**, non un valore di comodo: un «assente» scritto nel record renderebbe invisibile proprio l'ambiente che non porta la variabile.

## Nessun default

**Uno scenario è sempre una risposta vera.** La segnalazione che nessuno decide non produce nessun record, e il comando non ha un modo di scriverne uno «di default». Ne discende che il conteggio degli esiti umani non ha bisogno di un filtro che escluda i default: ogni record con `Chi: umano` è una decisione che un umano ha preso. Il recupero delle segnalazioni rimaste senza risposta è un'operazione a posteriori, e scrive `Momento: posteriori`.

## Lo scarto passa per il registro ADR

Le tre uscite sbagliano a costi diversi: una task in più si cancella, un «subito» sbagliato si ripristina con un diff, uno scarto sbagliato è un segnale perso che nessuno recupera. Quindi **l'agente non scarta**: il comando rifiuta uno scarto con `Chi: agente` (exit 1) prima di scrivere qualunque cosa.

Lo scarto di un umano scrive due record, e la sequenza è fissa:

1. il comando valida tutti i campi dello scenario, il perché e le ancore, e verifica che né `triage/<id>.md` né `adr/<id>.md` esistano;
2. chiama `adr.sh scarta --no-commit` con lo stesso slug e lo stesso istante;
3. scrive lo scenario col campo `ADR` preso dall'output di `adr.sh` — mai ricopiato da chi chiama;
4. committa i due file in un commit solo.

La validazione precede la chiamata: su un input sbagliato non si scrive niente, né lo scenario né il record ADR. Il perché e le ancore valgono solo sullo scarto, e passati con un'altra uscita sono un rifiuto: il record di `subito` e `task` non ha un campo dove metterli, e accettarli li perderebbe in silenzio.

## Immutabilità

**Il file degli scenari è append-only.** Il comando rifiuta un path che esiste già (exit 2), sullo scenario come sul record ADR dello stesso id.

Una decisione che ne ribalta un'altra — l'umano che risponde «task» dove l'agente aveva già marcato «subito» — è un record nuovo accanto al vecchio, senza un campo di rimando. I due si accoppiano per `Sessione` più riga 1, che è una citazione byte per byte: un campo di rimando sarebbe una seconda chiave per la stessa coppia, e le due divergerebbero al primo record scritto a mano. Tenere entrambi è il dato: la decisione dell'agente e quella dell'umano sulla stessa segnalazione sono ciò che si confronta per sapere quanto l'agente decide come l'umano.

## Il comando

Un solo script, `scripts/task/triage.sh`, con due sottocomandi. Il dettaglio d'uso e gli exit code stanno nel suo header; qui il contratto di forma.

```bash
triage.sh scenario --slug <slug> --uscita subito|task|scarto --chi umano|agente \
                   --momento flusso|posteriori --skill <nome> \
                   [--progetto <id>] [--sessione <id>] \
                   [--ancora <path>]... [--no-commit] <<'SCENARIO'
<la segnalazione alla lettera, su una riga>
<il perché dello scarto, anche su più righe — solo con --uscita scarto>
SCENARIO

triage.sh conta [--dal <YYYY-MM-DD[ HH:MM]>] [--sessione <id>]
```

**La segnalazione arriva su stdin**, riga 1, e le righe dopo sono il perché dello scarto. Un heredoc col delimitatore fra apici è l'unico canale che porta un testo arbitrario intatto: fra virgolette doppie la shell eseguirebbe i backtick come comandi, fra apici singoli ogni apostrofo va spezzato a mano. `--segnalazione` e `--perche` esistono per chi chiama da uno script.

**`scenario` committa da sé** i propri file, con pathspec e senza push. Chi batcha — la skill che scrive più scenari dopo un report — passa `--no-commit` e committa i path che il comando stampa.

**`conta` stampa una tabella a tab**, una riga per chiave: il totale, `umano` e `agente`, le sei coppie `<uscita>.<chi>`, i due momenti, i record malformati, la data del primo e dell'ultimo record. Con `--dal` aggiunge la colonna dei soli record da quella data in poi. La riga `scarto.agente` vale 0 per costruzione.

## Il file degli scenari non entra nel sistema doc

Due esclusioni, entrambe su `triage/`, le stesse del registro ADR:

- `doc_excluded` in `lib-doc.sh` — la usa `doc-metrics.sh`, che percorre la docs-root intera. Senza, ogni record prenderebbe `MERGE?` e gli scenari diventerebbero una coda di lavoro per `rebalance-doc`.
- il `case` del perimetro in `check-doc-links.sh` — senza, ogni path citato in una segnalazione diventerebbe `DANGLING` per sempre su un file che per contratto non si riscrive.

`md-wrap.py` non ha un canale di esclusione e non gli serve: i record li scrive uno script, a campi su una riga.
