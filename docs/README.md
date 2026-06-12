# loom-works — Doc utente del plugin

Questa cartella contiene la documentazione utente del plugin loom-works: i manuali, le convenzioni e i riferimenti tecnici che descrivono il sistema che il plugin implementa.

File previsti (popolati progressivamente durante task D04):
- `task-management.md` — struttura lane/task, ciclo di vita, grafo dipendenze, comandi
- `doc-management.md` — livelli online/offline, formato TLDR, build-index, freshness
- `caveman.md` — modalità comunicazione ultra-compressa
- `task-management-technical.md` — naming convention, esempi comandi, dettaglio workflow

I primi tre file vengono iniettati automaticamente nel context Claude Code via hook SessionStart (`${CLAUDE_PLUGIN_ROOT}/docs/task-management.md` + `doc-management.md` + `caveman.md`). Il quarto è accessibile on-demand tramite `docs/reference/INDEX.md` del progetto utente.

Per il meta-progetto del plugin (design, roadmap, integration progress) vedi `DESIGN.md` e `INTEGRATION.md` nella root del plugin.
