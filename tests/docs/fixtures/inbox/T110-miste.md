# T110 — deck modello per conversazione

> **INBOX**: nozioni · drainable

- **n1** — Il campo `model` di un transcript porta id versionati e alias mescolati nello stesso file, e la normalizzazione va fatta sul token di famiglia alla resa, mai nel modello dati: il valore grezzo resta la fonte. Ancora: colonna modello nella lista sessioni del deck.
  - router → reference/loom-deck/loom-deck-sessions.md — la pagina possiede già il blocco preview della sessione, e la colonna modello ne è un campo
- **n2** — I record assistant sintetici (`<synthetic>`) vanno esclusi dal conteggio dei turni o il contatore mente su ogni sessione con errori API. Ancora: contatore turni del deck.
- **n3** — Due last-wins nello stesso ciclo di parse si mascherano a vicenda: `customTitle` e `model` vanno raccolti in passate separate o il secondo sovrascrive il primo su file fusi da un fork. Ancora: parse del transcript store.
  - router ✖️ noto: K3 javascript dichiarato dal progetto — pattern di riduzione standard su stream di record
