# loom-works — Doc utente del plugin

Manuali, convenzioni e riferimenti tecnici del sistema che il plugin implementa.

**Iniettato a `SessionStart`** — una hook entry per file, perché il cap di 10.000 char è per comando: un `cat A B C` unico condividerebbe il budget e affamerebbe gli ultimi in coda.

- `task-management.md` — task, ciclo di vita, grafo dipendenze, comandi
- `scarti.md` — registro degli scarti: interroga prima di risollevare una segnalazione, registra lo scarto motivato. Non lo inietta un `cat`, ma `scripts/context/inject-scarti.sh`: il testo porta un comando eseguibile, e `CLAUDE_PLUGIN_ROOT` non è nell'ambiente del tool Bash — il segnaposto `{PLUGIN_ROOT}` lo riempie l'emitter

**Iniettato a `UserPromptSubmit`**: `restamp.md` — nocciolo dei contratti doc e task ri-timbrato a ogni turno contro il drift. Unica entry a costo moltiplicativo, tetto 4.500 char scritto nel file stesso. Le regole di scrittura non ci stanno: le porta l'output style, che regge il drift da sé.

**Portato dall'output style** (`output-styles/regole-output.md`, `force-for-plugin`): il contratto di scrittura della chat — comprensione contro sintesi, scala `K0`-`K3`, raggio `R0`-`R3`, meccanica del terminale. È l'unico canale che per costruzione **non** raggiunge un subagent.

**On-demand, letti da path**:

- `doc-management.md` — **contratto doc**: i quattro layer più l'inbox come punto d'arrivo di una nozione, criteri indipendenti e dipendenti, chi scrive la doc. Fonte unica, senza copie per-progetto né override. Lo apre chi scrive una nozione o una pagina di doc
- `task-management-technical.md` — naming, esempi di comando, dettaglio workflow
- `tldr-formats.md` — le due sedi del TLDR (riga 3 di `reference/`, riga 4 dell'inbox) e la formula `inbox/`
- `inbox-format.md` — struttura di un file inbox `nozioni` e le tre operazioni sul corpo (append, riscrittura, eliminazione). Lo apre chiunque scriva dentro l'inbox WIP di una task: le skill di cattura e il modello in chat
- `path-conventions.md` — da dove parte un path scritto in un sorgente del plugin, e quale grafia porta un segnaposto
- `scarti-format.md` — **contratto del registro degli scarti**: sede `{docs_root}/scarti/` e perché non `adr/`, campi di un record, immutabilità, `Supera` multi-valore con indirizzo alla voce, la migrazione dalla sede di prima (`migra`) e l'alias `adr.sh`. Lo apre chi scrive, interroga o migra il registro fuori dai sottocomandi di `scripts/task/scarti.sh`
- `taskfields-hooks-format.md` — **contratto dei blocchi di progetto** `taskFields` e `hooks` di `.claude/loom-works.json`: campi propri nell'header del task file (chiavi riservate, `pattern` nel dialetto di jq, eredità dal parent) e skill di progetto su `deliverableDone` e `taskDone` (quando scattano, gli argomenti, il contratto della skill hook non presidiata, il fallimento che non ferma il ciclo). Lo apre chi dichiara i blocchi o scrive una skill hook; la regola operativa vive nel body di `create-task`, `run-task` e `checkpoint-task`
- `mandate-format.md` — **contratto del perimetro di lavoro**: il task file `Size: Mandate` (sezione `## Membri`, le voci del piano e dello stato dell'orchestrator in `## Materiale`), la regola che vieta a epiche e mandati di copiare stato o cifre dei membri, e il lettore unico dei membri (`resolve-task.sh <id> --members`). Lo apre chi scrive o legge il file di un'epica o di un mandato
- `schedule-format.md` — **contratto del piano di un perimetro**: `schedule.md` nella task folder del perimetro, prosa per chi legge e un blocco JSON per lo script del flusso (`passo`, `dopo`, `risorse`, `dlv`, `umano`), e i controlli di `schedule.py verify`. Lo apre chi scrive il piano o lo legge
- `mandate-analysis.md` — **metodo dell'analisi del perimetro**: dalle relazioni fra i membri, metà meccanica da `mandate.py tree` e metà del modello, ai campi del piano; la rianalisi di un piano o di un'analisi vecchia. Lo apre chi scrive il piano: `prepare-mandate`, e l'orchestrator a metà giro
- `flow-format.md` — **contratto dello script del flusso**: `flow.py` e i suoi comandi, il giro dello script, la lettura di un turno a lista bianca, i motivi di risveglio, gli ordini, il keep-alive, la ripresa e le righe del flusso. Lo apre l'orchestrator, e chi rilegge un giro
- `triage-format.md` — **contratto degli scenari di triage**: la sezione `🚦 Segnalazioni` che chiude il report di `run-task` e `checkpoint-task`, la risposta in prosa libera, sede `{docs_root}/triage/`, campi di un record, lo scarto che passa per il registro degli scarti, nessun default. La regola operativa vive nel body delle due skill, non in un'iniezione: qui sta il contratto per chi scrive o conta gli scenari fuori da `scripts/task/triage.sh`
