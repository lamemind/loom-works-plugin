# Task: {{Descrizione_breve}}

- **ID**: {{taskId}}
- **Created on**: {{data_corrente}}
- **Priority**: {{priorita_raccolta}}
- **Estimated Time**: {{durata_standard}}
- **Size**: {{size}}
- **Lane**: {{lane}}
- **Parent Task**:
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
*Chi cattura (`create-task`, `preflight-task`, `run-task`) scrive: **nozione + ancora primaria**; se una pagina in esercizio diventa falsa aggiungere `🚨 drift: <path>`.*
*`⏳ <evento di sblocco>` lo scrive chiunque, per trattenere una nozione il cui referente non è ancora materializzato (`⏳ publish`, `⏳ deploy`, `⏳ F7`): è l'unico marker non terminale.*
*Solo `checkpoint-task` marca l'esito — `→ ✔️ inbox` · `→ ✖️ <parola>` — e sono terminali: scriverli qui significa che nessuno ripassa più sulla voce.*

{{doc_impact}}

## Prod Validation
*Attivita di test e verifica da eseguire in produzione post-deploy. Questa sezione NON blocca il completamento della task.*
