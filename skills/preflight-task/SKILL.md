---
name: preflight-task
description: Interactive Q&A to freeze design decisions on a task before execution.
allowed-tools: Bash(*), Read, Edit, Glob, AskUserQuestion
model: opus
---

Fase di preparazione prima di `run-task`. Identifica ambiguità nella task, le pone all'utente **in chat, tutte insieme e precedute da un recap del contesto**, scrive le risposte come decisioni congelate nel task file e **committa immediatamente** il task file. Le decisioni restano così tracciate separatamente dall'implementazione.

## Note utente
~~~human
$ARGUMENTS
~~~

## 0. Risoluzione task file

Stessa cascata di `run-task` — `arg → $LOOM_TASK → symlink`, risolta dallo script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

`${taskId}` = ID nelle Note utente (es. `T310`); ometti l'argomento se non c'è. Output: `TASK_ID` · `TASK_FILE` · `TASK_SRC`.

**Exit non-zero = nessun binding risolvibile: termina con un errore.** Non chiedere all'utente quale task: aprire un preflight su un bersaglio che nessuno ha nominato significa congelare e committare decisioni su una task indovinata, e il costo non si paga nel turno ma a valle. La cascata `arg → $LOOM_TASK → symlink` esiste apposta — quando non risolve, la risposta corretta è invocare la skill nominando la task.

**No subagent. `Read` diretto di `TASK_FILE`.**

Stampa header compatto identico a run-task:

```
📋 ${taskId} — ${titolo}
📐 Size: ${size} | ⚡ ${priority}
📝 ${prima riga della Description, troncata a ~100 char}
📦 ${numero deliverables} deliverables
📁 Folder: ${campo Folder se popolato, altrimenti ometti riga}
🛫 Preflight
```

## 1. Analisi ambiguità

Leggi tutto il task file. Identifica punti dove l'esecuzione richiederebbe scelte non documentate:

- **Description vaga**: termini astratti senza concretizzazione operativa
- **Acceptance Criteria non misurabili**: criteri qualitativi senza metrica/check verificabile
- **Dependencies implicite**: la task riferisce moduli/librerie/task non listate
- **Scope incerto**: confine tra cosa è "in" e cosa è "out" non chiaro
- **Scelte architetturali aperte**: dove mettere il nuovo codice, quale pattern, quali tradeoff
- **Deliverables ambigui**: item che ammettono più interpretazioni
- **Edge case non considerati**: comportamento atteso su input borderline

Per ogni punto, formula una domanda **concreta e decidibile**: deve nominare la scelta che l'esecuzione dovrà comunque fare, non chiedere un parere generico ("come faresti X?"). Concreta non vuol dire chiusa — le domande restano **aperte**, senza ventaglio di opzioni da spuntare: chiudere il dominio adesso obbligherebbe a ritagliare tre alternative su un terreno che al momento della domanda è ancora aperto, e chi legge tre alternative tende a sceglierne una invece di produrne una quarta.

Per ogni domanda, registra internamente due cose che servono allo step 2:

- **il sottosistema che tocca** — il perimetro del recap si ricava da qui, non dal progetto intero;
- **le strade che hai già visto** analizzando la task — entrano nel blocco come materiale non vincolante (step 2b), non come opzioni.

## 2. Recap del contesto, poi tutte le domande insieme

Le domande si pongono **scrivendo in chat**, non con `AskUserQuestion`, e arrivano tutte in un turno solo con tre tempi: il recap, il blocco delle domande, la fine del turno. L'utente risponde in prosa nel turno successivo.

La ragione è che una domanda posta da sola arriva prima del contesto che la rende decidibile: chi risponde a `D1` non ha ancora visto `D5`, e le due possono essere accoppiate — dove va un parser vincola come si chiama il flag che lo attiva.

Un solo ping TTS, prima di scrivere il blocco:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

Topic = argomento concreto del blocco, 3-7 parole. NO generici. **Uno solo, non uno per domanda**: è l'unico segnale che avvisa l'utente che la sessione ha smesso di lavorare, perché il badge di stato non annuncia più `ask` (§Note).

### 2a. Il recap — grado `K1`, perimetro derivato dalle domande

Prima delle domande, scrivi in chat il quadro dei sottosistemi su cui le decisioni cadranno. Serve a rendere presente in memoria ciò su cui si decide: una decisione si può prendere solo su ciò che si ha in mente.

- **Grado: `K1`.** Fisso, non un decremento della competenza dichiarata in §Competenze utente — quella sezione non marca quali voci siano settori progettuali e quali materie, quindi un decremento relativo non è calcolabile. La scala vive nell'output style (`output-styles/regole-output.md` §La scala delle Competenze utente): qui si dichiara **a che grado scrivere e su cosa**, mai cosa `K1` significhi.
- **Perimetro: tutti i sottosistemi che le domande toccano**, quelli registrati allo step 1, coperti per intero. Non il progetto intero — un preflight che recappa tutto ha sostituito l'affaticamento da context-switch con l'affaticamento da volume. Se le domande ne toccano cinque, il recap ne copre cinque.
- **Nessun freno di volume.** Niente tetto in righe, niente riduzione al sottosistema dominante, niente criterio di sufficienza. Il recap è materiale da consultare, non un'introduzione alle domande: `K1` glossa i termini specialistici ed esplicita le implicazioni proprio per renderlo consultabile, e accorciarlo per brevità toglie la funzione per cui il grado è stato scelto. Un minuto di lettura in più costa meno di una decisione sbagliata congelata in `## Decisions` ed eseguita da `run-task`.

### 2b. Il blocco delle domande

Tutte le domande insieme, dopo il recap, in un blocco unico:

```markdown
- **D3** — dove collocare il parser dei glifi
  <la domanda per esteso, aperta>
  *Strade viste (materiale, non un ventaglio da spuntare):* dentro `view.ts` · modulo nuovo `glyphs.ts` · inline nel renderer
```

- **Ogni `D{N}` porta una maniglia verbo+oggetto**, la prima citazione compresa. `D3` da solo è una coordinata opaca: non porta contenuto proprio, e un blocco di sette righe `D1`…`D7` nude costringe a rileggere per capire di cosa si parla — esattamente il costo che questo formato esiste per togliere.
- **Le strade candidate stanno in riga separata sotto la domanda**, mai dentro il suo corpo, e sono dichiarate non vincolanti. Dentro la prosa si leggerebbero come il ventaglio delle possibilità; in riga a parte si leggono come materiale. Ometti la riga quando non hai candidati: nominarne di finti è peggio che tacere.
- **La numerazione è quella che finirà nel file.** `D{N}` riparte da `D1` a ogni esecuzione della skill (è la data del blocco a disambiguare i giri di preflight), ma dentro **questa** esecuzione non si rinumera mai: né fra un giro di domande e il successivo, né alla scrittura di `## Decisions`. Rinumerare farebbe scadere ogni `D{N}` che l'utente ha già citato rispondendo.

### 2c. Il turno finisce qui

Scritto il blocco, **fermati**. Non rispondere alle domande da solo, non scrivere `## Decisions`, non committare: lo step 3 parte solo dopo che l'utente ha risposto in un turno successivo.

Questo vincolo è un'istruzione, non un meccanismo. `AskUserQuestion` sospendeva l'esecuzione per costruzione — finché la risposta non arrivava la sessione non poteva proseguire. Un blocco di domande in markdown è testo come il resto del turno, e nulla impedisce di tirare dritto fino al commit con decisioni che nessun umano ha preso. Il fallimento è silenzioso: produce un `## Decisions` pieno e ben formato, non un errore.

### 2d. Il giro successivo — la risposta parziale è il regime normale

L'utente risponde alle domande che ha in mente adesso e lascia le altre. Non è un caso degradato: è come funziona. Ma le risposte date **non lasciano intatte** le domande rimaste — alcune le risolvono per implicazione, altre ne riducono il dominio senza chiuderlo.

Il giro successivo quindi **ricalcola** le domande aperte invece di ricopiarle:

- **risolta per implicazione** → ripresentala con la risposta derivata **e il perché**, come proposta smentibile con una parola — es. *D6 — nome del flag → `--glyphs`, discende da D1*. Non chiuderla in silenzio: metterebbe nel file una decisione che nessuno ha preso, ed è un errore invisibile perché produce una voce ben formata come tutte le altre.
- **solo ristretta** → ripresentala con meno strade, dichiarando quali sono cadute e per quale risposta.
- **intatta** → ripresentala com'è.

Nessuna domanda sparisce senza passare davanti all'utente, nessuna derivazione entra nel file senza essere stata mostrata. Gli id restano gli stessi: `D6` resta `D6`.

Vale a ogni giro anche il resto dello step 2: un ping TTS solo, e il turno che finisce dopo il blocco.

### 2e. Nessuna domanda si chiude senza verdetto

**Ogni `D{N}` deve arrivare a un esito esplicito prima che la skill scriva e committi.** «Non decido ora» è un verdetto legittimo, ma va dichiarato dall'utente **con la sua motivazione** e scritto nel file come tale — non è il silenzio su una domanda evaporata.

Ne discende che i giri di domande si ripetono finché la copertura non è piena: la skill **non chiude e non committa** con una `D{N}` senza esito. Una domanda posta e poi evaporata lascia `run-task` davanti al nulla, senza sapere se lì è libero o se qualcuno si è dimenticato di decidere.

Per ogni risposta, registra internamente: la domanda, l'esito, il razionale se l'utente lo fornisce, e la derivazione se l'esito viene da un collasso non smentito.

**Non procedere all'esecuzione**: questa skill si ferma allo step 4 (write + commit del task file). Niente implementazione.

## 3. Aggiornamento task file

Aggiungi/aggiorna la sezione `## Decisions` nel task file. Posizionamento: tra `## Deliverables Checklist` e `## Implementation Notes`. Se la sezione non esiste, creala. Se esiste, **appendi** in fondo (non sovrascrivere — preflight può essere ri-eseguito su task evolute).

Formato:

```markdown
## Decisions

### Preflight ${YYYY-MM-DD HH:mm}

- **D1** — ${la maniglia verbo+oggetto, la stessa mostrata in chat}
  - **Scelta**: ${risposta}
  - **Razionale**: ${se presente, altrimenti omettere riga}

- **D2** — ...
```

Tre regole sulla scrittura del blocco:

- **Gli id sono quelli mostrati in chat**, uno per uno. Non si rinumera e non si ricompatta: l'utente ha risposto citandoli, e cambiarli qui li fa scadere. `D{N}` riparte da `D1` solo alla prossima **esecuzione** della skill, che è un blocco datato nuovo.
- **Ogni `D{N}` del giro compare, con il suo esito.** Non decisa dall'utente:

  ```markdown
  - **D4** — ${maniglia}
    - **Non decisa**: ${motivazione dell'utente, testuale}
  ```

  È l'unica forma ammessa oltre a `**Scelta**`, e rende leggibile a `run-task` la differenza fra «qui sei libero» e «qualcuno si è dimenticato». Se una domanda è ancora senza esito, **non sei allo step 3**: torna al giro di domande (§2d).
- **Una scelta derivata da un collasso non smentito porta la derivazione accanto**: `- **Scelta**: ${risposta} — *derivata da D1, non smentita*`.

**Caso nessuna ambiguità (step 1 vuoto)**: scrivi comunque il blocco header datato, senza decisioni:

```markdown
### Preflight ${YYYY-MM-DD HH:mm}

- _Nessuna ambiguità rilevata._ Task pronta per `run-task` senza decisioni da congelare.
```

L'assenza di bullet `**D{N}**` sotto il blocco è il segnale che `start-task` legge come "preflight verificata, nessuna decisione" (distinto da "preflight mai eseguita" = blocco assente).

## 3b. Le decisioni che rendono falsa una pagina di doc

Una `D{N}` che sceglie di cambiare un comportamento **già descritto in doc** produce un drift nell'istante in cui viene congelata, non quando il codice arriva. Preflight è l'unico momento presidiato del ciclo: c'è un umano nella stanza e dirlo costa una riga. Ricavare lo stesso fatto più tardi, rileggendo la prosa di una `D{N}`, sarebbe un giudizio invece che un meccanismo.

Per ogni decisione appena scritta, chiediti: *esiste una pagina di `{docs_root}/reference/` o un file @-importato da `CLAUDE.md` che dopo questa scelta dirà il falso?* Se sì, appendi una voce alla sezione `## Doc Impact` del task file:

```markdown
- **<la nozione: cosa diventa vero, non cosa si è deciso>**
  Ancora: <trigger concreto — comando, keyword, pattern>
  🚨 drift: {docs_root}/reference/<file>.md
```

Regole di scrittura, tutte già note e nessuna nuova:

- **La sezione `## Doc Impact` sta fra `## Testing Notes` e `## Prod Validation`.** Se manca, creala lì. Se contiene solo il placeholder `*Nessuna nozione documentale emersa al create-task.*`, sostituiscilo con le tue voci.
- **Appendi in coda, senza deduplicare** — stesso regime dei blocchi datati di `## Decisions`: preflight è ri-eseguibile, e due giri che decidono la stessa cosa lasciano due voci. Le scarta il checkpoint, che è chi le filtra.
- **Nessun marker di esito.** `→ ✔️ inbox` e `→ ✖️ <parola>` li scrive solo `checkpoint-task`: una voce senza è per costruzione «non ancora lavorata», e metterli qui la farebbe saltare. `⏳ <evento di sblocco>` è l'eccezione — puoi scriverlo tu quando la nozione è vera ma il suo referente non esiste ancora, e non è terminale: il checkpoint la ripesca comunque.
- **Non decidere il target doc.** La sentinella nomina i file *candidati a essere falsi*, che non sono il file dove la nozione atterrerà: quello lo decide `drain-doc`, in differita.
- **Una voce senza sentinella è legittima.** Una decisione può produrre una nozione documentale senza rendere falso niente: entra in `## Doc Impact` normale, e va a coda.

Se nessuna decisione tocca la doc, **non scrivere niente** — nessun placeholder, nessuna sezione vuota. `## Doc Impact` non è il registro delle decisioni, quello è `## Decisions`.

## 3c. Promozione a 🟢 Ready

Scritte le decisioni, porta la task allo stato **🟢 Ready** — «preflight fatto, zero codice», il gradino fra `🔵` e `🟡`. Serve perché il preflight è un investimento già pagato, e senza un glifo suo resta leggibile solo aprendo il task file per vedere se `## Decisions` è popolata.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/task/promote-ready.sh" ${taskId}
```

Lo script promuove **solo da 🔵** e tace altrimenti: la skill è ri-eseguibile, e rifare il preflight su una task già `🟡` o `✔️` non deve riaprirla. Il confronto legge la cella `Prog` di `tasks.md`, non il campo `Progress` del task file, che è testo libero. Aggiorna riga di tabella, nodo del grafo lane e campo `Progress`.

Vale anche nel caso «nessuna ambiguità»: il marker in `## Decisions` dice che il preflight è passato, e la Prog deve dire la stessa cosa.

## 4. Commit del task file

Appena promossa la Prog, committa **subito** task file e `tasks.md` (commit dedicato, separato dall'implementazione). Usa gli helper di `lib.sh`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh"
# N≥1 → "...- ${N} decisioni congelate" | N=0 (nessuna ambiguità) → "...- nessuna ambiguità"
lw_git_add_n_commit "task(${taskId}): preflight - ${N} decisioni congelate" "${task_file}" "${tasks_md}"
lw_git_push
```

- Committa **solo** quei due file: `lw_git_add_n_commit` stagia e committa con la stessa pathspec, quindi ciò che altre sessioni hanno lasciato in stage nello stesso worktree resta fuori. Non usare `git commit -m` nudo — senza pathspec committa l'intero indice. `tasks.md` entra perché lo step 3c può averne cambiato la riga; se la promozione non è scattata il file è pulito e non produce diff.
- Messaggio: `task(${taskId}): preflight - ${N} decisioni congelate` se `${N}` ≥ 1, altrimenti `task(${taskId}): preflight - nessuna ambiguità`.
- `${N}` = numero di `D{N}` scritte da **questa** esecuzione, le non-decise comprese: hanno un esito dichiarato come le altre (0 nel caso nessuna ambiguità).
- Push subito dopo il commit, coerente con `create-task` / `checkpoint-task` (tutte pushano). Senza remote `lw_git_push` avvisa su stderr ed esce 0: la skill prosegue, il commit resta locale.

Dopo commit+push, mostra all'utente:

```
✅ Preflight completato: ${N} decisioni congelate in ${task_file}
   📌 Committate e pushate: task(${taskId}): preflight - ${N} decisioni congelate
   🚨 ${M} sentinelle di drift in Doc Impact  ← solo se ${M} > 0
   Pronta per /loom-works:run-task
```

## Note

- **Non esegue codice**: preflight congela decisioni e, quando una di quelle rende falsa una pagina di doc, ne cattura la sentinella (step 3b). Implementazione resta a `run-task`.
- **Due sezioni, due mestieri.** `## Decisions` porta *cosa si è deciso* ed è cronaca datata: nessuno la legge a valle. `## Doc Impact` porta *cosa è diventato vero*, e il checkpoint la svuota in inbox. Scrivere la decisione in `## Doc Impact` è il modo tipico di sbagliare: quella riga andrebbe in inbox come intenzione e verrebbe scartata allo smaltimento.
- **Idempotenza parziale**: ri-eseguire preflight su una task aggiunge un nuovo blocco datato. Lo storico delle decisioni resta intatto. Ogni giro produce il suo commit dedicato.
- **Task piccole / nessuna ambiguità**: se l'analisi (step 1) non trova ambiguità reali, salta l'intero step 2 — **recap compreso** — ma **scrivi comunque il marker** in `## Decisions` (step 3, caso nessuna ambiguità) e committalo (step 4, messaggio `nessuna ambiguità`). Serve a `start-task` per distinguere "preflight già passata, niente da decidere" da "preflight mai eseguita". Mostra: `🛫 Nessuna ambiguità rilevata — marker registrato. Task pronta per run-task.`
  Il recap esiste per rendere prendibile una decisione: senza domande non ha bersaglio e diventerebbe volume gratuito sul ramo di maggioranza. Chi vuole il quadro di una task senza decidere niente ha già `recap-status-task`.
- **Lo stato che la sessione annuncia durante l'attesa è `done`, non `ask`** — conseguenza nota del porre le domande in chat, non un difetto da correggere qui. I due hook che alimentano il badge di compass sono macchina-personali (`~/.claude/settings.json`): `Notification` esegue `compass ask`, `Stop` esegue `compass done`. `AskUserQuestion` scatenava il primo perché sospendeva l'esecuzione; un blocco di domande scritto chiude il turno e scatena il secondo. Nel rollup `error > ask > done > running > idle` un preflight che aspetta pesa quindi quanto una sessione finita, e perde contro qualunque altra tab che stia chiedendo un permesso. Non è correggibile dentro il plugin — quegli hook stanno fuori dal perimetro di famiglia — ed è la ragione per cui il ping TTS dello step 2 resta obbligatorio.
- **Commit + push automatici**: lo step 4 committa **solo** il task file (commit dedicato) e pusha, come le altre skill task-level. Decisioni tracciate separatamente dall'implementazione.
