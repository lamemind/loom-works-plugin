---
name: preflight-task
description: Interactive Q&A to freeze design decisions on a task before execution.
allowed-tools: Bash(*), Read, Edit, Glob, AskUserQuestion
model: opus
---

Fase di preparazione prima di `run-task`. Verifica le premesse della task, identifica le ambiguità, le passa dal test di appartenenza — **pone all'utente solo le decisioni che sono sue** e mostra come **proposte smentibili** quelle che prende da sé — **in chat, in un turno solo, ognuna sotto il recap del sottosistema che tocca e di nuovo tutte insieme in un blocco finale**, scrive risposte e proposte non smentite come decisioni congelate nel task file e **committa immediatamente** il task file. Le decisioni restano così tracciate separatamente dall'implementazione.

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

## 0b. Verifica delle premesse — prima di cercare ambiguità

Una task poggia su affermazioni di meccanismo: «il canale che consegna l'envelope codifica in entità HTML», «un file da 12.000 caratteri porta qualche centinaio di span», «il body della skill entra nel transcript come record utente». Lo step 1 non le vede per costruzione — cerca ciò che **non è deciso**, e una premessa si presenta come fatto stabilito, quindi passa; il layout dello step 2 poi la peggiora, perché entra nel recap e ne esce glossata come se fosse sempre stata verificata. Su T143 sette domande su sette taravano il rimedio a un canale che nessuno aveva misurato, e la task è morta superseduta. Ne discende che le premesse si verificano **qui, prima**, non dentro l'analisi.

1. **Elenca** le affermazioni di meccanismo su cui poggia **più di un DLV, o un AC**: Description, Dependencies, Implementation Notes. Un'affermazione che regge un solo DLV si verifica quando quel DLV si esegue, non qui.
2. **Marca** ognuna: `misurata` — il task file o il materiale porta la misura (una cifra contata, l'output di un comando, un transcript nominato) — oppure `asserita` — detta come fatto, senza una misura accanto.
3. **Le asserite le misuri tu, adesso, quando la misura è una lettura**: `Read`, `Grep`, `git log`, un conteggio, un transcript aperto. È analisi, non implementazione — questa skill vieta di scrivere codice, non di leggere. Quando la misura richiede **eseguire codice o toccare un sistema vivo** (lanciare un job, chiamare un servizio, costruire un banco) non la fai: diventa una proposta `P{N}` di primo deliverable — «DLV0: misurare X prima di tutto» — che l'utente vede nel turno accanto alle altre (§2).
4. **Esito per premessa**, uno dei tre: `✅ misurata` con la cifra o il comando · `⏸ da misurare` con la `P{N}` che la porta a DLV · `❌ decaduta`. Il blocco delle premesse **apre il turno** dello step 2, prima delle generali, come lista compatta — una riga per premessa, esito e prova accanto; se la task non porta affermazioni che reggano più di un DLV, la lista lo dice in una riga e non si scrive altro.

### Premessa decaduta — decade tutto

Se la misura smentisce una premessa su cui poggia più di un DLV, **il preflight non pone domande**: le domande costruite su un terreno falso producono decisioni ben formate e inutili. Invece:

- **in chat**, per esteso: la premessa com'era scritta nel task file, la misura che la smentisce, i DLV e gli AC che ci poggiano;
- **nel task file**, in `## Decisions`, un blocco che dice la stessa cosa e nessuna `D{N}`:

  ```markdown
  ### Preflight ${YYYY-MM-DD HH:mm} — premessa decaduta

  - **Premessa**: ${testuale, com'era scritta}
  - **Misura**: ${cosa hai misurato, come, la cifra o l'output}
  - **Poggiano su di lei**: ${DLV e AC}
  - _Nessuna domanda posta. Ricostruire le premesse nel task file, poi rilanciare il preflight._
  ```

- **commit del solo task file** (§4, messaggio `task(${taskId}): preflight - premessa decaduta`), **nessuna promozione** — §3c non gira, la task non è pronta — poi **termina**.

La ricostruzione delle premesse è dell'utente, in questa conversazione o in un'altra: per questo lo stato sta nel file e non solo in chat, e un preflight rilanciato dopo legge il blocco e riparte da qui, non dallo step 1. Il heading porta `— premessa decaduta` perché `start-task` e `run-task` lo distinguono per costruzione dal marker «nessuna ambiguità» (anche lui un blocco datato senza `D{N}`): senza la dicitura, una task fermata davanti a una premessa falsa risulterebbe pronta per `run-task`.

## 1. Analisi ambiguità — produce candidate, non domande

Leggi tutto il task file. Identifica punti dove l'esecuzione richiederebbe scelte non documentate:

- **Description vaga**: termini astratti senza concretizzazione operativa
- **Acceptance Criteria non misurabili**: criteri qualitativi senza metrica/check verificabile
- **Dependencies implicite**: la task riferisce moduli/librerie/task non listate
- **Scope incerto**: confine tra cosa è "in" e cosa è "out" non chiaro
- **Scelte architetturali aperte**: dove mettere il nuovo codice, quale pattern, quali tradeoff
- **Deliverables ambigui**: item che ammettono più interpretazioni
- **Edge case non considerati**: comportamento atteso su input borderline

Per ogni punto, formula una **candidata** concreta e decidibile: deve nominare la scelta che l'esecuzione dovrà comunque fare, non chiedere un parere generico ("come faresti X?"). Poi la candidata passa dal test di appartenenza (§1b), che ha tre uscite e una sola per voce: **domanda** `D{N}` quando la risposta dipende da un dato che nel repo non c'è; **proposta** `P{N}` quando il dato sta nel repo e la decisione è tua, dichiarata con la sua ragione; **chiusa da una misura** quando la risposta si conta. Nessuna candidata diventa `D{N}` senza passare dal test: è il test, non l'elenco sopra, a decidere cosa arriva all'utente come domanda — l'elenco dice dove guardare, non cosa chiedere.

Le domande restano **aperte**, senza ventaglio di opzioni da spuntare: chiudere il dominio adesso obbligherebbe a ritagliare tre alternative su un terreno che al momento della domanda è ancora aperto, e chi legge tre alternative tende a sceglierne una invece di produrne una quarta. Le proposte invece **scelgono**: una strada, la ragione, smentibile con una parola.

Per ogni voce — domanda o proposta — registra internamente due cose che servono allo step 2:

- **i sottosistemi che tocca**, oppure la classe **generale** — il perimetro del recap si ricava da qui, non dal progetto intero, e da qui si ricava anche dove la voce comparirà nel turno (§2c, §2d);
- **le strade che hai già visto** analizzando la task — in una domanda entrano come materiale non vincolante (§2a), non come opzioni; in una proposta sono le strade scartate, e il perché le hai scartate è la ragione della proposta.

Sul primo dato, tre precisazioni:

- **Un sottosistema è un'area su cui le voci cadono**, alla granularità che serve a te: non un elenco derivato dai file che la task tocca, né un livello architetturale fissato in anticipo. Ordinali come preferisci — nessun criterio è imposto.
- **Una voce può toccarne due.** Registrali entrambi: comparirà sotto entrambi (§2d), e la ripetizione è la stessa che regge tutto questo layout.
- **`generale` è una classe residua e va dichiarata**, non lasciata implicita. Ci cade la voce trasversale, o quella su una scelta che precede la partizione stessa. Senza questa classe una voce simile non ha nessun sottosistema sotto cui stare e sparisce dal turno in silenzio — un turno ben formato con una decisione in meno, che è un fallimento invisibile.

  Vale anche il contrario: la comparsa di voci generali è un **sintomo**, non un caso ordinario da gestire. Se l'architettura sopra la task fosse completa, ogni voce cadrebbe dentro un perimetro suo.

## 1b. Il test di appartenenza — da candidata a domanda, proposta o misura

Lo step 1 produce **candidate**, non domande. Un elenco di classi di ambiguità è una quota di produzione: chi lo applica formula una voce per ogni classe che riesce a riempire, e il numero di voci finisce per misurare la ricchezza dell'analisi, non il numero di decisioni che sono davvero dell'utente. Il test qui sotto è la frase che le distingue.

**Ogni candidata passa il test prima di diventare una `D{N}`, e ha esattamente una di tre uscite.**

### Il discriminante: dove sta il dato che risolve

**Una decisione è dell'utente quando la risposta dipende da un dato che nel repo non c'è.** Non «è importante», non «è architetturale», non «ha più strade»: il codice è già stato letto da chi formula la candidata, e tutto ciò che si ricava dal codice, dai contratti, dai precedenti già in uso e dai principi già scritti appartiene a chi l'ha appena letto. I dati che nel repo non ci sono hanno un nome, e sono questi:

- **tolleranza di spesa** — quante invocazioni a pagamento, quanto diff su quanti file, quanto tempo: rigenerare 55 TLDR per ~110 chiamate haiku (T144 `D3`)
- **roadmap e sequenza fra task aperte** — quale delle due va prima, chi assorbe un disallineamento: T140 tocca le stesse tre skill che T139 riscriverà per un motivo suo (T144 `D2`, T139 `D2`)
- **perimetro della task** — se un difetto trovato per strada entra, se la task si spacca in figlie, quanto può crescere oltre i DLV dichiarati (T138 `D13` `D14`, T141 `D3`)
- **intento dietro un criterio ambiguo** — un AC che dice «ogni script del sistema doc» senza definirlo: solo chi l'ha scritto sa cosa intendeva (T139 `D1`)
- **abitudini di lavoro e lettori** — chi legge la doc, come si usano i log oggi, quanti turni l'utente vuole spendere adesso (T141 `D1` `D2`)
- **appetito al rischio** — quanto blast radius accettare su consumer fuori perimetro, quanta autonomia dare a un'automazione notturna (T139 `D4` `D11`)

Se la risposta dipende da uno di questi, la candidata è una **domanda** → `D{N}`. Se no, è **del modello** → **proposta** `P{N}`: la scelta, con la ragione — il dato del repo che la decide — smentibile con una parola (forma in §2a). Dove collocare un filtro, quale forma dà a una riga d'indice, quale exit code, se un predicato è dedicato o generico, quale delle due fonti deterministiche già esistenti si usa: su T140 erano tutte e nove di questo tipo, e nessuna aveva bisogno dell'utente.

### Non è una domanda, è una misura

**Se la risposta si ottiene contando qualcosa nel repo, si conta.** File, occorrenze, righe, commit: `Grep`, `wc`, `git log`. La cifra decide la candidata da sola o entra in una proposta con il suo numero — mai in una domanda. **Nessuna cifra a spanne nel corpo di una `D{N}`**: «qualche centinaio», «facilmente», «circa» dentro una domanda sono il sintomo che la misura manca, e la stima è libera di essere sbagliata senza che nulla lo segnali. Su T144 `D6` «qualche centinaio di span fra backtick» su un file da 12.000 caratteri erano 62, 69 e 79 su tre file contati: a quel volume la domanda non aveva più oggetto.

Vale anche per la **misura già fatta**: se un paragrafo del tuo stesso turno — il recap, una cifra che hai appena riportato — risolve la candidata, la candidata è chiusa. Su T144 `D11` la misura stava quattro paragrafi sopra la domanda (4 ancore orfane su 1.296, 3 sul file esente) e la domanda è stata posta comunque; su T139 `D12` il recap arrivava alla risposta e la domanda seguiva.

**Una misura decide un fatto, non un intento.** Quando un criterio è ambiguo — un AC che dice «ogni script del sistema doc» senza definire il perimetro — contare quanti script esistono risolve «quanti sono», non «quali intendeva chi ha scritto il criterio»: sono due domande diverse, e la seconda resta dell'utente anche dopo che la prima è stata contata (§Il discriminante, «intento dietro un criterio ambiguo»). Una candidata di questo tipo non si chiude con la cifra: la cifra entra nel corpo della domanda come misura già fatta, e la domanda resta `D{N}`.

### Non è una proposta, è esecuzione

Una candidata del modello diventa `P{N}` **solo se la strada scartata è una che qualcuno potrebbe ragionevolmente preferire** — costa diverso, rompe qualcosa di diverso, resta visibile dopo. Se la strada scartata non ha nessuno dalla sua parte, non c'è niente da smentire: la scelta è **esecuzione**, la prende `run-task` e si legge nel diff. Quale script numera i DLV, se due template si fondono in uno, a che passo del turno gira un controllo: nessuna di queste è una proposta.

Il test è una frase: «se l'utente la smentisse, cosa direbbe?». Se non c'è una risposta che non sia «fai come ti pare», la `P` non nasce. Una proposta senza avversario è una quota di produzione spostata dalle domande alle proposte: il turno si allunga di una voce che nessuno leggerà, e le proposte che contano affogano in mezzo.

### Casi limite

- **Il caso misto si spacca, ma non in due domande.** Una candidata con una metà di preferenza e una metà tecnica pone la sola metà dell'utente; la metà del modello **non diventa una `D{N}` a parte** — va sotto la domanda come conseguenza già derivata per ciascuna risposta possibile («se A, il TLDR si riproduce a ogni checkpoint; se B, solo al rilascio»), o come proposta. Su T138 la scelta fra trasloco a ogni checkpoint e trasloco al rilascio (`D1`, dell'utente) ha generato `D6` e `D7` come domande separate, ed erano le sue conseguenze tecniche: due domande in più per una decisione sola.
- **L'incertezza del modello non è un dato assente dal repo.** Una candidata su cui sei incerto fra due strade resta del modello: l'incertezza è lettura non finita, non una preferenza dell'utente. Si legge ancora finché una strada vince, e si propone con la ragione; se dopo aver letto le due strade sono davvero pari, la proposta lo dice e sceglie — l'utente smentisce con una parola.
- **Il coordinamento con un'altra task aperta è sempre dell'utente**, anche quando il modello vede benissimo qual è l'ordine migliore: la sequenza è roadmap, e la roadmap non sta nel repo. La proposta di ordine può accompagnare la domanda, non sostituirla.
- **Una premessa non è una candidata.** Un'affermazione di meccanismo su cui la task poggia si verifica **prima** dello step 1 (§0b): arrivata qui, una premessa falsa si presenta come fatto stabilito e passa il test senza essere guardata. Su T143 sette domande su sette taravano il rimedio a un canale che nessuno aveva misurato.

### Una uscita per candidata, e il conto si fa per voce

Ogni candidata esce dal test una volta: `D{N}`, `P{N}`, o chiusa da una misura. **Una proposta copre una candidata**; se ne copre due, le nomina entrambe. Niente «il resto lo decido io»: la copertura si verifica voce per voce, non per differenza.

Il numero di domande che ne esce **non è un obiettivo in nessuna direzione**: una domanda dell'utente in meno è una decisione presa al posto suo, una del modello in più è il costo che il test esiste per togliere. Il test non accorcia il turno — sposta le decisioni dove il dato sta.

## 2. Il turno — premesse, recap, domande e proposte intrecciati, blocco unico in coda

Domande e proposte si pongono **scrivendo in chat**, non con `AskUserQuestion`, e arrivano tutte in un turno solo. L'utente risponde in prosa nel turno successivo: alle domande con la scelta, alle proposte solo se le smentisce.

La ragione per cui arrivano insieme è che una voce posta da sola precede il contesto che la rende decidibile: chi risponde a `D1` non ha ancora visto `D5`, e le due possono essere accoppiate — dove va un parser vincola come si chiama il flag che lo attiva. Vale per le proposte quanto per le domande: una proposta si smentisce solo se il materiale che la motiva è sotto gli occhi, e una proposta letta senza il suo recap è un fatto compiuto.

Il turno ha quattro tempi, in quest'ordine:

```
intro / header
⓪ le premesse verificate (§0b): una riga per premessa, esito e prova accanto
① le domande e le proposte generali, precedute dal loro recap contestualizzante        (§2c)
② per ogni sottosistema toccato: il suo recap, poi le sue domande, poi le sue proposte  (§2d)
③ la copertura per DLV, poi il blocco finale: domande verbatim, proposte a maniglia         (§2e)
```

**Ogni voce compare due volte, ed è voluto: non è ridondanza da potare — ma le due occorrenze non pesano uguale.** La prima, sotto il sottosistema, arriva mentre il materiale che la risolve è ancora sotto gli occhi — chi decide non deve rimappare a memoria quale paragrafo di recap serviva a quale voce, e la maniglia verbo+oggetto identifica la voce ma non riporta indietro il contesto. La seconda è dove si risponde: per una domanda è il posto dove l'utente scrive la sua prosa, e dev'essere completa quanto la prima; per una proposta è dove l'utente la smentisce citando l'id, e la maniglia basta — il corpo che la motiva è a poche righe sopra, letto una volta sola. Chi rilegge questo prompt e vede una domanda ripetuta due volte sta guardando il meccanismo, non un residuo.

Vale la stessa economia del recap senza freni di volume (§2b): un minuto di lettura in più costa meno di una decisione sbagliata congelata in `## Decisions` ed eseguita da `run-task`.

**Il layout a tempi vale sempre, a qualunque numero di domande** — con una sola, con nessuna e sole proposte, con un solo sottosistema, con tutte le voci generali. Nessun collasso a un blocco solo, nessuna soglia sotto cui il turno si accorcia. Il test di §1b riduce le domande, non il layout: quello che resta dopo il test sono per lo più proposte, e valgono per loro la stessa ragione sopra — collassare il layout quando le domande sono poche toglierebbe il contesto proprio alle voci che l'utente non ha chiesto e che deve poter rifiutare. Il costo del layout su un giro leggero è lo scroll, che è gratuito; un criterio di soglia è una regola in più da valutare a ogni giro, compreso quello da tredici domande dove il layout serve davvero.

**Separazione visiva** (§2c, §2d, §2e la usano tutte):

- ogni tempo apre con un **heading di livello 2** — le premesse, il blocco delle generali, ogni sottosistema, il blocco finale;
- dentro un sottosistema, le sue domande aprono con un **heading di livello 3** (`Domande`), le sue proposte con un altro (`Proposte`);
- ogni sottosistema chiude con un separatore `---`.

Sono i livelli **logici**. In chat si scrivono secondo la convenzione del terminale dell'output style, che vuole un `#` in più (`# ## Sottosistema`, `# ### Domande`), non con `##`/`###` letterali che il terminale renderebbe piatti.

Un solo ping TTS, prima di scrivere il turno:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

Topic = argomento concreto del turno, 3-7 parole. NO generici. **Uno solo, non uno per domanda**: è l'unico segnale che avvisa l'utente che la sessione ha smesso di lavorare, perché il badge di stato non annuncia più `ask` (§Note).

### 2a. La forma di una voce — `D{N}` e `P{N}`

Due forme, ognuna usata identica in tutte le sue occorrenze — sotto le generali, sotto il sottosistema, nel blocco finale.

La domanda:

```markdown
- **D3** — dove collocare il parser dei glifi
  <la domanda per esteso, aperta>
  *Strade viste (materiale, non un ventaglio da spuntare):* dentro `view.ts` · modulo nuovo `glyphs.ts` · inline nel renderer
```

La proposta:

```markdown
- **P2** — bump patch, non minor
  <la scelta, e la ragione: il dato del repo che la decide — la regola citata, il precedente, la cifra contata, le strade scartate e perché>
  *Smentibile con una parola.*
```

- **Le due occorrenze di una domanda portano lo stesso testo, parola per parola.** Non «la stessa forma» in senso lato: maniglia, corpo e riga di chiusura sono **identici** nelle due posizioni, e la seconda si ottiene ricopiando la prima, non riscrivendola. Il verso che cede non è mai il primo: riscrivere un testo già scritto lo comprime per gravità — la seconda stesura esce più corta, con le strade viste ridotte a due parole ciascuna — e chi risponde decide sulla versione povera invece che su quella mostrata dieci righe prima.
- **Una proposta non si ricopia: nella sua seconda occorrenza, nel blocco finale (§2e), compare come sola maniglia puntata al posto dove sta il corpo** — `- **P7** — exit code del gate → ③ Guardie deterministiche`. Il corpo di una proposta si legge una volta sola, sotto il sottosistema (§2d) o le generali (§2c), accanto al recap che la motiva: chi vuole smentirla risale lì, chi tace lascia la maniglia così com'è. Vale solo per il primo turno — dal secondo giro in poi (§2g) una proposta nuova non ha nessun sottosistema sopra cui stare, e torna col corpo intero.
- **Ogni voce porta una maniglia verbo+oggetto**, la prima citazione compresa. `D3` da solo è una coordinata opaca: non porta contenuto proprio, e un blocco di sette righe `D1`…`D7` nude costringe a rileggere per capire di cosa si parla — esattamente il costo che questo formato esiste per togliere.
- **Le strade candidate di una domanda stanno in riga separata sotto**, mai dentro il suo corpo, e sono dichiarate non vincolanti. Dentro la prosa si leggerebbero come il ventaglio delle possibilità; in riga a parte si leggono come materiale. Ometti la riga quando non hai candidati: nominarne di finti è peggio che tacere.
- **La ragione di una proposta sta nel corpo, ed è un dato del repo.** «Mi sembra più pulito» non è una ragione: lo sono la regola che lo dice (`plugin-dev.md` fissa il discriminante sul consumo), il precedente già in uso (`doc_config_file` è già lo scope di `reference/`), la cifra contata (62 span, non «qualche centinaio»). Una proposta senza il dato che la decide è una domanda travestita, e va rimessa al test (§1b).
- **Una proposta copre una candidata** (§1b); se ne copre due, le nomina entrambe nel corpo.
- **Due numerazioni indipendenti, entrambe nell'ordine di presentazione**: le generali prime, poi sottosistema per sottosistema nell'ordine in cui il giro li percorre; dentro un sottosistema prima le domande poi le proposte. Non l'ordine in cui l'analisi ha trovato le candidate — chi legge incontra `D1`, `D2`, `D3` in fila, e un salto negli id qui si legge come una voce persa.
- **La numerazione è quella che finirà nel file.** `D{N}` e `P{N}` ripartono da 1 a ogni esecuzione della skill (è la data del blocco a disambiguare i giri di preflight), ma dentro **questa** esecuzione non si rinumera mai: né fra un giro e il successivo, né alla scrittura di `## Decisions`. Rinumerare farebbe scadere ogni id che l'utente ha già citato rispondendo.
- **Una voce che tocca due sottosistemi compare sotto entrambi**, con lo stesso id e la stessa forma. Non «sotto il primo», non fra le generali: è la stessa ridondanza voluta che regge il layout, e sotto il secondo sottosistema arriva accanto all'altra metà del contesto che la decide.

### 2b. Il recap — grado `K1`, uno per sottosistema

Il recap è il quadro di ciò su cui le decisioni cadranno. Serve a rendere presente in memoria ciò su cui si decide: una decisione si può prendere solo su ciò che si ha in mente, e una proposta si può smentire solo su ciò che si ha in mente. **Sta in pezzi, uno per sottosistema**, e ogni pezzo va scritto appena sopra le voci che risolve (§2d) — non raccolto in un blocco unico a inizio turno, che costringerebbe a rimappare a memoria quale paragrafo serviva a quale voce.

- **Grado: `K1`.** Fisso, non un decremento della competenza dichiarata in §User assumed knowledge — quella sezione non marca quali voci siano settori progettuali e quali materie, quindi un decremento relativo non è calcolabile. La scala vive nell'output style (`output-styles/regole-output.md` §La scala di User assumed knowledge): qui si dichiara **a che grado scrivere e su cosa**, mai cosa `K1` significhi.
- **Perimetro: tutti i sottosistemi che le voci toccano**, quelli registrati allo step 1, coperti per intero. Non il progetto intero — un preflight che recappa tutto ha sostituito l'affaticamento da context-switch con l'affaticamento da volume. Se le voci ne toccano cinque, il giro ne copre cinque.
- **Nessun freno di volume.** Niente tetto in righe, niente riduzione al sottosistema dominante, niente criterio di sufficienza. Il recap è materiale da consultare, non un'introduzione alle voci: `K1` glossa i termini specialistici ed esplicita le implicazioni proprio per renderlo consultabile, e accorciarlo per brevità toglie la funzione per cui il grado è stato scelto.

### 2c. Primo tempo — le generali, domande e proposte

Le voci della classe **generale** (§1) aprono il turno, subito dopo le premesse (⓪) e prima che il giro sui sottosistemi cominci. Stanno sopra e non in coda perché una voce trasversale può vincolare le altre: leggerla dopo aver già deciso il resto arriva tardi.

Non avendo un sottosistema sotto cui stare, portano davanti **un recap contestualizzante minimo**, scritto sul **contesto più piccolo che le contiene comunque** — la task stessa, o l'architettura in cui la task rientra. Il criterio è lo stesso del recap per sottosistema, applicato un gradino più in alto: una voce generale non attraversa i sottosistemi, sta sopra di essi, quindi il suo contesto va cercato fuori dalla partizione. Presentarla senza niente davanti la renderebbe la meno decidibile di tutte, cioè l'inverso di quello che questo layout ottiene per tutte le altre.

Stesso grado `K1`, stesse forme di voce (§2a), prima le domande poi le proposte. Se non ci sono voci generali, il tempo ① non si scrive affatto: nessun heading vuoto, nessun recap orfano.

### 2d. Secondo tempo — il giro sui sottosistemi

Per ogni sottosistema toccato, nell'ordine che hai scelto allo step 1:

1. il **recap del sottosistema** (§2b);
2. le **domande di quel sottosistema**, nella forma di §2a, sotto un heading di livello 3 `Domande`;
3. le **proposte di quel sottosistema**, nella forma di §2a, sotto un heading di livello 3 `Proposte`;
4. il separatore `---`.

Poi il sottosistema successivo. Il giro copre **tutti** i sottosistemi registrati, anche quello con una voce sola. **Un sottosistema che porta solo proposte compare lo stesso, col suo recap**: è la forma normale dopo il test — su una task tecnica precisa può non restare nessuna domanda — e vale la ragione di §2 (il recap sotto gli occhi è ciò che rende una proposta smentibile). Se un tempo non ha domande, il heading `Domande` non si scrive; lo stesso per `Proposte`.

### 2e. Copertura per DLV, poi il blocco finale

Prima del blocco finale, una riga per ogni deliverable ancora aperto — `${CLAUDE_PLUGIN_ROOT}/scripts/task/task-deliverables.sh ${taskId}` numera gli stessi DLV che `run-task --scope` userà, ed è la lista da cui partire: i DLV già `[x]` restano fuori. Per ciascuno, le voci (`D{N}`, `P{N}`) che lo toccano, o la dichiarazione esplicita che non ne tocca nessuna:

```markdown
- DLV3 — potatura della prosa: `D2`, `P6`
- DLV4 — gate preflight: nessuna decisione aperta
```

**Un DLV non nominato affatto è un turno da rifare.** «Nessuna decisione aperta» è una dichiarazione passata davanti all'utente, smentibile come le altre; il silenzio su un DLV intero non lo è — è indistinguibile da una dimenticanza.

Poi, chiuso il giro, il **blocco finale**: prima tutte le domande nell'ordine degli id, poi tutte le proposte nell'ordine degli id — le generali e quelle di ogni sottosistema, ognuna una volta sola anche se ne tocca due.

**Le domande si ricopiano, non si riassumono.** Ogni domanda arriva qui **verbatim** come l'hai scritta sopra — stessa maniglia, stesso corpo, stessa riga di chiusura (§2a). Se la domanda in coda è più corta di quella sopra, il blocco è sbagliato anche quando si legge bene: hai prodotto un riepilogo del turno, e chi risponde decide sulla versione povera di una voce che sopra era completa. **È la seconda occorrenza, ed è quella su cui l'utente risponde**: chi risponde in fila deve poter leggere la domanda intera lì dove risponde, senza risalire al sottosistema che la conteneva.

**Le proposte compaiono come sola maniglia** (§2a). Alle proposte l'utente risponde solo se le smentisce: il silenzio su una `P{N}` vale accettazione, ed è così che finisce nel file (§3). Il silenzio è su una proposta già letta per intero pochi paragrafi sopra, non su una versione povera ricopiata in coda — è quella ripetizione, non l'assenza, che su una task con più proposte che domande produce il muro che nessuno rilegge.

### 2f. Il turno finisce qui

Scritto il blocco, **fermati**. Non rispondere alle domande da solo, non chiudere le proposte da solo, non scrivere `## Decisions`, non committare: lo step 3 parte solo dopo che l'utente ha risposto in un turno successivo.

Questo vincolo è un'istruzione, non un meccanismo. `AskUserQuestion` sospendeva l'esecuzione per costruzione — finché la risposta non arrivava la sessione non poteva proseguire. Un blocco di domande in markdown è testo come il resto del turno, e nulla impedisce di tirare dritto fino al commit con decisioni che nessun umano ha preso. Il fallimento è silenzioso: produce un `## Decisions` pieno e ben formato, non un errore. Con le proposte il rischio raddoppia: una `P{N}` è già una decisione scritta, e «non smentita» presuppone che chi poteva smentirla l'abbia **vista** — un turno che non si ferma la rende non smentita per assenza, non per silenzio.

### 2g. Il giro successivo — la risposta parziale è il regime normale

L'utente risponde alle domande che ha in mente adesso, smentisce le proposte che vuole smentire e lascia il resto. Non è un caso degradato: è come funziona. Ma le risposte date **non lasciano intatte** le voci rimaste — alcune domande le risolvono per implicazione, altre ne riducono il dominio senza chiuderlo, e una proposta smentita riapre una scelta.

Il giro successivo quindi **ricalcola** le voci aperte invece di riproporle immutate — vincolo opposto a quello del blocco finale (§2e), e non è una contraddizione: dentro **un** turno una domanda si ricopia verbatim, fra **due** turni si ricalcola su ciò che l'utente ha appena risposto.

- **domanda risolta per implicazione** → diventa una proposta nuova, nella forma di §2a, con la risposta derivata **e il perché** — es. *P7 — nome del flag → `--glyphs`, discende da D1*. Non chiuderla in silenzio: metterebbe nel file una decisione che nessuno ha visto, ed è un errore invisibile perché produce una voce ben formata come tutte le altre. È lo stesso meccanismo del primo giro (§1b): al primo giro la decisione discende dal repo, qui da una risposta.
- **domanda solo ristretta** → ripresentala con meno strade, dichiarando quali sono cadute e per quale risposta.
- **domanda intatta** → ripresentala com'è.
- **proposta smentita** → torna come `D{N}` nuova se la smentita apre una scelta dell'utente, o come `P{N}` nuova che recepisce la ragione dell'utente; mai riproposta uguale.
- **proposta non smentita** → chiusa, non si ripresenta.

Nessuna voce sparisce senza passare davanti all'utente, nessuna derivazione entra nel file senza essere stata mostrata. Gli id restano gli stessi: `D6` resta `D6`, e una voce nuova prende l'id successivo del suo contatore.

**Dal secondo giro in poi cade il layout a tempi: solo il blocco delle domande aperte e delle proposte nuove.** Niente giro sui sottosistemi, niente recap riscritto, niente doppia occorrenza. La ripetizione accanto al contesto paga la prima volta che quel contesto viene letto: al secondo giro il materiale è già stato letto una volta e le voci aperte sono un sottoinsieme, quindi il guadagno cade mentre il costo in volume resta. Se una voce ricalcolata ha bisogno di contesto nuovo — perché la risposta ne ha spostato il terreno — quel pezzo si scrive accanto a lei, non ricostruendo il recap del sottosistema. **Le proposte nuove tornano col corpo intero**, non a maniglia: la riduzione a maniglia (§2a, §2e) vale solo quando il corpo sta altrove nello stesso turno, e dal secondo giro non c'è nessun sottosistema sopra cui stare — a maniglia arriverebbero senza la loro ragione da nessuna parte.

Vale a ogni giro il resto dello step 2: le forme di voce di §2a, un ping TTS solo, e il turno che finisce dopo il blocco.

### 2h. Nessuna voce si chiude senza verdetto

**Ogni `D{N}` deve arrivare a un esito esplicito prima che la skill scriva e committi.** «Non decido ora» è un verdetto legittimo, ma va dichiarato dall'utente **con la sua motivazione** e scritto nel file come tale — non è il silenzio su una domanda evaporata. **Ogni `P{N}` ha un esito per costruzione**: non smentita, o smentita e sostituita dalla voce che ne è nata (§2g).

Ne discende che i giri si ripetono finché la copertura non è piena: la skill **non chiude e non committa** con una `D{N}` senza esito. Una domanda posta e poi evaporata lascia `run-task` davanti al nulla, senza sapere se lì è libero o se qualcuno si è dimenticato di decidere.

Per ogni voce, registra internamente: la domanda o la proposta, l'esito, il razionale se l'utente lo fornisce, e la derivazione se l'esito viene da un'implicazione non smentita.

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

**Proposte mostrate nel turno.** Decisioni prese dal preflight col dato del repo e passate davanti all'utente prima di questo commit.

- **P1** — ${la maniglia, la stessa mostrata in chat} — *non smentita*
  ${la scelta e la ragione, com'erano nel turno}
- **P2** — ${maniglia} — *smentita → D4* ${oppure → P5}
```

Quattro regole sulla scrittura del blocco:

- **Gli id sono quelli mostrati in chat**, uno per uno. Non si rinumera e non si ricompatta: l'utente ha risposto citandoli, e cambiarli qui li fa scadere. `D{N}` e `P{N}` ripartono da 1 solo alla prossima **esecuzione** della skill, che è un blocco datato nuovo.
- **Ogni `D{N}` del giro compare, con il suo esito.** Non decisa dall'utente:

  ```markdown
  - **D4** — ${maniglia}
    - **Non decisa**: ${motivazione dell'utente, testuale}
  ```

  Risolta per implicazione da una risposta (§2g): `- **Scelta**: ${risposta} — *risolta da P7, non smentita*`, e `P7` sta fra le proposte con la sua ragione. Sono le sole forme ammesse oltre a `**Scelta**`, e rendono leggibile a `run-task` la differenza fra «qui sei libero» e «qualcuno si è dimenticato». Se una domanda è ancora senza esito, **non sei allo step 3**: torna al giro (§2g).
- **Ogni `P{N}` mostrata compare, con il suo esito**: *non smentita*, o *smentita →* la voce che ne è nata. Una proposta smentita non sparisce dal file: la sua riga dice dove è finita la scelta, e la voce nuova porta la ragione dell'utente.
- **Nel blocco entrano solo id che sono comparsi in chat prima di scriverlo.** Una derivazione che nasce **mentre scrivi** — «scrivendo `D4` vedo che il nome del flag discende da `D1`» — non è una riga in più, è un giro in più: torna a §2g, mostrala come `P{N}`, e scrivi il blocco solo dopo. «Non smentita» presuppone che chi poteva smentire abbia **visto**; una derivazione dichiarata dopo il push con «smentiscila adesso» è una decisione presa a cose fatte, comunicata con la forma di una proposta. Il §2h vieta di chiudere una domanda senza esito; questa regola vieta di aprire una decisione senza turno — ed è quella che morde sulle derivazioni, perché nascono quando lo step delle domande è già dichiarato chiuso.

**Verifica prima del commit, meccanica e non opzionale.** Scritto il blocco, estrai gli id dal blocco datato di questa esecuzione — `grep -oE '\*\*[DP][0-9]+\*\*' "${task_file}"` sulle righe sotto `### Preflight ${data}` — e confrontali uno per uno con gli id dei tuoi turni in questa conversazione. Un id nel file che nessun turno ha mostrato: **non committare**, togli la riga, torna a §2g. La verifica è a carico tuo perché nessuno script legge i turni; il fallimento che previene è silenzioso, produce un blocco ben formato.

**Caso nessuna ambiguità (step 1 vuoto e nessuna proposta)**: scrivi comunque il blocco header datato, senza decisioni:

```markdown
### Preflight ${YYYY-MM-DD HH:mm}

- _Nessuna ambiguità rilevata._ Task pronta per `run-task` senza decisioni da congelare.
```

L'assenza di bullet `**D{N}**` sotto il blocco è il segnale che `start-task` legge come "preflight verificata, nessuna decisione" (distinto da "preflight mai eseguita" = blocco assente, e da «premessa decaduta» = heading con la dicitura, §0b). Un giro con zero domande e una o più proposte **non è** questo caso: le proposte sono decisioni, passano dal turno (§2) e si scrivono nel blocco come sopra.

## 3b. Le decisioni che producono una nozione documentale

Una `D{N}` che rende vero un fatto durevole — un comportamento nuovo, un vincolo scoperto, un trade-off risolto — produce una nozione. Appendila alla sede che `## Doc Impact` dichiara — la sezione stessa, o il file inbox che la sua riga `- → inbox <basename> · storia: <sha>` nomina (formato e operazioni: `${CLAUDE_PLUGIN_ROOT}/docs/inbox-format.md`; id `max(nN)+1`, mai rinumerati; un inbox `drainable` è congelato e non si tocca):

```markdown
- **<la nozione: cosa diventa vero, non cosa si è deciso>**
  Ancora: <trigger concreto — comando, keyword, pattern>
```

Regole di scrittura, tutte già note e nessuna nuova:

- **La sezione `## Doc Impact` sta fra `## Testing Notes` e `## Prod Validation`.** Se manca, creala lì. Se contiene solo il placeholder `*Nessuna nozione documentale emersa al create-task.*`, sostituiscilo con le tue voci.
- **La voce resta viva.** Niente marker: finché la task è attiva la voce si riscrive e si elimina, e sei autorizzato a **riesaminare** quelle esistenti — nella sede corrente — quando una decisione di questo giro le smentisce. Il trasloco è del `checkpoint-task` e gira una volta sola.
- **Non decidere il target doc.** Dove la nozione atterri lo decide `drain-notions`, in differita.

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
# N≥1 → "...- ${N} decisioni congelate" | N=0 (nessuna ambiguità) → "...- nessuna ambiguità" | premessa decaduta → "...- premessa decaduta" (§0b)
lw_git_add_n_commit "task(${taskId}): preflight - ${N} decisioni congelate" "${task_file}" "${tasks_md}"
lw_git_push
```

- Committa **solo** quei due file: `lw_git_add_n_commit` stagia e committa con la stessa pathspec, quindi ciò che altre sessioni hanno lasciato in stage nello stesso worktree resta fuori. Non usare `git commit -m` nudo — senza pathspec committa l'intero indice. `tasks.md` entra perché lo step 3c può averne cambiato la riga; se la promozione non è scattata il file è pulito e non produce diff.
- Messaggio: `task(${taskId}): preflight - ${N} decisioni congelate` se `${N}` ≥ 1, altrimenti `task(${taskId}): preflight - nessuna ambiguità`.
- `${N}` = `D{N}` scritte da **questa** esecuzione, le non-decise comprese, **più** le `P{N}` non smentite: sono decisioni congelate quanto le altre, e lo sono diventate passando dal turno. 0 nel caso nessuna ambiguità.
- Push subito dopo il commit, coerente con `create-task` / `checkpoint-task` (tutte pushano). Senza remote `lw_git_push` avvisa su stderr ed esce 0: la skill prosegue, il commit resta locale.

Dopo commit+push, mostra all'utente:

```
✅ Preflight completato: ${N} decisioni congelate in ${task_file} — ${D} domande, ${P} proposte non smentite
   📌 Committate e pushate: task(${taskId}): preflight - ${N} decisioni congelate
   📝 ${M} nozioni in Doc Impact  ← solo se ${M} > 0
   Pronta per /loom-works:run-task
```

## Note

- **Non esegue codice**: preflight congela decisioni e cattura le nozioni che ne discendono (step 3b). Implementazione resta a `run-task`.
- **Due sezioni, due mestieri.** `## Decisions` porta *cosa si è deciso* ed è cronaca datata: nessuno la legge a valle e resta sempre nel task file. `## Doc Impact` porta *cosa è diventato vero*, e dal primo trasloco in poi è solo il puntatore all'inbox della task. Scrivere la decisione in `## Doc Impact` è il modo tipico di sbagliare: quella riga arriverebbe al drain come intenzione e verrebbe scartata.
- **Idempotenza parziale**: ri-eseguire preflight su una task aggiunge un nuovo blocco datato. Lo storico delle decisioni resta intatto. Ogni giro produce il suo commit dedicato.
- **Task piccole / nessuna ambiguità**: se l'analisi (step 1) non trova ambiguità reali, salta l'intero step 2 — **recap compreso** — ma **scrivi comunque il marker** in `## Decisions` (step 3, caso nessuna ambiguità) e committalo (step 4, messaggio `nessuna ambiguità`). Serve a `start-task` per distinguere "preflight già passata, niente da decidere" da "preflight mai eseguita". Mostra: `🛫 Nessuna ambiguità rilevata — marker registrato. Task pronta per run-task.`
  Il recap esiste per rendere prendibile una decisione: senza domande non ha bersaglio e diventerebbe volume gratuito sul ramo di maggioranza. Chi vuole il quadro di una task senza decidere niente ha già `recap-status-task`.
- **Lo stato che la sessione annuncia durante l'attesa è `done`, non `ask`** — conseguenza nota del porre le domande in chat, non un difetto da correggere qui. I due hook che alimentano il badge di compass sono macchina-personali (`~/.claude/settings.json`): `Notification` esegue `compass ask`, `Stop` esegue `compass done`. `AskUserQuestion` scatenava il primo perché sospendeva l'esecuzione; un blocco di domande scritto chiude il turno e scatena il secondo. Nel rollup `error > ask > done > running > idle` un preflight che aspetta pesa quindi quanto una sessione finita, e perde contro qualunque altra tab che stia chiedendo un permesso. Non è correggibile dentro il plugin — quegli hook stanno fuori dal perimetro di famiglia — ed è la ragione per cui il ping TTS dello step 2 resta obbligatorio.
- **Commit + push automatici**: lo step 4 committa **solo** il task file (commit dedicato) e pusha, come le altre skill task-level. Decisioni tracciate separatamente dall'implementazione.
