# Task: {{Descrizione_breve}}

- **ID**: {{taskId}}
- **Created on**: {{data_corrente}}
- **Priority**: {{priorita_raccolta}}
- **Estimated Time**: {{durata_standard}}
- **Size**: {{size}}
- **Lane**: {{lane}}
- **Folder**:
- **Progress**: 🔵 Todo

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
*Nozioni documentali emerse nella conversazione o durante l'esecuzione. Ogni voce: **nozione** (cosa merita documentazione) + **ancora primaria** (trigger concreto: tag, keyword, comando, pattern). Il target doc NON si decide qui — lo decide `drain-doc`, in differita. Popolata a create-task dal contesto conversazionale; append libero a run-task; **processing a checkpoint-task, senza gate**: ogni voce non marcata passa i soli criteri indipendenti e finisce in `{docs_root}/inbox/`, poi porta il marker `→ ✔️ inbox` (entrata) o `→ ✖️ <parola>` (scartata). Una voce marcata salta i checkpoint successivi; una senza marker resta pescabile da `align-doc` sul perimetro task.*

{{doc_impact}}

## Prod Validation
*Attivita di test e verifica da eseguire in produzione post-deploy. Questa sezione NON blocca il completamento della task.*
