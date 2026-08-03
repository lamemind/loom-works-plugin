# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettati a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — lane e task, ciclo di vita, grafo dipendenze, comandi
- `doc-management.md` — **contratto doc**: livelli online/offline, principi editoriali, soglie numeriche, formato TLDR, freshness. Fonte unica, senza copie per-progetto né override; le skill ne passano il path ai subagent, che non ricevono l'iniezione di sessione
- `caveman.md` — doctrine di risposta comprehension-first (comprimi la forma, mai la comprensione)

**Iniettato a `UserPromptSubmit`**: `caveman-restamp.md` — nocciolo di `caveman.md` ri-timbrato a ogni turno contro il drift.

**On-demand**: `task-management-technical.md` — naming, esempi di comando, dettaglio workflow.
