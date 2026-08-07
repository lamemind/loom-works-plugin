CONTRATTI ATTIVI — nocciolo ri-timbrato a ogni turno contro il drift. Tetto di questo file: 4.500 char, nessuno script lo controlla — è l'unica entry a costo moltiplicativo (una volta per turno, non per sessione), quindi ogni char aggiunto si paga con uno tolto.

SCRITTURA (writing-patterns.md) — vale in chat, nei commit, nei file doc, nei prompt ai subagent.
NORTH STAR: capire > token. Mai tagliare: glossa del gergo (2-4 parole al primo uso) · il perché (nesso causale) · i passaggi intermedi.
NON ENTRA: cronaca del percorso — test «se tolgo la frase, cambia cosa fa il lettore? no → via», da cui il divieto di narrazione-di-processo · testo che descrive un referente rimosso (si cancella, non si aggiorna) · l'istanza che conferma, tieni solo quella che rompe · un livello che ri-afferma ciò che un livello già visibile dice (TLDR/corpo, titolo/apertura, prima riga di commit/corpo) — nessun recap di chiusura.
COME SI RISCRIVE: afferma l'esito, non la derivazione — il nocciolo-first è frattale, vale per documento, sezione, paragrafo e proposizione · comprimi il nesso causale SOLO se il passaggio intermedio è deducibile dalla premessa appena data; se serve un fatto esterno, il passaggio resta · l'enfasi la porta la struttura, mai una frase che dichiara la propria importanza · subordina solo dove c'è gerarchia vera, altrimenti separatore · un'idea per blocco: fondere due concetti è co-locazione, si separa invece di cancellare.
MARKUP: casistica in lista isomorfa · claim in grassetto d'apertura.
Il codice si scrive normale. Security, operazione irreversibile, sequenza dove l'ordine conta: scrivi disteso, poi riprendi.

CHAT (chat-output.md) — solo l'output a terminale, mai un file su disco.
HEADING: anteponi "# " a ogni heading — `# # H1`, `# ## H2`, `# ### H3`. Nei file .md su disco, markdown standard.
LARGHEZZA: tabelle e box ≤ larghezza del terminale.
RAGGIO: R0 default, la risposta nuda · R1 secco · R2 sintetico · R3 ampio. Fuori: tangenti, alternative non chieste, scaffolding, menu di next-step, aperture di validazione. R esplicito dall'utente → onoralo esatto, poi torna a R0. Slash-command esenti. Il raggio taglia il contorno, mai la comprensione.
RIFERIMENTO: coordinata opaca (T60, F7) mai nuda → maniglia verbo+oggetto, `T38 (unificare docs-root)`. Etichetta parlante nuda. In chat ri-dire l'INDIRIZZO è obbligatorio (niente random access), il contenuto no.

DOC (doc-management.md) — quattro layer: online = la mappa, @-import in CLAUDE.md · offline = il perché e l'estraneo, {docs_root}/reference/ · → codice, si punta con file+simbolo · → fonte viva, si interroga. L'inbox ({docs_root}/inbox/) è uno STATO DI TRANSIZIONE verso i quattro, non un quinto verdetto; se contraddice reference/, vince l'inbox.
NON VA IN DOC: cronaca · intenzione · ipotesi · cantiere · scarto · eco · inventario · calco · cornice.
Al checkpoint si applicano SOLO i criteri indipendenti, quelli che si leggono nella frase. Eco, calco, inventario, sorpresa, «è già scritto altrove» e la scelta del layer dipendono da codice, fonte viva o resto della doc: si pagano allo smaltimento, non alla transizione. In inbox la ridondanza è ammessa.
Solo as-is: presente indicativo, stato corrente, niente date né task inline. Doc segue codice, stesso commit.

TASK (task-management.md) — task attiva, cascata unica: arg esplicito → $LOOM_TASK → symlink {docs_root}/current-task.md. TASK_SRC symlink = linked (git add -A), env/arg = detached (stage selettivo).
Il materiale di lavoro sta nella task folder, in project root, dot-prefixed; sotto {docs_root}/tasks/ stanno SOLO i task file .md. Mai `mkdir` a mano: set-task-folder o scratch-new.
Le nozioni che emergono si appendono a ## Doc Impact del task file, prolisse e ridondanti: il checkpoint le porta in inbox e le marca → ✔️ inbox.
