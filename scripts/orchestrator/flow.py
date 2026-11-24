"""
flow — lo script del flusso di un giro: porta il flusso meccanico, sveglia
l'orchestrator solo quando serve un giudizio.

  start     lancia il processo del flusso staccato, se non è già vivo, e
            aspetta la sua riga `avvio`. Riprende il flusso che trova; con
            `--nuovo` lo archivia, con gli ordini, e il giro riparte da zero
  status    se il processo del flusso è vivo: pid e ora d'avvio dal flusso,
            controllati sul processo vero
  wait      il Bash in background dell'orchestrator: esce alla prima riga
            `risveglio` con `seq` oltre `--dopo`, e stampa il recap da lì;
            esce anche quando il processo del flusso muore
  recap     lo stato del giro dal flusso: un membro per riga, il piano, il
            checkpoint; con `--dal` anche le righe dopo quel `seq`, per membro
  stop      ferma il processo del flusso
  prosegui | abbandona | tieni
            un ordine dell'orchestrator allo script, su un membro (o sul perimetro)
  run       il processo del flusso: lo lancia `start`, staccato

Il contratto — righe, motivi di risveglio, ordini, uscite — è
`docs/flow-format.md`. I file stanno in `.claude/loom/orchestrator/` del
progetto, ignorata da git (`flow_log.py`).

Uso:
  python -I flow.py [--project-root <radice>] start <perimetro> [--nuovo] [--context-threshold <token>] [--poll-seconds <s>]
  python -I flow.py [--project-root <radice>] status <perimetro>
  python -I flow.py [--project-root <radice>] wait <perimetro> --dopo <seq>
  python -I flow.py [--project-root <radice>] recap <perimetro> [--dal <seq>] [--testi]
  python -I flow.py [--project-root <radice>] stop <perimetro>
  python -I flow.py [--project-root <radice>] prosegui|abbandona|tieni <perimetro> <membro>

Exit: 0 ok · 1 errore (id malformato, processo che non parte) · 2 un altro
processo tiene il giro, flusso assente · 3 processo del flusso non vivo
(status, wait).
"""

import argparse
import os
import re
import signal
import subprocess
import sys
import time

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import flow_log  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import orchestrator_common  # noqa: E402

TASK_ID_PATTERN = re.compile(r"^T\d+$")
START_WAIT_S = 15
WAIT_POLL_S = 5
WAIT_LIVENESS_S = 30
STOP_WAIT_S = 10


# ---------------------------------------------------------------------------
# Il processo
# ---------------------------------------------------------------------------


def own_proc_start():
    """L'ora d'avvio di questo processo, nella forma con cui
    `orchestrator_common.process_is_alive` la confronta: il campo 22 di
    `/proc/<pid>/stat` su Linux, il FILETIME di creazione su Windows."""
    if orchestrator_common.IS_WINDOWS:
        try:
            created = orchestrator_common.windows_creation_filetime(os.getpid())
        except (OSError, AttributeError, ValueError):
            return ""
        return created if isinstance(created, str) else ""
    return orchestrator_common.linux_proc_start(os.getpid()) or ""


def liveness(paths, head):
    """(verdetto, riga `avvio`, stato del giro): `vivo`, `morto` o
    `assente`. Il pid si controlla con l'ora d'avvio: un pid riciclato non
    tiene vivo un flusso."""
    state, _ = flow_log.replay(paths["flow"], head)
    start = state.start
    if start is None:
        return "assente", None, state
    if state.end is not None:
        return "morto", start, state
    alive = orchestrator_common.process_is_alive(start.get("pid", -1), start.get("proc_start", ""))
    return ("morto" if alive is False else "vivo"), start, state


class Lock:
    """Il lock del giro: un solo processo del flusso per perimetro, anche con
    due `start` insieme. Tenuto aperto per la vita del processo."""

    def __init__(self, path):
        self.handle = open(path, "a+")

    def acquire(self):
        try:
            if orchestrator_common.IS_WINDOWS:
                import msvcrt
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return False
        return True


def command_run(project_root, head, arguments):
    import flow_engine  # solo qui: gli altri comandi non caricano gli scanner
    paths = flow_log.paths(project_root, head)
    os.makedirs(paths["dir"], exist_ok=True)
    lock = Lock(paths["lock"])
    if not lock.acquire():
        print(f"un altro processo del flusso tiene il giro di {head}", file=sys.stderr)
        return 2
    engine = flow_engine.Engine(project_root, head, threshold=arguments.context_threshold,
                                poll_seconds=arguments.poll_seconds, keepalive_minutes=arguments.keepalive_minutes)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    engine.write("avvio", pid=os.getpid(), proc_start=own_proc_start(), soglia=arguments.context_threshold,
                 poll=arguments.poll_seconds, script=os.path.abspath(__file__))
    reason = "giri finiti"
    try:
        rounds = 0
        while True:
            if not engine.tick():
                reason = "orchestrator fermo"
                break
            rounds += 1
            if arguments.giri and rounds >= arguments.giri:
                break
            time.sleep(arguments.poll_seconds)
    except SystemExit:
        reason = "fermato"
    except KeyboardInterrupt:
        reason = "interrotto"
    finally:
        engine.write("fine", motivo=reason)
    return 0


def archive(paths, start):
    """Il flusso e gli ordini di un giro chiuso, rinominati con l'ora del
    loro primo avvio: restano su disco per chi misura il giro, e nessun
    processo li rilegge."""
    stamp = re.sub(r"[^0-9]", "", (start or {}).get("ts", "") or flow_log.now_iso())[:14]
    moved = []
    for key in ("flow", "orders"):
        if os.path.exists(paths[key]):
            base, extension = os.path.splitext(paths[key])
            target = f"{base}.{stamp}{extension}"
            os.replace(paths[key], target)
            moved.append(target)
    return moved


def command_start(project_root, head, arguments):
    paths = flow_log.paths(project_root, head)
    verdict, start, state = liveness(paths, head)
    if verdict == "vivo":
        if arguments.nuovo:
            print(f"FLOW=vivo\nPID={start['pid']}\nERRORE|un giro nuovo vuole il processo fermo: flow.py stop {head}")
            return 2
        print(f"FLOW=vivo\nPID={start['pid']}\nSEQ={state.last_seq}")
        return 0
    os.makedirs(paths["dir"], exist_ok=True)
    if arguments.nuovo:
        first = next((row for row in flow_log.read_rows(paths["flow"])[0] if row.get("tipo") == "avvio"), None)
        for target in archive(paths, first):
            print(f"ARCHIVIATO={os.path.relpath(target, project_root)}")
    command = [sys.executable, "-B", "-I", os.path.abspath(__file__), "--project-root", project_root, "run", head,
               "--context-threshold", str(arguments.context_threshold),
               "--poll-seconds", str(arguments.poll_seconds),
               "--keepalive-minutes", str(arguments.keepalive_minutes)]
    with open(paths["log"], "a", encoding="utf-8") as log_handle:
        options = {"stdin": subprocess.DEVNULL, "stdout": log_handle, "stderr": log_handle, "close_fds": True,
                   "cwd": project_root}
        if orchestrator_common.IS_WINDOWS:
            options["creationflags"] = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
                                        | subprocess.CREATE_NO_WINDOW)
        else:
            options["start_new_session"] = True
        child = subprocess.Popen(command, **options)
    deadline = time.time() + START_WAIT_S
    while time.time() < deadline:
        time.sleep(0.2)
        verdict, start, state = liveness(paths, head)
        if verdict == "vivo" and start.get("pid") == child.pid:
            print(f"FLOW=avviato\nPID={child.pid}\nSEQ={state.last_seq}")
            return 0
        if child.poll() is not None:
            break
    print("FLOW=non partito")
    try:
        with open(paths["log"], encoding="utf-8", errors="replace") as log_handle:
            tail = log_handle.read().strip().splitlines()[-5:]
    except OSError:
        tail = []
    for line in tail:
        print(f"LOG|{line}")
    return 2 if child.poll() == 2 else 1


def command_status(project_root, head):
    paths = flow_log.paths(project_root, head)
    verdict, start, state = liveness(paths, head)
    print(f"FLOW={verdict}")
    if start is not None:
        print(f"PID={start.get('pid')}\nAVVIATO={start.get('ts')}")
        if state.end is not None:
            print(f"FINE={state.end.get('ts')} ({state.end.get('motivo')})")
    print(f"SEQ={state.last_seq}")
    return 0 if verdict == "vivo" else 3


def command_stop(project_root, head):
    paths = flow_log.paths(project_root, head)
    verdict, start, _ = liveness(paths, head)
    if verdict != "vivo":
        print(f"FLOW={verdict}")
        return 0
    try:
        os.kill(start["pid"], signal.SIGTERM)
    except OSError as error:
        print(f"FLOW=vivo\nERRORE|{error}")
        return 1
    deadline = time.time() + STOP_WAIT_S
    while time.time() < deadline:
        if orchestrator_common.process_is_alive(start["pid"], start.get("proc_start", "")) is not True:
            print("FLOW=fermato")
            return 0
        time.sleep(0.2)
    print("FLOW=vivo\nERRORE|il processo non si è fermato in tempo")
    return 1


def command_order(project_root, head, order, member):
    if not TASK_ID_PATTERN.match(member):
        print(f"ERROR: membro malformato: '{member}' (atteso T<numero>)", file=sys.stderr)
        return 1
    entry = flow_log.append_order(flow_log.paths(project_root, head)["orders"], order, member)
    print(f"ORDINE={entry['n']}|{order}|{member}")
    return 0


# ---------------------------------------------------------------------------
# Il recap
# ---------------------------------------------------------------------------


def short(session):
    return (session or "")[:8] or "-"


def step_line(member, step, state):
    held = state.held.get(member)
    parts = [f"MEMBRO|{member}"]
    if step is None:
        parts.append("nessun passo")
    else:
        parts.append(f"{step.get('passo')} {step.get('fase')}")
        if step.get("dlv"):
            parts.append("dlv=" + ",".join(str(number) for number in step["dlv"]))
        parts.append(f"sessione={short(step.get('sessione'))}")
        if step.get("titolo"):
            parts.append(f"titolo={step['titolo']}")
        if step.get("dettaglio"):
            parts.append(f"nota={step['dettaglio']}")
    if held is not None:
        parts.append(f"fermo={held or 'sì'}")
    return "|".join(parts)


def checkpoint_line(state):
    for member, step in state.open_steps().items():
        if step.get("passo") == "checkpoint" or step.get("fase") == "checkpoint" \
                or step.get("corrente") == "checkpoint" \
                or (step.get("genere") == "checkpoint" and step.get("fase") in ("attesa", "turno")):
            return f"CHECKPOINT={member} {short(step.get('sessione'))}"
    return "CHECKPOINT=libero"


def row_text(row):
    kind = row.get("tipo")
    if kind == "risveglio":
        return (f"RISVEGLIO|{row['seq']}|{row.get('motivo')}|{row.get('membro') or '-'}|"
                f"{short(row.get('sessione'))}|{row.get('dettaglio') or ''}")
    if kind == "evento":
        return f"{row['seq']} {row.get('testo')}"
    if kind == "passo":
        extra = f" · {row['dettaglio']}" if row.get("dettaglio") else ""
        return (f"{row['seq']} {row.get('membro')} passo {row.get('passo')} → {row.get('fase')}"
                f" · {short(row.get('sessione'))}{extra}")
    if kind == "turno":
        return (f"{row['seq']} {row.get('membro')} turno {row.get('turno')} {row.get('genere')} · "
                f"{row.get('esito')} · {row.get('verdetto')} · {row.get('out')}")
    if kind in ("fermo", "libero"):
        return f"{row['seq']} {row.get('membro')} {kind}" + (f" · {row['motivo']}" if row.get("motivo") else "")
    if kind == "ordine":
        return f"{row['seq']} {row.get('membro')} ordine {row.get('n')} {row.get('ordine')} · {row.get('esito')}"
    if kind == "piano":
        return f"{row['seq']} piano {row.get('stato')}" + (f" · {row['motivo']}" if row.get("motivo") else "")
    if kind == "guasto":
        return f"{row['seq']} guasto {row.get('dove')}: {row.get('errore')}"
    if kind in ("avvio", "fine"):
        return f"{row['seq']} processo {kind}" + (f" · {row['motivo']}" if row.get("motivo") else "")
    return f"{row['seq']} {kind}"


def member_of(row):
    if row.get("membro"):
        return row["membro"]
    tasks = row.get("task") or []
    return tasks[0] if len(tasks) == 1 else "-"


def print_recap(project_root, head, after=None, texts=False):
    paths = flow_log.paths(project_root, head)
    verdict, start, state = liveness(paths, head)
    rows, _ = flow_log.read_rows(paths["flow"])
    print(f"FLOW={verdict}" + (f" · pid {start.get('pid')} · avviato {start.get('ts')}" if start else ""))
    print(f"SEQ={state.last_seq}")
    plan = state.plan or {}
    if plan:
        detail = plan.get("sha") or plan.get("motivo") or ""
        print(f"PIANO={plan.get('stato')}" + (f" · {detail}" if detail else ""))
    else:
        print("PIANO=non letto")
    print(checkpoint_line(state))
    print(f"CICLI={state.closed_cycles} chiusi · {state.cycles} dall'ultimo checkpoint del perimetro")
    members = list(plan.get("membri") or [])
    for member in sorted(set(state.steps) | set(state.held), key=lambda task_id: int(task_id[1:])):
        if member not in members:
            members.append(member)
    for member in members:
        print(step_line(member, state.steps.get(member), state))
    if after is None:
        return
    later = [row for row in rows if row["seq"] > after]
    for row in later:
        if row.get("tipo") == "risveglio":
            print(row_text(row))
    groups = {}
    for row in later:
        if row.get("tipo") not in ("risveglio", "prima"):
            groups.setdefault(member_of(row), []).append(row)
    for member in sorted(groups, key=lambda key: (key == "-", key)):
        print(f"--- {member}")
        for row in groups[member]:
            print(row_text(row))
            if texts and row.get("tipo") == "turno":
                text = (row.get("testo") or "").strip()
                if text:
                    print("    " + text.replace("\n", "\n    "))


def command_wait(project_root, head, after):
    paths = flow_log.paths(project_root, head)
    if not os.path.exists(paths["flow"]):
        print("FLOW=assente")
        return 2
    offset = 0
    last_check = 0.0
    while True:
        rows, offset = flow_log.read_rows(paths["flow"], offset)
        if any(row.get("tipo") == "risveglio" and row["seq"] > after for row in rows):
            print_recap(project_root, head, after)
            return 0
        now = time.time()
        if now - last_check >= WAIT_LIVENESS_S:
            last_check = now
            verdict, _, _ = liveness(paths, head)
            if verdict != "vivo":
                print_recap(project_root, head, after)
                return 3
        time.sleep(WAIT_POLL_S)


# ---------------------------------------------------------------------------
# Riga di comando
# ---------------------------------------------------------------------------


def parse_arguments():
    parser = argparse.ArgumentParser(description="Lo script del flusso di un giro dell'orchestrator")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    for name in ("start", "run"):
        sub = subcommands.add_parser(name)
        sub.add_argument("head", help="il perimetro: un'epica o un mandato")
        sub.add_argument("--context-threshold", type=int, default=0,
                         help="soglia di contesto dell'orchestrator in token; 0 = nessuna misura")
        sub.add_argument("--poll-seconds", type=float, default=15)
        sub.add_argument("--keepalive-minutes", type=float, default=55)
        if name == "run":
            sub.add_argument("--giri", type=int, default=0, help="esce dopo tanti giri; 0 = mai")
        else:
            sub.add_argument("--nuovo", action="store_true",
                             help="giro nuovo: archivia flusso e ordini del giro prima invece di riprenderli")
    for name in ("status", "stop"):
        subcommands.add_parser(name).add_argument("head")
    wait_parser = subcommands.add_parser("wait")
    wait_parser.add_argument("head")
    wait_parser.add_argument("--dopo", type=int, required=True, help="l'ultimo seq già letto")
    recap_parser = subcommands.add_parser("recap")
    recap_parser.add_argument("head")
    recap_parser.add_argument("--dal", type=int, default=None, help="le righe dopo questo seq, per membro")
    recap_parser.add_argument("--testi", action="store_true", help="col testo finale di ogni turno")
    for name in flow_log.ORDERS:
        sub = subcommands.add_parser(name)
        sub.add_argument("head")
        sub.add_argument("member")
    return parser.parse_args()


def main():
    orchestrator_common.setup_stdout()
    arguments = parse_arguments()
    if not TASK_ID_PATTERN.match(arguments.head):
        print(f"ERROR: id task malformato: '{arguments.head}' (atteso T<numero>)", file=sys.stderr)
        return 1
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else orchestrator_common.find_project_root(os.getcwd())
    command = arguments.command
    if command == "run":
        return command_run(project_root, arguments.head, arguments)
    if command == "start":
        return command_start(project_root, arguments.head, arguments)
    if command == "status":
        return command_status(project_root, arguments.head)
    if command == "stop":
        return command_stop(project_root, arguments.head)
    if command == "wait":
        return command_wait(project_root, arguments.head, arguments.dopo)
    if command == "recap":
        print_recap(project_root, arguments.head, arguments.dal, arguments.testi)
        return 0
    return command_order(project_root, arguments.head, command, arguments.member)


if __name__ == "__main__":
    sys.exit(main())
