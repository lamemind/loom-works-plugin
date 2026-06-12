# Doc Task: {{Descrizione_breve}}

- **ID**: {{taskId}}
- **Created on**: {{data_corrente}}
- **Priority**: {{priorita_raccolta}}
- **Estimated Time**: {{durata_standard}}
- **Lane**: {{lane}}
- **Parent Task**: {{parent_task}}
- **Progress**: 🔵 Todo
- **Last tracked commit**:

## Description

{{descrizione_dettagliata}}

## Target

*Lista strutturata dei file/aree doc da toccare. Per ognuno: path, livello (online/offline), azione prevista (drift/extend/create). Separa il **dove metto le mani** dal **cosa consegno approvato** (quest'ultimo è in Deliverables Checklist). Può essere raffinato in corso d'esecuzione.*

{{target_raccolto}}

## Acceptance Criteria

{{criteri_accettazione_raccolti}}

## Deliverables Checklist

*Sezioni di doc approvate (aggiornate o create). Cosa deve essere presente e approvato a fine task.*

{{checklist_deliverables_raccolta}}

## Fonti

*Lista bullet libera: file sorgente, commit, link esterni, riferimenti conversazionali. Materiale grezzo che alimenta la doc.*

{{fonti_raccolte}}

## Execution

*Stato del workflow a giri. Popolata da `/loom-works:run-doc` giro per giro. Forma definita in `plugins/loom-works/DESIGN.md` §7.*

<!--
Ogni chunk è una sottosezione H3 diretta:

### Chunk 1 — <scope descrittivo libero>
**Status**: pending | done | blocked
**Round**: r1, r2, ...

<spazio libero: note editoriali, decisioni prese, TBD emersi.
Se blocked:>
**Block reason**: <motivo>
**Unblock action**: <cosa deve fare l'utente per sbloccare>
-->

### Rounds

*Log cronologico: 1-2 righe per round.*

### Resume context

*Prosa 2-5 righe con decisioni cross-chunk (stile adottato, convenzioni, rimandi). Duplice scopo: cold-restart della skill dopo `/clear` dell'utente + briefing per ogni `doc-writer` Agent sui chunk successivi.*
