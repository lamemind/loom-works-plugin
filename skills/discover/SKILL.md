---
name: discover
description: Documentary bootstrap for a project with zero docs. Filesystem scan + doc-writer invocation.
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
model: opus
---

Bootstrap documentale per un progetto **freshly installed** senza doc o con doc minimale. Pipeline a tre step: static scan → interview → delega a `doc-writer` per produrre la prima generazione di doc.

Input utente:
~~~human
$ARGUMENTS
~~~

## Quando usarla

- Plugin appena installato su un codebase di grandi dimensioni, nessun `docs/project/*`
- Workspace multi-progetto (es. N sub-repo indipendenti) dove serve una mappa d'insieme
- Subito dopo `/loom-works:init` per riempire i file scheletro appena creati
- NON per aggiornamenti incrementali: per quello usa `/loom-works:capture-doc` o il task-loop

Se il progetto ha già `docs/project/overview.md` o un `CLAUDE.md` corposo, segnalalo e chiedi se l'utente vuole comunque procedere (rischio duplicazione).

## Prerequisiti

- `.claude/loom-works.json` deve esistere (config progetto creata da `/loom-works:init`). Se manca, interrompi e suggerisci l'init.

## Flusso

### 1. Static scan

Lancia lo script scan e salva l'output in un file temporaneo (può superare le 200 righe su progetti grandi — non metterlo tutto in prompt):

```bash
SCAN_OUT="$(mktemp -t loom-discover-scan.XXXXXX.md)"
"${CLAUDE_PLUGIN_ROOT}/scripts/discover/scan-structure.sh" --root "$PWD" --depth 2 > "$SCAN_OUT"
```

Leggi il file con `Read` e mostra all'utente un **riassunto** in 10-15 righe coprendo:
- Tipo di progetto (monorepo / multi-repo workspace / single-package)
- Ecosistemi rilevati
- Sub-progetti elencati (path + ecosystem + size)
- Fulcri candidati (euristica — marcali esplicitamente come "tentativo, da confermare")
- Stato doc esistente (README, CLAUDE.md, `docs/`)

Conserva `$SCAN_OUT` — ti serve per lo step 4.

### 2. Classificazione sub-progetti (solo se > 1)

Se lo scan ha trovato più di un sub-progetto, usa `AskUserQuestion` per classificarli con opzioni:
- `core`: attivo, fa parte del perimetro da documentare
- `legacy`: ancora vivo ma non prioritario
- `deprecated`: non documentare
- `unknown`: chiedi più contesto all'utente

Se c'è un solo progetto, salta questo step.
Tieni traccia della classificazione: userai solo i `core` + eventualmente `legacy` negli step successivi.

### Convenzioni domande all'utente (AskUserQuestion)

L'iterazione standard richiede context-switching effort continuo e procura affaticamento mentale. Riduci il costo:

1. **Raggruppa** le domande per vicinanza tematica, no salti tra argomenti scorrelati.
2. Fornisci **contesto strutturato** prima di `AskUserQuestion`.
3. Una chiamata `AskUserQuestion` per **singola** domanda, prompt nudo.

`AskUserQuestion` non renderizza markdown → contesto in chat prima, tool dopo.
No prosa densa: produci un **layout visivo facilitatore**: bullet points, grassetti, emoji, righe vuote, ascii tree, tabelle.

### 3. Interview fulcri

Per ogni sub-progetto `core` (o per il progetto intero se single):
- Se lo scan ha prodotto candidati euristici (services, entities, core modules), proponili con `AskUserQuestion` multi-select come "questi sono fulcri?" + opzione `nessuno di questi`
- **In ogni caso** termina con un messaggio testuale all'utente:
  > Elenca i **fulcri** del progetto (servizi/entità/oggetti chiave che attraversano il sistema), massimo 5-7 per ora. Per ciascuno: nome + 1 riga di ruolo. Esempio: `OrderDispatcher — riceve ordini dal frontend e li smista ai worker`.

Se l'utente non risponde o dice "non so": procedi comunque, lascia `doc-writer` fare guess su base scan, marca tutto come `draft`.

### 4. Delega al doc-writer (mode propose)

Invoca `doc-writer` via `Task` con un prompt strutturato che contenga **tutto il materiale**:

```
Nozione da documentare:
- **Nozione**: Bootstrap documentale del progetto. Produrre
  `${user_config.doc_folder_name}/project/overview.md` (vision/scope + mappa sub-progetti + fulcri)
  ed eventualmente stub in `${user_config.doc_folder_name}/reference/<area>/<fulcro>.md` per i fulcri principali.
- **Ancora primaria**: n/a (overview è online, stub offline hanno ancore dedicate)

Contesto:
<<< SCAN REPORT >>>
<contenuto integrale di $SCAN_OUT>
<<< END SCAN REPORT >>>

Classificazione sub-progetti (input utente):
- <path> — core | legacy | deprecated
- ...

Fulcri nominati dall'utente:
- <nome> — <ruolo (1 riga)>
- ...

Docs root: <PROJECT_ROOT>/${user_config.doc_folder_name}

Mode: propose

Istruzioni:
1. Se già esiste `docs/project/overview.md` o un CLAUDE.md corposo, NON duplicare —
   proponi invece un EXTEND mirato o segnala overlap.
2. `overview.md` deve avere: paragrafo cos'è il progetto (dal tuo meglio, basato
   su nome/manifesti/struttura), tabella sub-progetti con scope 1-riga, sezione
   "Fulcri" con bullet per ogni fulcro nominato.
3. Per ogni fulcro nominato, proponi uno stub in `${user_config.doc_folder_name}/reference/<area>/<fulcro>.md`:
   solo header + TLDR ancorato + sezione "Ruolo" (2-3 righe) + sezione
   "Da documentare" bullet list con "TODO" — è uno stub, non una doc completa.
4. Se crei file online (overview.md), includi patch a CLAUDE.md per aggiungere
   l'@-import, come da tue regole standard.
5. Se vedi incertezza su un fulcro (ruolo ambiguo, nome che non corrisponde a
   nulla di visibile nello scan), usa AskUserQuestion per disambiguare prima di
   scrivere la patch.
```

Il subagent produce il blocco `## Proposta` con uno o più target.

### 5. Review utente

Mostra all'utente **tutta la proposta** del subagent. Poi esegui il ping TTS e chiedi via `AskUserQuestion`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su proposta overview da applicare"
```

Usa `AskUserQuestion` con opzioni:
- `ok / apply` → step 6
- `edit` → raccogli feedback, rilancia doc-writer con le correzioni
- `skip` → fine, nessuna modifica

### 6. Apply (solo su conferma esplicita)

Rilancia `doc-writer` via `Task` con **stesso input** + `Mode: apply`. Il subagent scrive i file (overview.md, stub reference, patch CLAUDE.md).

### 7. Rebuild INDEX se serve

Se l'output del subagent in mode apply contiene `INDEX_REBUILD_NEEDED: yes` (oppure sai che ha toccato `${user_config.doc_folder_name}/reference/`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/docs/build-index.sh" --docs-root "${user_config.doc_folder_name}"
```

### 8. Report finale

Lista:
- File creati (overview.md, stub reference)
- CLAUDE.md patched sì/no
- INDEX rigenerato sì/no
- Fulcri ancora da approfondire (quelli con solo stub)

Stampa anche la pulizia:
```bash
rm -f "$SCAN_OUT"
```

Suggerisci come prossimo passo: "per ogni fulcro stub, usa `/loom-works:capture-doc` a mano a mano che emergono dettagli, oppure rilancia `/loom-works:discover` dopo aver esplorato un sub-progetto specifico".

## Convenzione TTS

Prima di ogni `AskUserQuestion`, esegui:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/utils/say.sh" && say_auto "domanda su <topic 3-7 parole specifiche>"
```
Topic = argomento concreto della domanda. NO generici.

## Note

- **Non committare**: le modifiche restano uncommitted. Decisione dell'utente.
- **Non invocare discover due volte senza aspettare review**: ogni chiamata al doc-writer è costosa in token.
- **Multi-lingua**: lo scan copre workspace-level (ecosystemi). Per doc di dettaglio intra-codice (classi, metodi) di progetti TS/JS esiste `scripts/explorer/extract-codebase.ts` come futuro L3 — non integrato in questa versione della skill.
- **Fallback no-repo**: la skill funziona uguale in progetti senza git. Nessun git touch richiesto.
- **Scope split con `capture-doc`**: discover produce la **prima generazione** (scaffold + stub). capture-doc riempie i dettagli **man mano**. Non duplicare responsabilità: se l'utente chiede "documenta meglio il servizio X", rimandalo a capture-doc.
