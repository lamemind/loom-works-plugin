# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettato a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — lane e task, ciclo di vita, grafo dipendenze, comandi

**Iniettato a `UserPromptSubmit`**: `restamp.md` — nocciolo dei contratti doc e task ri-timbrato a ogni turno contro il drift. Unica entry a costo moltiplicativo, tetto 4.500 char scritto nel file stesso. Le regole di scrittura non ci stanno: le porta l'output style, che regge il drift da sé.

**Portato dall'output style** (`output-styles/regole-output.md`, `force-for-plugin`): il contratto di scrittura della chat — comprensione contro sintesi, scala `K0`-`K3`, raggio `R0`-`R3`, meccanica del terminale. È l'unico canale che per costruzione **non** raggiunge un subagent, ed è la garanzia strutturale che un agent non scriva su disco i trick di rendering del terminale.

**On-demand, letti da path**:

- `doc-management.md` — **contratto doc**: i quattro layer più l'inbox, criteri indipendenti e dipendenti, soglie numeriche, formato TLDR. Fonte unica, senza copie per-progetto né override. Lo aprono le skill che scrivono doc e gli agent, che ne ricevono o risolvono il path
- `task-management-technical.md` — naming, esempi di comando, dettaglio workflow
- `tldr-formats.md` — le due sedi del TLDR (riga 3 di `reference/`, riga 4 dell'inbox), la formula `inbox/` e chi produce quella di `reference/`
- `inbox-format.md` — struttura di un file inbox `nozioni` e le tre operazioni sul corpo (append, riscrittura, eliminazione). Lo apre chiunque scriva dentro l'inbox WIP di una task: le skill di cattura e il modello in chat
- `path-conventions.md` — da dove parte un path scritto in un sorgente del plugin, e quale grafia porta un segnaposto

**Incluso a build time, non letto da path**: il **contratto di scrittura degli agent** — gemello di ciò che l'output style dà alla chat, senza la meccanica del terminale, il raggio e le domande all'utente — non vive qui. Il sorgente sta nel repo cappello (`plugin-src/fragments/agent-output.md`) e `plugin-src/build-agents.sh` lo interpola dentro il body di ogni agent tramite la direttiva `<!-- include: agent-output.md -->`. Nessun agent lo apre a runtime: un contratto consegnato per path ha due modi di non arrivare — il consumer che non lo legge e il permesso che glielo impedisce — e l'inclusione a build time li toglie entrambi.
