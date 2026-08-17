# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettato a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — lane e task, ciclo di vita, grafo dipendenze, comandi

**Iniettato a `UserPromptSubmit`**: `restamp.md` — nocciolo dei contratti doc e task ri-timbrato a ogni turno contro il drift. Unica entry a costo moltiplicativo, tetto 4.500 char scritto nel file stesso. Le regole di scrittura non ci stanno: le porta l'output style, che regge il drift da sé.

**Portato dall'output style** (`output-styles/regole-output.md`, `force-for-plugin`): il contratto di scrittura della chat — comprensione contro sintesi, scala `K0`-`K3`, raggio `R0`-`R3`, meccanica del terminale. È l'unico canale che per costruzione **non** raggiunge un subagent, ed è la garanzia strutturale che un agent non scriva su disco i trick di rendering del terminale.

**On-demand, letti da path**:

- `doc-management.md` — **contratto doc**: i quattro layer più l'inbox, criteri indipendenti e dipendenti, soglie numeriche, formato TLDR. Fonte unica, senza copie per-progetto né override. Lo aprono le skill che scrivono doc e gli agent, che ne ricevono o risolvono il path
- `agent-output.md` — **contratto di scrittura degli agent**: gemello di ciò che l'output style dà alla chat, senza la meccanica del terminale, il raggio e le domande all'utente. Ogni agent ne risolve il path da sé con `${CLAUDE_PLUGIN_ROOT}` e lo legge al primo passo
- `doc-criteria.md` — razionale dei criteri dipendenti, delle soglie e della manutenzione
- `task-management-technical.md` — naming, esempi di comando, dettaglio workflow
- `tldr-formats.md` — le due formule del TLDR, `reference/` e `inbox/`
- `path-conventions.md` — da dove parte un path scritto in un sorgente del plugin, e quale grafia porta un segnaposto
