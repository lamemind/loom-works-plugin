"""
orchestrator_state — lo stato su disco dell'orchestrator di un perimetro orchestrabile:
dove sta, di chi è.

  check   al lancio dell'orchestrator: i path, la cartella creata, il controllo
          che git la ignori, e il verdetto su ciò che l'orchestrator trova — un giro
          nuovo, una ripresa, o una ragione per fermarsi
  facts   per `checkpoint-perimeter`: la sezione `## Fatti del perimetro` dello
          stato, se lo stato è di questo perimetro orchestrabile

I file stanno in `<radice>/.claude/loom/orchestrator/`, col nome ricavato
dall'id del perimetro orchestrabile. Due li tocca questo script:

  T<id>.md           lo stato dell'orchestrator, scritto dall'orchestrator col tool `Write`
  T<id>-watch.json   il punto di lettura degli scanner del monitor, scritto
                     dallo script del flusso

Gli altri — il flusso del giro, gli ordini, il lock e il log dello script del
flusso — sono di `flow_log.py`, e il giro nuovo li archivia con `flow.py start
--nuovo`.

Non nella scratchpad della conversazione: sta nella temp di sistema, e un
reboot o una pulizia la svuotano a giro aperto. Non nella task folder del
perimetro orchestrabile: è tracciata, quindi lo stato riscritto a ogni giro
terrebbe sporco il worktree, e un commit che nomina la cartella intera nella sua
pathspec porterebbe nel commit lo stato a metà giro. `.claude/loom/` è ignorata da git
dove il progetto la ignora, e `check` lo verifica: dove non la ignora l'orchestrator si
ferma, perché `init` non scrive la regola.

La testa dello stato, le prime righe prima del primo heading:

  Stato: attiva · <sessionId>       un orchestrator in corso, e la sessione che lo tiene
  Stato: in passaggio · <sessionId> l'orchestrator ha chiesto il successore e
                                    aspetta che nasca: il passaggio di consegne
                                    è cominciato, e chi lo tiene è ancora lui
  Stato: passata a <nuova> · da <vecchia>
                                    consegne passate: il successore e l'orchestrator
                                    che le ha passate, che il successore chiude
  Stato: ferma · <sessionId>        l'orchestrator si è fermato allo stop
  Perimetro: T<id> · Created on <data del task file del perimetro orchestrabile>

`in passaggio` esiste perché il `sessionId` del successore si conosce solo
dopo lo spawn: senza la riga intermedia, un successore che legge lo stato
prima che l'orchestrator vecchio scriva `passata a` troverebbe `attiva` di una
sessione viva, e si fermerebbe.

La riga `Perimetro` è l'identità. Un id non identifica un perimetro orchestrabile
per sempre: `get-next-task-id.sh` dà il massimo più uno fra i task file e le righe
di `tasks.md`, quindi l'id di un perimetro orchestrabile purgato torna a una task
nuova se era il
più alto, e lo stato vecchio resterebbe col suo nome. Uno stato il cui
`Created on` non è quello del task file vale come assente. Nessuno script
cancella lo stato: l'orchestrator allo stop toglierebbe i fatti prima che un
`checkpoint-perimeter` lanciato a mano li legga.

Verdetti di `check` (riga `STATE=`):

  assente      nessuno stato: giro nuovo                               exit 0
  altro        lo stato di un perimetro orchestrabile passato con lo stesso id:
               giro nuovo, l'orchestrator lo sovrascrive                     exit 0
  ferma        un orchestrator fermato: giro nuovo che eredita i fatti       exit 0
  mia          `attiva` o `in passaggio` scritta da questa sessione:
               ripresa                                                 exit 0
  consegne     `passata a` questa sessione: la ripresa del
               successore, delega compresa (`STATE_FROM` = l'orchestrator
               che ha passato le consegne)                             exit 0
  morta        `attiva`, `in passaggio` o `passata a` di una sessione
               che non è più viva: ripresa, senza la delega            exit 0
  viva         `attiva` o `passata a` di un'altra sessione viva        exit 2
  in passaggio `in passaggio` di un'altra sessione viva, anche dopo
               l'attesa di --wait: l'orchestrator vecchio non ha finito      exit 2
  illeggibile  il file c'è, ma la testa non si legge                   exit 2

Con --wait <secondi>, su `in passaggio` di un'altra sessione viva `check`
rilegge lo stato ogni WAIT_POLL_S secondi, fino al tetto: è l'attesa del
successore mentre l'orchestrator vecchio chiude il passaggio.

Un giro nuovo toglie `-watch.json`: gli scanner ripartiti su un file vecchio
darebbero come eventi tutto ciò che è cambiato dallo stop precedente. Una
ripresa lo tiene, e gli scanner ripartono dal punto in cui erano.

Uso:
  python -I orchestrator_state.py [--project-root <radice>] check <id del perimetro orchestrabile> --own-session <session id> [--wait <secondi>]
  python -I orchestrator_state.py [--project-root <radice>] facts <id del perimetro orchestrabile>

Exit: 0 avanti · 1 id malformato, task file del perimetro orchestrabile mancante, registro
delle sessioni illeggibile · 2 l'orchestrator si ferma: cartella non ignorata da git,
o uno dei verdetti sopra.
"""

import argparse
import os
import re
import subprocess
import sys
import time

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import orchestrator_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)

TASK_ID_PATTERN = re.compile(r"^T\d+$")
STATE_DIR = os.path.join(".claude", "loom", "orchestrator")
GITIGNORE_RULE = ".claude/loom/"

STATE_LINE = re.compile(r"^Stato:\s*(attiva|ferma|in passaggio)\s*·\s*(\S+)\s*$")
HANDED_LINE = re.compile(r"^Stato:\s*passata a\s+(\S+?)(?:\s*·\s*da\s+(\S+))?\s*$")
IDENTITY_LINE = re.compile(r"^Perimetro:\s*(T\d+)\s*·\s*Created on\s*(.*?)\s*$")
FACTS_HEADING = "## Fatti del perimetro"

GO, STOP = 0, 2
VERDICT_EXIT = {"assente": GO, "altro": GO, "ferma": GO, "mia": GO, "consegne": GO, "morta": GO,
                "viva": STOP, "in passaggio": STOP, "illeggibile": STOP}
NEW_ROUND = {"assente", "altro", "ferma"}
# Ogni quanto `check --wait` rilegge uno stato `in passaggio`.
WAIT_POLL_S = 10


def state_paths(project_root, perimeter):
    directory = os.path.join(project_root, STATE_DIR)
    return {"dir": directory,
            "state": os.path.join(directory, f"{perimeter}.md"),
            "watch": os.path.join(directory, f"{perimeter}-watch.json")}


def perimeter_created_on(project_root, perimeter):
    """Il `Created on` del task file del perimetro orchestrabile: `None` se il file non c'è,
    stringa vuota se il campo manca."""
    path = orchestrator_common.find_task_file(project_root, orchestrator_common.docs_root(project_root), perimeter)
    if path is None:
        return None
    with open(path, encoding="utf-8", errors="replace") as task_handle:
        return orchestrator_common.header_field(task_handle.read().splitlines(), "Created on")


def read_head(state_path):
    """La testa dello stato: `{kind, holder, perimeter, created_on}` più
    `from` su `passata a … · da …`, oppure `None` se manca la riga `Stato:` o
    la riga `Perimetro:`.

    La testa sono le righe prima del primo heading: l'orchestrator la scrive in cima
    e riscrive il file intero a ogni cambio."""
    head = {}
    with open(state_path, encoding="utf-8", errors="replace") as state_handle:
        for line in state_handle:
            line = line.rstrip("\n").strip()
            if line.startswith("#"):
                break
            state_match = STATE_LINE.match(line)
            handed_match = HANDED_LINE.match(line)
            identity_match = IDENTITY_LINE.match(line)
            if state_match:
                head["kind"], head["holder"] = state_match.group(1), state_match.group(2)
            elif handed_match:
                head["kind"], head["holder"] = "passata", handed_match.group(1)
                if handed_match.group(2):
                    head["from"] = handed_match.group(2)
            elif identity_match:
                head["perimeter"], head["created_on"] = identity_match.group(1), identity_match.group(2)
    if "kind" not in head or "perimeter" not in head:
        return None
    return head


def same_session(first, second):
    """Due session id sono la stessa sessione: uguali, o uno prefisso dell'altro
    (l'orchestrator può scrivere l'id corto)."""
    return bool(first and second) and (first.startswith(second) or second.startswith(first))


def gitignore_state(project_root, state_path):
    """`si` se git ignora il file di stato, `no` se non lo ignora, `fuori da
    git` se il progetto non è un repo, `?` se git non risponde.

    Il file non deve esistere: `check-ignore` confronta il path con le regole,
    e `.claude/loom/` copre tutto ciò che sta sotto. Il caso «non è un repo» si
    riconosce dall'exit di `rev-parse`, non dal messaggio, che git traduce."""
    try:
        inside = subprocess.run(["git", "-C", project_root, "rev-parse", "--is-inside-work-tree"],
                                capture_output=True, text=True)
        if inside.returncode != 0:
            return "fuori da git"
        result = subprocess.run(["git", "-C", project_root, "check-ignore", "-q", "--", state_path],
                                capture_output=True, text=True)
    except OSError:
        return "?"
    return {0: "si", 1: "no"}.get(result.returncode, "?")


def verdict_of(head, perimeter, created_on, own_session, live_session_ids):
    if head is None:
        return "illeggibile"
    if head["perimeter"] != perimeter or head["created_on"] != created_on:
        return "altro"
    if head["kind"] == "ferma":
        return "ferma"
    holder = head["holder"]
    if same_session(holder, own_session):
        return "consegne" if head["kind"] == "passata" else "mia"
    if any(same_session(holder, session_id) for session_id in live_session_ids):
        return "in passaggio" if head["kind"] == "in passaggio" else "viva"
    return "morta"


def read_verdict(project_root, paths, perimeter, created_on, own_session):
    """`(verdetto, testa)` dello stato su disco, o `None` se il registro delle
    sessioni non si legge."""
    if not os.path.exists(paths["state"]):
        return "assente", None
    head = read_head(paths["state"])
    live_session_ids = []
    if head is not None and head["kind"] != "ferma":
        registry = orchestrator_common.read_registry(project_root)
        if not registry.readable:
            return None
        live_session_ids = [session.session_id for session in registry.sessions]
    return verdict_of(head, perimeter, created_on, own_session, live_session_ids), head


def command_check(project_root, perimeter, own_session, wait_seconds=0):
    created_on = perimeter_created_on(project_root, perimeter)
    if created_on is None:
        print(f"ERROR: task file di {perimeter} non trovato", file=sys.stderr)
        return 1
    paths = state_paths(project_root, perimeter)
    print(f"STATE_DIR={paths['dir']}")
    print(f"STATE_FILE={paths['state']}")
    print(f"WATCH_FILE={paths['watch']}")
    print(f"CREATED_ON={created_on}")

    ignored = gitignore_state(project_root, paths["state"])
    print(f"IGNORED={ignored}")
    if ignored == "no":
        print(f"IGNORE_RULE={GITIGNORE_RULE}")
        print("CHECK=stop")
        return STOP
    os.makedirs(paths["dir"], exist_ok=True)

    deadline = time.monotonic() + max(wait_seconds, 0)
    waited = 0
    while True:
        found = read_verdict(project_root, paths, perimeter, created_on, own_session)
        if found is None:
            print("ERROR: registro delle sessioni illeggibile: ~/.claude/sessions", file=sys.stderr)
            return 1
        verdict, head = found
        if verdict != "in passaggio" or time.monotonic() >= deadline:
            break
        time.sleep(WAIT_POLL_S)
        waited += WAIT_POLL_S
    print(f"STATE={verdict}")
    if wait_seconds > 0:
        print(f"WAITED={waited}")
    if head is not None:
        print(f"STATE_KIND={head['kind']}")
        print(f"STATE_HOLDER={head['holder']}")
        if head.get("from"):
            print(f"STATE_FROM={head['from']}")
        print(f"STATE_CREATED_ON={head['created_on']}")

    if verdict in NEW_ROUND:
        if os.path.exists(paths["watch"]):
            os.remove(paths["watch"])
            print("WATCH=tolto")
        else:
            print("WATCH=assente")
        print("ROUND=nuovo")
    elif VERDICT_EXIT[verdict] == GO:
        print(f"WATCH={'resta' if os.path.exists(paths['watch']) else 'assente'}")
        print("ROUND=ripresa")
    print(f"CHECK={'ok' if VERDICT_EXIT[verdict] == GO else 'stop'}")
    return VERDICT_EXIT[verdict]


def facts_section(state_path):
    """I fatti della sezione `## Fatti del perimetro`, uno per voce: una riga
    che comincia con `- ` apre un fatto, una riga indentata lo continua."""
    facts, inside = [], False
    with open(state_path, encoding="utf-8", errors="replace") as state_handle:
        for raw_line in state_handle:
            line = raw_line.rstrip("\n")
            if line.startswith("## ") or line.startswith("# "):
                inside = line.strip() == FACTS_HEADING
                continue
            if not inside or not line.strip() or line.strip().startswith("<!--"):
                continue
            if line.startswith("- "):
                facts.append(line[2:].strip())
            elif facts and line[:1].isspace():
                facts[-1] += " " + line.strip()
    return facts


def command_facts(project_root, perimeter):
    created_on = perimeter_created_on(project_root, perimeter)
    if created_on is None:
        print(f"ERROR: task file di {perimeter} non trovato", file=sys.stderr)
        return 1
    paths = state_paths(project_root, perimeter)
    print(f"STATE_FILE={paths['state']}")
    if not os.path.exists(paths["state"]):
        print("STATE=assente")
        print("FATTI=0")
        return 0
    head = read_head(paths["state"])
    if head is None:
        print("STATE=illeggibile")
        print("FATTI=0")
        return 0
    if head["perimeter"] != perimeter or head["created_on"] != created_on:
        print("STATE=altro")
        print(f"STATE_CREATED_ON={head['created_on']}")
        print("FATTI=0")
        return 0
    print("STATE=presente")
    print(f"STATE_KIND={head['kind']}")
    facts = facts_section(paths["state"])
    for fact in facts:
        print(f"FATTO|{fact}")
    print(f"FATTI={len(facts)}")
    return 0


def parse_arguments():
    parser = argparse.ArgumentParser(description="Lo stato su disco dell'orchestrator di un perimetro orchestrabile")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    check_parser = subcommands.add_parser("check")
    check_parser.add_argument("perimeter", help="l'id del perimetro orchestrabile: un'epica o una lista custom")
    check_parser.add_argument("--own-session", required=True, help="session id dell'orchestrator che chiede")
    check_parser.add_argument("--wait", type=int, default=0,
                              help="secondi di attesa su `in passaggio` di un'altra sessione viva")
    facts_parser = subcommands.add_parser("facts")
    facts_parser.add_argument("perimeter", help="l'id del perimetro orchestrabile: un'epica o una lista custom")
    return parser.parse_args()


def main():
    orchestrator_common.setup_stdout()
    arguments = parse_arguments()
    if not TASK_ID_PATTERN.match(arguments.perimeter):
        print(f"ERROR: id task malformato: '{arguments.perimeter}' (atteso T<numero>)", file=sys.stderr)
        return 1
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else orchestrator_common.find_project_root(os.getcwd())
    if arguments.command == "check":
        return command_check(project_root, arguments.perimeter, arguments.own_session, arguments.wait)
    return command_facts(project_root, arguments.perimeter)


if __name__ == "__main__":
    sys.exit(main())
