# Convenzioni di path nei sorgenti del plugin

Vale per `skills/`, `agents/`, `templates/` e i file di `docs/` — i sorgenti che un modello
legge. **Non** per `scripts/`, che è bash vero: lì una variabile è una variabile.

## La base è la root del progetto

Un path scritto in un sorgente del plugin è **project-root-relative**, e la base non è mai
la posizione del file che lo contiene: un `SKILL.md` viene letto dentro una sessione il cui
`cwd` è la root del progetto, non la cartella della skill.

Ne discende che una risorsa **interna al plugin** non si scrive relativa mai — sempre
`${CLAUDE_PLUGIN_ROOT}/...`. Un `docs/task-management.md` nudo esiste in due mondi e ne
indica due diversi (la `docs/` del plugin, e la docs-root di default di un progetto),
quindi non fallisce: risolve al posto sbagliato in silenzio su ogni progetto che non ha
personalizzato la docs-root.

## Due segnaposto

- `{project_root}` — la root del progetto, dove serve nominarla esplicita.
- `{docs_root}` — la cartella doc del progetto (`docs` di default, `runtime` su loom-works).
  Si legge con `"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"`; è un fatto
  per-progetto, non si assume e non si riporta da un'altra sessione.

## `${...}` interpola, `{...}` è un buco da riempire

`${...}` **solo** dove il valore arriva già sostituito:

- `${CLAUDE_PLUGIN_ROOT}` — interpolato nei body delle skill;
- `${taskId}`, `${TASK_ID}`, `${lane}`, `${N}` — narrazione interna della skill: valori che
  la skill ha già in mano, ricevuti nell'invocazione o calcolati un passo prima.

`{...}` dove il valore è un **fatto di progetto** che qualcun altro deve risolvere: prosa,
template d'esempio, blocchi-prompt destinati a un subagent.

**Il discriminante non è estetico.** Nei body degli agent `${...}` non risulta interpolato —
il path glielo passa il chiamante nel prompt (dettaglio nel cappello,
`runtime/project/plugin-dev.md` §Contratto vincolante per un subagent). Una forma
shell-looking in un posto che non interpola **mente sulla propria natura**: chi la legge la
crede risolta, e nessun errore lo smentisce.

`${DOCS_ROOT}` è il caso storico. Era l'erede testuale di `${user_config.doc_folder_name}`,
che l'harness interpolava per davvero; il passaggio della docs-root su
`.claude/loom-works.json` ha cambiato il nome e tenuto la forma. Sotto, il meccanismo si è
ribaltato da interpolazione-harness a sostituzione-modello, e la grafia è sopravvissuta al
proprio referente senza che niente si rompesse.

## Il canale a due capi

Una skill che passa la docs-root a un subagent la scrive nel blocco-prompt:

```
Docs root: {project_root}/{docs_root}
```

Il body dell'agent rilegge quel valore col proprio nome. Sono **due capi dello stesso
canale in due file diversi**: cambiare la grafia da una parte sola lascia due nomi per lo
stesso valore, e il guasto non si presenta come errore — l'agent riceve un segnaposto non
risolto e improvvisa.

## Nessuno strumento presidia questo perimetro

`check-doc-links.sh` non scandisce i sorgenti del plugin di default, e puntandoceli con
`--also` non distingue un riferimento da un esempio didattico. I `SKILL.md` contengono per
mestiere path che **devono** non esistere: righe di invocazione d'esempio, anti-esempi
dentro la frase che li vieta, segnaposto non interpolati. Il perimetro si misura e si
legge — non può essere un gate a zero.
