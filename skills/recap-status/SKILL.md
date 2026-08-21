---
name: recap-status
description: Recap dispatcher — risolve la task attiva, classifica e passa a recap-status-project|task|epic. Da usare quando si chiede un recap senza nominare il livello.
allowed-tools: Bash(*), Read, Skill
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

**Questa skill non produce il recap.** Classifica e passa la palla. L'unico testo che scrivi per l'utente è la riga di dispatch dello step 3 — tutto il resto lo scrive la sotto-skill, che eredita contesto di sessione e output style perché gira nello stesso turno.

## 1. Risolvi la task attiva

Se le Note utente nominano un ID task (`T113`), passalo come argomento; altrimenti omettilo.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/task/resolve-task.sh ${taskId}
```

Cascata di famiglia `arg → $LOOM_TASK → symlink {docs_root}/current-task.md`. Exit non-zero significa «nessuna task attiva»: è un caso normale e previsto, non un errore da riportare all'utente.

## 2. Classifica

| Esito della risoluzione | Sotto-skill |
|---|---|
| exit non-zero — nessuna task risolta | `loom-works:recap-status-project` |
| task risolta con `Size: Epic` | `loom-works:recap-status-epic` |
| task risolta con qualunque altro `Size` | `loom-works:recap-status-task` |

Il `Size` si legge facendo `Read` di `TASK_FILE`, non da ciò che l'iniezione ha portato in contesto: il fill del budget può averlo troncato.

Se l'utente ha nominato lui la sotto-skill (`/loom-works:recap-status-project` invocata a mano) questa skill non è nemmeno in mezzo — non c'è niente da dispacciare.

## 3. Invoca

Tool `Skill`:

- `skill` = il nome scelto allo step 2
- `args` = **le Note utente verbatim**, senza riassumerle, tradurle, riordinarle o interpretarle

Verbatim non è pignoleria: l'input porta spesso più richieste distinte più un `[Kx]` inline, e un dispatcher che riassume prima di passare butta via proprio la parte che la sotto-skill deve onorare.

Prima di invocare stampa **una riga sola**, nella forma `→ recap-status-{project|task|epic}` più l'id della task risolta quando c'è. Poi passa la palla e non aggiungere altro.
