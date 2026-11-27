"""
perimeter — le letture dell'orchestrator sul perimetro orchestrabile: gate, albero,
cifre prima → dopo.

  gate    se l'orchestrator può partire: il permission mode della sessione che lo
          lancia, letto dal suo transcript, e quello del progetto, letto da
          `.claude/loom-works.json`, entrambi `auto`; e `loom-deck-headless`
          sul PATH, il comando con cui l'orchestrator apre e porta avanti i membri,
          in una versione che conosce `--orchestrator`. Dice anche, senza chiudere
          il gate, se `loom-deck-spawn` sa aprire l'orchestrator successore di un
          passaggio di consegne (`HANDOFF`)
  tree    lo stato del perimetro orchestrabile dai file: per ogni membro Prog, Size,
          preflight, cifre di DLV e AC, prossimo passo, dipendenze aperte,
          dipendenze verso un id che il progetto non conosce (`WARN`),
          `## Materiale`; poi le coppie di membri che non possono girare insieme
  recap   le cifre di oggi accanto a quelle di partenza del giro, la riga `prima`
          che lo script del flusso scrive al primo avvio del giro

Solo letture: nessuno di questi comandi scrive un file.

Lo stato di una task si legge dalla cella Prog della tabella Tasks Overview e
dal task file, mai dai glifi del grafo: fra la promozione e il checkpoint i
glifi del grafo restano indietro. Il grafo dà solo le frecce, cioè chi dipende
da chi.

Il perimetro orchestrabile è un id solo, un'epica o una lista custom
(`Size: Custom`, o `Size: Mandate`, il nome di prima). I suoi membri non li
cerca questo script: le figlie di un'epica e la lista di una lista custom le
legge il lettore unico, `resolve-task.sh <id> --members`, e la skill le passa
dopo `--children`. Una regola sola per contare i membri. `--children` è
obbligatoria per `tree`: senza, lo script non legge i membri come zero, esce 2
e rimanda al lettore.

Uso:
  python -I perimeter.py [--project-root <radice>] gate --own-session <session id>
  python -I perimeter.py [--project-root <radice>] tree <id del perimetro orchestrabile> --children [T1 T2 …]
  python -I perimeter.py [--project-root <radice>] recap <id del perimetro orchestrabile>

Exit: 0 ok · 1 id malformato o file mancante · 2 gate chiuso, e ogni errore di
argparse — un'opzione ignota, `--children` mancante a `tree`.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import flow_log  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import orchestrator_common  # noqa: E402

TASK_ID_PATTERN = re.compile(r"^T\d+$")
# Un id di task nella prosa: `T23`, `✔️T23`, `🟡T23`. Fuori `ks·T22`, l'id di
# una task di un altro progetto nel grafo di un cappello.
TASK_REFERENCE = re.compile(r"(?<![A-Za-z0-9·_])T(\d+)(?!\d)")
CHECKBOX = re.compile(r"^- \[([ xX])\]")
DATED_HEADING = re.compile(r"^###\s.*\d{4}-\d{2}-\d{2}")
BACKTICKED = re.compile(r"`([^`]+)`")
VARIATION_SELECTOR = "️"
# Il glifo della voce di `## Materiale` che punta allo stato dell'orchestrator.
ORCHESTRATOR_STATE_GLYPH = "🎬"

# ---------------------------------------------------------------------------
# gate
# ---------------------------------------------------------------------------

PERMISSION_MODE_FIELD = re.compile(r'"permissionMode"\s*:\s*"([A-Za-z]+)"')
# Il comando del pacchetto del deck che apre e porta avanti le conversazioni
# headless. Su Windows npm lo installa come `.cmd`: `shutil.which` lo trova
# lo stesso, perché prova le estensioni di PATHEXT.
HEADLESS_COMMAND = "loom-deck-headless"
# L'opzione con cui l'orchestrator dichiara sé stesso a ogni apertura e a ogni
# risposta: la conversazione nasce con `LOOM_ORCHESTRATOR`. Un `loom-deck-headless`
# più vecchio la rifiuta con uscita 2, e l'orchestrator lo scoprirebbe al primo membro.
HEADLESS_ORCHESTRATOR_FLAG = "--orchestrator"
HEADLESS_HELP_TIMEOUT_S = 20
# Il client dell'endpoint del deck, con cui l'orchestrator apre il successore quando
# passa le consegne (kind `orchestrator`).
SPAWN_COMMAND = "loom-deck-spawn"
USAGE_KIND_LINE = re.compile(r"^\s*<kind>\s+(.*)$", re.M)


def command_usage(command):
    """L'uso di un comando del deck (`--help`), o stringa vuota se il comando
    non parte o non risponde in tempo."""
    try:
        result = subprocess.run(
            [command, "--help"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=HEADLESS_HELP_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout


def spawn_knows_orchestrator(spawn):
    """`True` se la riga `<kind>` dell'uso di `loom-deck-spawn` elenca `orchestrator`.

    La riga dei kind, e non l'uso intero: l'uso nomina l'orchestrator anche per
    `--orchestrator`, che c'è da prima del passaggio di consegne. La riga nasce dalla
    stessa tabella con cui il deck rifiuta un kind, quindi un kind elencato è un
    kind che il deck accetta."""
    match = USAGE_KIND_LINE.search(command_usage(spawn))
    return bool(match) and "orchestrator" in [kind.strip() for kind in match.group(1).split("|")]


def headless_knows_orchestrator(headless):
    """`True` se l'uso di `loom-deck-headless` nomina `--orchestrator`.

    L'uso è la sola fonte che il comando offre senza fare niente: `--help` esce
    0 e non apre nessun turno. Un comando che non parte, che non risponde in
    tempo o che non nomina l'opzione vale `False`, e il gate si chiude.
    """
    return HEADLESS_ORCHESTRATOR_FLAG in command_usage(headless)


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
        with open(os.path.join(project_root, orchestrator_common.PROJECT_CONFIG), encoding="utf-8") as config_handle:
            value = json.load(config_handle).get("permissionMode")
    except (OSError, ValueError, AttributeError):
        return "manual"
    return value if isinstance(value, str) and value else "manual"


def command_gate(project_root, own_session):
    transcript = orchestrator_common.transcript_path(project_root, own_session)
    own_mode = last_permission_mode(transcript) if os.path.exists(transcript) else None
    project_mode = project_permission_mode(project_root)
    print(f"PROJECT_ROOT={project_root}")
    print(f"DOCS_ROOT={orchestrator_common.docs_root(project_root)}")
    print(f"OWN_SESSION={own_session}")
    print(f"OWN_TRANSCRIPT={transcript if os.path.exists(transcript) else '(non trovato)'}")
    print(f"OWN_MODE={own_mode or '?'}")
    print(f"PROJECT_MODE={project_mode}")
    # Senza il comando l'orchestrator scoprirebbe la mancanza al primo membro, a giro
    # avviato, come un'anomalia: il gate la scopre prima di aprire niente.
    headless = shutil.which(HEADLESS_COMMAND)
    print(f"HEADLESS={headless or 'assente'}")
    # Un deck installato da prima di `--orchestrator` apre i membri senza `LOOM_ORCHESTRATOR`
    # solo se l'orchestrator non lo passa; l'orchestrator lo passa sempre, e quel deck
    # rifiuterebbe ogni apertura: anche questo si scopre qui, non al primo membro.
    knows_orchestrator = headless is not None and headless_knows_orchestrator(headless)
    print(f"HEADLESS_ORCHESTRATOR={'sì' if knows_orchestrator else ('no' if headless else '-')}")
    # Il passaggio di consegne serve solo ai giri lunghi: un deck che non sa
    # aprire il successore non ferma il lancio, e l'orchestrator lo dice in una riga.
    spawn = shutil.which(SPAWN_COMMAND)
    print(f"HANDOFF={'sì' if spawn is not None and spawn_knows_orchestrator(spawn) else 'no'}")
    open_gate = own_mode == "auto" and project_mode == "auto" and knows_orchestrator
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
    nel piano del perimetro orchestrabile, come risorsa. Le voci con prosa prima dell'id restano lette:
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

    Una voce 🎬 non è un path della task: punta allo stato dell'orchestrator del
    perimetro orchestrabile, in `.claude/loom/orchestrator/`, che scrive solo l'orchestrator. Non entra
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
        if ORCHESTRATOR_STATE_GLYPH in line[:match.start()]:
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
    path = orchestrator_common.find_task_file(project_root, docs, task_id)
    if path is None:
        return task
    with open(path, encoding="utf-8", errors="replace") as task_handle:
        lines = task_handle.read().splitlines()
    task["file"] = os.path.relpath(path, project_root)
    if not task["title"] and lines and lines[0].startswith("# Task:"):
        task["title"] = lines[0][len("# Task:"):].strip()
    task["size"] = orchestrator_common.header_field(lines, "Size") or "?"
    task["preflight"] = preflight_state(lines)
    task["dlv"] = list(count_checkboxes(section_lines(lines, "Deliverables Checklist")))
    task["ac"] = list(count_checkboxes(section_lines(lines, "Acceptance Criteria")))
    task["deps"] = declared_dependencies(lines)
    task["materiale"], task["read_only"] = materiale_paths(lines, orchestrator_common.header_field(lines, "Folder"))
    return task


def next_step(task):
    """Il prossimo passo del ciclo di una task, dai soli file: preflight se
    manca, poi run finché c'è un DLV aperto, poi checkpoint. Lane e branch
    non entrano: dove e quando lanciare lo decide l'orchestrator, non un campo
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
    # Un'epica o una lista custom fra i membri è un perimetro orchestrabile a
    # sé: non si lancia, si orchestra a parte (docs/perimeter-format.md), e i
    # suoi membri non entrano in questo albero. `mandate` è il nome di prima di
    # `custom`, letto uguale.
    if task["size"].lower().startswith(("epic", "custom", "mandate")):
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
    Un'epica e una lista custom non arrivano qui: `next_step` le ferma prima."""
    words = size.split()
    return bool(words) and words[0].upper() == "L"


# Le cause di una dipendenza con Prog `?`: la stessa attesa senza fine, due
# rimedi diversi — correggere la voce, o aggiungere la riga in tasks.md.
UNKNOWN_ID = "id assente nel progetto"
MISSING_ROW = "task file senza riga in tasks.md"


def unknown_cause(project_root, docs, task_id, tasks, overview):
    """Perché il progetto non dà una Prog a `task_id`, la dipendenza di un
    membro; `None` quando la riga in tasks.md c'è. Un id con Prog `?` non vale
    ✔️, quindi resta in `blocked=` e tiene fermo il membro: la causa è ciò che
    chi legge l'albero deve correggere."""
    if task_id in overview:
        return None
    if task_id in tasks:
        has_file = tasks[task_id]["file"] is not None
    else:
        has_file = orchestrator_common.find_task_file(project_root, docs, task_id) is not None
    return MISSING_ROW if has_file else UNKNOWN_ID


def paths_overlap(first, second):
    if first == second:
        return True
    return (first.endswith("/") and second.startswith(first)) or (second.endswith("/") and first.startswith(second))


def snapshot(project_root, head, members):
    docs = orchestrator_common.docs_root(project_root)
    tasks_md = os.path.join(project_root, docs, "tasks.md")
    try:
        with open(tasks_md, encoding="utf-8", errors="replace") as tasks_handle:
            tasks_md_lines = tasks_handle.read().splitlines()
    except OSError:
        tasks_md_lines = []
    overview = overview_rows(tasks_md_lines)
    unique_members = []
    for task_id in members:
        if task_id not in unique_members and task_id != head:
            unique_members.append(task_id)
    tasks = {task_id: read_task(project_root, docs, task_id, overview) for task_id in [head] + unique_members}
    # Un membro che nomina il proprio perimetro orchestrabile fra le dipendenze
    # non aspetta niente: il perimetro orchestrabile si chiude dopo i membri, e
    # contarlo terrebbe il membro fermo per sempre. Vale per la figlia che nomina
    # la sua epica.
    dependencies = {task_id: [] for task_id in unique_members}
    for task_id in unique_members:
        for dependency in tasks[task_id]["deps"]:
            if dependency != head:
                dependencies[task_id].append((dependency, "deps"))
    for task_id, dependency, source in graph_edges(tasks_md_lines):
        if task_id in dependencies and dependency not in (task_id, head):
            dependencies[task_id].append((dependency, source))
    closed = normalize_glyph("✔️")
    for task_id in unique_members:
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
        # Una dipendenza che il progetto non conosce resta aperta: può essere la
        # base mancante del membro, e partire senza costa più che aspettare.
        unknown = []
        for dependency, _, progress in unique:
            cause = unknown_cause(project_root, docs, dependency, tasks, overview) if progress == "?" else None
            if cause:
                unknown.append({"id": dependency, "cause": cause})
        tasks[task_id]["unknown_dependencies"] = unknown
        tasks[task_id]["next"] = next_step(tasks[task_id])
    # Le coppie che non possono girare insieme, fra le sole task ancora aperte:
    # una task chiusa non riparte, e un suo conflitto non ferma nessuno.
    conflicts = []
    still_open = [task_id for task_id in unique_members if tasks[task_id]["next"] != "chiusa"]
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
    return {"head": head, "members": unique_members, "tasks": tasks, "conflicts": conflicts, "overview": overview}


def figures(task):
    return f"dlv={task['dlv'][0]}/{task['dlv'][1]}|ac={task['ac'][0]}/{task['ac'][1]}"


def print_tree(state):
    head = state["tasks"][state["head"]]
    print(f"PERIMETRO|{head['id']}|prog={head['prog']}|size={head['size']}|{figures(head)}|title={head['title']}")
    for task_id in state["members"]:
        task = state["tasks"][task_id]
        print(f"TASK|{task_id}|prog={task['prog']}|size={task['size']}"
              f"|preflight={task['preflight']}|{figures(task)}|next={task['next']}"
              f"|blocked={','.join(task['open_dependencies']) or '-'}|title={task['title']}")
        if task["dependencies"]:
            listed = " · ".join(f"{item['id']} {item['prog']} ({item['source']})" for item in task["dependencies"])
            print(f"DEPS|{task_id}|{listed}")
        for item in task["unknown_dependencies"]:
            print(f"WARN|{task_id}|{item['id']}|{item['cause']}")
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
    return 0


def command_recap(project_root, head):
    """Le cifre di oggi accanto a quelle di partenza del giro: la riga `prima`
    del flusso (`flow_log`), che lo script scrive al primo avvio del giro,
    con un piano valido. I membri sono quelli di quella riga: un membro
    entrato dopo non ha un «prima»."""
    if not TASK_ID_PATTERN.match(head):
        print(f"ERROR: id task malformato: '{head}' (atteso T<numero>)", file=sys.stderr)
        return 1
    flow_path = flow_log.paths(project_root, head)["flow"]
    state, _ = flow_log.replay(flow_path, head)
    before = (state.before or {}).get("cifre")
    if not isinstance(before, dict) or head not in before:
        print(f"PRIMA=assente ({os.path.relpath(flow_path, project_root)}: nessuna riga prima, il giro non è partito)")
        return 0
    print(f"PRIMA={state.before.get('ts')}")
    members = [task_id for task_id in before if task_id != head]
    state = snapshot(project_root, head, members)
    for task_id in [head] + members:
        then = before[task_id]
        now = state["tasks"][task_id]
        print(f"RECAP|{task_id}|prog={then['prog']}→{now['prog']}"
              f"|dlv={then['dlv'][0]}/{then['dlv'][1]}→{now['dlv'][0]}/{now['dlv'][1]}"
              f"|ac={then['ac'][0]}/{then['ac'][1]}→{now['ac'][0]}/{now['ac'][1]}"
              f"|title={now['title'] or then['title']}")
    return 0


MEMBERS_HINT = ("i membri del perimetro orchestrabile li legge il lettore unico, "
                "resolve-task.sh <id> --members, e si passano dopo --children")


class SubcommandParser(argparse.ArgumentParser):
    """Il parser dei sottocomandi: a un `--children` mancante aggiunge dove si
    leggono i membri. Senza i membri `tree` vedrebbe un perimetro orchestrabile vuoto, e
    argparse da solo dice che manca l'opzione, non dove si prendono i valori."""

    def error(self, message):
        if "--children" in message:
            message = f"{message} — {MEMBERS_HINT}"
        super().error(message)


def parse_arguments():
    parser = argparse.ArgumentParser(description="Letture dell'orchestrator sul perimetro orchestrabile")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True, parser_class=SubcommandParser)
    gate_parser = subcommands.add_parser("gate")
    gate_parser.add_argument("--own-session", required=True, help="session id della sessione dell'orchestrator")
    tree_parser = subcommands.add_parser("tree")
    tree_parser.add_argument("head", help="il perimetro orchestrabile: un'epica o una lista custom")
    tree_parser.add_argument("--children", nargs="*", required=True,
                             help="i membri, dal lettore unico resolve-task.sh --members")
    recap_parser = subcommands.add_parser("recap")
    recap_parser.add_argument("head", help="il perimetro orchestrabile: un'epica o una lista custom")
    return parser.parse_args()


def main():
    orchestrator_common.setup_stdout()
    arguments = parse_arguments()
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else orchestrator_common.find_project_root(os.getcwd())
    if arguments.command == "gate":
        return command_gate(project_root, arguments.own_session)
    if arguments.command == "tree":
        return command_tree(project_root, arguments)
    return command_recap(project_root, arguments.head)


if __name__ == "__main__":
    sys.exit(main())
