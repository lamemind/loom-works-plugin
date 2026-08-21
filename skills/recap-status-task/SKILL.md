---
name: recap-status-task
description: Recap di una singola task — stato reale vs dichiarato, DLV e AC aperti voce per voce, documenti prodotti, interdipendenze interne, e una proposta nominata di cosa fare adesso.
allowed-tools: Bash(*), Read, Glob
model: opus
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

Recap di **una task**, per rientrarci sapendo dove mettere le mani nel prossimo turno. **Read-only**: non scrive né modifica nessun file.

## Grado di competenza — `K1` sulla task e sul suo dominio

Chi chiede un recap dichiara, con l'atto stesso, di non avere la bussola della situazione. Scrivi quindi a **`K1`** su un perimetro dichiarato:

- **cosa** — la task corrente: cosa vuole ottenere, cosa ha già prodotto, cosa le manca
- **dove** — il dominio su cui la task interviene (il sottosistema che tocca, il suo perimetro di applicazione)

`K1` significa: termini comuni nudi, termini specialistici glossati alla prima occorrenza, implicazioni sempre esplicitate, nessuna ancora al mondo di tutti i giorni. La scala `K0`-`K3` non la ridefinisci — vive nell'output style; qui dichiari solo a che grado leggerla dentro il perimetro.

**Fuori dal perimetro vale il grado dichiarato normalmente**: un recap di task non abbassa `java`, `sql` o qualunque altra materia — il vuoto che un recap presume riguarda lo stato di un lavoro, non il possesso di un vocabolario.

**Un `[Kx]` inline vince secco** sul settore che nomina: è la dichiarazione cosciente di quanto l'utente ricorda adesso, e correggerla significherebbe non credergli. I settori che l'override non nomina restano a `K1` dentro il perimetro.

**Le coordinate opache restano opache a ogni grado.** `T113`, `D14`, `#4782` non sono termini da imparare, sono indirizzi: ogni citazione porta la sua maniglia verbo+oggetto — `T113 (partizione di recap-status)`, mai `T113` nudo. Fa eccezione l'id che l'utente ha nominato lui nel prompt: quello è già in memoria a chi legge.

## 1. Risolvi e leggi la task

Se le Note utente nominano un ID (`/loom-works:recap-status-task T47`), passalo come argomento; altrimenti omettilo e lascia lavorare la cascata.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Cascata di famiglia `arg → $LOOM_TASK → symlink {docs_root}/current-task.md`. Exit non-zero = nessuna task risolvibile: dillo e fermati, non tirare a indovinare.

Fai **sempre** `Read` di `TASK_FILE`, per intero. Non lavorare su ciò che l'iniezione ha portato in contesto: il fill del budget si ferma alla prima sezione che non entra, quindi una sezione può mancare dal contesto senza mancare dal file.

**Se la task ha `Size: Epic`** sei sul caso sbagliato — è un cappello, e il suo stato vero sta nelle figlie. Dichiaralo in una riga, indica `/loom-works:recap-status-epic ${TASK_ID}`, e **procedi comunque** col recap del solo cappello: fermarsi sarebbe peggio che consegnare un quadro parziale dichiarato tale.

## 2. Raccogli il contesto reale

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/recap-git-status.sh
```

Serve a misurare lo stato **reale** contro quello **dichiarato**: una checkbox aperta su un file che esiste già, o una checkbox chiusa su un file che non c'è, valgono più di qualunque riassunto.

Poi, se il campo `**Folder**:` è popolato, lista la task folder (`ls -la`) — è lì che sta il materiale prodotto.

## 3. Documenti di rilievo

Il materiale prodotto è **parte dello stato della task**, non un allegato: su una task di progettazione le sole checkbox misurano zero avanzamento mentre il lavoro prodotto è tutto testo.

**Se `## Materiale` è popolata**, è la fonte: onora i glifi (`📖` fonte · `🔬` analisi · `📤` prodotto) e risolvi la radice `📁/` contro il campo `**Folder**:`. Riporta le voci con la loro maniglia, non i path nudi.

**Se manca o è vuota — ed è il caso di maggioranza**, nessuna skill la popola in automatico e non c'è retrofit sulle task già aperte. Ricostruisci l'insieme da due sedi:

- la **task folder**, se il campo `Folder` è popolato
- i **path citati** nel task file: `Description`, `Deliverables Checklist`, `Doc Impact`

Elenca solo ciò che è di rilievo — un documento che porta contenuto — non l'inventario della cartella.

## 4. Il recap — in quest'ordine

**4a. Quadro d'insieme, prima del dettaglio.** Cosa vuole ottenere la task, a che punto è davvero, cosa è cambiato rispetto a quello che il file dichiara. Poche righe, e vengono per prime anche quando l'utente chiede «zoom alto»: zoom alto non chiede meno copertura, chiede che il quadro preceda il dettaglio, che arriva comunque dopo.

**4b. DLV e AC, voce per voce.** Non riassumere in un giudizio di sintesi: **elenca esplicitamente** i deliverable aperti e gli acceptance criteria aperti. Dai la cifra (`4/12 DLV`, `3/16 AC`) e poi le voci. Per i chiusi basta il conteggio, salvo quelli che spiegano lo stato corrente.

Segnala le **incongruenze** dove le trovi: voce spuntata ma file assente, voce aperta ma lavoro già a terra nel repo.

**4c. Materiale**, dallo step 3.

**4d. Interdipendenze interne.** Qui il grafo è **fra le voci della stessa task**, non fra task: «l'AC sul guard non è verificabile finché il DLV del bump non è fatto». Nessun campo lo dichiara — si ricava leggendo il testo delle voci, ed è precisamente ciò che rende la proposta finale una scelta motivata invece della prima casella non spuntata.

**4e. La proposta — blocco terminale, singola e nominata.** Chiudi nominando **un** DLV o **un** AC da affrontare adesso, con la ragione in una riga. A questo zoom l'informazione per sceglierlo sta tutta nel file: lasciare la scelta al lettore significa non aver fatto il lavoro. Una lista di opzioni equivalenti non è una proposta.

Se qualcosa blocca davvero la scelta — una dipendenza esterna non risolta, un'ambiguità nel testo della task — dillo e proponi comunque il movimento che la sblocca.
