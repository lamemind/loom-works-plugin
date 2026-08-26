# Pagina normale — resolve della task attiva

> **TLDR**: cascata di risoluzione della task attiva — arg esplicito, poi env di sessione, poi symlink di worktree; la provenienza decide linked contro detached.

La task attiva si risolve con una cascata sola per ogni consumer: l'argomento esplicito dell'invocazione, poi la variabile d'ambiente di sessione, poi il symlink del worktree. L'argomento sta in cima perché una sessione già vincolata deve poter chiedere un'altra task; l'ambiente batte il symlink perché N sessioni parallele nello stesso worktree ne condividono uno solo, e quale delle N sei tu lo sa solo l'ambiente.

La provenienza non è cosmetica: decide il regime di staging. Un binding di worktree significa che tutto il movimento del repo appartiene alla task, quindi lo stage può essere globale; un binding di sessione significa che il repo si muove anche per mano d'altri, quindi ogni commit porta la propria pathspec e lo stage altrui resta in stage.

La cascata è implementata una volta sola nella libreria condivisa, e chi non può sourcare bash — il markdown di una skill — usa il wrapper CLI gemello. Restituisce tre valori: l'id della task, il path assoluto del task file, e la provenienza. Il wrapper stampa righe eval-abili coi valori quotati, così un path con spazi non rompe il chiamante.

Il symlink del worktree non va mai importato nel contesto di sessione in parallelo all'iniezione: entrerebbe in conflitto con la task iniettata dall'hook, e una sessione con l'ambiente settato vedrebbe due task attive divergenti — quella iniettata e quella stale del worktree. Un solo canale scrive la task in contesto, ed è l'hook di avvio sessione.

Lo start della task rifiuta di girare quando l'ambiente è già settato, anche sullo stesso id: scriverebbe un symlink che la sessione corrente ignora, cioè esattamente lo stale che la cascata esiste per non produrre. Il rifiuto è un errore dichiarato, non un no-op silenzioso: chi lo incontra deve sapere che il binding di sessione possiede la task, e che il symlink appartiene a un altro regime.

La risoluzione per un consumer esterno — il deck, la statusline — segue la stessa cascata ma con un vincolo in più: fuori da un processo di sessione l'ambiente non esiste, quindi il fallback al symlink è la norma e non l'eccezione. Un consumer che legge solo l'ambiente mostra il vuoto su ogni progetto in cui nessuna sessione è viva, e un consumer che legge solo il symlink mente dentro le sessioni spawnate con un binding proprio. La cascata intera è l'unico modo di dire la verità in entrambi i regimi.

Il caso degenere è il progetto senza task attiva: nessun argomento, nessun ambiente, nessun symlink. La cascata esce non-zero e il chiamante decide — chiedere all'utente quale task eseguire è la risposta giusta per una skill interattiva, degradare a vuoto è quella giusta per un widget. Nessuno dei due indovina: la cascata non ha un default, perché un default sarebbe una task inventata.
