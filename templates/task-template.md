# Task: {{Descrizione_breve}}

- **ID**: {{taskId}}
- **Created on**: {{data_corrente}}
- **Priority**: {{priorita_raccolta}}
- **Estimated Time**: {{durata_standard}}
- **Size**: {{size}}
- **Lane**: {{lane}}
- **Folder**:
- **Progress**: 🔵 Todo
- **Last tracked commit**:

## Description
{{descrizione_dettagliata}}

## Acceptance Criteria
{{criteri_accettazione_raccolti}}

## Dependencies
{{dipendenze_raccolte}}

## Deliverables Checklist
{{checklist_deliverables_raccolta}}

## Implementation Notes
*Note tecniche e considerazioni implementative*

## Testing Notes
*Criteri di test e validazione*

## Doc Impact
*Nozioni documentali emerse nella conversazione o durante l'esecuzione. Ogni voce: **nozione** (cosa merita documentazione) + **ancora primaria** (trigger concreto: tag, keyword, comando, pattern). Il target doc NON si decide qui — è deferito al processing. Popolata a create-task dal contesto conversazionale; append libero a run-task; **processing a checkpoint-task con gate morbido**: per ogni voce non marcata, l'utente sceglie capture-doc inline / crea D-task / skip. Voci consolidate appendono marker `→ ✔️ capture` o `→ ✔️ D{N}` e saltano i checkpoint successivi.*

{{doc_impact}}

## Prod Validation
*Attivita di test e verifica da eseguire in produzione post-deploy. Questa sezione NON blocca il completamento della task.*
