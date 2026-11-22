# Convenzioni di path nei sorgenti del plugin

Vale per `skills/`, `templates/` e i file di `docs/` — i sorgenti che un modello legge. **Non** per `scripts/`, che è bash vero: lì una variabile è una variabile.

## La base è la root del progetto

Un path scritto in un sorgente del plugin è **project-root-relative**, e la base non è mai la posizione del file che lo contiene: un `SKILL.md` viene letto dentro una sessione il cui `cwd` è la root del progetto, non la cartella della skill.

Ne discende che una risorsa **interna al plugin** non si scrive relativa mai — sempre `${CLAUDE_PLUGIN_ROOT}/...`. Un `docs/task-management.md` nudo esiste in due mondi e ne indica due diversi (la `docs/` del plugin, e la docs-root di default di un progetto), quindi non fallisce: risolve al posto sbagliato in silenzio su ogni progetto che non ha personalizzato la docs-root.

La doc di un progetto non ha una base sola: vi convivono link markdown relativi al file e path relativi alla root, e la base la dichiara la grafia — `🏠/` davanti a un path vuol dire «parte da project root» (regola completa: `${CLAUDE_PLUGIN_ROOT}/docs/doc-management.md` §La base di un path). Nei sorgenti del plugin la base è già la root, quindi il marcatore non serve a leggerli. Serve a ciò che i sorgenti fanno scrivere: un template, un prompt o un agent che mette in doc un path a un progetto fratello lo scrive `🏠/../<fratello>/…`, perché un `../<fratello>/…` nudo parte dalla cartella del file che lo cita, e risulta appeso anche quando il file esiste.

## Due segnaposto

- `{project_root}` — la root del progetto, dove serve nominarla esplicita.
- `{docs_root}` — la cartella doc del progetto (`docs` di default, `runtime` su loom-works). Si legge con `"${CLAUDE_PLUGIN_ROOT}/scripts/utils/docs-root.sh"`; è un fatto per-progetto, non si assume e non si riporta da un'altra sessione.

## `${...}` interpola, `{...}` è un buco da riempire

`${...}` **solo** dove il valore arriva già sostituito:

- `${CLAUDE_PLUGIN_ROOT}` — interpolato nei body delle skill;
- `${taskId}`, `${TASK_ID}`, `${lane}`, `${N}` — narrazione interna della skill: valori che la skill ha già in mano, ricevuti nell'invocazione o calcolati un passo prima.

`{...}` dove il valore è un **fatto di progetto** che qualcun altro deve risolvere: prosa, template d'esempio, blocchi-prompt destinati a un subagent.

**Il discriminante non è estetico.** Una forma shell-looking in un posto che non interpola **mente sulla propria natura**: chi la legge la crede risolta, e nessun errore lo smentisce.

`${DOCS_ROOT}` è il caso storico. Era l'erede testuale di `${user_config.doc_folder_name}`, che l'harness interpolava per davvero; il passaggio della docs-root su `.claude/loom-works.json` ha cambiato il nome e tenuto la forma. Sotto, il meccanismo si è ribaltato da interpolazione-harness a sostituzione-modello, e la grafia è sopravvissuta al proprio referente senza che niente si rompesse.

## Nessuno strumento presidia questo perimetro

Nessuno script verifica i path dei sorgenti del plugin, e uno che lo facesse non distinguerebbe un riferimento da un esempio didattico. I `SKILL.md` contengono per mestiere path che **devono** non esistere: righe di invocazione d'esempio, anti-esempi dentro la frase che li vieta, segnaposto non interpolati. Il perimetro si legge — non può essere un gate a zero.
