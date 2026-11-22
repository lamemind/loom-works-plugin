# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettato a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — task, ciclo di vita, grafo dipendenze, comandi
- `adr.md` — registro ADR: interroga prima di risollevare una segnalazione, registra lo scarto motivato. Non lo inietta un `cat`, ma `scripts/context/inject-adr.sh`: il testo porta un comando eseguibile, e `CLAUDE_PLUGIN_ROOT` non è nell'ambiente del tool Bash — il segnaposto `{PLUGIN_ROOT}` lo riempie l'emitter

**Iniettato a `UserPromptSubmit`**: `restamp.md` — nocciolo dei contratti doc e task ri-timbrato a ogni turno contro il drift. Unica entry a costo moltiplicativo, tetto 4.500 char scritto nel file stesso. Le regole di scrittura non ci stanno: le porta l'output style, che regge il drift da sé.

**Portato dall'output style** (`output-styles/regole-output.md`, `force-for-plugin`): il contratto di scrittura della chat — comprensione contro sintesi, scala `K0`-`K3`, raggio `R0`-`R3`, meccanica del terminale. È l'unico canale che per costruzione **non** raggiunge un subagent.

**On-demand, letti da path**:

- `doc-management.md` — **contratto doc**: i quattro layer più l'inbox come punto d'arrivo di una nozione, criteri indipendenti e dipendenti, chi scrive la doc. Fonte unica, senza copie per-progetto né override. Lo apre chi scrive una nozione o una pagina di doc
- `task-management-technical.md` — naming, esempi di comando, dettaglio workflow
- `tldr-formats.md` — le due sedi del TLDR (riga 3 di `reference/`, riga 4 dell'inbox) e la formula `inbox/`
- `inbox-format.md` — struttura di un file inbox `nozioni` e le tre operazioni sul corpo (append, riscrittura, eliminazione). Lo apre chiunque scriva dentro l'inbox WIP di una task: le skill di cattura e il modello in chat
- `path-conventions.md` — da dove parte un path scritto in un sorgente del plugin, e quale grafia porta un segnaposto
- `adr-format.md` — **contratto del registro ADR**: sede `{docs_root}/adr/`, campi di un record, immutabilità, `Supera` multi-valore con indirizzo alla voce, e l'esclusione che tiene il registro fuori dalle misure della doc. Lo apre chi scrive o interroga il registro fuori dai due sottocomandi di `scripts/task/adr.sh`
- `taskfields-hooks-format.md` — **contratto dei blocchi di progetto** `taskFields` e `hooks` di `.claude/loom-works.json`: campi propri nell'header del task file (chiavi riservate, `pattern` nel dialetto di jq, eredità dal parent) e skill di progetto su `deliverableDone` e `taskDone` (quando scattano, gli argomenti, il contratto della skill hook non presidiata, il fallimento che non ferma il ciclo). Lo apre chi dichiara i blocchi o scrive una skill hook; la regola operativa vive nel body di `create-task`, `run-task` e `checkpoint-task`
- `mandate-format.md` — **contratto del perimetro di lavoro**: il task file `Size: Mandate` (sezioni `## Membri`, `## Preferenze d'ordine`, `## Analisi del perimetro`), la regola che vieta a epiche e mandati di copiare stato o cifre dei membri, e il lettore unico dei membri (`resolve-task.sh <id> --members`). Lo apre chi scrive o legge il file di un'epica o di un mandato
- `triage-format.md` — **contratto degli scenari di triage**: la sezione `🚦 Segnalazioni` che chiude il report di `run-task` e `checkpoint-task`, la risposta in prosa libera, sede `{docs_root}/triage/`, campi di un record, lo scarto che passa per il registro ADR, nessun default. La regola operativa vive nel body delle due skill, non in un'iniezione: qui sta il contratto per chi scrive o conta gli scenari fuori da `scripts/task/triage.sh`
