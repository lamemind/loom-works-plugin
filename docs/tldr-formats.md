# Formule TLDR

Due sedi: **riga 3** per i file di `reference/`, **riga 4** per i file inbox di natura `nozioni` (la riga 3 è del marker `> **INBOX**:`). `build-index.sh` copia il TLDR nell'indice così com'è, senza misurarne la lunghezza; un file di `reference/` senza riga 3 entra col solo titolo.

```markdown
# Titolo                                   # reference/
                                           #
> **TLDR**: <ancora>                       # riga 3

# Titolo                                   # inbox, natura nozioni
                                           #
> **INBOX**: nozioni · indexed · …         # riga 3 — marker
> **TLDR**: <perimetro>                    # riga 4 — opzionale
```

**`inbox/` — perimetro.** Risponde alla domanda «l'area che sto per toccare ha nozioni in un inbox?». Sintetico, e qui la cronaca è ammessa — il corpo deve sopravvivere alla task, il TLDR traccia solo il confine del file. Opzionale: l'indicizzazione la decide il marker `indexed`, e un file `indexed` senza TLDR entra nell'INDEX col solo titolo.

- ✅ `cache prompt Anthropic per subagent · prefisso cachabile · misura dai transcript`
- ❌ `Nozioni emerse durante il lavoro sulla task.`

Il TLDR di un inbox si scrive una volta, alla creazione (`inbox.sh new --tldr`), e **nessuno lo riscrive dopo** — nemmeno i checkpoint che continuano ad appendere nozioni nel file. Regge perché descrive un **perimetro**, non un contenuto: il cerchio del lavoro della task, non l'area di ciò che il file contiene adesso. Una riga che enumerasse le voci presenti sarebbe vera solo nell'istante in cui è scritta.
