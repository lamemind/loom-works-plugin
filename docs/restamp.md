CONTRATTI ATTIVI — nocciolo ri-timbrato a ogni turno contro il drift. Tetto di questo file: 4.500 char, nessuno script lo controlla — è l'unica entry a costo moltiplicativo (una volta per turno, non per sessione), quindi ogni char aggiunto si paga con uno tolto.

Le regole di scrittura e di output in chat NON stanno qui: le porta l'output style `regole-output`, che il plugin impone. Ri-timbrarle sarebbe una seconda copia in gara con quella.

DOC (doc-management.md) — quattro layer: online = la mappa, @-import in CLAUDE.md · offline = il perché e l'estraneo, {docs_root}/reference/ · → codice, si punta con file+simbolo · → fonte viva, si interroga. L'inbox ({docs_root}/inbox/) è uno STATO DI TRANSIZIONE verso i quattro, non un quinto verdetto; se contraddice reference/, vince l'inbox.
NON VA IN DOC: cronaca · intenzione · ipotesi · cantiere · scarto · eco · inventario · calco · cornice.
Al checkpoint si applicano SOLO i criteri indipendenti, quelli che si leggono nella frase. Eco, calco, inventario, sorpresa, «è già scritto altrove» e la scelta del layer dipendono da codice, fonte viva o resto della doc: si pagano allo smaltimento, non alla transizione. In inbox la ridondanza è ammessa.
Solo as-is: presente indicativo, stato corrente, niente date né task inline. Doc segue codice, stesso commit.

TASK (task-management.md) — task attiva, cascata unica: arg esplicito → $LOOM_TASK → symlink {docs_root}/current-task.md. TASK_SRC symlink = linked (git add -A), env/arg = detached (stage selettivo).
Il materiale di lavoro sta nella task folder, in project root, dot-prefixed; sotto {docs_root}/tasks/ stanno SOLO i task file .md. Mai `mkdir` a mano: set-task-folder o scratch-new.
Le nozioni che emergono si appendono a ## Doc Impact del task file, prolisse e ridondanti: il checkpoint le porta in inbox e le marca → ✔️ inbox.
