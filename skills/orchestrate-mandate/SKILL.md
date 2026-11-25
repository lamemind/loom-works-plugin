---
name: orchestrate-mandate
description: Nome di prima di `orchestrate-perimeter`, tenuto come inoltro — invoca `orchestrate-perimeter` con gli stessi argomenti. Si usa solo quando un chiamante scrive ancora questo nome, come un deck installato prima del rename.
argument-hint: "<epica|lista custom> [--soglia <token>]"
disable-model-invocation: true
allowed-tools: Skill
---

Argomenti:
~~~human
$ARGUMENTS
~~~

`orchestrate-mandate` è il nome di prima di `orchestrate-perimeter`. Il nome resta perché un chiamante esterno lo scrive ancora: il deck apre l'orchestrator, e il successore di un passaggio di consegne, dalla riga `orchestrator` del suo `scripts/prompt-catalog`, ed esce da npm separato dal plugin, quindi un deck installato prima del rename chiama ancora questo nome.

Invoca subito il tool `Skill` con `skill` = `loom-works:orchestrate-perimeter` e `args` = gli argomenti qui sopra, copiati tali e quali, anche vuoti. Non leggere niente prima e non aggiungere niente: da lì in poi valgono le istruzioni di `orchestrate-perimeter`.
