# Formule TLDR

Due sedi: **riga 3** per i file di `reference/`, **riga 4** per i file inbox di natura `nozioni` (la riga 3 è del marker `> **INBOX**:`). Il cap in char vale per entrambe le formule e vive in `lib-doc.sh` (sede unica delle soglie): la violazione è bloccante — `build-index.sh` esce non-zero e stampa la misura.

```markdown
# Titolo                                   # reference/
                                           #
> **TLDR**: <ancora>                       # riga 3

# Titolo                                   # inbox, natura nozioni
                                           #
> **INBOX**: nozioni · indexed · …         # riga 3 — marker
> **TLDR**: <perimetro>                    # riga 4 — opzionale
```

**`reference/` — non si scrive a mano.** La riga 3 è un **artefatto derivato**: la produce la skill `write-tldr` in tre stadi — raccoglitore, gate a `grep`, potatore — come ultimo passo prima di `build-index.sh`. Chi tocca il corpo di un file non tocca la riga 3, e i criteri di merito vivono nelle due attività `raccogli-tldr` e `pota-tldr` di `doc-helper`, non qui: una seconda formula scritta in questa pagina tornerebbe a essere un secondo giudice, cioè il difetto per cui il produttore unico esiste. Resta obbligatorio: senza TLDR il file resta fuori dall'INDEX.

**`inbox/` — perimetro.** Risponde a un'altra domanda: «l'area che sto per toccare ha una nozione non ancora collocata?». Più sintetico, e qui la cronaca è ammessa — il corpo deve sopravvivere alla task, il TLDR solo al file, che è temporaneo per contratto. Opzionale: l'indicizzazione la decide il marker `indexed`, e un file `indexed` senza TLDR entra nell'INDEX col solo titolo.

- ✅ `cache prompt Anthropic per subagent · prefisso cachabile · misura dai transcript`
- ❌ `Nozioni emerse durante il lavoro sulla task.`

Il TLDR di un inbox si scrive una volta, alla creazione (`inbox.sh new --tldr`), e **nessuno lo riscrive dopo** — nemmeno i checkpoint che continuano ad appendere nozioni nel file. Regge perché descrive un **perimetro**, non un contenuto: il cerchio del lavoro della task, non l'area di ciò che il file contiene adesso. Una riga che enumerasse le voci presenti sarebbe vera solo nell'istante in cui è scritta.
