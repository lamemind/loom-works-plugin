# T120 — rebalance-doc su branch

> **INBOX**: nozioni · indexed · branch:feat/rebalance-doc
> **TLDR**: la topologia come skill unica — split, merge e regroup sono cross-file e nessun attore del drain li può fare; ordine vincolante split → merge → group.

- **n1** — La topologia è una skill unica perché split, merge e regroup sono operazioni cross-file, e nessun attore del drain — che lavora un file alla volta — le può eseguire. Ancora: `rebalance-doc`.
- **n2** — L'ordine split → merge → group è vincolante: gli split cambiano i conteggi di tutto il resto, e un merge deciso prima dello split misura file che non esisteranno più. Ancora: fase di misura di `rebalance-doc`.
