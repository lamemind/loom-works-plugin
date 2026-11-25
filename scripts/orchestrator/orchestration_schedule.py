"""
orchestration_schedule — il piano di un perimetro orchestrabile:
`orchestration-schedule.md` nella sua task folder (`schedule.md`, il nome di
prima, letto quando il nuovo manca).

  verify  il piano contro i file del progetto: un blocco ```json solo e valido,
          i membri uguali a quelli del lettore unico, ogni dipendenza dichiarata
          fra membri aperti nel «Dopo», ogni path in comune fra due membri aperti
          coperto da una risorsa o da un «Dopo», i perimetri eseguibili dentro il
          numero dei DLV; poi il commit del piano e i membri cambiati dopo.
          Con `--bozza` i soli controlli sui file, senza il commit: è la
          verifica di chi scrive il piano prima di committarlo
  show    il piano letto e normalizzato, una riga per membro

Il contratto del file — dove sta, la prosa, il blocco JSON, i campi e il loro
significato — è `docs/orchestration-schedule-format.md`. Qui il parser, che è anche lo schema
eseguibile: una chiave ignota, un tipo sbagliato o un valore fuori dominio sono
un errore, mai un default. Un campo letto col significato sbagliato non dà
errore: lascia partire un membro troppo presto, e nessuno lo vede.

Il modulo serve tre lettori. La skill dell'orchestrator lancia `verify` prima di
partire, e lo stop la ferma. `prepare-perimeter` lancia `verify --bozza` sul piano
appena scritto, prima della conferma e del commit. Lo script del flusso (`flow.py`) importa il parser e
`check`, e rilancia il controllo quando un task file di un membro cambia: lì
conta la sola parte strutturale (`Result.blocking`), perché a giro avviato i
membri cambiano di continuo e il commit del piano lo scrive l'orchestrator.

I membri li legge il lettore unico, `resolve-task.sh <id> --members`:
una regola sola per contare i membri, anche quando chi chiede è un processo
Python staccato che nessuna skill imbocca.

Uso:
  python -I orchestration_schedule.py [--project-root <radice>] verify <id del perimetro orchestrabile> [--bozza]
  python -I orchestration_schedule.py [--project-root <radice>] show <id del perimetro orchestrabile>

Exit: 0 ok · 1 id malformato, task file del perimetro orchestrabile mancante, lettore dei
membri che non risponde · 2 piano che non vale (verify: stop; show: piano
assente o non valido).
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import orchestrator_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import perimeter  # noqa: E402
import perimeter_analysis  # noqa: E402

# Il nome del piano, e quello di prima: un piano nato prima del rename resta
# `schedule.md` finché `prepare-perimeter` non ci passa, e un giro vivo su di lui
# gira con uno script del flusso che conosce solo quel nome.
PLAN_NAME = "orchestration-schedule.md"
PLAN_NAME_BEFORE = "schedule.md"
TASK_ID_PATTERN = re.compile(r"^T\d+$")
DEP_PATTERN = re.compile(r"^(T\d+)(?::(.+))?$")
FENCE_OPEN = re.compile(r"^```json\s*$")
FENCE_CLOSE = re.compile(r"^```\s*$")
STEPS = ("preflight", "run", "checkpoint")
TOP_KEYS = ("perimetro", "membri")
MEMBER_KEYS = ("id", "passo", "dopo", "risorse", "dlv", "umano")
ALL_OTHERS = "*"
CLOSED = perimeter.normalize_glyph("✔️")
# I membri su cui l'orchestrator non lancia niente: chiusi, assenti, o un
# perimetro orchestrabile a sé fra i membri.
NOT_RUNNABLE = ("chiusa", "epica", "assente")
RESOLVE_TIMEOUT_S = 30


class PlanError(ValueError):
    """Un piano che non si può usare: il motivo, in una riga."""


# ---------------------------------------------------------------------------
# Il perimetro eseguibile: la stessa grammatica di `task-deliverables.sh --scope`
# ---------------------------------------------------------------------------


def parse_dlv_spec(spec):
    """`1,3-5` → [1, 3, 4, 5], crescente e senza ripetizioni. Errore su un
    pezzo vuoto, un numero non positivo o un intervallo rovesciato: la stessa
    spec che `run-task` rifiuterebbe."""
    if not isinstance(spec, str) or not spec.strip():
        raise PlanError("perimetro eseguibile vuoto")
    numbers = set()
    for piece in spec.split(","):
        piece = piece.strip()
        match = re.fullmatch(r"(\d+)(?:-(\d+))?", piece)
        if not match:
            raise PlanError(f"perimetro eseguibile «{spec}» malformato (forma 1,3-5)")
        first = int(match.group(1))
        last = int(match.group(2)) if match.group(2) else first
        if first < 1 or last < first:
            raise PlanError(f"perimetro eseguibile «{spec}»: «{piece}» non è un intervallo valido")
        numbers.update(range(first, last + 1))
    return sorted(numbers)


def format_dlv(numbers):
    """[1, 3, 4, 5] → `1,3-5`: la forma che `loom-deck-headless open … run` accetta."""
    pieces = []
    start = previous = None
    for number in sorted(numbers):
        if start is None:
            start = previous = number
        elif number == previous + 1:
            previous = number
        else:
            pieces.append(f"{start}" if start == previous else f"{start}-{previous}")
            start = previous = number
    if start is not None:
        pieces.append(f"{start}" if start == previous else f"{start}-{previous}")
    return ",".join(pieces)


# ---------------------------------------------------------------------------
# Il piano: parser e schema
# ---------------------------------------------------------------------------


class Dependency:
    """Una voce di «Dopo»: `*`, `T21` (dopo la chiusura di T21) o `T21:2,4`
    (dopo i DLV 2 e 4 di T21, chiusi a ciclo finito)."""

    def __init__(self, text):
        if not isinstance(text, str):
            raise PlanError(f"voce di «dopo» non stringa: {json.dumps(text, ensure_ascii=False)}")
        self.text = text.strip()
        if self.text == ALL_OTHERS:
            self.target, self.dlv = ALL_OTHERS, None
            return
        match = DEP_PATTERN.match(self.text)
        if not match:
            raise PlanError(f"voce di «dopo» «{text}» fuori forma (attese *, T<n>, T<n>:<dlv>)")
        self.target = match.group(1)
        self.dlv = parse_dlv_spec(match.group(2)) if match.group(2) is not None else None


class Member:
    """Una voce di `membri`, coi default dei campi facoltativi."""

    def __init__(self, data, position):
        if not isinstance(data, dict):
            raise PlanError(f"membro {position}: atteso un oggetto")
        self.id = data.get("id")
        if not isinstance(self.id, str) or not TASK_ID_PATTERN.match(self.id):
            raise PlanError(f"membro {position}: «id» assente o fuori forma (atteso T<numero>)")
        where = f"membro {self.id}"
        unknown = sorted(key for key in data if key not in MEMBER_KEYS)
        if unknown:
            raise PlanError(f"{where}: chiave ignota «{unknown[0]}» (attese {', '.join(MEMBER_KEYS)})")
        self.step = data.get("passo")
        if self.step is not None and self.step not in STEPS:
            raise PlanError(f"{where}: «passo» «{self.step}» fuori dominio (attesi {', '.join(STEPS)})")
        after = data.get("dopo", [])
        if not isinstance(after, list):
            raise PlanError(f"{where}: «dopo» non è una lista")
        self.after = [Dependency(entry) for entry in after]
        targets = [dependency.target for dependency in self.after]
        if self.id in targets:
            raise PlanError(f"{where}: «dopo» nomina il membro stesso")
        if len(set(targets)) != len(targets):
            raise PlanError(f"{where}: «dopo» nomina due volte la stessa task")
        resources = data.get("risorse", [])
        if not isinstance(resources, list) or not all(isinstance(item, str) and item.strip() for item in resources):
            raise PlanError(f"{where}: «risorse» non è una lista di stringhe non vuote")
        self.resources = [item.strip() for item in resources]
        self.dlv_text = data.get("dlv")
        self.dlv = None if self.dlv_text is None else parse_dlv_spec(self.dlv_text)
        self.human = data.get("umano", False)
        if not isinstance(self.human, bool):
            raise PlanError(f"{where}: «umano» non è true o false")

    def describe(self):
        """La riga di `show`, nella forma normalizzata."""
        after = ",".join(dependency.text for dependency in self.after) or "-"
        resources = ",".join(self.resources) or "-"
        dlv = format_dlv(self.dlv) if self.dlv else "-"
        return (f"MEMBRO|{self.id}|passo={self.step or '-'}|dopo={after}|risorse={resources}"
                f"|dlv={dlv}|umano={'sì' if self.human else 'no'}")


class Plan:
    """Il piano letto e valido. `sha` è l'impronta del JSON normalizzato: due
    letture con la stessa impronta sono lo stesso piano, anche se la prosa
    intorno è cambiata."""

    def __init__(self, data):
        if not isinstance(data, dict):
            raise PlanError("atteso un oggetto JSON con «perimetro» e «membri»")
        unknown = sorted(key for key in data if key not in TOP_KEYS)
        if unknown:
            raise PlanError(f"chiave ignota «{unknown[0]}» (attese {', '.join(TOP_KEYS)})")
        self.head = data.get("perimetro")
        if not isinstance(self.head, str) or not TASK_ID_PATTERN.match(self.head):
            raise PlanError("«perimetro» assente o fuori forma (atteso T<numero>)")
        members = data.get("membri")
        if not isinstance(members, list):
            raise PlanError("«membri» assente o non è una lista")
        self.members = [Member(entry, index + 1) for index, entry in enumerate(members)]
        self.by_id = {}
        for member in self.members:
            if member.id == self.head:
                raise PlanError(f"membro {member.id}: il perimetro orchestrabile non è un membro di sé stesso")
            if member.id in self.by_id:
                raise PlanError(f"membro {member.id} ripetuto")
            self.by_id[member.id] = member
        self.sha = hashlib.sha1(json.dumps(data, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()

    @property
    def ids(self):
        return [member.id for member in self.members]


def extract_json(text):
    """Il testo dell'unico blocco ```json del file. Errore se non ce n'è
    nessuno, se ce n'è più d'uno o se il blocco non si chiude: due blocchi
    lascerebbero allo script la scelta di quale valga."""
    blocks = []
    current = None
    for line in text.splitlines():
        if current is None:
            if FENCE_OPEN.match(line):
                current = []
            continue
        if FENCE_CLOSE.match(line):
            blocks.append("\n".join(current))
            current = None
            continue
        current.append(line)
    if current is not None:
        raise PlanError("blocco ```json senza la riga ``` che lo chiude")
    if not blocks:
        raise PlanError("nessun blocco ```json nel piano")
    if len(blocks) > 1:
        raise PlanError(f"{len(blocks)} blocchi ```json nel piano: ne vale uno solo")
    return blocks[0]


def parse_plan_text(text):
    """Il piano dal testo del suo file; `PlanError` col motivo."""
    try:
        data = json.loads(extract_json(text))
    except ValueError as error:
        if isinstance(error, PlanError):
            raise
        raise PlanError(f"JSON non valido: {error}") from None
    return Plan(data)


def plan_path(project_root, head):
    """(path, motivo): il piano sta nella task folder del perimetro orchestrabile,
    il campo `Folder` del suo task file. Il nome nuovo vince; il
    nome di prima vale quando il nuovo non c'è; senza nessuno dei due il path è
    quello nuovo, e chi lo legge trova il piano assente. `path` è `None` quando
    il task file manca o il campo è vuoto, e il motivo lo dice."""
    task_file = orchestrator_common.find_task_file(project_root, orchestrator_common.docs_root(project_root), head)
    if task_file is None:
        return None, f"task file di {head} non trovato"
    with open(task_file, encoding="utf-8", errors="replace") as task_handle:
        folder = orchestrator_common.header_field(task_handle.read().splitlines(), "Folder")
    while folder.startswith("./"):
        folder = folder[2:]
    folder = folder.strip().rstrip("/")
    if not folder:
        return None, f"{head} non ha una task folder (campo Folder vuoto)"
    path = os.path.join(project_root, folder, PLAN_NAME)
    before = os.path.join(project_root, folder, PLAN_NAME_BEFORE)
    if not os.path.isfile(path) and os.path.isfile(before):
        return before, ""
    return path, ""


def load_plan(path):
    """(piano, motivo): il piano letto, o `None` e perché."""
    try:
        with open(path, encoding="utf-8", errors="replace") as plan_handle:
            text = plan_handle.read()
    except OSError:
        return None, f"piano assente: {path}"
    try:
        return parse_plan_text(text), ""
    except PlanError as error:
        return None, str(error)


# ---------------------------------------------------------------------------
# I membri dal lettore unico
# ---------------------------------------------------------------------------


def resolver_script():
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "task", "resolve-task.sh")


def read_members(project_root, head):
    """(membri, mancanti): le righe `TASK_MEMBER` e `TASK_MEMBER_MISSING` di
    `resolve-task.sh <id> --members`, nell'ordine del lettore.

    `PROJECT_ROOT` fissa la radice e `LOOM_TASK` si toglie: il lettore non deve
    risolvere una task diversa da quella chiesta. `bash` c'è su Linux e, su
    Windows, col Git Bash che gli script del plugin richiedono comunque.
    `PlanError` se il lettore non risponde."""
    environment = dict(os.environ, PROJECT_ROOT=project_root)
    environment.pop("LOOM_TASK", None)
    try:
        completed = subprocess.run(["bash", resolver_script(), head, "--members"], cwd=project_root,
                                   env=environment, stdin=subprocess.DEVNULL, capture_output=True,
                                   encoding="utf-8", errors="replace", timeout=RESOLVE_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError) as error:
        raise PlanError(f"lettore dei membri non eseguibile: {error}") from None
    if completed.returncode != 0:
        reason = completed.stderr.strip().splitlines()[-1:] or [f"exit {completed.returncode}"]
        raise PlanError(f"lettore dei membri: {reason[0]}")
    members, missing = [], []
    for line in completed.stdout.splitlines():
        if line.startswith("TASK_MEMBER="):
            members.append(line[len("TASK_MEMBER="):].split(" ", 1)[0])
        elif line.startswith("TASK_MEMBER_MISSING="):
            missing.append(line[len("TASK_MEMBER_MISSING="):].strip())
    return members, missing


# ---------------------------------------------------------------------------
# Il controllo
# ---------------------------------------------------------------------------


class Result:
    """L'esito di `check`. `errors` e `diffs` fermano l'orchestrator e mettono in
    pausa i passi nuovi dello script; `warnings` si dicono e basta; `commit` e
    `changed` contano solo al lancio."""

    def __init__(self):
        self.path = None
        self.plan = None
        self.state = None
        self.members = []
        self.missing = []
        self.errors = []
        self.diffs = []
        self.warnings = []
        self.commit = None
        self.commit_reason = ""
        self.changed = {}

    @property
    def blocking(self):
        return bool(self.errors or self.diffs)


def covers(member, target):
    """Vero se il «Dopo» di `member` ordina il membro dopo `target`: una voce
    su `target`, con o senza DLV, o la voce `*`."""
    return any(dependency.target in (target, ALL_OTHERS) for dependency in member.after)


def check_members(plan, members, missing, result):
    declared = members + missing
    for task_id in declared:
        if task_id not in plan.by_id:
            result.diffs.append(("membri", task_id, "membro del perimetro orchestrabile senza voce nel piano"))
    for task_id in plan.ids:
        if task_id not in declared:
            result.diffs.append(("membri", task_id, "voce del piano che non è un membro del perimetro orchestrabile"))


def is_open(state, task_id):
    task = state["tasks"].get(task_id)
    return task is not None and task.get("next") not in NOT_RUNNABLE


def known_task(state, task_id):
    return task_id in state["tasks"] or task_id in state["overview"] or \
        orchestrator_common.find_task_file(state["project_root"], state["docs"], task_id) is not None


def check_after(plan, state, result):
    """Le voci di «Dopo»: una task che esiste, un perimetro eseguibile dentro il
    numero dei DLV del membro che nomina. Poi P4: ogni dipendenza che un membro
    aperto dichiara verso un altro membro aperto sta nel suo «Dopo» — lo script
    legge l'ordine solo dal piano, e una dipendenza aggiunta dopo la stesura
    farebbe partire il membro troppo presto."""
    for member in plan.members:
        for dependency in member.after:
            if dependency.target == ALL_OTHERS:
                continue
            if not known_task(state, dependency.target):
                result.diffs.append(("dopo", member.id, f"{dependency.target} non esiste"))
                continue
            target = state["tasks"].get(dependency.target)
            if dependency.dlv and target is not None and target["file"] is not None \
                    and dependency.dlv[-1] > target["dlv"][1]:
                result.diffs.append(("dopo", member.id,
                                     f"{dependency.text}: {dependency.target} ha {target['dlv'][1]} DLV"))
    for member in plan.members:
        if not is_open(state, member.id):
            continue
        for item in state["tasks"][member.id].get("dependencies", []):
            if item["id"] in plan.by_id and item["prog"] != CLOSED and is_open(state, item["id"]) \
                    and not covers(member, item["id"]):
                source = "Dependencies" if item["source"] == "deps" else "grafo di tasks.md"
                result.diffs.append(("dopo", member.id,
                                     f"dipende da {item['id']} ({source}), che manca dal suo «dopo»"))


def check_materials(plan, state, result):
    """Ogni coppia di membri aperti con un path in comune che almeno uno dei
    due scrive (`CONFLICT … materiale` di `perimeter.py tree`) ha una risorsa in
    comune o un «Dopo» fra i due: senza, lo script li lancerebbe insieme."""
    for conflict in state["conflicts"]:
        if not conflict["reason"].startswith("materiale: "):
            continue
        first, second = conflict["tasks"]
        if first not in plan.by_id or second not in plan.by_id:
            continue
        one, other = plan.by_id[first], plan.by_id[second]
        if set(one.resources) & set(other.resources) or covers(one, second) or covers(other, first):
            continue
        result.diffs.append(("risorse", f"{first} · {second}",
                             f"{conflict['reason']} — nessuna risorsa in comune e nessun «dopo» fra i due"))


def check_steps(plan, state, result):
    """Il perimetro eseguibile dentro il numero dei DLV; e il passo di partenza
    contro i file, come avviso: un passo che non vale più non ferma niente,
    perché lo script parte dal passo che i file dicono."""
    for member in plan.members:
        task = state["tasks"].get(member.id)
        if task is None or task["file"] is None:
            continue
        done, total = task["dlv"]
        if member.dlv and member.dlv[-1] > total:
            result.diffs.append(("dlv", member.id, f"{member.dlv_text}: il membro ha {total} DLV"))
        if member.step is None or not is_open(state, member.id):
            continue
        if member.step == "preflight" and task["preflight"] == "ok":
            result.warnings.append(("passo", member.id, "preflight già fatto: il primo passo sarà quello dei file"))
        elif member.step == "run" and done >= total:
            result.warnings.append(("passo", member.id, "nessun DLV aperto: il primo passo sarà quello dei file"))
        elif member.step == "run" and task["next"] == "preflight" and \
                (task["preflight"] == "decaduta" or perimeter.is_size_large(task["size"])):
            result.diffs.append(("passo", member.id, "run-task rifiuta il run senza un preflight valido"))
        elif member.step == "checkpoint" and task["next"] == "preflight":
            result.diffs.append(("passo", member.id, "checkpoint su un membro senza preflight valido"))


def plan_commit(project_root, path, result):
    """Il commit del piano, o il motivo per cui non c'è: un piano non
    committato non è ancora un fatto, e `changed_members` non avrebbe da dove
    partire."""
    top = perimeter_analysis.repository_top(project_root)
    if top is None:
        result.commit_reason = "il progetto non è un repo git"
        return None, None
    rel = perimeter_analysis.relative_to(top, path)
    committed = perimeter_analysis.git(top, "show", f"HEAD:{rel}")
    if committed is None:
        result.commit_reason = "piano non committato"
        return top, None
    with open(path, encoding="utf-8", errors="replace") as plan_handle:
        if plan_handle.read() != committed:
            result.commit_reason = "il piano ha modifiche non committate"
            return top, None
    log = perimeter_analysis.git(top, "log", "-1", "--format=%H", "--", rel)
    if not log or not log.strip():
        result.commit_reason = "nessun commit del piano nella storia"
        return top, None
    return top, log.strip()


def check(project_root, head, history=True):
    """Il piano di `head` contro i file. Con `history` anche il commit del
    piano e i membri cambiati dopo: al lancio sì, nel ciclo dello script no.

    `PlanError` solo se il lettore dei membri non risponde; ogni altro guasto
    sta in `errors` o `diffs`."""
    result = Result()
    result.members, result.missing = read_members(project_root, head)
    path, reason = plan_path(project_root, head)
    if path is None:
        result.errors.append(reason)
        return result
    result.path = path
    result.plan, reason = load_plan(path)
    if result.plan is None:
        result.errors.append(reason)
        return result
    if result.plan.head != head:
        result.diffs.append(("perimetro", result.plan.head, f"il piano è di {result.plan.head}, non di {head}"))
    state = perimeter.snapshot(project_root, head, result.members)
    state["project_root"] = project_root
    state["docs"] = orchestrator_common.docs_root(project_root)
    result.state = state
    check_members(result.plan, result.members, result.missing, result)
    check_after(result.plan, state, result)
    check_materials(result.plan, state, result)
    check_steps(result.plan, state, result)
    if history:
        top, result.commit = plan_commit(project_root, path, result)
        if result.commit:
            open_members = {task_id for task_id in result.members if is_open(state, task_id)}
            tasks_rel = perimeter_analysis.relative_to(top, os.path.join(project_root, state["docs"], "tasks"))
            result.changed = perimeter_analysis.changed_members(top, tasks_rel, result.commit, open_members)
    return result


# ---------------------------------------------------------------------------
# Riga di comando
# ---------------------------------------------------------------------------


def relative(project_root, path):
    return os.path.relpath(path, project_root).replace(os.sep, "/")


def command_verify(project_root, head, draft=False):
    """`draft`: il piano appena scritto, non ancora committato. I controlli sui
    file restano tutti; il commit e i membri cambiati dopo non si guardano, e
    il verdetto è `ok` o `stop` sui soli `ERRORE` e `DIFF`."""
    try:
        result = check(project_root, head, history=not draft)
    except PlanError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    size = "?"
    task_file = orchestrator_common.find_task_file(project_root, orchestrator_common.docs_root(project_root), head)
    with open(task_file, encoding="utf-8", errors="replace") as task_handle:
        size = orchestrator_common.header_field(task_handle.read().splitlines(), "Size") or "?"
    # `mandate` è il nome di prima di `custom`, letto uguale.
    form = "custom" if size.lower().startswith(("custom", "mandate")) else "epica"
    print(f"PERIMETRO={head}|{form}")
    print(f"PLAN={relative(project_root, result.path) if result.path else 'assente'}")
    print(f"MEMBRI={len(result.members)}" + (f" (senza task file: {', '.join(result.missing)})" if result.missing else ""))
    for error in result.errors:
        print(f"ERRORE|{error}")
    if result.plan is not None and not draft:
        print(f"PLAN_COMMIT={result.commit[:12] if result.commit else f'? ({result.commit_reason})'}")
    for kind, who, detail in result.diffs:
        print(f"DIFF|{kind}|{who}|{detail}")
    for kind, who, detail in result.warnings:
        print(f"AVVISO|{kind}|{who}|{detail}")
    for task_id in result.members:
        if task_id in result.changed:
            print(f"CAMBIATO|{task_id}|{result.changed[task_id]}")
    if result.blocking or (result.commit is None and not draft):
        verdict = "stop"
    else:
        verdict = "riesame" if result.changed else "ok"
    print(f"VERIFY={verdict}")
    return 2 if verdict == "stop" else 0


def command_show(project_root, head):
    path, reason = plan_path(project_root, head)
    if path is None:
        print(f"ERRORE|{reason}")
        return 2
    plan, reason = load_plan(path)
    print(f"PLAN={relative(project_root, path)}")
    if plan is None:
        print(f"ERRORE|{reason}")
        return 2
    print(f"PERIMETRO={plan.head}")
    for member in plan.members:
        print(member.describe())
    return 0


def parse_arguments():
    parser = argparse.ArgumentParser(description="Il piano di un perimetro orchestrabile: orchestration-schedule.md")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    verify_parser = subcommands.add_parser("verify")
    verify_parser.add_argument("head", help="il perimetro orchestrabile: un'epica o una lista custom")
    verify_parser.add_argument("--bozza", action="store_true",
                               help="il piano non ancora committato: i soli controlli sui file, senza il commit")
    subcommands.add_parser("show").add_argument("head", help="il perimetro orchestrabile: un'epica o una lista custom")
    return parser.parse_args()


def main():
    orchestrator_common.setup_stdout()
    arguments = parse_arguments()
    if not TASK_ID_PATTERN.match(arguments.head):
        print(f"ERROR: id task malformato: '{arguments.head}' (atteso T<numero>)", file=sys.stderr)
        return 1
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else orchestrator_common.find_project_root(os.getcwd())
    if orchestrator_common.find_task_file(project_root, orchestrator_common.docs_root(project_root),
                                          arguments.head) is None:
        print(f"ERROR: task file di {arguments.head} non trovato", file=sys.stderr)
        return 1
    if arguments.command == "verify":
        return command_verify(project_root, arguments.head, arguments.bozza)
    return command_show(project_root, arguments.head)


if __name__ == "__main__":
    sys.exit(main())
