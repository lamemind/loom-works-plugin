# Registro ADR — interroga prima di risollevare

Lo **scarto motivato** di una segnalazione è una decisione, e vive nel registro: `{docs_root}/adr/`, un record per file, immutabile. Non è doc e non è un task file — nessun altro canale lo porta in contesto e non esiste un indice: si interroga.

**Interroga prima di risollevare.** Prima di riportare segnalazioni a fine analisi o a fine implementazione, cerca nel registro i path che toccano e le parole che le nominano:

```bash
{PLUGIN_ROOT}/scripts/task/adr.sh cerca <path|keyword|Tnn>
```

Exit `0` = esiste già un record: quella segnalazione è stata scartata con un motivo, **taci** invece di ridecidere. Exit `2` = nessuno, riportala.

**Registra lo scarto.** Quando una segnalazione viene scartata, da te o dall'utente, scrivila subito — uno scarto senza registro non è uno scarto, è un rinvio, e al giro dopo la stessa segnalazione torna e va ridecisa:

```bash
{PLUGIN_ROOT}/scripts/task/adr.sh scarta --slug <slug> --chi umano|agente|delega \
  --segnalazione "<cosa>" --ancora <path> --perche "<perché>" [--delega "<parole>"]
```

`--chi` non ha default: `umano` se la decisione è dell'utente, `agente` se è tua, `delega` se la prendi su una delega che l'utente ti ha dato — e allora `--delega` porta le sue parole, alla lettera. Committa da sé; `--no-commit` per chi batcha. Un record non si riscrive: una decisione superata si marca con un record nuovo che la nomina in `--supera`.

Campi, supersessione e sede: `{PLUGIN_ROOT}/docs/adr-format.md`.
