# Formule TLDR

Il TLDR sta **esattamente sulla riga 3**, o il file resta fuori dall'INDEX. Cap **600 char** per entrambe le formule, violazione bloccante — `build-index.sh` esce non-zero.

```markdown
# Titolo

> **TLDR**: <ancora oppure perimetro>

Contenuto...
```

**`reference/` — ancora.** Fa decidere *se aprire* il file, non risparmia l'apertura. Trigger concreti separati da `·`: comando, flag, tag, pattern, messaggio d'errore, la frase con cui uno cercherebbe la cosa. Mai un riassunto del contenuto.

- ✅ `deck-run --resume · sidecar session-tasks.jsonl · "bindare una task a una sessione"`
- ❌ `Descrive il funzionamento del deck e le sue interazioni con le sessioni.`

**`inbox/` — perimetro.** Risponde a un'altra domanda: «l'area che sto per toccare ha una nozione non ancora collocata?». Più sintetico, e qui la cronaca è ammessa — il corpo deve sopravvivere alla task, il TLDR solo al file, che è temporaneo per contratto.

- ✅ `checkpoint-task · fase doc · marker di scarto sulle voci Doc Impact`
- ❌ `Nozioni emerse durante il lavoro sulla task.`

Un file inbox è **per cappello** e ogni checkpoint lo riscrive: il perimetro va allargato man mano che il file cresce, nominando le materie invece delle singole nozioni. È l'unico modo di restare sotto i 600 char quando le nozioni aggregate sono venti, e la perdita di grana è voluta — a decidere *se aprire* basta sapere che l'area è toccata.
