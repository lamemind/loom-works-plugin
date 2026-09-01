---
name: run-task
description: Esegue i deliverable di una task — perimetro dichiarabile sui DLV, un commit per DLV chiuso, rito di validazione scelto da Size.
allowed-tools: Bash(*), Task, Read, Edit, Write, Glob, Grep, TodoWrite
model: sonnet
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

Poi riporta quali DLV sono chiusi e quali restano aperti nel task file, e suggerisci `/loom-works:checkpoint-task` per il checkpoint (Prog, Progress Log, fase doc).

## Artefatti e materiale di lavoro

Output intermedi che non sono codice del progetto (dump, analisi, findings, script di supporto) → dentro la **task folder**, mai sparsi nel repo né sotto `{docs_root}/tasks/`.

- La task folder vive in **project root**, dot-prefixed; il campo `📁 Folder` la mostra root-relative (`./.YY-MM-DD-slug`). Sotto `{docs_root}/tasks/` stanno **solo** i task file `.md` — **mai** una folder.
- **Non creare folder a mano** (`mkdir`). Crearla/agganciarla solo via skill:
  - task senza folder che ora serve → `/loom-works:set-task-folder ${taskId}`
  - materiale fuori dal ciclo task → `/loom-works:scratch-new <slug>`
- CWD resta sempre project root: scrivi nei file passando il path della folder, non con `cd`.

## Doc Impact (append libero durante l'esecuzione)

Se durante run-task emergono nozioni documentali (decisioni di design, pattern non-ovvi, gotcha, conoscenza che merita doc), **appendile direttamente** alla sezione `## Doc Impact` del task file. Format: bullet con **nozione** + **ancora primaria** (tag/keyword/comando/pattern).

**La voce resta viva, senza marker.** Finché la task è attiva le voci si riscrivono e si eliminano, e sei autorizzato — anzi tenuto — a farlo sulle voci esistenti quando il codice che stai scrivendo le smentisce: anche run-task riesamina, non è un archivio ad append. Il trasloco in inbox è del `checkpoint-task`, al rilascio o alla chiusura; dove una nozione atterri lo decide `drain-notions`, in differita.
