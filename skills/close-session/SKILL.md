---
name: close-session
description: Chiede al deck acceso sul progetto di chiudere una conversazione viva che una richiesta spawn-task ha aperto, o l'orchestrator che ha passato le consegne al successore — il processo claude termina, la tab si chiude, il transcript resta e la conversazione si riprende dal deck. Una conversazione per invocazione, per sessionId, nessuna domanda e nessuna conferma. Usa quando una conversazione che orchestra ha finito con una conversazione aperta da lei, per esempio l'orchestrator di un'epica a ciclo chiuso: «chiudi la conversazione 0a1b2c3d».
argument-hint: "<sessionId>"
---

Argomenti:
~~~human
$ARGUMENTS
~~~

## Cosa fa, e cosa non fa

La chiusura resta del **deck**: la skill è un client, gemella di `spawn-task`. Il deck acceso sul progetto ascolta lo stesso endpoint locale dello spawn — named pipe su Windows, socket Unix su Linux, un indirizzo per progetto — e chiude la conversazione terminando il suo processo `claude`: la tab si chiude da sé, il transcript resta su disco, e la conversazione si riprende dal deck come ogni altra chiusa. Il deck risponde dopo aver verificato la fine del processo.

Il deck chiude solo una conversazione **viva**, **del progetto**, **aperta da una richiesta `spawn-task`** e **ferma** — senza un turno in corso né un comando in esecuzione. Fa eccezione l'**orchestrator che ha passato le consegne**: anche aperto a mano, il deck l'ha marcato `origin: orchestrator` quando ha aperto il successore (`spawn-task <perimetro> orchestrator`), e il successore lo chiude. Rifiuta, col motivo, la conversazione che chiede la chiusura e ogni altra conversazione aperta a mano: quelle le chiude l'utente.

**Un'invocazione, una chiusura.** Più chiusure sono più invocazioni. La skill non pone domande, non chiede conferme e non sceglie il bersaglio: la decisione è già avvenuta nella conversazione che la invoca.

## 1. Il bersaglio

Dagli argomenti ricavi **un `sessionId`**: intero, o un prefisso di almeno 8 caratteri esadecimali (`0a1b2c3d`). È il valore che la riga `sessionId:` di `spawn-task` ha restituito all'apertura.

Argomenti che non sono un `sessionId` — un id di task, un nome di tab, più sessioni insieme — → riporta cosa manca ed esci, senza invocare niente: la skill non risolve un nome in una sessione, e una scelta tua chiuderebbe una conversazione diversa da quella chiesta.

## 2. Chiedi la chiusura

Dalla project root, una chiamata sola:

```bash
loom-deck-close <sessionId>
```

Nessuna regola di permesso accompagna il comando: fuori da auto mode Claude Code chiede conferma a ogni chiusura, ed è voluto — la chiusura termina un processo che non è di questa conversazione.

## 3. Riporta l'esito

Secondo l'uscita del comando, senza ritentare:

| Uscita | Esito | Cosa scrivi |
|---|---|---|
| `0` | conversazione chiusa | le righe di stdout così come sono: `sessionId`, task, processo terminato |
| `1` | il deck ha rifiutato, il processo non è finito in tempo, o il deck non ha risposto | il motivo da stderr, com'è (conversazione non viva o già chiusa, prefisso ambiguo, aperta a mano e non marcata da un passaggio di consegne, al lavoro, è la conversazione che chiede, processo non terminato) |
| `2` | errore d'uso | il messaggio da stderr: il `sessionId` del passo 1 era malformato |
| `3` | nessun deck in ascolto sul progetto | che serve il deck acceso sul progetto, o aggiornato: la chiusura c'è da `loom-deck` 0.88.0 |
| `127` | `loom-deck-close` non trovato | che il deck installato è più vecchio della chiusura: `npm install -g @lamemind/loom-deck@latest` |

Una riga `⚠` in fondo allo stdout di un'uscita `0` vuol dire che il processo è finito ma un passo dopo no — la marca che il bottone di restore del deck legge: riportala com'è.

Un rifiuto per processo non terminato lascia la conversazione aperta e al suo posto: non ritentare, e non terminarla per altre vie.
