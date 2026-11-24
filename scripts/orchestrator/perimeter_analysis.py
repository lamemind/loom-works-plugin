"""
perimeter_analysis — l'analisi scritta di un perimetro contro i file e contro git.

La sezione `## Analisi del perimetro` di un'epica o di un mandato ha due metà
(contratto: `docs/mandate-format.md`, metodo: `docs/mandate-analysis.md`):

  - le righe `dichiarata` e `materiale`, che si ricalcolano dai file: sono le
    righe `CONFLICT` di `mandate.py tree`, e qui si confrontano con loro;
  - le righe `modello`, che vengono da una lettura dei task file dei membri e
    nessun calcolo rifà: qui si restituiscono, perché l'orchestrator le conti come
    le `CONFLICT` quando decide chi parte insieme.

Poi la storia: il commit da cui l'analisi vale e i membri il cui task file è
cambiato dopo, gli unici che l'orchestrator rilegge al lancio.

Il modulo non importa `mandate.py`: riceve lo stato già calcolato da `snapshot`
(un dict) e le righe del task file, e restituisce dati. La dipendenza va in un
verso solo, da `mandate.py` a qui.
"""

import os
import re
import subprocess

ANALYSIS_HEADING = "Analisi del perimetro"
MEMBERS_HEADING = "Membri"
TASK_REFERENCE = re.compile(r"(?<![A-Za-z0-9·_])T(\d+)(?!\d)")
BACKTICKED = re.compile(r"`([^`]+)`")
ARROWS = ("→", "->")
RELATIONS = ("dipende", "collide")
SOURCES = ("dichiarata", "materiale", "modello")
PROGRESS_ENTRY = re.compile(r"^###\s+Avanzamento\s+(\d+)")
TASK_FILE_NAME = re.compile(r"^(T\d+)-.*\.md$")

# ---------------------------------------------------------------------------
# La sezione e la tabella
# ---------------------------------------------------------------------------


def section_bounds(lines, heading):
    """(inizio, fine) della sezione `## <heading>`, indici 0-based con la fine
    esclusa; `None` se la sezione non c'è. La sezione finisce al prossimo `## `
    o alla fine del file: una sezione in coda al file è la forma di ogni
    mandato appena creato."""
    start = None
    for index, line in enumerate(lines):
        if not line.startswith("## "):
            continue
        if start is not None:
            return start, index
        if line[3:].strip().lower().startswith(heading.lower()):
            start = index
    return (start, len(lines)) if start is not None else None


def section_text(lines, heading):
    bounds = section_bounds(lines, heading)
    return None if bounds is None else "\n".join(lines[bounds[0]:bounds[1]]).rstrip()


def parse_rows(lines):
    """Le righe della tabella dell'analisi: una per riga `|` che non sia
    l'intestazione o il separatore. Ogni riga è un dict con la coppia, gli id,
    il verso, la relazione, `Su cosa` e la fonte; `problem` dice perché una
    riga non ha la forma del contratto."""
    bounds = section_bounds(lines, ANALYSIS_HEADING)
    rows = []
    if bounds is None:
        return rows
    for line in lines[bounds[0] + 1:bounds[1]]:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if not cells or cells[0].lower() == "coppia" or set(cells[0]) <= set("-: "):
            continue
        pair = cells[0]
        ids = [f"T{number}" for number in TASK_REFERENCE.findall(pair)]
        row = {"pair": pair, "ids": ids, "directed": any(arrow in pair for arrow in ARROWS),
               "relation": cells[1].lower() if len(cells) > 1 else "",
               "what": cells[2] if len(cells) > 2 else "",
               "source": cells[3].lower() if len(cells) > 3 else "", "problem": ""}
        if len(cells) < 4:
            row["problem"] = "meno di quattro colonne"
        elif len(ids) != 2 or ids[0] == ids[1]:
            row["problem"] = "la coppia non nomina due task"
        elif row["relation"] not in RELATIONS:
            row["problem"] = f"relazione «{cells[1]}» fuori dominio"
        elif row["source"] not in SOURCES:
            row["problem"] = f"fonte «{cells[3]}» fuori dominio"
        rows.append(row)
    return rows


def normalize_path(path):
    path = path.strip()
    for prefix in ("🏠/", "./"):
        if path.startswith(prefix):
            path = path[len(prefix):]
    return path


# ---------------------------------------------------------------------------
# Il confronto meccanico
# ---------------------------------------------------------------------------


def compare(state, rows):
    """Le differenze fra la tabella e il calcolo di `tree`, e le righe `modello`.

    Una riga che nomina un membro chiuso non conta: `tree` tace sulle task
    chiuse, e la riga resta scritta finché qualcuno non riscrive la sezione.
    Una riga che nomina una task che non è un membro, e non è chiusa, è una
    differenza: il perimetro è cambiato e l'analisi no.
    """
    tasks = state["tasks"]
    members = state["mandate"]
    still_open = [task_id for task_id in members if tasks[task_id]["next"] != "chiusa"]
    open_set = set(still_open)

    def is_closed(task_id):
        if task_id in tasks:
            return tasks[task_id]["next"] == "chiusa" or tasks[task_id]["prog"] == "✔"
        return state["overview"].get(task_id, ("", ""))[0].replace("️", "").strip() == "✔"

    expected_edges = {}
    for task_id in still_open:
        for dependency in tasks[task_id]["dependencies"]:
            if dependency["id"] in open_set:
                expected_edges[(task_id, dependency["id"])] = False
    expected_material = {}
    for conflict in state["conflicts"]:
        if conflict["reason"].startswith("materiale: "):
            paths = conflict["reason"][len("materiale: "):].split(", ")
            expected_material[frozenset(conflict["tasks"])] = {"pair": conflict["tasks"], "paths": paths, "cited": set()}

    differences = []
    model_rows = []
    for row in rows:
        if row["problem"]:
            differences.append(("forma", row["pair"], row["problem"]))
            continue
        first, second = row["ids"]
        if is_closed(first) or is_closed(second):
            continue
        outsiders = [task_id for task_id in row["ids"] if task_id not in open_set]
        if outsiders:
            differences.append(("fuori", row["pair"], f"{', '.join(outsiders)} non è un membro aperto del perimetro"))
            continue
        if row["source"] == "modello":
            model_rows.append((first, second, row["what"]))
            continue
        if row["source"] == "dichiarata":
            candidates = [(first, second)] if row["directed"] else [(first, second), (second, first)]
            hits = [edge for edge in candidates if edge in expected_edges]
            if hits:
                for edge in hits:
                    expected_edges[edge] = True
            else:
                differences.append(("in più", row["pair"], "dichiarata: tree non calcola questa dipendenza"))
            continue
        entry = expected_material.get(frozenset((first, second)))
        if entry is None:
            differences.append(("in più", row["pair"], "materiale: tree non calcola questa collisione"))
            continue
        entry["cited"].update(normalize_path(path) for path in BACKTICKED.findall(row["what"]))
        entry["matched"] = True

    for (task_id, dependency), matched in expected_edges.items():
        if not matched:
            differences.append(("manca", f"{task_id} → {dependency}", "dichiarata: dipendenza senza riga"))
    for entry in expected_material.values():
        pair = f"{entry['pair'][0]} · {entry['pair'][1]}"
        if not entry.get("matched"):
            differences.append(("manca", pair, "materiale: " + ", ".join(entry["paths"])))
            continue
        missing = [path for path in entry["paths"] if path not in entry["cited"]]
        if missing:
            differences.append(("manca", pair, "materiale, path non citato: " + ", ".join(missing)))
    return differences, model_rows


# ---------------------------------------------------------------------------
# La storia: il commit dell'analisi e i membri cambiati dopo
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
    return os.path.relpath(os.path.abspath(path), top).replace(os.sep, "/")


def analysis_commit(top, rel, working_lines):
    """Il commit da cui l'analisi vale, e da dove viene: `(sha, fonte, motivo)`.

    Vale il più recente fra l'ultimo commit che ha cambiato le righe della
    sezione e il commit dell'ultimo `### Avanzamento N` del Progress Log, cioè
    l'ultimo giro di `checkpoint-mandate`, che per contratto riverifica
    l'analisi: dopo un giro senza modifiche i membri sono già riverificati.

    Le righe della sezione si calcolano dal file in HEAD e passano a `git log
    -L` come intervallo numerico: la forma `-L '/^## …/,/^## /'` fallisce
    quando la sezione è l'ultima del file. Una sezione che nel working tree
    differisce da HEAD non è ancora un fatto: `sha` resta `None`.
    """
    committed = git(top, "show", f"HEAD:{rel}")
    if committed is None:
        return None, "", "il task file del perimetro non è committato"
    committed_lines = committed.splitlines()
    if section_text(committed_lines, ANALYSIS_HEADING) != section_text(working_lines, ANALYSIS_HEADING):
        return None, "", "la sezione ha modifiche non committate"
    start, end = section_bounds(committed_lines, ANALYSIS_HEADING)
    # Le righe vuote in coda non sono analisi: chi appende una sezione dopo
    # (il Progress Log del primo avanzamento) le tocca, e il commit della
    # sezione diventerebbe il suo.
    while end > start + 1 and not committed_lines[end - 1].strip():
        end -= 1
    candidates = []
    section_log = git(top, "log", "-L", f"{start + 1},{end}:{rel}", "-1", "-s", "--format=%H")
    if section_log and section_log.strip():
        candidates.append((section_log.strip().splitlines()[0], "sezione"))
    entries = [(int(match.group(1)), line) for line in committed_lines for match in [PROGRESS_ENTRY.match(line)] if match]
    if entries:
        last_entry = max(entries)[1]
        entry_log = git(top, "log", f"-S{last_entry}", "-1", "--format=%H", "--", rel)
        if entry_log and entry_log.strip():
            candidates.append((entry_log.strip(), "avanzamento"))
    if not candidates:
        return None, "", "nessun commit della sezione nella storia"
    if len(candidates) == 1:
        return candidates[0][0], candidates[0][1], ""
    (section_sha, _), (entry_sha, _) = candidates
    if section_sha == entry_sha:
        return entry_sha, "avanzamento", ""
    # Il più recente per storia, non per data: due commit nello stesso secondo
    # hanno la stessa data, e l'ordine di rev-list fra loro non dice niente.
    if git(top, "merge-base", "--is-ancestor", section_sha, entry_sha) is not None:
        return entry_sha, "avanzamento", ""
    if git(top, "merge-base", "--is-ancestor", entry_sha, section_sha) is not None:
        return section_sha, "sezione", ""
    newest = git(top, "rev-list", "-n", "1", section_sha, entry_sha)
    newest = newest.strip() if newest else section_sha
    return newest, "avanzamento" if newest == entry_sha else "sezione", ""


def members_section_changed(top, rel, commit, working_lines):
    """Vero se `## Membri` di un mandato è cambiata dopo il commit dell'analisi:
    `prepare-mandate` riscrive lista e analisi nello stesso commit, quindi una
    lista cambiata dopo è un membro che l'analisi non ha visto."""
    then = git(top, "show", f"{commit}:{rel}")
    if then is None:
        return True
    return section_text(then.splitlines(), MEMBERS_HEADING) != section_text(working_lines, MEMBERS_HEADING)


def changed_members(top, tasks_rel, commit, open_members):
    """id → `modificato` | `nuovo` per i membri aperti il cui task file è
    cambiato fra il commit dell'analisi e HEAD. Un file nato dopo è `nuovo`:
    le sue coppie l'analisi non le ha mai viste. Un rename resta lo stesso
    membro. Le modifiche non committate non contano: sono il lavoro in corso
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
