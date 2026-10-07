# Il file degli scenari di triage — formato del record e sede

Contratto per chi **scrive e conta** gli scenari di triage: la sezione del report da cui nascono, la sede su disco, i campi di un record — le parole dell'umano comprese —, la regola che manda lo scarto nel registro ADR e tiene l'ignora fuori, l'assenza di ogni default, e l'uscita eseguita in un altro progetto.

Uno **scenario** è la decisione presa su una segnalazione del report di fine skill: la segnalazione citata alla lettera, l'uscita scelta fra `subito` · `task` · `scarto` · `ignora`, e chi l'ha scelta. Il file degli scenari sta **fuori dal sistema documentale**, per la stessa ragione del registro ADR (`adr-format.md`): un record è datato, cita alla lettera e porta chi ha deciso, e nessuno di questi tratti ha posto in una doc as-is. È stato di task, e nessun attore del sistema doc lo legge, lo misura o lo instrada.

## Il report e la risposta

Il report finale di `run-task` e di `checkpoint-task` chiude con la sezione **`🚦 Segnalazioni`**, presente anche quando è vuota: a zero segnalazioni è la riga `**🚦 Segnalazioni** — nessuna`, così l'assenza è dichiarata e non presunta. Ogni segnalazione è una riga `**S{N}** — <segnalazione>`, numerata da 1 dentro il singolo report, con le quattro uscite sulla riga sotto. Il testo dopo `— ` è quello che lo scenario cita in riga 1.

Ciò che l'agente ha corretto di sua iniziativa sta **dentro** la sezione, con «subito» già marcato e `Chi: agente`, mai in un inciso del report: è una decisione già presa, e resta ribaltabile solo se l'umano la vede fra le segnalazioni. Il suo scenario si scrive prima di stampare la sezione. L'agente non scarta e non ignora: una segnalazione che ritiene irrilevante la riporta comunque con le quattro uscite.

**La risposta dell'umano è prosa libera, e nessuno strumento la presidia.** Niente domande a scelta, niente griglie: in un terminale una forma imposta costa più di quanto renda, e la prosa è l'unica che si detta anche a voce. La legge l'agente della stessa conversazione, che riconosce la segnalazione da `S1`, `s1`, `1` o «la prima» e scrive uno scenario per ogni segnalazione decisa. La regola operativa sta nel body delle due skill, non in un contratto iniettato: il body è nel transcript quando la risposta arriva, e una sessione senza la skill non ha nessuna sezione a cui rispondere. Una risposta che arriva in un'altra sessione, o dopo un `/clear`, non ha più nessuno che la registri.

Le quattro uscite nel flusso:

- **subito** — operativo: l'agente scrive lo scenario ed esegue.
- **task** — operativo: l'agente scrive lo scenario e fa senza chiedere ciò che le parole dell'umano dicono; quando non dicono altro, apre la task con `create-task` in modalità YOLO. «task» è già la richiesta: una decisione registrata senza la task che ne segue lascia il lavoro da nessuna parte.
- **scarto** — vuole il perché, di solito già nella risposta («S2 scarto: capita una volta l'anno»). Lo scenario scrive anche il record ADR.
- **ignora** — vuole l'ancora e nessun perché. Non scrive nessun record ADR: se la segnalazione torna, l'agente la riporta di nuovo.

**Un'uscita copre forme diverse, e le parole dell'umano dicono quale.** «task» è una task nuova nel progetto, una task in un altro progetto, un DLV aggiunto a una task che esiste già, oppure l'umano che se ne occupa da sé; «subito» può volere un subagente. L'agente esegue la forma che le parole dicono — «task» con «aggiungi un DLV alla task corrente» aggiunge il DLV e non apre nessuna task, «ci penso io» non esegue niente — e lo scenario le registra alla lettera nel campo `Approfondimento` (§Struttura di un record): senza, due scenari `task` della stessa sessione restano indistinguibili, e il criterio con cui l'umano ha scelto resta solo nel transcript. È il dato che la retroazione sul triage cerca, e l'umano lo dichiara da sé, prima di qualunque punteggio dell'agente, quindi senza ancoraggio.

**L'approfondimento di una segnalazione è tutto ciò che l'umano dice su di lei**, alla lettera, parola d'uscita compresa: spesso l'uscita sta dentro la frase («è a metà tra subito e task… quindi task»), e toglierla vorrebbe dire riscrivere. Restano fuori solo l'identificatore (`S1`, «la prima») e la punteggiatura che la separa dalle vicine. È obbligatorio quando la risposta lo porta; un'uscita nuda, una conferma o un rifiuto nudo («subito», «ok», «no») non lo producono. Una frase che copre più segnalazioni entra nello scenario di ognuna, perché ogni scenario si legge da solo; i pezzi non contigui della stessa segnalazione si uniscono nell'ordine in cui compaiono, con ` […] ` a segnare il salto. Sullo scarto le parole dell'umano sono il perché, e stanno nel record ADR; sull'ignora nominato («S5 ignora: già gestito in S4») sono un approfondimento, mentre un rifiuto che porta un motivo senza nominare l'ignora resta uno scarto.

**Un rifiuto nudo si legge come ignora.** «S2 no», «lascia perdere», «non vale la pena» — nessun motivo e nessuna parola «scarto» — sono un ignora, e l'agente lo scrive senza chiedere niente. Lo scarto si scrive solo quando la risposta lo nomina o porta un perché; nominato senza perché, l'agente lo chiede una volta sola. Fra i due errori possibili si accetta quello che la ricorrenza recupera (§Scarto e ignora): un ignora scritto dove l'umano voleva uno scarto torna nel report se la segnalazione torna, uno scarto scritto dove voleva un ignora è un record ADR che nessuna query colpirà.

La conferma vale quanto il ribaltamento: «ok» sulla segnalazione marcata dall'agente è uno scenario `subito` dell'umano accanto a quello dell'agente, e i due record sono il dato che misura quanto l'agente decide come l'umano.

**Il modello della riga nel body delle skill porta `S{N}`, mai un numero.** Il body di una skill entra nel transcript a ogni invocazione: un id in grassetto con un numero vero lì verrebbe contato come segnalazione stampata da chi conta gli id a `grep` sui transcript. Il titolo invece compare per forza anche lì, e nei tool call che lo scrivono: chi lo cerca in un transcript filtra i blocchi di testo dell'assistente.

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
- **L'header è a campi**, nell'ordine canonico della tabella sotto. `Approfondimento` compare solo quando l'umano ha detto qualcosa oltre l'uscita, `ADR` solo sullo scarto, `Ancore` solo sull'ignora: l'ultimo campo è `ADR` o `Ancore` quando ci sono, e i due non coesistono mai.
- **Nessun corpo.** Il perché di uno scarto sta nel record ADR: duplicarlo qui lo farebbe divergere al primo record scritto a mano. L'ignora non ha perché: la sua ragione è la marginalità, e chiederla costa più della decisione.
- **Le parole dell'umano stanno in un campo di header, su una riga, mai in un corpo.** I lettori del record — l'awk di `conta` e i `grep` delle misure — cercano righe `- **Campo**:` su tutto il file, non solo nell'header: in un corpo libero una riga dell'umano che iniziasse come un campo verrebbe letta come campo, mentre un valore scritto dopo l'etichetta sulla stessa riga non può. Il comando rifiuta un a-capo nel valore, come nella segnalazione.

Lo scenario di un ignora chiude con le ancore al posto del campo `ADR`:

```markdown
# Il messaggio d'errore di `deck-run` cita `--prompt` dove il flag è `--prompt-kind`

- **Uscita**: ignora
- **Chi**: umano
- **Momento**: flusso
- **Skill**: run-task
- **Progetto**: loom-works
- **Sessione**: 0a0f369d-c827-4fd4-ba34-ddc1b3be56c3
- **Data**: 2026-09-24 18:42
- **Ancore**: loom-deck/scripts/deck-run
```

Le parole dell'umano, quando la risposta le porta, stanno nel campo `Approfondimento`, dopo `Data`:

```markdown
# Il banco del deck sfora il timeout del foreground e il turno si chiude sull'attesa

- **Uscita**: task
- **Chi**: umano
- **Momento**: flusso
- **Skill**: run-task
- **Progetto**: loom-works
- **Sessione**: 0a0f369d-c827-4fd4-ba34-ddc1b3be56c3
- **Data**: 2026-09-24 18:44
- **Approfondimento**: task, ma come DLV della task aperta sul banco: è lo stesso difetto di `run_in_background`, non uno nuovo
```

| Campo | Dominio | Regola |
|---|---|---|
| `Uscita` | `subito` \| `task` \| `scarto` \| `ignora` | vocabolario chiuso |
| `Chi` | `umano` \| `agente` | obbligatorio, **senza default**; lo scarto e l'ignora con `agente` sono un rifiuto |
| `Momento` | `flusso` \| `posteriori` | obbligatorio, **senza default** |
| `Skill` | `[a-z0-9-]+` | token libero: il nome della skill del report |
| `Progetto` | `[A-Za-z0-9._-]+` | l'`id` di `.claude/loom-works.json`, override `--progetto` |
| `Sessione` | `[A-Za-z0-9._:-]+` | `CLAUDE_CODE_SESSION_ID`, override `--sessione` |
| `Data` | `YYYY-MM-DD HH:MM` | la scrive il comando |
| `Approfondimento` | testo libero, una riga | le parole dell'umano alla lettera; solo con `Chi: umano` e `Uscita` diversa da `scarto`, presente solo quando la risposta le porta |
| `ADR` | id di un record in `adr/` | solo con `Uscita: scarto`; lo scrive il comando |
| `Ancore` | path relativi alla project root, separati da `, ` | solo con `Uscita: ignora`, almeno uno, ognuno deve esistere |

**`Uscita` e `Chi` sono chiusi perché si contano.** `Skill` no: dice solo da quale report viene lo scenario, e una skill che adotti la sezione delle segnalazioni non deve richiedere una modifica del comando.

**`Chi` non ha default**, ed è ciò che separa i due usi del file: gli scenari con `umano` sono il corpus su cui si misura un triage delegato, quelli con `agente` sono il campione delle decisioni che l'agente ha già preso da sé.

**`Momento` distingue la decisione che ha avuto effetto da quella che non l'ha avuto.** Nel flusso — l'umano risponde al report nella stessa conversazione — «subito» e «task» sono operativi: l'agente esegue il primo e apre la task del secondo. A posteriori — una sessione aperta dopo, che rilegge i transcript — le stesse parole sono un esito: registrano che si sarebbe voluto farlo, e nessuno lo esegue. La data non basta a distinguerli, perché una risposta a posteriori sulla segnalazione di ieri porta la data di oggi. Il campo sta nel formato dal primo record per la stessa ragione di `Supera` nel registro ADR: aggiunto dopo, lascerebbe su disco due generazioni di record che un parser legge in modo diverso.

**`Uscita` è il solo campo che si conta; le parole dell'umano si registrano, non si classificano.** «Fallo subito ma in un subagente» resta `subito`: il modo di esecuzione non ha un campo strutturato, perché aprirebbe un dominio che nessuno sa contare — e lo stesso vale per il progetto dove l'uscita si esegue e per ciò che ha prodotto. Quando l'umano li dice, entrano nell'`Approfondimento` alla lettera, con tutto il resto delle sue parole.

**`Approfondimento` porta solo parole dell'umano.** Con `Chi: agente` è un rifiuto: lo scenario dell'agente si scrive prima di stampare la sezione, quando una risposta ancora non esiste. Sullo scarto è un rifiuto anche con `Chi: umano`: le parole dell'umano sono il perché, il record ADR le porta e lo scenario lo raggiunge col campo `ADR` — una seconda copia divergerebbe.

**`Ancore` è lo stesso campo del record ADR**: stesso nome, stesso separatore `, `, stessa grafia relativa alla project root, e la stessa normalizzazione — `lw_norm_ancora` in `lib.sh`, che `adr.sh` e `triage.sh` chiamano entrambi. Lo stesso file produce quindi la stessa stringa nei due registri, e un solo pattern `^- \*\*Ancore\*\*:` li legge tutti e due: accoppiare due ignora sullo stesso path, o un ignora a uno scarto, è un confronto fra stringhe. Sull'ignora le ancore sono obbligatorie perché sono la chiave che accoppia una segnalazione che torna allo scenario di prima, e un record scritto senza non si completa dopo. Sullo scarto non si scrivono: stanno nel record ADR, e una copia divergerebbe come il perché. Su `subito` e `task` sono un rifiuto, perché nessuno le legge.

**`Sessione` e `Progetto` assenti su entrambi i canali sono un rifiuto**, non un valore di comodo: un «assente» scritto nel record renderebbe invisibile proprio l'ambiente che non porta la variabile.

## Nessun default

**Uno scenario è sempre una risposta vera.** La segnalazione che nessuno decide non produce nessun record, e il comando non ha un modo di scriverne uno «di default». Ne discende che il conteggio degli esiti umani non ha bisogno di un filtro che escluda i default: ogni record con `Chi: umano` è una decisione che un umano ha preso. Il recupero delle segnalazioni rimaste senza risposta è un'operazione a posteriori, e scrive `Momento: posteriori`.

L'ignora non è un default: è sempre una risposta dell'umano. È anche ciò che separa «vista, e non è niente» dalla segnalazione che nessuno ha letto — la non-risposta non scrive niente, e nel file degli scenari le due sarebbero indistinguibili.

## Scarto e ignora — la ricorrenza

Scarto e ignora chiudono entrambi una segnalazione con «non si fa», e li separa una domanda sola: la segnalazione tornerà? Il record ADR rende solo se torna, perché serve a farla tacere al giro dopo — l'agente interroga il registro prima di stampare, trova il record e tace.

- **scarto** — «tornerà, e deve tacere»: scrive il record ADR col perché, immutabile.
- **ignora** — «non tornerà, e se torna parla»: scrive solo lo scenario, con le ancore. La segnalazione che torna non trova nessun record ADR, arriva di nuovo all'umano e viene rivalutata.

**La ricorrenza è il falsificatore dell'ignora.** Un ignora sbagliato si smentisce da solo: la segnalazione torna nel report, e l'umano decide di nuovo. Uno scarto usato su una segnalazione che non torna non si smentisce mai: resta un record immutabile che nessuna query colpisce, e il registro cresce di decisioni che nessuno consulta.

## Lo scarto passa per il registro ADR

Le uscite sbagliano a costi diversi: una task in più si cancella, un «subito» sbagliato si ripristina con un diff, uno scarto sbagliato è un segnale perso che nessuno recupera. Quindi **l'agente non scarta**: il comando rifiuta uno scarto con `Chi: agente` (exit 1) prima di scrivere qualunque cosa. Per la stessa ragione **l'agente non ignora**: un suo ignora è una segnalazione non stampata, e l'agente riporta tutto.

Lo scarto di un umano scrive due record, e la sequenza è fissa:

1. il comando valida tutti i campi dello scenario, il perché e le ancore, e verifica che né `triage/<id>.md` né `adr/<id>.md` esistano;
2. chiama `adr.sh scarta --no-commit` con lo stesso slug e lo stesso istante;
3. scrive lo scenario col campo `ADR` preso dall'output di `adr.sh` — mai ricopiato da chi chiama;
4. committa i due file in un commit solo.

La validazione precede la chiamata: su un input sbagliato non si scrive niente, né lo scenario né il record ADR. Il perché vale solo sullo scarto, le ancore su scarto e ignora; passati con un'altra uscita sono un rifiuto, perché il record non ha un campo dove metterli e accettarli li perderebbe in silenzio. L'ignora non chiama `adr.sh`: scrive lo scenario e committa quel file solo.

## Immutabilità

**Il file degli scenari è append-only.** Il comando rifiuta un path che esiste già (exit 2), sullo scenario come sul record ADR dello stesso id.

Una decisione che ne ribalta un'altra — l'umano che risponde «task» dove l'agente aveva già marcato «subito» — è un record nuovo accanto al vecchio, senza un campo di rimando. I due si accoppiano per `Sessione` più riga 1, che è una citazione byte per byte: un campo di rimando sarebbe una seconda chiave per la stessa coppia, e le due divergerebbero al primo record scritto a mano. Tenere entrambi è il dato: la decisione dell'agente e quella dell'umano sulla stessa segnalazione sono ciò che si confronta per sapere quanto l'agente decide come l'umano.

## Il comando

Un solo script, `scripts/task/triage.sh`, con due sottocomandi. Il dettaglio d'uso e gli exit code stanno nel suo header; qui il contratto di forma.

```bash
triage.sh scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano|agente \
                   --momento flusso|posteriori --skill <nome> \
                   [--progetto <id>] [--sessione <id>] \
                   [--ancora <path>]... [--no-commit] <<'SCENARIO'
<la segnalazione alla lettera, su una riga>
<le parole dell'umano: il perché dello scarto, anche su più righe;
 l'approfondimento su subito, task e ignora, su una riga>
SCENARIO

triage.sh conta [--dal <YYYY-MM-DD[ HH:MM]>] [--sessione <id>]
```

**La segnalazione arriva su stdin**, riga 1, e le righe dopo sono le parole dell'umano, che l'uscita smista: il perché sullo scarto, l'approfondimento su `subito`, `task` e `ignora`. Una grammatica sola per le quattro uscite, perché le parole dell'umano portano backtick e apostrofi quanto la segnalazione e vogliono lo stesso canale. Un heredoc col delimitatore fra apici è l'unico canale che porta un testo arbitrario intatto: fra virgolette doppie la shell eseguirebbe i backtick come comandi, fra apici singoli ogni apostrofo va spezzato a mano. `--segnalazione`, `--perche` e `--approfondimento` esistono per chi chiama da uno script; lo stesso campo passato sui due canali è un rifiuto.

**`scenario` committa da sé** i propri file, con pathspec e senza push. Chi batcha — la skill che scrive più scenari dopo un report — passa `--no-commit` e committa i path che il comando stampa.

**`conta` stampa una tabella a tab**, una riga per chiave: il totale, `umano` e `agente`, le otto coppie `<uscita>.<chi>`, i due momenti, gli scenari con l'approfondimento, i record malformati, la data del primo e dell'ultimo record. Con `--dal` aggiunge la colonna dei soli record da quella data in poi. Le righe `scarto.agente` e `ignora.agente` valgono 0 per costruzione. La riga `approfondimento` non include gli scarti, le cui parole stanno nel record ADR: chi vuole tutte le risposte con parole registrate la somma a `scarto.umano`.

## L'uscita eseguita in un altro progetto

Una segnalazione decisa nel report di un progetto può riguardarne un altro: «task» va aperta nella lista task dell'altro progetto, «subito» si esegue nel suo repo. **Il destinatario lo porta la segnalazione**, che nomina di norma il progetto o i file che riguarda: «subito» e «task» agiscono lì, senza una conferma prima del lancio. Quando l'umano nomina un progetto nelle sue parole vince quello; quando nessuno ne nomina uno resta il progetto della sessione. Lo scenario si scrive nel progetto della sessione — `Progetto` è quello del report, non quello dell'esecuzione — e il destinatario sta nella riga 1 o nell'approfondimento.

**Esegue una sessione figlia nella cartella del destinatario, non la sessione del report.** `claude -p --permission-mode auto` lanciato con cwd nel progetto destinazione ne carica `CLAUDE.md`, settings, skill e regole di commit: scrive il progetto che possiede il confine, col proprio contesto, e un progetto che tiene gli altri in sola lettura (un deny `Edit` sui fratelli) resta rispettato invece di essere aggirato da Bash. Il rischio è accettabile perché l'azione tipica è aprire una task, che si cancella con un clic. Due condizioni:

- **Il binding di sessione e le variabili che spostano la scrittura non attraversano il confine.** Il figlio eredita l'ambiente intero del chiamante, e tre variabili gli arrivano e lo spostano: `LOOM_TASK` — gli id delle task valgono dentro un progetto, e il figlio risolverebbe una task che lì non esiste, o un'altra; `PROJECT_ROOT` — la ricerca della root le dà precedenza sulla cwd, e il figlio scriverebbe nel progetto del chiamante; `PTYXIS_PROFILE` — è la chiave con cui gli hook di stato annunciano a compass, e una sessione `claude -p` esegue gli hook come una interattiva: il figlio porterebbe a `done` il badge del progetto chiamante mentre il chiamante lavora ancora. Il lancio passa quindi per `env -u LOOM_TASK -u PROJECT_ROOT -u PTYXIS_PROFILE`. Le altre variabili di sessione o il figlio le riscrive da sé (`CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`), o non spostano né dove scrive né su quali canali parla.
- **Il ritorno del figlio è self-report, e il chiamante lo riverifica su disco.** Il figlio dichiara cosa ha fatto in prosa, con un hash corto dentro; il gate non parte da lì, ma dall'intervallo fra due `HEAD` del destinatario.

**Il gate legge l'intervallo, e il dichiarato lo restringe.** `HEAD` si fotografa prima del lancio; dopo, un commit atteso vuole almeno un commit nuovo, una task attesa vuole un commit che aggiunge un task file `T<N>-*.md` sotto la docs-root del destinatario e la riga di quell'id in `tasks.md` — l'id si ricava dal file aggiunto, non dal racconto. Una chiave presa solo dal racconto dipenderebbe da come si legge la prosa, e sarebbe verde anche su un commit vecchio citato da un figlio che non ha fatto niente. Se il figlio dichiara un hash, quell'hash deve stare nell'intervallo, e il gate guarda solo lui: è ciò che restringe il caso debole, una sessione parallela che committa nel destinatario nel frattempo. Per la stessa ragione due figli sullo stesso destinatario girano in sequenza — condividono l'intervallo e il contatore degli id delle task —, su destinatari diversi in parallelo. Sul rosso nessun secondo lancio: l'agente riporta all'umano il motivo e il path dell'output del figlio.

**Ciò che si attende è il prodotto, non l'uscita.** «subito» attende un commit; «task» aperta con `create-task` attende una task; «task» che nelle parole dell'umano aggiunge un DLV a una task esistente attende un commit. Un destinatario senza lista task non ha dove aprire una task: lì «task» non parte, e l'agente lo dice; «subito» parte su qualunque repo git.

**Dal nome alla cartella, sul registry dei progetti.** L'umano e le segnalazioni nominano un progetto ora per `id`, ora per nome della cartella, e i due non coincidono sempre (`shop-legacy` sta in `shop-v2_legacy`): la risoluzione prova prima l'`id`, poi il nome della cartella. Un risultato solo è la cartella; nessuno o più d'uno, e l'agente chiede all'umano e non lancia. Il registry è stato della macchina, e lo legge solo lo script: le skill non lo nominano.

Lo script è `scripts/task/triage-altrove.sh`, con tre sottocomandi — `risolvi <nome>`, `prima --dest <dir> --atteso commit|task`, `verifica --dest <dir> --prima <sha> --atteso commit|task [--hash <sha>]...` —; exit `0` verde, `2` verdetto (non si lancia, o rosso), `1` errore d'uso. Il lancio sta nel body delle due skill.

## Il file degli scenari non entra nel sistema doc

Due esclusioni, entrambe su `triage/`, le stesse del registro ADR:

- `doc_excluded` in `lib-doc.sh` — la usa `doc-metrics.sh`, che percorre la docs-root intera. Senza, ogni record prenderebbe `MERGE?` e gli scenari diventerebbero una coda di lavoro per `rebalance-doc`.
- il `case` del perimetro in `check-doc-links.sh` — senza, ogni path citato in una segnalazione diventerebbe `DANGLING` per sempre su un file che per contratto non si riscrive.

`md-wrap.py` non ha un canale di esclusione e non gli serve: i record li scrive uno script, a campi su una riga.
