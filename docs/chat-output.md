# Output in chat

Contratto **specifico del terminale**. Non dice come si scrive — quello è `writing-patterns.md`, che vale ovunque. Qui sta solo ciò che compensa il comportamento di un renderer: cambiato il renderer, queste regole sparirebbero senza che nulla di ciò che si sa scrivere cambi.

**Non va mandato a un subagent che scrive su disco**: il trick degli heading qui sotto produce markdown rotto dentro un file `.md`.

## Heading — il terminale stila solo l'H1

`##`/`###`/`####` rendono piatti e la gerarchia si perde. Rimedio: ogni heading è un vero H1 (`# `, che viene stilato) più i `#` letterali extra come marcatore di profondità.

`# # Titolo` → H1 · `# ## Sezione` → H2 · `# ### Sotto` → H3

⚠️ **Solo in chat.** Nei file `.md` su disco si usa markdown standard: in un editor o su GitHub `# ## Titolo` renderizza come H1 con dentro il testo letterale «## Titolo», cioè rotto.

## Larghezza

Tabelle e box ≤ larghezza del terminale. Niente box-drawing che va a capo: la struttura deve aiutare la lettura, non combattere il medium. Se una tabella non ci sta, è una bullet list.

## Raggio — quanto terreno copre la risposta

| Raggio | Copre |
| --- | --- |
| **R0** | **default** — la risposta nuda, zero contorno |
| **R1** | nocciolo: la risposta + il perché essenziale, **un** approccio |
| **R2** | + contesto minimo necessario, caveat rilevanti, implicazioni dirette |
| **R3** | trattazione distesa: alternative, trade-off, tangenti pertinenti, esempi |

Fuori dal contorno, salvo richiesta esplicita: tangenti e nessi collaterali · alternative non chieste · caveat non pertinenti · scaffolding («il ruolo di…», «un po' di contesto») · menu di next-step · aperture di validazione («ottima domanda»).

- **Domanda ampia** → sali, al minimo livello che la copre.
- **L'utente specifica un R** (`[R2]` a fine prompt, «rispondi ampio») → onoralo esatto: non salire e non scendere. Vale per la risposta corrente, poi si torna a R0.
- **Slash-command esenti**: sono larghi per contratto. Restano soggetti a tutto il resto.

Il raggio taglia il **contorno**, mai la comprensione: le tre cose che il North Star non fa tagliare restano a ogni livello, R0 incluso.

## Riferimento — l'unica regola che cambia segno fra i medium

In chat **ri-dire l'indirizzo è obbligatorio**; in un file basta puntarlo una volta. Non è una preferenza di stile: il terminale è lineare e non ha random access, quindi ogni rimando indietro è un'azione fisica del lettore, mentre chi legge un file può saltare. Stessa preoccupazione — il costo che paga chi legge — con soluzione opposta per medium.

- **Coordinata opaca** — sigla o numero senza contenuto proprio (`T60`, `T02`, `F7`): **mai nuda**, sempre con una maniglia verbo+oggetto — `T38 (unificare docs-root)`.
- **Etichetta parlante** — il nome *è* il contenuto (`capture-doc`, `build-index.sh`): va nuda.
- **Namespace non condiviso = inesistente.** Un codice che vive in un file non aperto in questa conversazione si espande al primo uso, anche se l'hai coniato tu in una sessione precedente.
- **Etichetta coniata da te**: valida entro lo schermo. Oltre una schermata porta il proprio contenuto — non `F7` ma `F7 · README stale`.

Deroga a «dillo una volta sola»: ri-dire il **contenuto** è ridondanza, ri-dire l'**indirizzo** quanto basta a non tornare indietro è risoluzione. Senza questa deroga le due regole si contraddicono, perché abbreviare *è* il modo di non ripetersi.

Il caso peggiore è **opaco × alta cardinalità**: 25 skill non fanno male, 60 task sì. Che le abbia scritte l'utente non basta — la paternità non implica il richiamo.
