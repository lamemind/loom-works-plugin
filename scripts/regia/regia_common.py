"""
regia_common — le letture condivise dai due script della regia.

`watch_sessions.py` (il monitor) e `sessions.py` (list, tail) leggono le stesse
fonti: la radice del progetto e la sua docs-root. Stanno qui, in un posto solo,
perché due copie della stessa lettura divergono alla prima correzione.

Solo libreria standard di Python: gli script girano dalla cache del plugin su
Linux e su Windows, dove nessuno installa pacchetti per loro.

Come si carica. Ogni script aggiunge la propria cartella a `sys.path` prima di
importare questo modulo: con `python -I` (modalità isolata) la cartella dello
script non entra da sola in `sys.path`, e un `import` nudo fallirebbe.
"""

import json
import os
import sys

PROJECT_CONFIG = os.path.join(".claude", "loom-works.json")


def setup_stdout():
    """Stdout in UTF-8 e a capo `\\n` su ogni piattaforma.

    Su Windows la console di default non è UTF-8, e le emoji degli eventi
    farebbero fallire la `print`. Il monitor scrive in una pipe (il tool
    Monitor di Claude Code), quindi la codifica la decide lo script.
    """
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")


def find_project_root(start):
    """La radice del progetto: la prima cartella, salendo da `start`, che
    contiene `.claude/loom-works.json`.

    Stessa regola di `lw_find_project_root` in `scripts/utils/lib.sh`, senza la
    risalita a git: un progetto loom ha sempre il suo file di configurazione.
    Senza file, `start` stesso.
    """
    current = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(current, PROJECT_CONFIG)):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return os.path.abspath(start)
        current = parent


def docs_root(project_root):
    """La docs-root del progetto: campo `docsRoot` di `.claude/loom-works.json`,
    poi `LOOM_DOCS_ROOT`, poi `docs`.

    Stessa precedenza di `lw_docs_root` in `scripts/utils/lib.sh`: il file del
    progetto vince, l'ambiente resta una via di fuga per banchi e fixture.
    """
    config_path = os.path.join(project_root, PROJECT_CONFIG)
    try:
        with open(config_path, encoding="utf-8") as config_handle:
            value = json.load(config_handle).get("docsRoot")
        if isinstance(value, str) and value:
            return value
    except (OSError, ValueError, AttributeError):
        pass
    return os.environ.get("LOOM_DOCS_ROOT") or "docs"
