# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettati a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — lane e task, ciclo di vita, grafo dipendenze, comandi
- `doc-management.md` — **contratto doc**: i quattro layer più l'inbox, criteri indipendenti e dipendenti, soglie numeriche, formato TLDR. Fonte unica, senza copie per-progetto né override; le skill ne passano il path ai subagent, che non ricevono l'iniezione di sessione
- `writing-patterns.md` — **primitiva globale di scrittura**, comprehension-first: vale in chat, nei commit, nei file doc, nei prompt ai subagent
- `chat-output.md` — solo ciò che è specifico dell'output a terminale (heading, larghezza, raggio, riferimento). **Mai passato a un subagent che scrive su disco**: i suoi trick di rendering producono markdown rotto in un file

**Iniettato a `UserPromptSubmit`**: `restamp.md` — nocciolo di ogni contratto (scrittura, chat, doc, task) ri-timbrato a ogni turno contro il drift. Unica entry a costo moltiplicativo, tetto 4.500 char scritto nel file stesso.

**On-demand, letti da path**: `doc-criteria.md` — razionale dei criteri dipendenti, delle soglie e della manutenzione · `task-management-technical.md` — naming, esempi di comando, dettaglio workflow · `tldr-formats.md` — le due formule del TLDR, `reference/` e `inbox/` · `path-conventions.md` — da dove parte un path scritto in un sorgente del plugin, e quale grafia porta un segnaposto.
