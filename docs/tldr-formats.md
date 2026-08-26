# Formule TLDR

Due sedi: **riga 3** per i file di `reference/`, **riga 4** per i file inbox di natura `nozioni` (la riga 3 è del marker `> **INBOX**:`). Cap **600 char** per entrambe le formule, violazione bloccante — `build-index.sh` esce non-zero.

```markdown
# Titolo                                   # reference/
                                           #
> **TLDR**: <ancora>                       # riga 3

# Titolo                                   # inbox, natura nozioni
                                           #
> **INBOX**: nozioni · indexed · …         # riga 3 — marker
> **TLDR**: <perimetro>                    # riga 4 — opzionale
```

**`reference/` — ancora.** Fa decidere *se aprire* il file, non risparmia l'apertura. Trigger concreti separati da `·`: comando, flag, tag, pattern, messaggio d'errore, la frase con cui uno cercherebbe la cosa. Mai un riassunto del contenuto. Obbligatorio: senza TLDR il file resta fuori dall'INDEX.

- ✅ `deck-run --resume · sidecar session-tasks.jsonl · "bindare una task a una sessione"`
- ❌ `Descrive il funzionamento del deck e le sue interazioni con le sessioni.`

**`inbox/` — perimetro.** Risponde a un'altra domanda: «l'area che sto per toccare ha una nozione non ancora collocata?». Più sintetico, e qui la cronaca è ammessa — il corpo deve sopravvivere alla task, il TLDR solo al file, che è temporaneo per contratto. Opzionale: l'indicizzazione la decide il marker `indexed`, e un file `indexed` senza TLDR entra nell'INDEX col solo titolo.

- ✅ `cache prompt Anthropic per subagent · prefisso cachabile · misura dai transcript`
- ❌ `Nozioni emerse durante il lavoro sulla task.`

Un file inbox nasce **congelato**: il TLDR si scrive una volta, alla creazione (`inbox.sh new --tldr`), e nessuno lo riscrive dopo — un trasloco successivo dello stesso cappello produce un file nuovo, col TLDR suo.
