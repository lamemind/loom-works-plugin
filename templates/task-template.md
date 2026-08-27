# Task: {{Descrizione_breve}}

- **ID**: {{taskId}}
- **Created on**: {{data_corrente}}
- **Priority**: {{priorita_raccolta}}
- **Estimated Time**: {{durata_standard}}
- **Size**: {{size}}
- **Lane**: {{lane}}
- **Parent Task**:
- **Branch**:
- **Folder**:
- **Progress**: 🔵 Todo

## Description
{{descrizione_dettagliata}}

## Acceptance Criteria
{{criteri_accettazione_raccolti}}

## Dependencies
{{dipendenze_raccolte}}

## Deliverables Checklist
*Numerati **posizionalmente 1-based** sulle sole checkbox a colonna zero — è così che `run-task` li indirizza (`--scope "1,3-5"`). Le righe indentate sono prosa di una voce, non voci: aggiungerne non sposta la numerazione.*

{{checklist_deliverables_raccolta}}

## Materiale
*📖 fonte · 🔬 analisi · 📤 prodotto; 📁/ = task folder. Solo materiale di alto rilievo, non l'inventario della folder.*

## Implementation Notes
*Note tecniche e considerazioni implementative*

## Testing Notes
*Criteri di test e validazione*

## Doc Impact
*Chi cattura (`create-task`, `preflight-task`, `run-task`) scrive: **nozione + ancora primaria**. La voce resta qui VIVA (clessidra): si riscrive o si elimina finché la task è attiva, nessun marker di esito, nessuna attesa.*
*Il trasloco in inbox è del `checkpoint-task` — subito per le nozioni di mondo, al rilascio per la feature rilasciata, alla chiusura per tutto — e al posto delle voci lascia `→ inbox <file> · storia: <sha>`.*

{{doc_impact}}

## Prod Validation
*Attivita di test e verifica da eseguire in produzione post-deploy. Questa sezione NON blocca il completamento della task.*
