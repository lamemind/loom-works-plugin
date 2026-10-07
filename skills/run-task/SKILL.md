---
name: run-task
description: Esegue i deliverable di una task — perimetro dichiarabile sui DLV, un commit per DLV chiuso, rito di validazione scelto da Size.
allowed-tools: Bash(*), Task, Read, Edit, Write, Glob, Grep, TodoWrite
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

Da qui si leggono due cose, e due sole: l'**ID della task** (es. `T310`) e il **perimetro dei DLV**, in qualunque forma l'utente lo scriva — `solo DLV5`, `1,2,6`, `dal 3 all'8`, `fermati al 4`. Traducilo nella spec dello script (§2). Tutto il resto è istruzione libera, e vale quanto qualunque altra riga del prompt.

## 0. Presenta la task

Risolvi il task file con lo script, mai a mano — la cascata `arg → $LOOM_TASK → symlink` è una sola per tutta la famiglia:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

`${taskId}` = ID trovato nelle Note utente; ometti l'argomento se non c'è. Output: `TASK_ID` · `TASK_FILE` (assoluto) · `TASK_SRC` ∈ `arg|env|symlink`. Exit non-zero = nessun binding risolvibile: chiedi all'utente quale task eseguire, non tirare a indovinare.

Fai **sempre** `Read` di `TASK_FILE`: in contesto può non esserci affatto (invocazione on-the-fly) o esserci troncato (budget dell'hook di iniezione).

`TASK_SRC` decide il regime di commit e nient'altro: `symlink` → linked · `env`/`arg` → **detached**, e in detached ogni commit porta la propria pathspec (§6).

## 1. Gate `Size: Epic` — dichiara e fermati

Prima di ogni altra cosa, e prima del fallback su Size assente, o un cappello verrebbe eseguito come una task media. Un perimetro dichiarato nelle Note utente **non** apre il gate.

Una task `Size: Epic` è un cappello, e un cappello non ha lavoro eseguibile proprio: sta tutto nelle figlie. Non aprire nessun deliverable, non scrivere codice. Stampa invece:

- che `${taskId}` è un'epica e che `run-task` non la esegue
- l'elenco delle figlie con la loro Prog, da `${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId} --children`
- l'invito a eseguire una figlia (`/loom-works:run-task T{N}`) o a chiedere il quadro con `/loom-works:recap-status-epic ${taskId}`

Poi termina. Nessuna promozione, nessun ping TTS, nessuna fase Doc Impact: non è stato fatto lavoro.

## 2. Perimetro — quali DLV entrano

I deliverable sono **oggetti indirizzabili**, numerati **posizionalmente 1-based** sulle checkbox a colonna zero di `## Deliverables Checklist`. Il conteggio non lo fai a occhio: lo fa lo script, che è anche quello che spunta (§6) — due conteggi diversi divergerebbero al primo task file con una forma inattesa.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/task-deliverables.sh ${taskId} [--scope "1,3-5"]
```

- **Nessun perimetro nelle Note utente** → invoca senza `--scope`: il perimetro è **tutti i DLV ancora `[ ]`**, in ordine di file.
- **Perimetro dichiarato** → traducilo in spec: lista `1,2,6`, range `3-8`, combinabili `1,3-5,9`. «Fermati al 4» su una task ai primi DLV è `1-4`.

Output: una riga per deliverable — `DLV|<n>|open⎪done|in⎪out|<testo>` — più `SCOPE_RESOLVED` e `SCOPE_COUNT`. Il testo è sempre l'ultimo campo perché può contenere `|`.

**Exit non-zero = fermati e riporta l'errore all'utente.** Lo script rifiuta un indice fuori range, una spec malformata, un perimetro vuoto e un DLV già `[x]` nominato esplicitamente — un deliverable fatto non si ri-esegue mai, nemmeno chiesto da solo; per rifarlo davvero l'utente toglie la spunta a mano. Non ripiegare su «eseguo quello che ho capito»: un run-task che lavora su un insieme diverso da quello annunciato è indistinguibile a valle da uno corretto.

**Dichiara il perimetro in apertura**, prima di aprire qualunque file di lavoro — è il contratto con chi ti ha invocato:

```
🎯 Perimetro: DLV 3, 5, 6 di 8
   ▶ DLV3 <maniglia>
   ▶ DLV5 <maniglia>
   ▶ DLV6 <maniglia>
   ⏸ fuori perimetro: DLV1, 2, 4, 7, 8
   ✔️ già chiusi: (nessuno)
```

## 3. Gate preflight — mai partire con dubbi architetturali aperti

Il piano dev'essere chiaro **prima** di scrivere codice. Chi congela le aspettative è `preflight-task`, non tu: da questa skill non parte nessuna domanda architetturale inline.

- **Size L** → preflight **obbligatorio**. Assente = rifiuto: fermati e rimanda a `/loom-works:preflight-task ${taskId}`.
- **Size S/M** → preflight **preteso quando i dubbi emergono**. Finché la strada è chiara procedi; al primo dubbio architetturale ti fermi e rimandi, non decidi tu e non chiedi in chat.

«Preflight fatto» lo attesta il blocco `## Decisions` datato nel task file — vale anche un marker esplicito di «nessuna ambiguità». La Prog 🟢 è il glifo derivato, la fonte è il file.

**Non vale un blocco il cui heading porta `— premessa decaduta`**: è il preflight che si è fermato davanti a una premessa smentita dalla misura, e non ha posto domande. Se è il blocco `### Preflight` più recente, fermati **a ogni Size** e rimanda alla ricostruzione delle premesse nel task file, poi a `/loom-works:preflight-task ${taskId}`: i DLV poggiano su un meccanismo che la misura ha smentito, ed eseguirli produce lavoro ben formato su un terreno falso.

## 4. Rito di validazione — lo sceglie `Size`

`Size` e perimetro sono **ortogonali**: Size decide quanta validazione e pianificazione precedono il codice, il perimetro su quali DLV si lavora.

| Size | Rito |
|------|------|
| **S** | Nessuno. Leggi, implementa, testa, builda. |
| **M** | Validazione leggera: requisiti chiari, dipendenze dichiarate presenti. `TodoWrite` solo se servono più di 3 step distinti. |
| **L** | Validazione profonda (collocazione dell'implementazione, requisiti a monte verificabili e presenti, librerie esterne dichiarate) · scomposizione in micro-step con `TodoWrite`, ognuno validabile · piano top-down prima di toccare codice. |

Size assente → tratta come **M**.

Nessun checkpoint di feedback, a nessun Size: il punto di fermo è il commit per-DLV di §6, e una task L può chiudersi in un'unica mandata. Esecuzione unsupervised — qualità e correttezza vincono su velocità, l'utente controllerà ogni riga.

## 5. Promozione a 🟡 — subito prima di scrivere codice

Dopo i gate (§1, §3) e dopo il piano quando Size è L:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/promote-wip.sh ${taskId}
```

Aggiorna insieme cella `Prog`, nodo del grafo lane e campo `Progress` del task file, poi committa e pusha da sé. Promuove **solo da 🔵 e da 🟢**; da ✔️ o 🔒 dichiara il no-op e non tocca niente, così un id sbagliato non riapre una task chiusa.

Il commit è dedicato e immediato perché `tasks.md` è condiviso: una promozione lasciata non committata viaggia sul commit della prima altra sessione che passa — contenuto giusto, attribuzione sbagliata.

## 6. Il ciclo — un DLV alla volta

Per ogni DLV del perimetro, **in ordine**:

1. **Lavora** il deliverable fino a chiuderlo davvero: implementa, testa, builda.
2. **Spunta** la voce: `${CLAUDE_PLUGIN_ROOT}/scripts/task/task-deliverables.sh ${taskId} --check <n>`
3. **Committa** solo il codice di quel DLV, più la spunta appena scritta:

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
     && lw_git_add_n_commit "run(${taskId}): DLV<n> <maniglia>" <path>... "${TASK_FILE}" \
     && lw_git_push "$(lw_current_branch)"
   ```

   La pathspec è **obbligatoria** e la componi tu, elencando i file che hai toccato per quel deliverable: l'indice è una zona comune del worktree e un commit senza path rastrella anche ciò che altre sessioni hanno in stage. Vale in entrambi i regimi — in linked è comunque ciò che tiene un DLV separato dal successivo.

Il commit è **leggero**: codice + spunta, niente `Prog`, niente Progress Log, niente inbox. Il tracking e la doc restano di `checkpoint-task`, che è l'unico a chiudere la task (✔️, `Done at`, trasloco delle nozioni). Non fare qui il suo mestiere.

Un DLV che non riesci a chiudere: **non spuntarlo e non committarlo come fatto**. Fermati, dichiara quale è e perché, e lascia intatti quelli dopo.

## 7. Chiusura

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "$(say_id ${taskId}) done"
```

In caso di blocco reale: `say_auto "$(say_id ${taskId}) blocked"`.

Poi riporta quali DLV sono chiusi e quali restano aperti nel task file, e suggerisci `/loom-works:checkpoint-task` per il checkpoint (Prog, Progress Log, fase doc). Il report chiude con la sezione `🚦 Segnalazioni` (§8), sempre.

## 8. 🚦 Segnalazioni — la sezione fissa del report

> Stato e requisiti rinviati: factory · T12 §Custodia — un limite del triage si segnala lì, non si apre una task qui.

Una segnalazione è un problema incontrato durante il lavoro che chiede una decisione: un difetto fuori perimetro, un rischio, un residuo, una cosa che hai lasciato com'era, una cosa che hai corretto di tua iniziativa. Ogni segnalazione ha quattro uscite — **subito** (si risolve ora), **task** (diventa una task), **scarto** (non si fa, e se torna deve tacere: un motivo nel registro ADR), **ignora** (non si fa, e se torna parla: nessun record ADR) — e ogni decisione diventa uno **scenario** su disco. Formato e sede: `${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md`.

**La sezione c'è sempre, anche vuota**: l'assenza di segnalazioni è un fatto dichiarato, non una dimenticanza. La forma è fissa, perché è ciò che chi rilegge i transcript cerca:

```
**🚦 Segnalazioni**

**S{N}** — <la segnalazione, su una riga>
  subito · task · scarto · ignora
**S{N}** — <ciò che hai corretto di tua iniziativa, su una riga>
  ☑ subito (agente) · task · scarto · ignora
```

A zero segnalazioni, una riga sola: `**🚦 Segnalazioni** — nessuna`.

- **`S{N}` numera da 1 dentro questo report**, e la riga porta l'id e la segnalazione, nient'altro: il testo dopo `— ` è quello che lo scenario cita byte per byte.
- **Prima di stampare, interroga il registro ADR** su ogni segnalazione (`adr.sh cerca`, regola in contesto): exit `0` vuol dire già scartata con un motivo, e non la riporti.
- **Ciò che hai corretto di tua iniziativa sta dentro la sezione, con «subito» già marcato e chi = agente — mai in un inciso del report.** «Ho corretto un difetto pre-esistente» è una decisione che hai già preso: resta ribaltabile solo se l'umano la vede fra le segnalazioni. Prima di stampare la sezione ne scrivi lo scenario:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito --chi agente \
    --momento flusso --skill run-task --no-commit <<'SCENARIO'
  <la segnalazione, identica al testo della riga S{N}>
  SCENARIO
  ```

- **Tu non scarti e non ignori.** Una segnalazione che ritieni irrilevante la riporti comunque con le quattro uscite: uno scarto sbagliato è un segnale perso che nessuno recupera, un tuo ignora è una segnalazione non stampata, e lo script rifiuta entrambi con `--chi agente`.

Gli scenari si scrivono con `--no-commit`, uno per segnalazione, e si committano insieme — i path sono quelli che lo script stampa (`-> scenario scritto:`, e `-> record ADR:` sullo scarto):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && lw_git_add_n_commit "triage(${taskId}): <N> scenari" <path>... \
  && lw_git_push "$(lw_current_branch)"
```

### La risposta — prosa libera, lo scenario lo scrivi tu

L'umano risponde come vuole: in prosa, dettando a voce, in ordine sparso, su una parte sola delle segnalazioni. Nessuna domanda a scelta e nessuna griglia da compilare — nessuno strumento presidia la risposta, la leggi tu nel turno dopo. Riconosci la segnalazione da `S1`, `s1`, `1` o «la prima», e per ogni segnalazione decisa scrivi uno scenario `--chi umano --momento flusso`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/triage.sh" scenario --slug <slug> --uscita subito|task|scarto|ignora --chi umano \
  --momento flusso --skill run-task [--ancora <path>]... --no-commit <<'SCENARIO'
<la segnalazione, identica al testo della riga S{N}>
<le parole dell'umano su quella segnalazione: il perché sullo scarto, l'approfondimento sulle altre uscite>
SCENARIO
```

Poi un commit solo per tutti, con lo snippet sopra.

- **Nessun default.** La segnalazione su cui l'umano non dice niente non produce niente: non la decidi tu e non la ripresenti. Il recupero delle segnalazioni rimaste senza risposta si fa a posteriori, fuori da questa conversazione.
- **L'approfondimento è obbligatorio quando la risposta lo porta.** Sono le parole con cui l'umano accompagna l'uscita — il criterio con cui la sceglie, la forma dell'azione, il progetto dove eseguirla — e lo script le scrive alla lettera nel campo `Approfondimento` dello scenario: senza, due scenari `task` della stessa sessione restano indistinguibili. Il ritaglio di una `S{N}` è tutto ciò che l'umano dice su quella segnalazione, parola d'uscita compresa; restano fuori solo l'identificatore (`S1`, «la prima») e la punteggiatura che la separa dalle vicine. Non ritocchi niente, refusi compresi; parole dettate su più righe le unisci con uno spazio, perché il campo sta su una riga. Un'uscita nuda, una conferma o un rifiuto nudo («subito», «ok», «no») non hanno approfondimento: la seconda riga non si scrive. Una frase che vale per più segnalazioni entra nello scenario di ognuna, e i pezzi non contigui della stessa segnalazione si uniscono nell'ordine in cui compaiono con ` […] ` a segnare il salto: «S1 subito, S2 ignora ; AUTORIZZO» dà a S1 `subito […] AUTORIZZO`. Sullo scarto le parole dell'umano sono il perché e vanno nel record ADR; con `--chi agente` non c'è nessuna risposta da citare — in entrambi i casi lo script rifiuta il campo.
- **Le parole dell'umano dettano la forma dell'esecuzione, non solo l'uscita.** «task» con «aggiungi un DLV alla task corrente» aggiunge il DLV e non apre nessuna task; «ci penso io» non esegue niente. Vale anche per il modo: «fallo subito ma in un subagente» resta `subito`, il modo sta nell'approfondimento, e `Uscita` resta il solo campo che si conta.
- **«subito» nel flusso è operativo**: scrivi lo scenario ed esegui, nella forma che le parole dicono.
- **«task» nel flusso è operativo come «subito»**: scrivi lo scenario e fai senza chiedere niente ciò che le parole dicono. Quando non dicono altro, apri la task: invoca `/loom-works:create-task` in modalità YOLO, con `yolo <la segnalazione>` come argomento, una task per segnalazione. «task» è già la richiesta della task: aspettare una seconda conferma lascerebbe la decisione registrata e il lavoro da nessuna parte.
- **«scarto»** vuole il perché e un'ancora. Lo scrivi solo quando la risposta nomina lo scarto o porta un perché («S2 scarto: capita una volta l'anno», «S2 no, capita una volta l'anno»); nominato senza perché, chiedilo una volta sola, poi scrivi. L'ancora è il path che la segnalazione tocca. Lo script scrive anche il record ADR, e stampa il suo path da mettere nel commit.
- **«ignora», e ogni rifiuto nudo** — «S2 no», «lascia perdere», «non vale la pena»: nessun motivo e nessuna parola «scarto» — lo scrivi subito, senza chiedere niente. Vuole l'ancora, il path che la segnalazione tocca, e nessun perché: lo script rifiuta `--perche` sull'ignora. Le parole con cui l'umano lo nomina («S5 ignora: già gestito in S4») sono l'approfondimento, non un perché. Non scrive nessun record ADR, quindi se la segnalazione torna la riporti di nuovo. Nel dubbio fra i due scegli l'ignora, perché è l'errore che si recupera: un ignora scritto dove l'umano voleva uno scarto torna nel report se la segnalazione torna, uno scarto scritto dove voleva un ignora è un record ADR che nessuna query colpirà.
- **La conferma e il ribaltamento valgono uguale.** Sulla segnalazione che avevi marcato `☑ subito (agente)`, «ok» è uno scenario `subito` e «fanne una task» uno scenario `task`, entrambi `--chi umano`, accanto al tuo: non si riscrive niente, i due record sono il dato.
- **Detta a posteriori, la stessa parola è un esito e non un'azione.** Chi rilegge il report da un'altra sessione registra con `--momento posteriori` e non esegue niente.

### L'uscita che riguarda un altro progetto

**Il destinatario lo porta la segnalazione.** Una segnalazione nomina di norma il progetto o i file che riguarda, e «subito» e «task» agiscono lì, senza una conferma prima del lancio. Quando l'umano nomina un progetto nelle sue parole vince quello; quando nessuno ne nomina uno resta il progetto della sessione, e si esegue qui. Lo scenario si scrive comunque qui: il destinatario sta nella segnalazione o nell'approfondimento, e non ha un campo suo.

Un altro progetto non lo scrivi da questa sessione: può tenerti in sola lettura, e una scrittura da Bash aggirerebbe il suo confine. Lo esegue una sessione figlia lanciata nella sua cartella, che ne carica `CLAUDE.md`, settings, skill e regole di commit. In ordine, con `A="${CLAUDE_PLUGIN_ROOT}/scripts/task/triage-altrove.sh"`:

1. `"$A" risolvi <progetto>` stampa la cartella. Exit `2`: nessun progetto con quel nome, o più d'uno — chiedi la cartella all'umano e non lanciare. Se la cartella è quella di questa sessione, nessun figlio: esegui qui.
2. `"$A" prima --dest <cartella> --atteso task|commit` stampa lo sha di `HEAD`, da passare al gate. `--atteso task` quando il figlio apre una task nuova, `commit` per «subito» e per ogni altra forma, come un DLV aggiunto a una task che c'è già. Exit `2`: l'uscita lì non parte (una task vuole la lista task del destinatario) — dillo all'umano.
3. Scrivi il prompt del figlio in un file fuori dai due repo. Per una task nuova: `/loom-works:create-task yolo <la segnalazione, il contesto che serve a chi non ha questa conversazione, le parole dell'umano>`. Altrimenti: cosa fare, con la segnalazione e le parole dell'umano alla lettera, e la richiesta di committare con le regole del progetto e di chiudere dichiarando l'hash del commit.
4. Lancia il figlio:

   ```bash
   cd <cartella> && env -u LOOM_TASK -u PROJECT_ROOT -u PTYXIS_PROFILE \
     claude -p --permission-mode auto --output-format text < <prompt> > <out> 2>&1
   ```

   Le tre variabili arrivano al figlio, e nessuna deve attraversare il confine: `LOOM_TASK` è il binding di sessione, e gli id delle task valgono dentro un progetto — il figlio risolverebbe una task che lì non esiste, o un'altra; `PROJECT_ROOT` batte la cartella nella ricerca della root, e il figlio scriverebbe nel progetto di questa sessione; `PTYXIS_PROFILE` è la chiave con cui gli hook annunciano lo stato a compass, e il figlio porterebbe a `done` il badge di questo progetto mentre lavori ancora.
5. `"$A" verifica --dest <cartella> --prima <sha> --atteso task|commit [--hash <l'hash che il figlio dichiara>]`. Il ritorno del figlio è self-report: il gate legge i commit nati nel destinatario dopo `prima`, e per una task vuole il task file aggiunto e la sua riga in `tasks.md`. Verde (exit `0`): riporta all'umano cosa è nato, id e hash. Rosso (exit `2`): nessun secondo lancio — riporta il motivo del gate e il path di `<out>`.

Due figli sullo stesso destinatario girano in sequenza, perché condividono l'intervallo del gate e il contatore degli id; su destinatari diversi vanno in parallelo.

## Artefatti e materiale di lavoro

Output intermedi che non sono codice del progetto (dump, analisi, findings, script di supporto) → dentro la **task folder**, mai sparsi nel repo né sotto `{docs_root}/tasks/`.

- La task folder vive in **project root**, dot-prefixed; il campo `📁 Folder` la mostra root-relative (`./.YY-MM-DD-slug`). Sotto `{docs_root}/tasks/` stanno **solo** i task file `.md` — **mai** una folder.
- **Non creare folder a mano** (`mkdir`). Crearla/agganciarla solo via skill:
  - task senza folder che ora serve → `/loom-works:set-task-folder ${taskId}`
  - materiale fuori dal ciclo task → `/loom-works:scratch-new <slug>`
- CWD resta sempre project root: scrivi nei file passando il path della folder, non con `cd`.

## Doc Impact (append libero durante l'esecuzione)

Se durante run-task emergono nozioni documentali (decisioni di design, pattern non-ovvi, gotcha, conoscenza che merita doc), **appendile direttamente** alla sede corrente. Format: bullet con **nozione** + **ancora primaria** (tag/keyword/comando/pattern).

**La sede la dichiara `## Doc Impact` del task file**, ed è una sola: se la sezione porta le voci, scrivi lì; se porta la riga `- → inbox <basename> · storia: <sha>`, il `checkpoint-task` ha già traslocato e la sede è quel file — scrivi in `{docs_root}/inbox/<basename>`, con id `max(nN)+1` e senza rinumerare niente. Formato e operazioni: `${CLAUDE_PLUGIN_ROOT}/docs/inbox-format.md`. Un inbox che porta `drainable` nella riga 3 è congelato: non scriverci, riporta la nozione all'utente.

**La voce resta viva, senza marker.** Finché la task è attiva le voci si riscrivono e si eliminano, e sei autorizzato — anzi tenuto — a farlo sulle voci esistenti quando il codice che stai scrivendo le smentisce: anche run-task riesamina, non è un archivio ad append. Dove una nozione atterri lo decide `drain-notions`, in differita.
