# Reference Index

Indice della documentazione offline.

## (root)

- `assumed-knowledge.md` — competenza assunta del lettore della doc di progetto — set settore: grado, chiave default, catena di risoluzione settore → default → K2.
- `cita.md` — pagina sorgente della fixture NOSECTION — cita nel fratello una sezione che non esiste.
- `citato.md` — pagina bersaglio della fixture NOSECTION — porta una sezione reale e nessuna sezione fantasma.
- `grande.md` — fixture sopra la soglia di split — contenuto ripetuto fino a superare il tetto.
- `normale.md` — cascata di risoluzione della task attiva — arg esplicito, poi env di sessione, poi symlink di worktree; la provenienza decide linked contro detached.
- `tldr-lungo.md` — perimetro di ricerca ripetuto 1 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 2 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 3 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 4 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 5 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 6 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 7 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 8 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 9 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 10 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 11 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 12 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 13 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 14 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 15 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 16 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 17 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 18 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 19 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 20 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 21 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 22 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 23 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 24 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 25 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 26 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 27 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 28 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 29 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 30 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 31 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 32 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 33 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 34 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 35 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 36 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 37 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 38 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 39 volte per superare il cap del riassunto; perimetro di ricerca ripetuto 40 volte per superare il cap del riassunto;

## inbox — nozioni non ancora collocate

> Precedenza: in caso di contraddizione con un file di `reference/`, **prevale la voce inbox** — descrive un rilascio che la doc consolidata non ha ancora assorbito.

- `T109-cache-anthropic.md` — comportamento della cache prompt Anthropic per i subagent Claude Code — cosa sta nel prefisso cachabile (body dell'agent) e cosa no (prompt d'invocazione, contesto progetto), minimi per modello, TTL, fan-out, fork, e come misurare dai transcript.
- `T109-cache-completo.md` — comportamento della cache prompt Anthropic per i subagent Claude Code — cosa sta nel prefisso cachabile (body dell'agent) e cosa no (prompt d'invocazione, contesto progetto), minimi per modello, TTL, fan-out, fork, e come misurare dai transcript.
- `T109-cache-verdetti.md` — comportamento della cache prompt Anthropic per i subagent Claude Code — cosa sta nel prefisso cachabile (body dell'agent) e cosa no (prompt d'invocazione, contesto progetto), minimi per modello, TTL, fan-out, fork, e come misurare dai transcript.
- `T112-indexed-notldr.md` — *T112 — invocare una skill del plugin in headless dal deck*

## inbox — branch `feat/pull`

> As-is di uno sviluppo, non di prod: vale **solo lavorando su `feat/pull`**, e per chi sta su prod non ha nessuna precedenza sulla doc consolidata.

- `T121-branch-drainable.md` — `.gitmodules` come unico registro dei submodule; lo sblocco di un inbox `branch:` è una constatazione (il file sta su main), non un confronto di liste.

## inbox — branch `feat/rebalance-doc`

> As-is di uno sviluppo, non di prod: vale **solo lavorando su `feat/rebalance-doc`**, e per chi sta su prod non ha nessuna precedenza sulla doc consolidata.

- `T120-branched.md` — la topologia come skill unica — split, merge e regroup sono cross-file e nessun attore del drain li può fare; ordine vincolante split → merge → group.
