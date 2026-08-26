# T112 — invocare una skill del plugin in headless dal deck

> **INBOX**: nozioni · indexed · drainable

- **n1** — Una skill del plugin invocata in headless (`claude -p`) non riceve i rami interattivi: il token `yolo` li salta, e l'esito non si legge da `is_error` ma dal testo catturato. Ancora: `clean-tasks` dal deck.
- **n2** — Uno script del plugin eseguito fuori da un processo Claude Code non ha `CLAUDE_PLUGIN_ROOT`: il chiamante risolve la cache a runtime o accetta di duplicare la regola. Ancora: confine deck/plugin.
