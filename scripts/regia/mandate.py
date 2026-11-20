"""
mandate — le letture della regia sul mandato: gate, albero, cifre prima → dopo.

  gate    se la regia può partire: il permission mode della sessione che la
          lancia, letto dal suo transcript, e quello del progetto, letto da
          `.claude/loom-works.json`, entrambi `auto`; e `loom-deck-headless`
          sul PATH, il comando con cui la regia apre e porta avanti i membri
  tree    lo stato del perimetro dai file: per ogni membro Prog, Size,
          preflight, cifre di DLV e AC, prossimo passo, dipendenze aperte,
          `## Materiale`; poi le coppie di membri che non possono girare insieme
  verify  l'analisi scritta nel task file del perimetro contro `tree` e
          contro git: le differenze della metà meccanica, le righe della metà
          del modello, il commit da cui vale e i membri cambiati dopo
  recap   le cifre di oggi accanto a quelle salvate da `tree --save` all'armo

Solo letture: nessuno di questi comandi scrive nei repo. `tree --save` scrive il
file che gli si indica: la skill lo tiene in `.claude/loom/regia/`, ignorata da git.

Lo stato di una task si legge dalla cella Prog della tabella Tasks Overview e
dal task file, mai dai glifi del grafo: fra la promozione e il checkpoint i
glifi del grafo restano indietro. Il grafo dà solo le frecce, cioè chi dipende
da chi.

Il perimetro è un id solo, un'epica o un mandato (`Size: Mandate`). I suoi
membri non li cerca questo script: le figlie di un'epica e la lista di un
mandato le legge il lettore unico, `resolve-task.sh <id> --members`, e la skill
le passa dopo `--children`. Una regola sola per contare i membri. `--children`
è obbligatoria per `tree` e `verify`: senza, lo script non legge il perimetro
come vuoto, esce 2 e rimanda al lettore.

Uso:
  python -I mandate.py [--project-root <radice>] gate --own-session <session id>
  python -I mandate.py [--project-root <radice>] tree <perimetro> --children [T1 T2 …] [--save <file.json>]
  python -I mandate.py [--project-root <radice>] verify <perimetro> --children [T1 T2 …]
  python -I mandate.py [--project-root <radice>] recap --before <file.json>

Exit: 0 ok · 1 id malformato o file mancante · 2 gate chiuso, analisi che non
combacia o assente, e ogni errore di argparse — un'opzione ignota, `--children`
mancante a `tree` e `verify`.
"""

import argparse
import json
import os
import re
import shutil
import sys

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import perimeter_analysis  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import regia_common  # noqa: E402

TASK_ID_PATTERN = re.compile(r"^T\d+$")
# Un id di task nella prosa: `T23`, `✔️T23`, `🟡T23`. Fuori `ks·T22`, l'id di
# una task di un altro progetto nel grafo di un cappello.
TASK_REFERENCE = re.compile(r"(?<![A-Za-z0-9·_])T(\d+)(?!\d)")
CHECKBOX = re.compile(r"^- \[([ xX])\]")
DATED_HEADING = re.compile(r"^###\s.*\d{4}-\d{2}-\d{2}")
BACKTICKED = re.compile(r"`([^`]+)`")
VARIATION_SELECTOR = "️"
# Il glifo della voce di `## Materiale` che punta allo stato della regia.
REGIA_STATE_GLYPH = "🎬"

# ---------------------------------------------------------------------------
# gate
# ---------------------------------------------------------------------------

PERMISSION_MODE_FIELD = re.compile(r'"permissionMode"\s*:\s*"([A-Za-z]+)"')
# Il comando del pacchetto del deck che apre e porta avanti le conversazioni
# headless. Su Windows npm lo installa come `.cmd`: `shutil.which` lo trova
# lo stesso, perché prova le estensioni di PATHEXT.
HEADLESS_COMMAND = "loom-deck-headless"


def last_permission_mode(transcript):
    """L'ultimo `permissionMode` scritto nel transcript, `None` se non c'è.

    Claude Code lo scrive nei record di tipo utente: l'ultimo dice il modo in
    vigore all'ultimo prompt, compreso quello che ha lanciato la skill. Il
    registro dei processi vivi non porta il campo.
    """
    found = None
    try:
        with open(transcript, encoding="utf-8", errors="replace") as transcript_handle:
            for line in transcript_handle:
                for match in PERMISSION_MODE_FIELD.finditer(line):
                    found = match.group(1)
    except OSError:
        return None
    return found


def project_permission_mode(project_root):
    """Il campo `permissionMode` di `.claude/loom-works.json`; assente o
    illeggibile vale `manual`, il default con cui il deck apre le tab."""
    try:
        with open(os.path.join(project_root, regia_common.PROJECT_CONFIG), encoding="utf-8") as config_handle:
            value = json.load(config_handle).get("permissionMode")
    except (OSError, ValueError, AttributeError):
        return "manual"
    return value if isinstance(value, str) and value else "manual"


def command_gate(project_root, own_session):
    transcript = regia_common.transcript_path(project_root, own_session)
    own_mode = last_permission_mode(transcript) if os.path.exists(transcript) else None
    project_mode = project_permission_mode(project_root)
    print(f"PROJECT_ROOT={project_root}")
    print(f"DOCS_ROOT={regia_common.docs_root(project_root)}")
    print(f"OWN_SESSION={own_session}")
    print(f"OWN_TRANSCRIPT={transcript if os.path.exists(transcript) else '(non trovato)'}")
    print(f"OWN_MODE={own_mode or '?'}")
    print(f"PROJECT_MODE={project_mode}")
    # Senza il comando la regia scoprirebbe la mancanza al primo membro, a giro
    # avviato, come un'anomalia: il gate la scopre prima di aprire niente.
    headless = shutil.which(HEADLESS_COMMAND)
    print(f"HEADLESS={headless or 'assente'}")
    open_gate = own_mode == "auto" and project_mode == "auto" and headless is not None
    print(f"GATE={'ok' if open_gate else 'stop'}")
    return 0 if open_gate else 2


# ---------------------------------------------------------------------------
# Letture di tasks.md e dei task file
# ---------------------------------------------------------------------------


def normalize_glyph(glyph):
    return glyph.replace(VARIATION_SELECTOR, "").strip()


def section_lines(lines, heading):
    """Le righe sotto `## <heading>` fino al prossimo `## `."""
    collected = []
    inside = False
    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip().lower().startswith(heading.lower())
            continue
        if inside:
            collected.append(line)
    return collected


def overview_rows(tasks_md_lines):
    """id → (Prog, titolo) dalla sola tabella Tasks Overview: le tabelle che
    seguono (lane attive, cross-deps) hanno righe della stessa forma, e lette
    come task porterebbero Prog finte."""
    rows = {}
    for line in section_lines(tasks_md_lines, "Tasks Overview"):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 4 and TASK_ID_PATTERN.match(cells[0]):
            rows[cells[0]] = (cells[2], cells[3])
    return rows


def graph_edges(tasks_md_lines):
    """Le dipendenze scritte in `## Execution Plan`: (task, dipendenza, fonte).

    Due forme. Le frecce: in `A → B` la task B aspetta A; di ogni lato si
    prende l'id più vicino alla freccia, così `✔️T07 · ✔️T11 → ✔️T08 · ✔️T09`
    dà T08 dopo T11. La tabella Cross-deps: `| Task | Parent | Cross Deps |`,
    ogni id delle due colonne di destra è una dipendenza della prima.
    """
    edges = []
    for line in section_lines(tasks_md_lines, "Execution Plan"):
        stripped = line.strip()
        if stripped.startswith("|"):
            cells = [cell.strip() for cell in stripped.strip("|").split("|")]
            head = TASK_REFERENCE.findall(cells[0]) if cells else []
            if len(cells) >= 3 and len(head) == 1:
                for cell in cells[1:3]:
                    for number in TASK_REFERENCE.findall(cell):
                        edges.append((f"T{head[0]}", f"T{number}", "grafo"))
            continue
        segments = stripped.split("→")
        for left, right in zip(segments, segments[1:]):
            left_ids = TASK_REFERENCE.findall(left)
            right_ids = TASK_REFERENCE.findall(right)
            if left_ids and right_ids:
                edges.append((f"T{right_ids[0]}", f"T{left_ids[-1]}", "grafo"))
    return edges


def count_checkboxes(section):
    marks = [CHECKBOX.match(line).group(1) for line in section if CHECKBOX.match(line)]
    return sum(1 for mark in marks if mark in "xX"), len(marks)


def preflight_state(lines):
    """`none` senza un blocco datato in `## Decisions`; `decaduta` se l'ultimo
    porta `premessa decaduta` (il preflight si è fermato su una premessa
    smentita e non vale come fatto); `ok` altrimenti. La stessa regola con cui
    `run-task` decide se un preflight è stato fatto."""
    headings = [line for line in section_lines(lines, "Decisions") if DATED_HEADING.match(line)]
    if not headings:
        return "none"
    return "decaduta" if "premessa decaduta" in headings[-1] else "ok"


# Una voce di `## Dependencies` che comincia con «Nessuna» (o «Nessuno»), anche
# in grassetto o in corsivo, non dichiara dipendenze.
NO_DEPENDENCY = re.compile(r"^-\s+[*_`]*\s*nessun", re.IGNORECASE)


def declared_dependencies(lines):
    """Le task nominate in `## Dependencies`: il primo id di ogni voce a
    colonna zero, la stessa regola del lettore dei membri e di `Parent Task`.

    Il resto della voce è prosa, e può citare altre task per spiegare. Una riga
    indentata è prosa della voce sopra. Una voce che comincia con «Nessuna» non
    dichiara niente anche quando poi nomina una task («Nessuna. Non parte
    insieme a T211»): un vincolo «non insieme» è una collisione, e sta
    nell'analisi del perimetro. Le voci con prosa prima dell'id restano lette:
    una dipendenza vera scritta in prosa e non letta farebbe partire una task
    prima della sua base, l'errore che costa di più.
    """
    dependencies = []
    for line in section_lines(lines, "Dependencies"):
        if not line.startswith("-") or NO_DEPENDENCY.match(line):
            continue
        numbers = TASK_REFERENCE.findall(line)
        if numbers:
            dependencies.append(f"T{numbers[0]}")
    return dependencies


def materiale_paths(lines, folder):
    """I path di `## Materiale`, nella forma su cui si confrontano: relativi
    alla radice, `📁/` sciolto nella task folder, nessun `./` davanti. Un path
    che finisce con `/` è una cartella.

    Restituisce la lista dei path e l'insieme di quelli che la task dichiara
    solo come 📖 fonte, cioè legge e basta: un path nominato anche con un altro
    glifo non ci entra.

    Una voce 🎬 non è un path della task: punta allo stato della regia del
    perimetro, in `.claude/loom/regia/`, che scrive solo la regia. Non entra
    nella lista, e non si confronta con nessun membro."""
    # Solo il prefisso `./`: la folder stessa comincia con un punto
    # (`./.26-11-16-slug`), e uno strip dei caratteri lo mangerebbe.
    folder = (folder or "").strip()
    while folder.startswith("./"):
        folder = folder[2:]
    paths = []
    read_only = set()
    written = set()
    for line in section_lines(lines, "Materiale"):
        if not line.lstrip().startswith("-"):
            continue
        match = BACKTICKED.search(line)
        if not match:
            continue
        if REGIA_STATE_GLYPH in line[:match.start()]:
            continue
        source_only = "📖" in line[:match.start()]
        path = match.group(1).strip()
        if path.startswith("📁/"):
            if not folder:
                continue
            path = folder.rstrip("/") + "/" + path[len("📁/"):]
        for prefix in ("🏠/", "./"):
            if path.startswith(prefix):
                path = path[len(prefix):]
        if path:
            paths.append(path)
            (read_only if source_only else written).add(path)
    return paths, read_only - written


def read_task(project_root, docs, task_id, overview):
    progress, title = overview.get(task_id, ("?", ""))
    task = {"id": task_id, "prog": normalize_glyph(progress) or "?", "title": title,
            "file": None, "size": "?", "preflight": "none",
            "dlv": [0, 0], "ac": [0, 0], "deps": [], "materiale": [], "read_only": set()}
    path = regia_common.find_task_file(project_root, docs, task_id)
    if path is None:
        return task
    with open(path, encoding="utf-8", errors="replace") as task_handle:
        lines = task_handle.read().splitlines()
    task["file"] = os.path.relpath(path, project_root)
    if not task["title"] and lines and lines[0].startswith("# Task:"):
        task["title"] = lines[0][len("# Task:"):].strip()
    task["size"] = regia_common.header_field(lines, "Size") or "?"
    task["preflight"] = preflight_state(lines)
    task["dlv"] = list(count_checkboxes(section_lines(lines, "Deliverables Checklist")))
    task["ac"] = list(count_checkboxes(section_lines(lines, "Acceptance Criteria")))
    task["deps"] = declared_dependencies(lines)
    task["materiale"], task["read_only"] = materiale_paths(lines, regia_common.header_field(lines, "Folder"))
    return task


def next_step(task):
    """Il prossimo passo del ciclo di una task, dai soli file: preflight se
    manca, poi run finché c'è un DLV aperto, poi checkpoint. Lane e branch
    non entrano: dove e quando lanciare lo decide la regia, non un campo
    dell'header.

    Un preflight mancante manda a `preflight` una task 🔵 (o senza riga in
    `tasks.md`): una task 🟢 o 🟡 è già partita senza preflight, che per una
    S o una M non è obbligatorio, e il suo passo è il run o il checkpoint.
    Una task Size L senza preflight va a `preflight` a ogni Prog: `run-task`
    su una L senza preflight si rifiuta di partire. Un preflight decaduto
    manda sempre a `preflight`: `run-task` lo rifiuta a ogni Size."""
    if task["file"] is None:
        return "assente"
    if task["prog"] == normalize_glyph("✔️"):
        return "chiusa"
    # Un'epica o un mandato fra i membri è un perimetro a sé: non si lancia,
    # si orchestra a parte (docs/mandate-format.md), e i suoi membri non
    # entrano in questo albero.
    if task["size"].lower().startswith(("epic", "mandate")):
        return "epica"
    if task["preflight"] == "decaduta":
        return "preflight"
    if task["preflight"] == "none" and (task["prog"] not in STARTED or is_size_large(task["size"])):
        return "preflight"
    done, total = task["dlv"]
    if done < total:
        return "run"
    return "checkpoint"


# Le Prog di una task già partita: preflight fatto (🟢) o lavoro in corso (🟡).
STARTED = (normalize_glyph("🟢"), normalize_glyph("🟡"))


def is_size_large(size):
    """Vero per `Size: L`, la sola Size su cui `run-task` pretende il preflight.
    Un'epica e un mandato non arrivano qui: `next_step` li ferma prima."""
    words = size.split()
    return bool(words) and words[0].upper() == "L"


def paths_overlap(first, second):
    if first == second:
        return True
    return (first.endswith("/") and second.startswith(first)) or (second.endswith("/") and first.startswith(second))


def snapshot(project_root, head, members):
    docs = regia_common.docs_root(project_root)
    tasks_md = os.path.join(project_root, docs, "tasks.md")
    try:
        with open(tasks_md, encoding="utf-8", errors="replace") as tasks_handle:
            tasks_md_lines = tasks_handle.read().splitlines()
    except OSError:
        tasks_md_lines = []
    overview = overview_rows(tasks_md_lines)
    mandate = []
    for task_id in members:
        if task_id not in mandate and task_id != head:
            mandate.append(task_id)
    tasks = {task_id: read_task(project_root, docs, task_id, overview) for task_id in [head] + mandate}
    # Un membro che nomina il proprio perimetro fra le dipendenze non aspetta
    # niente: il perimetro si chiude dopo i membri, e contarlo terrebbe il
    # membro fermo per sempre. Vale per la figlia che nomina la sua epica.
    dependencies = {task_id: [] for task_id in mandate}
    for task_id in mandate:
        for dependency in tasks[task_id]["deps"]:
            if dependency != head:
                dependencies[task_id].append((dependency, "deps"))
    for task_id, dependency, source in graph_edges(tasks_md_lines):
        if task_id in dependencies and dependency not in (task_id, head):
            dependencies[task_id].append((dependency, source))
    closed = normalize_glyph("✔️")
    for task_id in mandate:
        unique = []
        for dependency, source in dependencies[task_id]:
            if all(dependency != seen for seen, _, _ in unique):
                progress = tasks[dependency]["prog"] if dependency in tasks else normalize_glyph(
                    overview.get(dependency, ("?", ""))[0]) or "?"
                unique.append((dependency, source, progress))
        tasks[task_id]["dependencies"] = [
            {"id": dependency, "source": source, "prog": progress} for dependency, source, progress in unique]
        tasks[task_id]["open_dependencies"] = [
            dependency for dependency, _, progress in unique if progress != closed]
        tasks[task_id]["next"] = next_step(tasks[task_id])
    # Le coppie che non possono girare insieme, fra le sole task ancora aperte:
    # una task chiusa non riparte, e un suo conflitto non ferma nessuno.
    conflicts = []
    still_open = [task_id for task_id in mandate if tasks[task_id]["next"] != "chiusa"]
    for index, first in enumerate(still_open):
        for second in still_open[index + 1:]:
            linked = any(item["id"] == second for item in tasks[first]["dependencies"]) or \
                any(item["id"] == first for item in tasks[second]["dependencies"])
            if linked:
                conflicts.append({"tasks": [first, second], "reason": "dipendenza"})
            # Due letture non si scontrano: un path in comune conta solo se
            # almeno una delle due task non lo dichiara come 📖 fonte.
            shared = sorted({path for path in tasks[first]["materiale"]
                             for other in tasks[second]["materiale"]
                             if paths_overlap(path, other)
                             and not (path in tasks[first]["read_only"] and other in tasks[second]["read_only"])})
            if shared:
                conflicts.append({"tasks": [first, second], "reason": "materiale: " + ", ".join(shared)})
    return {"head": head, "mandate": mandate, "tasks": tasks, "conflicts": conflicts, "overview": overview}


def figures(task):
    return f"dlv={task['dlv'][0]}/{task['dlv'][1]}|ac={task['ac'][0]}/{task['ac'][1]}"


def print_tree(state):
    head = state["tasks"][state["head"]]
    print(f"PERIMETRO|{head['id']}|prog={head['prog']}|size={head['size']}|{figures(head)}|title={head['title']}")
    for task_id in state["mandate"]:
        task = state["tasks"][task_id]
        print(f"TASK|{task_id}|prog={task['prog']}|size={task['size']}"
              f"|preflight={task['preflight']}|{figures(task)}|next={task['next']}"
              f"|blocked={','.join(task['open_dependencies']) or '-'}|title={task['title']}")
        if task["dependencies"]:
            listed = " · ".join(f"{item['id']} {item['prog']} ({item['source']})" for item in task["dependencies"])
            print(f"DEPS|{task_id}|{listed}")
        if task["materiale"]:
            print(f"MATERIALE|{task_id}|{' · '.join(task['materiale'])}")
    for conflict in state["conflicts"]:
        print(f"CONFLICT|{conflict['tasks'][0]}|{conflict['tasks'][1]}|{conflict['reason']}")


def command_tree(project_root, arguments):
    for task_id in [arguments.head] + arguments.children:
        if not TASK_ID_PATTERN.match(task_id):
            print(f"ERROR: id task malformato: '{task_id}' (atteso T<numero>)", file=sys.stderr)
            return 1
    state = snapshot(project_root, arguments.head, arguments.children)
    if state["tasks"][arguments.head]["file"] is None:
        print(f"ERROR: task file di {arguments.head} non trovato", file=sys.stderr)
        return 1
    print_tree(state)
    if arguments.save:
        temporary_path = arguments.save + ".tmp"
        with open(temporary_path, "w", encoding="utf-8") as save_handle:
            json.dump({"head": state["head"], "mandate": state["mandate"],
                       "figures": {task_id: {key: state["tasks"][task_id][key] for key in ("prog", "dlv", "ac", "title")}
                                   for task_id in [state["head"]] + state["mandate"]}},
                      save_handle, ensure_ascii=False)
        os.replace(temporary_path, arguments.save)
    return 0



def command_verify(project_root, arguments):
    """L'analisi scritta nel task file del perimetro contro `tree` e contro git.

    Stampa il perimetro, la presenza dell'analisi, il commit da cui vale, le
    differenze della metà meccanica (`DIFF`), le righe della metà del modello
    (`MODELLO`) e i membri aperti cambiati dopo il commit (`CAMBIATO`), che la
    skill rilegge. `VERIFY=ok` combacia e nessun membro è cambiato,
    `VERIFY=riesame` combacia ma ci sono membri da rileggere, `VERIFY=stop`
    non combacia, o l'analisi manca o non è committata.
    """
    for task_id in [arguments.head] + arguments.children:
        if not TASK_ID_PATTERN.match(task_id):
            print(f"ERROR: id task malformato: '{task_id}' (atteso T<numero>)", file=sys.stderr)
            return 1
    state = snapshot(project_root, arguments.head, arguments.children)
    head = state["tasks"][arguments.head]
    if head["file"] is None:
        print(f"ERROR: task file di {arguments.head} non trovato", file=sys.stderr)
        return 1
    head_path = os.path.join(project_root, head["file"])
    with open(head_path, encoding="utf-8", errors="replace") as head_handle:
        lines = head_handle.read().splitlines()
    form = "mandato" if head["size"].lower().startswith("mandate") else "epica"
    print(f"PERIMETRO={arguments.head}|{form}")
    if perimeter_analysis.section_bounds(lines, perimeter_analysis.ANALYSIS_HEADING) is None:
        print("ANALYSIS=assente")
        print("VERIFY=stop")
        return 2
    rows = perimeter_analysis.parse_rows(lines)
    print("ANALYSIS=presente")
    print(f"ROWS={len(rows)}")

    commit = None
    top = perimeter_analysis.repository_top(project_root)
    if top is None:
        print("ANALYSIS_COMMIT=? (il progetto non è un repo git)")
    else:
        rel = perimeter_analysis.relative_to(top, head_path)
        commit, source, reason = perimeter_analysis.analysis_commit(top, rel, lines)
        if commit is None:
            print(f"ANALYSIS_COMMIT=? ({reason})")
        else:
            print(f"ANALYSIS_COMMIT={commit[:12]}")
            print(f"ANALYSIS_FROM={source}")

    differences, model_rows = perimeter_analysis.compare(state, rows)
    if commit and form == "mandato" and perimeter_analysis.members_section_changed(top, rel, commit, lines):
        differences.append(("membri", "## Membri", "lista cambiata dopo il commit dell'analisi"))
    for kind, pair, detail in differences:
        print(f"DIFF|{kind}|{pair}|{detail}")
    for first, second, what in model_rows:
        print(f"MODELLO|{first}|{second}|{what}")

    changed = {}
    if commit:
        open_members = {task_id for task_id in state["mandate"] if state["tasks"][task_id]["next"] != "chiusa"}
        tasks_rel = perimeter_analysis.relative_to(
            top, os.path.join(project_root, regia_common.docs_root(project_root), "tasks"))
        changed = perimeter_analysis.changed_members(top, tasks_rel, commit, open_members)
        for task_id in state["mandate"]:
            if task_id in changed:
                print(f"CAMBIATO|{task_id}|{changed[task_id]}")

    verdict = "stop" if commit is None or differences else ("riesame" if changed else "ok")
    print(f"VERIFY={verdict}")
    return 2 if verdict == "stop" else 0


def command_recap(project_root, before_path):
    try:
        with open(before_path, encoding="utf-8") as before_handle:
            before = json.load(before_handle)
    except (OSError, ValueError) as error:
        print(f"ERROR: cifre di partenza illeggibili: {before_path}: {error}", file=sys.stderr)
        return 1
    # `epic` è la chiave delle cifre salvate prima del rename della skill: una
    # regia rilanciata nella stessa sessione rilegge il file che aveva scritto.
    head = before.get("head") or before.get("epic")
    state = snapshot(project_root, head, before["mandate"])
    for task_id in [head] + before["mandate"]:
        then = before["figures"].get(task_id, {"prog": "?", "dlv": [0, 0], "ac": [0, 0], "title": ""})
        now = state["tasks"][task_id]
        print(f"RECAP|{task_id}|prog={then['prog']}→{now['prog']}"
              f"|dlv={then['dlv'][0]}/{then['dlv'][1]}→{now['dlv'][0]}/{now['dlv'][1]}"
              f"|ac={then['ac'][0]}/{then['ac'][1]}→{now['ac'][0]}/{now['ac'][1]}"
              f"|title={now['title'] or then['title']}")
    return 0


MEMBERS_HINT = ("i membri del perimetro li legge il lettore unico, "
                "resolve-task.sh <perimetro> --members, e si passano dopo --children")


class SubcommandParser(argparse.ArgumentParser):
    """Il parser dei sottocomandi: a un `--children` mancante aggiunge dove si
    leggono i membri. Senza i membri `tree` e `verify` vedrebbero un perimetro
    vuoto — `verify` darebbe ogni riga dell'analisi come `fuori`, anche sui
    membri aperti — e argparse da solo dice che manca l'opzione, non dove si
    prendono i valori."""

    def error(self, message):
        if "--children" in message:
            message = f"{message} — {MEMBERS_HINT}"
        super().error(message)


def parse_arguments():
    parser = argparse.ArgumentParser(description="Letture della regia sul mandato")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True, parser_class=SubcommandParser)
    gate_parser = subcommands.add_parser("gate")
    gate_parser.add_argument("--own-session", required=True, help="session id della sessione della regia")
    tree_parser = subcommands.add_parser("tree")
    tree_parser.add_argument("head", help="il perimetro: un'epica o un mandato")
    tree_parser.add_argument("--children", nargs="*", required=True,
                             help="i membri, dal lettore unico resolve-task.sh --members")
    tree_parser.add_argument("--save", default="", help="file JSON delle cifre di partenza, in una cartella che git ignora")
    verify_parser = subcommands.add_parser("verify")
    verify_parser.add_argument("head", help="il perimetro: un'epica o un mandato")
    verify_parser.add_argument("--children", nargs="*", required=True,
                               help="i membri, dal lettore unico resolve-task.sh --members")
    recap_parser = subcommands.add_parser("recap")
    recap_parser.add_argument("--before", required=True)
    return parser.parse_args()


def main():
    regia_common.setup_stdout()
    arguments = parse_arguments()
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else regia_common.find_project_root(os.getcwd())
    if arguments.command == "gate":
        return command_gate(project_root, arguments.own_session)
    if arguments.command == "tree":
        return command_tree(project_root, arguments)
    if arguments.command == "verify":
        return command_verify(project_root, arguments)
    return command_recap(project_root, arguments.before)


if __name__ == "__main__":
    sys.exit(main())
