---
name: preflight-task
description: Interactive Q&A to freeze design decisions on a task before execution.
allowed-tools: Bash(*), Read, Edit, Glob, AskUserQuestion
model: opus
---

Fase di preparazione prima di `run-task`. Identifica ambiguità nella task, le pone all'utente **in chat, in un turno solo, ognuna sotto il recap del sottosistema che tocca e di nuovo tutte insieme in un blocco finale**, scrive le risposte come decisioni congelate nel task file e **committa immediatamente** il task file. Le decisioni restano così tracciate separatamente dall'implementazione.

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

Una task poggia su affermazioni di meccanismo: «il canale che consegna l'envelope codifica in entità HTML», «un file da 12.000 caratteri porta qualche centinaio di span», «il body della skill entra nel transcript come record utente». Lo step 1 non le vede per costruzione — cerca ciò che **non è deciso**, e una premessa si presenta come fatto stabilito, quindi passa. Il layout dello step 2 poi la peggiora: entra nel recap, ne esce glossata ed esplicitata, e chi risponde la legge scritta meglio di com'era. Su T143 sette domande su sette taravano il rimedio a un canale che nessuno aveva misurato; la premessa era falsa e la task è morta superseduta. Ne discende che le premesse si verificano **qui, prima**, non dentro l'analisi.

1. **Elenca** le affermazioni di meccanismo su cui poggia **più di un DLV, o un AC**: Description, Dependencies, Implementation Notes. Un'affermazione che regge un solo DLV si verifica quando quel DLV si esegue, non qui.
2. **Marca** ognuna: `misurata` — il task file o il materiale porta la misura (una cifra contata, l'output di un comando, un transcript nominato) — oppure `asserita` — detta come fatto, senza una misura accanto.
3. **Le asserite le misuri tu, adesso, quando la misura è una lettura**: `Read`, `Grep`, `git log`, un conteggio, un transcript aperto. È analisi, non implementazione — questa skill vieta di scrivere codice, non di leggere. Quando la misura richiede **eseguire codice o toccare un sistema vivo** (lanciare un job, chiamare un servizio, costruire un banco) non la fai: diventa una proposta `P{N}` di primo deliverable — «DLV0: misurare X prima di tutto» — che l'utente vede nel turno accanto alle altre (§2).
4. **Esito per premessa**, uno dei tre: `✅ misurata` con la cifra o il comando · `⏸ da misurare` con la `P{N}` che la porta a DLV · `❌ decaduta`.

Il blocco delle premesse **apre il turno** dello step 2, prima delle generali, come lista compatta — una riga per premessa, esito e prova accanto. Se la task non porta affermazioni di meccanismo che reggano più di un DLV, la lista lo dice in una riga e non si scrive altro.

### Premessa decaduta — decade tutto

Se la misura smentisce una premessa su cui poggia più di un DLV, **il preflight non pone domande**. Le domande costruite su un terreno falso producono decisioni ben formate e inutili, e ognuna verrebbe riscritta tre volte con sempre più dettaglio dal layout. Invece:

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

La ricostruzione delle premesse è dell'utente, in questa conversazione o in un'altra: per questo lo stato sta nel file e non solo in chat. Un preflight rilanciato dopo legge il blocco, riparte da qui e non dallo step 1. Il heading porta `— premessa decaduta` perché `start-task` e `run-task` distinguono per costruzione questo blocco dal marker «nessuna ambiguità», che è anche lui un blocco datato senza `D{N}`: senza la dicitura, una task fermata davanti a una premessa falsa risulterebbe pronta per `run-task`.

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

- **i sottosistemi che tocca**, oppure la classe **generale** — il perimetro del recap si ricava da qui, non dal progetto intero, e da qui si ricava anche dove la domanda comparirà nel turno (§2c, §2d);
- **le strade che hai già visto** analizzando la task — entrano nella voce come materiale non vincolante (§2a), non come opzioni.

Sul primo dato, tre precisazioni:

- **Un sottosistema è un'area su cui le domande cadono**, alla granularità che serve a te: non un elenco derivato dai file che la task tocca, né un livello architetturale fissato in anticipo. Ordinali come preferisci — nessun criterio è imposto.
- **Una domanda può toccarne due.** Registrali entrambi: comparirà sotto entrambi (§2d), e la ripetizione è la stessa che regge tutto questo layout.
- **`generale` è una classe residua e va dichiarata**, non lasciata implicita. Ci cade la domanda trasversale, o quella su una scelta che precede la partizione stessa. Senza questa classe una domanda simile non ha nessun sottosistema sotto cui stare e sparisce dal turno in silenzio — un turno ben formato con una domanda in meno, che è un fallimento invisibile.

  Vale anche il contrario: la comparsa di domande generali è un **sintomo**, non un caso ordinario da gestire. Se l'architettura sopra la task fosse completa, ogni domanda cadrebbe dentro un perimetro suo.

## 1b. Il test di appartenenza — da candidata a domanda, proposta o misura

Lo step 1 produce **candidate**, non domande. Un elenco di classi di ambiguità è una quota di produzione: chi lo applica formula una voce per ogni classe che riesce a riempire, e il numero di voci finisce per misurare la ricchezza dell'analisi, non il numero di decisioni che sono davvero dell'utente. Sul corpus di 12 giri col contratto precedente, 52 domande su 134 erano dell'utente; su T140 zero su nove, e una frase nell'invocazione le ha fatte sparire tutte senza che il modello leggesse niente di nuovo — le sapeva già mentre le scriveva. Il test qui sotto è quella frase, scritta nel contratto.

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

Vale anche per la **misura già fatta**: se un paragrafo del tuo stesso turno — il recap, una cifra che hai appena riportato — risolve la candidata, la candidata è chiusa. Su T144 `D11` la misura stava quattro paragrafi sopra la domanda (4 ancore orfane su 1.296, 3 sul file esente) e la domanda è stata posta comunque; su T139 `D12` il recap arrivava alla risposta e la domanda seguiva. Otto delle 134 domande del corpus erano di questa forma, e in tutte la cifra era nel repo o già nel turno.

### Casi limite

- **Il caso misto si spacca, ma non in due domande.** Una candidata con una metà di preferenza e una metà tecnica pone la sola metà dell'utente; la metà del modello **non diventa una `D{N}` a parte** — va sotto la domanda come conseguenza già derivata per ciascuna risposta possibile («se A, il TLDR si riproduce a ogni checkpoint; se B, solo al rilascio»), o come proposta. Su T138 la scelta fra trasloco a ogni checkpoint e trasloco al rilascio (`D1`, dell'utente) ha generato `D6` e `D7` come domande separate, ed erano le sue conseguenze tecniche: due domande in più per una decisione sola.
- **L'incertezza del modello non è un dato assente dal repo.** Una candidata su cui sei incerto fra due strade resta del modello: l'incertezza è lettura non finita, non una preferenza dell'utente. Si legge ancora finché una strada vince, e si propone con la ragione; se dopo aver letto le due strade sono davvero pari, la proposta lo dice e sceglie — l'utente smentisce con una parola.
- **Il coordinamento con un'altra task aperta è sempre dell'utente**, anche quando il modello vede benissimo qual è l'ordine migliore: la sequenza è roadmap, e la roadmap non sta nel repo. La proposta di ordine può accompagnare la domanda, non sostituirla.
- **Una premessa non è una candidata.** Un'affermazione di meccanismo su cui la task poggia si verifica **prima** dello step 1 (§0b): arrivata qui, una premessa falsa si presenta come fatto stabilito e passa il test senza essere guardata. Su T143 sette domande su sette taravano il rimedio a un canale che nessuno aveva misurato.

### Una uscita per candidata, e il conto si fa per voce

Ogni candidata esce dal test una volta: `D{N}`, `P{N}`, o chiusa da una misura. **Una proposta copre una candidata**; se ne copre due, le nomina entrambe. Niente «il resto lo decido io»: su T56 il modello ha dichiarato di aver deciso da sé 7 domande su 9, e le quattro proposte che ha scritto ne coprivano 5 — le altre quattro erano tornate fuse a coppie nelle due domande «vere». La copertura si verifica voce per voce, non per differenza.

Il numero di domande che ne esce **non è un obiettivo in nessuna direzione**: una domanda dell'utente in meno è una decisione presa al posto suo, una del modello in più è il costo che il test esiste per togliere. Il test non accorcia il turno — sposta le decisioni dove il dato sta.

## 2. Il turno delle domande — recap e domande intrecciati, blocco unico in coda

Le domande si pongono **scrivendo in chat**, non con `AskUserQuestion`, e arrivano tutte in un turno solo. L'utente risponde in prosa nel turno successivo.

La ragione per cui arrivano insieme è che una domanda posta da sola precede il contesto che la rende decidibile: chi risponde a `D1` non ha ancora visto `D5`, e le due possono essere accoppiate — dove va un parser vincola come si chiama il flag che lo attiva.

Il turno ha tre tempi, in quest'ordine:

```
intro / header
① le domande generali, precedute dal loro recap contestualizzante   (§2c)
② per ogni sottosistema toccato: il suo recap, poi le sue domande   (§2d)
③ il blocco finale: tutte le domande insieme, generali comprese     (§2e)
```

**Ogni domanda compare quindi due volte, ed è voluto: non è ridondanza da potare.** Le due occorrenze servono a due momenti diversi della lettura. Sotto il sottosistema la domanda arriva mentre il materiale che la risolve è ancora sotto gli occhi — chi decide non deve rimappare a memoria quale paragrafo di recap serviva a quale `D{N}`, e la maniglia verbo+oggetto identifica la domanda ma non riporta indietro il contesto. In coda il blocco unico resta il posto dove si risponde in fila senza risalire il documento, e l'unico da cui si copiano gli id. Chi rilegge questo prompt e vede la stessa domanda due volte sta guardando il meccanismo, non un residuo.

Vale la stessa economia del recap senza freni di volume (§2b): un minuto di lettura in più costa meno di una decisione sbagliata congelata in `## Decisions` ed eseguita da `run-task`.

**Il layout a tre tempi vale sempre**, anche nei casi degeneri — un solo sottosistema, o tutte le domande generali. Nessun collasso a un blocco solo: una regola sola, applicata uguale, costa meno di un criterio di collasso da valutare a ogni giro.

**Separazione visiva** (§2c, §2d, §2e la usano tutte):

- ogni tempo apre con un **heading di livello 2** — il blocco delle generali, ogni sottosistema, il blocco finale;
- dentro un sottosistema, le sue domande aprono con un **heading di livello 3**;
- ogni sottosistema chiude con un separatore `---`.

Sono i livelli **logici**. In chat si scrivono secondo la convenzione del terminale dell'output style, che vuole un `#` in più (`# ## Sottosistema`, `# ### Domande`), non con `##`/`###` letterali che il terminale renderebbe piatti.

Un solo ping TTS, prima di scrivere il turno:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```

Topic = argomento concreto del turno, 3-7 parole. NO generici. **Uno solo, non uno per domanda**: è l'unico segnale che avvisa l'utente che la sessione ha smesso di lavorare, perché il badge di stato non annuncia più `ask` (§Note).

### 2a. La forma di una voce `D{N}`

Una sola forma, usata identica in tutte e tre le occorrenze — sotto le generali, sotto il sottosistema, nel blocco finale:

```markdown
- **D3** — dove collocare il parser dei glifi
  <la domanda per esteso, aperta>
  *Strade viste (materiale, non un ventaglio da spuntare):* dentro `view.ts` · modulo nuovo `glyphs.ts` · inline nel renderer
```

- **Le due occorrenze portano lo stesso testo, parola per parola.** Non «la stessa forma» in senso lato: maniglia, corpo e riga delle strade viste sono **identici** nelle due posizioni, e la seconda si ottiene ricopiando la prima, non riscrivendola. La regola è **simmetrica** e va letta nei due versi: nessuna delle due si accorcia in una forma breve, e nessuna delle due si arricchisce di qualcosa che l'altra non ha.

  Il verso che cede è il secondo, non il primo. Riscrivere un testo già scritto lo comprime per gravità — la seconda stesura di una domanda esce più corta, con le strade viste ridotte a due parole ciascuna — e il risultato è un blocco finale che sembra un riepilogo del turno invece del posto dove si risponde. Chi risponde legge la versione povera e decide su meno materiale di quello che gli era stato mostrato dieci righe prima.
- **Ogni `D{N}` porta una maniglia verbo+oggetto**, la prima citazione compresa. `D3` da solo è una coordinata opaca: non porta contenuto proprio, e un blocco di sette righe `D1`…`D7` nude costringe a rileggere per capire di cosa si parla — esattamente il costo che questo formato esiste per togliere.
- **Le strade candidate stanno in riga separata sotto la domanda**, mai dentro il suo corpo, e sono dichiarate non vincolanti. Dentro la prosa si leggerebbero come il ventaglio delle possibilità; in riga a parte si leggono come materiale. Ometti la riga quando non hai candidati: nominarne di finti è peggio che tacere.
- **La numerazione segue l'ordine di presentazione**: le generali prime, poi sottosistema per sottosistema nell'ordine in cui il giro li percorre. Non l'ordine in cui l'analisi ha trovato le ambiguità — chi legge incontra `D1`, `D2`, `D3` in fila, e un salto negli id qui si legge come una domanda persa.
- **La numerazione è quella che finirà nel file.** `D{N}` riparte da `D1` a ogni esecuzione della skill (è la data del blocco a disambiguare i giri di preflight), ma dentro **questa** esecuzione non si rinumera mai: né fra un giro di domande e il successivo, né alla scrittura di `## Decisions`. Rinumerare farebbe scadere ogni `D{N}` che l'utente ha già citato rispondendo.
- **Una domanda che tocca due sottosistemi compare sotto entrambi**, con lo stesso id e la stessa forma. Non «sotto il primo», non fra le generali: è la stessa ridondanza voluta che regge il layout, e sotto il secondo sottosistema arriva accanto all'altra metà del contesto che la decide.

### 2b. Il recap — grado `K1`, uno per sottosistema

Il recap è il quadro di ciò su cui le decisioni cadranno. Serve a rendere presente in memoria ciò su cui si decide: una decisione si può prendere solo su ciò che si ha in mente. **Sta in pezzi, uno per sottosistema**, e ogni pezzo va scritto appena sopra le domande che risolve (§2d) — non raccolto in un blocco unico a inizio turno, che costringerebbe a rimappare a memoria quale paragrafo serviva a quale domanda.

- **Grado: `K1`.** Fisso, non un decremento della competenza dichiarata in §User assumed knowledge — quella sezione non marca quali voci siano settori progettuali e quali materie, quindi un decremento relativo non è calcolabile. La scala vive nell'output style (`output-styles/regole-output.md` §La scala di User assumed knowledge): qui si dichiara **a che grado scrivere e su cosa**, mai cosa `K1` significhi.
- **Perimetro: tutti i sottosistemi che le domande toccano**, quelli registrati allo step 1, coperti per intero. Non il progetto intero — un preflight che recappa tutto ha sostituito l'affaticamento da context-switch con l'affaticamento da volume. Se le domande ne toccano cinque, il giro ne copre cinque.
- **Nessun freno di volume.** Niente tetto in righe, niente riduzione al sottosistema dominante, niente criterio di sufficienza. Il recap è materiale da consultare, non un'introduzione alle domande: `K1` glossa i termini specialistici ed esplicita le implicazioni proprio per renderlo consultabile, e accorciarlo per brevità toglie la funzione per cui il grado è stato scelto.

### 2c. Primo tempo — le domande generali

Le domande della classe **generale** (§1) aprono il turno, prima che il giro sui sottosistemi cominci. Stanno sopra e non in coda perché una domanda trasversale può vincolare le altre: leggerla dopo aver già deciso il resto arriva tardi.

Non avendo un sottosistema sotto cui stare, portano davanti **un recap contestualizzante minimo**, scritto sul **contesto più piccolo che le contiene comunque** — la task stessa, o l'architettura in cui la task rientra. Il criterio è lo stesso del recap per sottosistema, applicato un gradino più in alto: una domanda generale non attraversa i sottosistemi, sta sopra di essi, quindi il suo contesto va cercato fuori dalla partizione. Presentarla senza niente davanti la renderebbe la meno decidibile di tutte, cioè l'inverso di quello che questo layout ottiene per tutte le altre.

Stesso grado `K1`, stessa forma di voce (§2a). Se non ci sono domande generali, il tempo ① non si scrive affatto: nessun heading vuoto, nessun recap orfano.

### 2d. Secondo tempo — il giro sui sottosistemi

Per ogni sottosistema toccato, nell'ordine che hai scelto allo step 1:

1. il **recap del sottosistema** (§2b);
2. le **domande di quel sottosistema**, nella forma di §2a, sotto un heading di livello 3;
3. il separatore `---`.

Poi il sottosistema successivo. Il giro copre **tutti** i sottosistemi registrati, anche quello con una domanda sola.

### 2e. Terzo tempo — il blocco finale, tutte le domande insieme

Chiuso il giro, **ricopia** tutte le domande in un blocco unico: le generali e quelle di ogni sottosistema, nell'ordine degli id, ognuna una volta sola anche se ne tocca due.

**Ricopia, non riassumere e non riscrivere.** Ogni voce arriva qui **verbatim** come l'hai scritta sopra — stessa maniglia, stesso corpo, stessa riga di strade viste (§2a). Se la voce in coda è più corta di quella sopra, il blocco è sbagliato anche quando si legge bene: hai prodotto un riepilogo del turno, e chi risponde decide sulla versione povera di una domanda che sopra era completa.

**È la seconda occorrenza, ed è quella su cui l'utente risponde.** Non è un indice di rimandi: chi risponde in fila deve poter leggere la domanda intera lì dove risponde, senza risalire al sottosistema che la conteneva. Ometterlo, o ridurlo a un elenco di id, rimette esattamente il costo che il resto del layout ha appena tolto.

### 2f. Il turno finisce qui

Scritto il blocco, **fermati**. Non rispondere alle domande da solo, non scrivere `## Decisions`, non committare: lo step 3 parte solo dopo che l'utente ha risposto in un turno successivo.

Questo vincolo è un'istruzione, non un meccanismo. `AskUserQuestion` sospendeva l'esecuzione per costruzione — finché la risposta non arrivava la sessione non poteva proseguire. Un blocco di domande in markdown è testo come il resto del turno, e nulla impedisce di tirare dritto fino al commit con decisioni che nessun umano ha preso. Il fallimento è silenzioso: produce un `## Decisions` pieno e ben formato, non un errore.

### 2g. Il giro successivo — la risposta parziale è il regime normale

L'utente risponde alle domande che ha in mente adesso e lascia le altre. Non è un caso degradato: è come funziona. Ma le risposte date **non lasciano intatte** le domande rimaste — alcune le risolvono per implicazione, altre ne riducono il dominio senza chiuderlo.

Il giro successivo quindi **ricalcola** le domande aperte invece di riproporle immutate — vincolo opposto a quello del blocco finale (§2e), e non è una contraddizione: dentro **un** turno la stessa domanda si ricopia verbatim, fra **due** turni si ricalcola su ciò che l'utente ha appena risposto.

- **risolta per implicazione** → ripresentala con la risposta derivata **e il perché**, come proposta smentibile con una parola — es. *D6 — nome del flag → `--glyphs`, discende da D1*. Non chiuderla in silenzio: metterebbe nel file una decisione che nessuno ha preso, ed è un errore invisibile perché produce una voce ben formata come tutte le altre.
- **solo ristretta** → ripresentala con meno strade, dichiarando quali sono cadute e per quale risposta.
- **intatta** → ripresentala com'è.

Nessuna domanda sparisce senza passare davanti all'utente, nessuna derivazione entra nel file senza essere stata mostrata. Gli id restano gli stessi: `D6` resta `D6`.

**Dal secondo giro in poi cade il layout a tre tempi: solo il blocco delle domande aperte.** Niente giro sui sottosistemi, niente recap riscritto, niente doppia occorrenza. La ripetizione accanto al contesto paga la prima volta che quel contesto viene letto: al secondo giro il materiale è già stato letto una volta e le domande aperte sono un sottoinsieme, quindi il guadagno cade mentre il costo in volume resta. Se una domanda ricalcolata ha bisogno di contesto nuovo — perché la risposta ne ha spostato il terreno — quel pezzo si scrive accanto a lei, non ricostruendo il recap del sottosistema.

Vale a ogni giro il resto dello step 2: la forma di voce di §2a, un ping TTS solo, e il turno che finisce dopo il blocco.

### 2h. Nessuna domanda si chiude senza verdetto

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

  È l'unica forma ammessa oltre a `**Scelta**`, e rende leggibile a `run-task` la differenza fra «qui sei libero» e «qualcuno si è dimenticato». Se una domanda è ancora senza esito, **non sei allo step 3**: torna al giro di domande (§2g).
- **Una scelta derivata da un collasso non smentito porta la derivazione accanto**: `- **Scelta**: ${risposta} — *derivata da D1, non smentita*`.

**Caso nessuna ambiguità (step 1 vuoto)**: scrivi comunque il blocco header datato, senza decisioni:

```markdown
### Preflight ${YYYY-MM-DD HH:mm}

- _Nessuna ambiguità rilevata._ Task pronta per `run-task` senza decisioni da congelare.
```

L'assenza di bullet `**D{N}**` sotto il blocco è il segnale che `start-task` legge come "preflight verificata, nessuna decisione" (distinto da "preflight mai eseguita" = blocco assente).

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
