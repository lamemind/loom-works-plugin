CONTRATTI ATTIVI — nocciolo ri-timbrato a ogni turno contro il drift.

DOC (doc-management.md) — quattro layer: online = la mappa, @-import in CLAUDE.md · offline = il perché e l'estraneo, {docs_root}/reference/ · → codice, si punta con file+simbolo · → fonte viva, si interroga. L'inbox ({docs_root}/inbox/) è uno STATO DI TRANSIZIONE verso i quattro, non un quinto verdetto; se contraddice reference/, vince l'inbox — e se porta branch:, solo per chi lavora su quel branch.
NON VA IN DOC: cronaca (cosa è successo, in ordine) · intenzione · ipotesi · cantiere · scarto · eco · inventario · calco (una cifra o una classifica ricopiata da una fonte che si muove) · cornice (il testo che annuncia il testo).
Al riesame e al trasloco si applicano SOLO i criteri indipendenti, quelli che si leggono nella frase. Eco, calco, inventario, sorpresa, «è già scritto altrove» e la scelta del layer dipendono da codice, fonte viva o resto della doc: li paga il drain, non la transizione.
Solo as-is DI PROD: presente indicativo, stato corrente, niente date né task inline. La doc segue il RILASCIO, non il commit.

TASK (task-management.md) — task attiva, cascata unica: arg esplicito → $LOOM_TASK → symlink {docs_root}/current-task.md. TASK_SRC symlink = linked (git add -A), env/arg = detached (stage selettivo).
Il materiale di lavoro sta nella task folder, in project root, dot-prefixed; sotto {docs_root}/tasks/ stanno SOLO i task file .md. Il nome lo assegna set-task-folder (o scratch-new) nel campo **Folder**, mai a mano; la folder non esiste finché non ci scrivi il primo file.
Le nozioni che emergono si appendono a ## Doc Impact del task file, e lì restano VIVE: ogni checkpoint le RIESAMINA — riscrivile o eliminale quando il codice le smentisce, nessun marker di esito. Scrivi il fatto per esteso — il perché, e le condizioni in cui vale — mai compresso in un aforisma: chi lo smaltisce non ha in memoria la conversazione che lo ha prodotto, e da una frase ellittica non può ricostruirlo. La ridondanza ammessa è FRA voci: ripetere un fatto già scritto altrove va bene, gonfiare la singola voce di cronaca o di cornice no. Il trasloco in inbox è del checkpoint — al rilascio o alla chiusura, subito per le nozioni di mondo.

# Reminder regole di output CHAT

Vale per il testo che scrivi in chat, non per i file su disco.

- Rispondi **in parole povere**
- **Onora la direttiva del raggio**, sempre. Assumi [R0] quando non esplicitata nel prompt utente
- Niente cornici, a nessun livello. **Un aggancio DICE la cosa**, non la annuncia — «I metadati EXIF spariscono nel ridimensionamento», mai «La cosa che si perde per sbaglio».
- Evita riepiloghi finali o offrire step successivi. Quando hai finito di rispondere alla domanda utente hai finito, non devi aggiungere altro.
