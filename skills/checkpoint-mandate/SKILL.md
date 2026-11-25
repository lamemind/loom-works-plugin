---
name: checkpoint-mandate
description: Nome di prima di `checkpoint-perimeter`, tenuto come inoltro — invoca `checkpoint-perimeter` con gli stessi argomenti. Si usa solo quando un chiamante scrive ancora questo nome.
argument-hint: "<epica|lista custom> [chiudi]"
disable-model-invocation: true
allowed-tools: Skill
---

Argomenti:
~~~human
$ARGUMENTS
~~~

`checkpoint-mandate` è il nome di prima di `checkpoint-perimeter`. Il nome resta perché chi l'ha imparato prima del rename lo scrive ancora: l'utente, una conversazione aperta da un'altra versione del plugin, il report di una skill di prima che lo cita.

Invoca subito il tool `Skill` con `skill` = `loom-works:checkpoint-perimeter` e `args` = gli argomenti qui sopra, copiati tali e quali, anche vuoti. Non leggere niente prima e non aggiungere niente: da lì in poi valgono le istruzioni di `checkpoint-perimeter`.
