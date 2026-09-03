---
name: create-sweep
description: Produce un file inbox di natura sweep — l'ordine in prosa che align-doc esegue. Analizza prima (bersagli dall'INDEX, perimetro editoriale per bersaglio, riferimenti morti, fonte nativa), scrive la prosa dopo, committa. Non esegue lo sweep.
allowed-tools: Bash(*), Read, Glob, Grep, Task, AskUserQuestion
model: opus
---

**Docs root** — primo passo, prima di ogni altra cosa:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"
```

Stampa la docs-root di **questo** progetto (es. `runtime`; default `docs`). Usa il valore ottenuto ovunque sotto compaia `{docs_root}`. È un fatto per-progetto, letto dal file config del progetto in cui giri: non assumerlo e non riportarlo da un'altra sessione. Lo stato shell non sopravvive fra invocazioni Bash — risolvilo una volta e riusa il valore letterale.

Scrivi un **ordine di sweep**: il file inbox in prosa che `align-doc` esegue per riallineare una parte della doc ai sorgenti. L'umano decide **che** una doc è vecchia; questa skill scrive il file che lo dice, con la densità che serve a chi lo eseguirà.

**Il valore sta nell'analisi, non nella scrittura.** Il file lo scrive già `inbox.sh new`. Quello che manca senza questa skill è ciò che precede: quali pagine sono i bersagli, quale perimetro editoriale ha ognuna perché i writer non si invadano, quali nomi la doc cita e il codice non ha più, dove sta la fonte nativa di ogni bersaglio. Un ordine scritto a memoria ha la densità di un appunto, e la densità dell'ordine determina la qualità della patch.

**Non esegui lo sweep.** Ti fermi al file committato; `align-doc` è un'invocazione separata, che l'utente lancia quando vuole.

## Note utente
~~~human
$ARGUMENTS
~~~

Da qui si legge l'**intenzione in prosa libera**: cosa va riallineato e perché. Tutto il resto (una task nominata, un modo già scelto, `drainable` già chiesto) è materiale che risparmia una domanda, non un formato da rispettare.

**Modalità.** Le keyword `yolo`, `no domande`, `senza domande` attivano YOLO: nessuna domanda di **analisi** — deduci bersagli e perimetro da solo. Le tre domande standard (§4) si pongono comunque, salvo quelle a cui gli argomenti rispondono già.

**Un'invocazione, un file.** Il taglio di un lavoro grande in più ordini lo fa l'utente invocando più volte, mai un criterio di partizione dentro la skill: due sweep nello stesso giro finirebbero su due branch che si sovrappongono senza che nessuno lo abbia deciso.

## 1. Analisi — i fatti che l'ordine deve portare

Raccogli **prima** di scrivere. Fuse in un passo solo, la prosa si inventa fatti che nessuno ha misurato.

La raccolta la fa `doc-helper` (agent haiku, attività atomiche) — tu orchestri e non leggi in larghezza. `Task` con `subagent_type: doc-helper`, un'invocazione per attività.

**1a. I bersagli.** Leggi `{docs_root}/reference/INDEX.md`. Se l'intenzione nomina un componente (`deck`, `compass`, `sistema doc`), i bersagli sono le pagine della sua sezione; se nomina dei path, quelli. Un'intenzione che non permette di ricavare nessun bersaglio è l'unico caso in cui ti fermi e chiedi, `yolo` o no: senza bersagli non c'è ordine.

**1b. Il perimetro editoriale per bersaglio.** Serve perché i writer di `align-doc` girano **in parallelo, uno per bersaglio**, e senza un confine dichiarato scrivono lo stesso fatto su pagine diverse. Passa a `doc-helper` l'attività `mappa-tldr` con le voci `{file, tldr}` dei bersagli, prese dall'INDEX:

```
attività: mappa-tldr
voci: [{"file": "...", "tldr": "<la riga dell'INDEX>"}, ...]
```

Da lì ricavi **una riga per bersaglio** che dice di cosa quella pagina si occupa. **Non aprire le pagine bersaglio**: il TLDR dell'INDEX è già la riga che ne descrive il perimetro, e rileggerle costerebbe N letture per un dato che hai già. Una sovrapposizione fra due perimetri non si dichiara e non si risolve qui — la risolve il writer, che ha il testo davanti.

**1c. I riferimenti morti.** I nomi che la doc cita e il codice non ha più: un file droppato, una skill rimossa, uno script rinominato. Prendi i nomi propri che compaiono nei TLDR dei bersagli e cercali nel codice (`grep -rn -F -- '<nome>'` sul perimetro sorgente, o `doc-helper` con `cerca-codice`). Quelli che non tornano vanno nell'ordine.

**Nessun giro sistematico e nessun criterio formale.** Raccogli quello che l'analisi incontra e dichiaralo per quello che è: materiale non esaustivo. Un falso positivo qui non si propaga — `align-doc` apre comunque la fonte nativa e rimette alla prova ogni fatto dell'ordine.

**1d. La fonte nativa.** Per ogni bersaglio, dove un writer deve guardare per ri-derivare i fatti. I path sono preferiti quando ci sono (`loom-deck/src/`), ma un nome di componente nudo (`deck`) è ammesso: `align-doc` ha il contesto per risolverlo.

**Perché l'approssimazione è ammessa.** Un ordine di sweep è un **piano di massima, non una specifica verificata**. Fra te e i writer c'è `align-doc`, che apre la fonte e ricontrolla. Un produttore che verificasse pagherebbe due volte la stessa lettura.

## 2. Cosa la prosa deve coprire

Nessun template e nessuna struttura fissa: scrivi prosa libera che tiene insieme i fatti dell'analisi. Quello che segue è l'elenco delle cose che devono esserci, non l'ordine in cui metterle.

- **Cosa va riallineato e perché** — l'intenzione dell'utente, resa esplicita.
- **I bersagli**, nominati.
- **Il perimetro editoriale di ognuno**, una riga a testa, introdotto come divisione da rispettare: ogni pagina ha un perimetro suo e non va invasa dalle sorelle.
- **Cosa deve sparire** — i riferimenti morti, con l'avvertenza che vale per tutti: un nome droppato **non si traduce nel suo successore**. Un successore che fa un mestiere diverso produce una doc plausibile e falsa, che è peggio di una doc vecchia perché nessuno la mette in dubbio.
- **Cosa la doc possiede e i sorgenti no** — il perché di una scelta, cosa costa, quale alternativa è stata scartata. Va tenuto dove la pagina già ce l'ha: è l'unica parte che una ri-derivazione dai sorgenti non può rigenerare.
- **L'avvertenza sui calchi** — una cifra o una classifica ricopiata da una fonte che si muove invecchia da sola. Le soglie si scrivono **con la loro sede** (quale variabile in quale file), mai come numero nudo.
- **Il registro** — presente indicativo, stato corrente, nessuna data, nessun id di task inline, nessun racconto di come ci si è arrivati.

**Vincoli di forma**, tutti e tre verificabili prima di scrivere il file:

- **Nessun hard-wrap.** Un paragrafo è una riga sola, per quanto lunga: è una garanzia di progetto sui `.md`, e `inbox.sh` la pretende.
- **Nessuna riga che apra con una parola minuscola seguita da due punti.** Il parser raccoglie quel pattern come ancora, e il separatore che protegge il blocco vero non copre chi lo scrive in mezzo alla prosa. Se un capoverso deve aprire così, apri con la maiuscola.
- **Le ancore non si scrivono nella prosa**: viaggiano su `--ancora`, e lo script le mette in coda dopo il separatore.

## 3. Le ancore

Facoltative, mai verificate a valle, e `align-doc` le legge come indicazioni:

| Ancora | Cosa dice | Da dove viene |
|---|---|---|
| `codice:` | dove guardare — ripetibile | le fonti native del passo 1d; `niente` se lo sweep è di sola prosa |
| `doc:` | dove scrivere — ripetibile | i bersagli del passo 1a |
| `modo:` | `integra` (assorbi la doc esistente) o `riscrivi` (rasala e riparti) | domanda §4 |
| `online: si` | fa entrare nei bersagli anche la doc @-importata da `CLAUDE.md` | domanda §4, solo se serve |

## 4. Le tre domande standard

In coda al giro, accorpate. **Sopravvivono a `yolo`**: sono decisioni, non deduzioni — nessuna si ricava dall'intenzione. Salta soltanto quelle a cui gli argomenti hanno già risposto.

Prima di `AskUserQuestion`, il ping:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su perimetro dello sweep"
```

- **`drainable`** — sempre. Scrivere un ordine e volerlo far eseguire da solo sono due decisioni distinte: il token apre la **coda automatica** di `nightly-doc`, non il permesso di eseguire. Un file parcheggiato resta comunque lanciabile a mano nominandolo.
- **`modo`** — sempre. `integra` assorbe la doc preesistente, `riscrivi` la rasa e riparte dal referto.
- **`online`** — **solo se** l'analisi ha trovato materiale pertinente nella doc online (i file @-importati da `CLAUDE.md`). Presentala nominando le pagine trovate; se non ce n'è, la domanda non si pone. La **lista** degli @-import resta fuori comunque: è topologia, mestiere di `rebalance-doc`.

## 5. Scrittura e commit

**Slug** — kebab-case dal tema dell'ordine, non dall'intenzione parola per parola.

**Cappello** — passa `--cappello` **solo se l'intenzione nomina una task** (`lo sweep di T131`). Altrimenti slug nudo: un cappello inventato è provenienza falsa.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/inbox.sh" new \
    --docs-root "{docs_root}" --slug <slug> --natura sweep \
    [--cappello <Txxx>] [--titolo "<titolo>"] [--drainable] \
    [--ancora 'codice:<path>']... [--ancora 'doc:<path>']... \
    --ancora 'modo:<integra|riscrivi>' [--ancora 'online:si'] \
    <<'PROSA'
<la prosa dell'ordine>
PROSA
```

Heredoc quotato (`<<'PROSA'`), sempre: la prosa contiene backtick e apici, che una shell non quotata eseguirebbe o mangerebbe.

Lo script stampa `INBOX_PATH=<path>`. Poi committa **quel file e basta** — nessun controllo sullo stato del worktree, il perimetro doc può essere sporco per mano di altri e non è affar tuo:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/lib.sh" \
  && lw_git_add_n_commit "docs(sweep): ordine <slug>" "<INBOX_PATH>" \
  && lw_git_push "$(lw_current_branch)"
```

**Il commit è il mestiere della skill, non un di più.** La guardia d'ingresso di ogni drain (`doc-guard.sh worktree`) sorveglia `{docs_root}/inbox` con `git status --porcelain -uall`, e un file appena scritto e non committato è per git indistinguibile da un drain morto a metà: `align-doc` uscirebbe 2 allo step 0, fermato dal file che deve consumare.

## 6. Chiusura

Riporta il path del file, i bersagli, il modo e se è `drainable`. Poi stampa sempre l'invocazione pronta:

```
/loom-works:align-doc <slug>
```

Vale quale che sia il token: un file **nominato** si esegue anche senza `drainable`.

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "sweep order ready"
```
