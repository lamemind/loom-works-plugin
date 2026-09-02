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
*Chi cattura (`create-task`, `preflight-task`, `run-task`, il modello in chat) scrive: **nozione + ancora primaria**. La voce resta VIVA e ogni checkpoint la RIESAMINA: si riscrive o si elimina finché la task è attiva, nessun marker di esito, nessuna attesa.*
*Il primo `checkpoint-task` con voci da spostare le trasloca nell'inbox della task e lascia qui `→ inbox <file> · storia: <sha>`. **Da quel momento le nozioni nuove si scrivono nell'inbox, non qui**: la sede è una sola, e questa riga dice quale.*

{{doc_impact}}

## Prod Validation
*Attivita di test e verifica da eseguire in produzione post-deploy. Questa sezione NON blocca il completamento della task.*
