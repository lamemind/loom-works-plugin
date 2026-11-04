# Campi di progetto e hook di progetto — i blocchi `taskFields` e `hooks`

Contratto per chi **dichiara** campi propri nell'header del task file, o lega **skill di progetto** a due eventi del ciclo di vita di una task, e per chi **scrive** quelle skill. Le due dichiarazioni vivono in `.claude/loom-works.json`, il file committato del progetto. Il loro posto è il progetto e non lo userConfig del plugin, perché valgono per un progetto solo e descrivono il formato di task file che stanno nello stesso repo: da un clone senza la dichiarazione le task nascerebbero senza campi, e senza nessun errore.

Loom conosce le chiavi e solleva l'evento. Non sa cosa c'è dietro. Cosa fare con i valori lo decide la skill di progetto.

```jsonc
"taskFields": [
  { "key": "User Story", "ask": "User story Jira di riferimento", "pattern": "^[A-Z]+-\\d+$", "inherit": true },
  { "key": "Sub-task",   "ask": "Sub-task Jira (vuoto = la task copre la story intera)", "pattern": "^[A-Z]+-\\d+$" }
],
"hooks": {
  "deliverableDone": ["jira-sync"],
  "taskDone": ["jira-sync"]
}
```

Tipo e dominio di ogni proprietà: `templates/loom-works.schema.json`. Lo schema non è il validatore: le regole qui sotto le applica `cfg_validate_blocks` in `scripts/config/lib-config.sh`.

## `taskFields` — campi dell'header

Ogni voce dichiara un campo. Nel task file il campo diventa una riga dell'header, `- **<key>**: <valore>`, al posto del segnaposto `{{campi_progetto}}` di `templates/task-template.md`: dopo `Folder`, prima di `Progress`, nell'ordine di dichiarazione, anche vuota. Un progetto senza `taskFields` ha l'header di sempre, perché la riga del segnaposto sparisce.

| Proprietà | Obbligo | Effetto |
|---|---|---|
| `key` | sì | Nome del campo nell'header. |
| `ask` | no | Domanda di `create-task` in interattivo. Assente → si chiede col nome del campo. |
| `pattern` | no | Regex che un valore non vuoto deve soddisfare. |
| `inherit` | no | `true` → alla nascita il campo prende come default il valore del parent. |

**Tutti i campi sono opzionali.** Si riempiono anche dopo, a mano: un'epica nasce spesso prima che il suo riferimento esterno esista. Nessuna proprietà rende un campo obbligatorio.

**Una `key` non può coincidere con un campo fisso del template**, senza distinguere maiuscole, né con un'altra voce. Il parser dell'header del deck tiene la prima occorrenza di una chiave, e un `Size` di progetto scritto prima del campo fisso ne prenderebbe il posto. Le chiavi riservate sono le righe `- **<k>**:` dell'header del template, lette dal template stesso: un campo fisso aggiunto al plugin diventa riservato senza toccare questa regola. Una `key` non contiene `*`, `:`, `|` né un a capo, e non ha spazi in testa o in coda: `*` e `:` romperebbero la riga `- **<key>**:`, `|` separa i campi nell'output del lettore.

**`pattern` è nel dialetto di jq** — `test()`, motore Oniguruma, dove `\d` funziona. In ERE POSIX (`grep -E`, `[[ =~ ]]`) `\d` non esiste: chi valuta la regex fuori da jq la valuta in un altro dialetto. Il vuoto passa sempre. La validazione rifiuta una regex che non compila.

**`create-task` chiede, non inventa.** In interattivo chiede ogni campo e accetta il vuoto; una risposta che non combacia col `pattern` si richiede una volta, alla seconda il campo resta vuoto. In YOLO un valore entra solo se il contesto lo attribuisce a quel campo, e combacia; altrimenti il campo resta vuoto.

**L'eredità vale solo alla nascita.** Un campo con `inherit: true` prende come default il valore dello stesso campo nel task file del `Parent Task`, qualunque `Size` abbia il parent, anche in YOLO: è un dato del repo, non un valore inventato. Un valore del parent vuoto o fuori `pattern` non diventa un default. Un `Parent Task` scritto a mano dopo la nascita non propaga niente.

## `hooks` — skill di progetto sul ciclo di vita

`hooks.<evento>` è una lista di **nomi di skill**, invocate una alla volta nell'ordine della lista, col tool `Skill`, nel turno della skill loom che solleva l'evento. Un nome è una stringa non vuota senza spazi: `jira-sync` per una skill del progetto o dell'utente, `<plugin>:<skill>` per una skill di un plugin.

| Evento | Chi lo solleva | Quando |
|---|---|---|
| `deliverableDone` | `run-task` | dopo commit e push di ogni DLV chiuso |
| `deliverableDone` | `checkpoint-task` | dopo il push dello step 5, per ogni DLV che il checkpoint spunta da sé, in ordine di numero |
| `taskDone` | `checkpoint-task` | dopo il commit e push finale (step 8), solo nel giro che porta la task a `✔️ Done` |

Un DLV già spuntato da `run-task` non risolleva l'evento in `checkpoint-task`. Un checkpoint che non chiude non solleva `taskDone`. Un evento parte solo dopo un push riuscito: senza, la skill riceverebbe un commit che le altre sessioni non vedono.

**L'hook nomina una skill e non uno script**, perché l'azione tipica passa da un tool MCP, e un tool MCP lo chiama solo il modello.

**L'esistenza della skill non si controlla alla validazione.** Una skill può stare in `.claude/skills/` del progetto, in `~/.claude/skills/` o in un plugin, e il file system del progetto mostra solo il primo caso. Si scopre all'invocazione.

### Gli argomenti

La skill hook riceve una riga sola, come `args` del tool `Skill`, cioè nel suo `$ARGUMENTS`:

```
deliverableDone   <taskId> <n> <sha> <task_file> -- <testo del DLV>
taskDone          <taskId> <sha> <task_file>
```

- `<n>` — numero posizionale del DLV, 1-based sulle checkbox a colonna zero di `## Deliverables Checklist`, contato dal parser che spunta.
- `<sha>` — sha corto del commit che porta l'evento: il commit del DLV, o il commit finale del checkpoint. Non è `HEAD`: in detached un'altra sessione può committare fra il push e l'hook.
- `<task_file>` — path del task file, relativo alla project root.
- `<testo del DLV>` — il testo della voce, dopo ` -- `. Può contenere spazi e `|`: è tutto ciò che segue il primo ` -- `.

La skill riceve path e testo perché una skill di progetto non vede `${CLAUDE_PLUGIN_ROOT}` — è interpolata solo nei body delle skill del plugin — e senza non può rifare docs-root e numerazione dei DLV. I valori dei campi di progetto non viaggiano negli argomenti: la skill li legge dall'header del task file, righe `- **<key>**: <valore>`, prima occorrenza.

La riga la compone `scripts/config/project-config.sh hooks <evento> --task <id> --sha <sha> [--dlv <n>]`, e la skill loom la copia tale e quale. Il formato vive in un posto solo.

### Il contratto della skill hook

La skill hook gira **senza nessuno che guardi**: `run-task` è un'esecuzione non presidiata, e nessun meccanismo si accorge di un hook che aspetta una risposta. Ne discende:

1. **Nessuna domanda.** Una domanda lascia la sessione in attesa fino a quando qualcuno la vede.
2. **I tool che usa li dichiara nel proprio `allowed-tools`**, MCP compresi (es. `mcp__plugin_coface-core_Jira-Connect__add_comment`). I settings del progetto non si toccano per un hook.
3. **Chiude dichiarando un esito**, riuscito o fallito, con il motivo. La skill loom lo legge per decidere l'avviso.
4. **Non committa e non spunta niente.** Il DLV è già chiuso; ciò che la skill fa resta suo.

Il body della skill hook entra nel contesto della sessione a ogni invocazione e vale per quell'hook soltanto: quando dichiara l'esito, riprendono le regole della skill loom che l'ha invocata.

### Il fallimento

**Un hook non ferma mai il ciclo.** Il DLV è già committato e pushato, e l'hook non lo riapre. Una skill che non esiste, che dà errore o che dichiara un fallimento produce un avviso in linea — `⚠ hook <skill> fallito su DLV<n>: <motivo>`, o `su taskDone` — e una riga nella sezione `🚦 Segnalazioni` del report. Le skill successive della lista e i DLV successivi girano comunque.

**Nessun secondo tentativo.** Un hook fallito a metà può aver già scritto fuori dal repo, per esempio un commento sulla issue, e lo scriverebbe due volte.

Un lettore che esce non-zero — blocco `hooks` invalido, `jq` assente, task, DLV o sha non risolvibili — vale come un hook fallito: nessuna skill per quell'evento, avviso, riga `🚦`.

## La validazione e `jq`

Un blocco invalido si scopre due volte, con la stessa funzione `cfg_validate_blocks`: in `cfg_validate`, a `init` e al refresh di compass, e nel lettore `scripts/config/project-config.sh`, a ogni `create-task`, `run-task` e `checkpoint-task`. La seconda serve perché `register.sh` esce prima di validare quando manca dconf, quindi su Windows `cfg_validate` non gira mai. Con un blocco invalido il lettore esce 1, col messaggio che nomina il valore: `create-task` crea la task senza campi di progetto, `run-task` e `checkpoint-task` non invocano hook, e tutte e tre lo dicono.

Oltre a chiavi riservate e liste di stringhe, la validazione rifiuta una proprietà sconosciuta in una voce di `taskFields` e un evento sconosciuto in `hooks`: un refuso come `inheritt` o `deliverabledone` altrimenti non farebbe niente, e nessuno lo vedrebbe.

**Il lettore richiede `jq` quando il file dichiara i blocchi.** Un file senza `"taskFields"` né `"hooks"` si legge anche senza `jq` (vuoto, exit 0); un file che li nomina, senza `jq`, dà exit 1. Uno stampato vuoto lascerebbe nascere task senza campi e hook mai invocati, con exit 0.

Banco: `plugin-tests/project-config/run.sh` nel repo cappello.
