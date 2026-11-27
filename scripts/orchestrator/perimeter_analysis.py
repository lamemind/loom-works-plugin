"""
perimeter_analysis — il piano di un perimetro orchestrabile contro git.

Le letture di git che `orchestration_schedule.py verify` fa sul piano
(`orchestration-schedule.md`, contratto `docs/orchestration-schedule-format.md`):
la radice del repo, il path relativo di
un file, e i membri aperti il cui task file è cambiato dopo il commit del
piano, gli unici che l'orchestrator rilegge al lancio. L'analisi delle relazioni
fra i membri sta nella prosa del piano, e nessuno script la confronta: il
confronto con i file lo fa `orchestration_schedule.py` sui campi del blocco JSON.

Il modulo non importa niente del plugin: la dipendenza va in un verso solo,
da `orchestration_schedule.py` a qui.
"""

import os
import re
import subprocess

TASK_FILE_NAME = re.compile(r"^(T\d+)-.*\.md$")

# ---------------------------------------------------------------------------
# La storia: i membri cambiati dopo il commit del piano
# ---------------------------------------------------------------------------


def git(top, *arguments):
    """stdout di un comando git, `None` se esce non-zero o git non c'è."""
    try:
        completed = subprocess.run(["git", "-C", top, *arguments], capture_output=True,
                                   encoding="utf-8", errors="replace", check=False)
    except OSError:
        return None
    return completed.stdout if completed.returncode == 0 else None


def repository_top(project_root):
    output = git(project_root, "rev-parse", "--show-toplevel")
    return os.path.normpath(output.strip()) if output else None


def relative_to(top, path):
    """Il path relativo alla radice del repo, con le due radici normalizzate
    prima del confronto. Git stampa la radice risolta: su Windows col nome
    lungo anche quando la radice del progetto arriva col nome breve 8.3
    (`ENRICO~1`), su Linux coi symlink sciolti. Senza la normalizzazione il
    path relativo esce dal repo, `git show HEAD:<path>` non trova niente e
    un piano committato risulta non committato."""
    return os.path.relpath(os.path.realpath(path), os.path.realpath(top)).replace(os.sep, "/")


def changed_members(top, tasks_rel, commit, open_members):
    """id → `modificato` | `nuovo` per i membri aperti il cui task file è
    cambiato fra il commit del piano e HEAD. Un file nato dopo è `nuovo`:
    le sue coppie l'analisi del piano non le ha mai viste. Un rename resta lo
    stesso membro. Le modifiche non committate non contano: sono il lavoro in corso
    di un'altra sessione, non ancora un fatto."""
    output = git(top, "diff", "--name-status", "-M", commit, "HEAD", "--", tasks_rel)
    changed = {}
    for line in (output or "").splitlines():
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        status = fields[0][:1]
        match = TASK_FILE_NAME.match(os.path.basename(fields[-1]))
        if not match or match.group(1) not in open_members or status == "D":
            continue
        changed[match.group(1)] = "nuovo" if status == "A" else "modificato"
    return changed
