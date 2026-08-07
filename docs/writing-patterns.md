# Pattern di scrittura

Contratto **globale**: vale in chat, nei messaggi di commit, nei file doc, nei prompt che scrivi a un subagent. Governa *come si pensa il testo*, quindi resta vero a prescindere da chi lo renderizza. I workaround di rendering del terminale non stanno qui — stanno in `chat-output.md`, e valgono solo lì.

## North Star — capire > token

Priorità non negoziabile: il lettore deve *capire*. Il risparmio è un effetto collaterale del buon formato, mai l'obiettivo. Se le due cose confliggono, vince la comprensione.

Tre cose non si tagliano mai:

1. **Glossa il gergo** — 2-4 parole inline al primo uso, per ogni termine non ovvio: sigle, codici d'errore, nomi di pattern, jargon di dominio. *backoff (attesa che raddoppia a ogni tentativo)* · *429 (codice HTTP «troppe richieste»)*.
2. **Tieni il perché** — mai tagliare il nesso causale. Non «usa `<`, fix» ma «usa `<` invece di `<=`, **quindi** rifiuta il token nell'istante esatto di scadenza».
3. **Tieni i passaggi intermedi** — se da A si arriva a C passando per B, dì B. Il confine di quando B è omissibile sta sotto, ed è ciò che rende questa regola applicabile invece che assoluta.

## Cosa non entra

**Niente cronaca del percorso.** Perché una scelta fu presa, e che poi si è risolta da sé, racconta la storia del sistema invece del sistema. Test: se tolgo la frase, cambia cosa fa il lettore? No → via. Ne discende il divieto di narrazione-di-processo: mostra l'esito, non i passi che hai fatto per arrivarci.

**Il testo muore col suo referente.** Una frase che descrive un simbolo rimosso, o il workaround di un campo che non esiste più, non si aggiorna: si cancella.

**Un'istanza sola, quella che rompe.** Fra tre esempi tieni quello che dimostra il caso pericoloso. Gli altri confermano, e confermare non è informare.

**Nessun livello ri-afferma ciò che un livello già visibile afferma.** Vale fra TLDR e corpo, titolo e apertura, prima riga di un commit e corpo, label di tabella e celle. Un concetto, un posto — e nessun recap di chiusura, che è il modo tipico in cui la regola si viola per intero.

## Come si riscrive ciò che entra

**Afferma l'esito, non la derivazione.** Il nocciolo-first è **frattale**: vale per il documento, la sezione, il paragrafo e la singola proposizione. «è l'unico consumer del baseline della finestra `<base>..HEAD`: lo chiede a `lw_task_baseline_sha`» → «chiede la base di `<base>..HEAD` a `lw_task_baseline_sha`». La qualifica («unico consumer») si dichiara una volta, dove pesa, e non si ripete a ogni frase.

**Il confine della compressione causale.** Comprimi il nesso solo quando il passaggio intermedio è deducibile dalla premessa appena data: «`-S` conta le occorrenze, quindi regge due header identici». Se il passaggio richiede un fatto esterno — una glossa, una misura, una convenzione — resta. Senza questo confine «tieni i passaggi intermedi» è inapplicabile: o si conserva tutto, o si taglia a intuito.

**L'enfasi la porta la struttura, mai una frase.** «Non è un dettaglio, è vincolante» non aggiunge peso: lo danno già la posizione e il grassetto. Una frase che dichiara la propria importanza è cornice, come pleasantries, hedging e filler.

**La subordinazione solo dove esprime una gerarchia vera.** Fatti sullo stesso piano logico non si annidano l'uno nell'altro: il connettivo che li subordina è rumore. Dove c'è markup, il separatore `·` è l'implementazione della regola, non la regola.

**Un'idea per blocco.** Fondere due concetti in una frase è un guasto diverso dal ripeterne uno in due posti — co-locazione, non duplicazione — e chiede il fix opposto: separare, non cancellare. La separazione è ciò che rende visibile che erano due cose.

## Dove c'è markup

- **Casistica in lista isomorfa.** Un paragrafo che è il caso N di una casistica già aperta appartiene alla lista, nella stessa forma degli altri: `condizione → esito → nota`. Il caso trattato a parte è il tell di una casistica non riconosciuta.
- **Nomina il claim in grassetto d'apertura.** `**Perché derivato.**` fa due lavori: elimina la frase-cornice che introduceva il tema e dà un punto d'aggancio a chi scorre. Questo file ne è la fonte unica — il contratto doc lo punta, non lo ricopia.

## Perimetro

- **Vale**: chat, commit, PR, file doc, prompt a un subagent.
- **Non vale**: il contenuto del codice, che si scrive normale.
- **Si sospende**: security, conferma di operazione irreversibile, sequenza multi-step dove l'ordine conta. Lì si scrive disteso ed esplicito; si riprende dopo la parte critica.
