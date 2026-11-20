"""
regia_state — lo stato su disco della regia di un perimetro: dove sta, di chi è.

  check   al lancio della regia: i tre path, la cartella creata, il controllo
          che git la ignori, e il verdetto su ciò che la regia trova — un giro
          nuovo, una ripresa, o una ragione per fermarsi
  facts   per `checkpoint-mandate`: la sezione `## Fatti del perimetro` dello
          stato, se lo stato è di questo perimetro

I quattro file stanno in `<radice>/.claude/loom/regia/`, col nome ricavato
dall'id del perimetro:

  T<id>.md           lo stato della regia, scritto dalla regia col tool `Write`
  T<id>-prima.json   le cifre di partenza, scritte da `mandate.py tree --save`
  T<id>-watch.json   il punto da cui riparte il monitor, scritto da
                     `watch_sessions.py --state`
  T<id>-filter.json  whitelist e blacklist del monitor, scritte dalla regia col
                     tool `Write` e lette da `watch_sessions.py --filter`

Non nella scratchpad della conversazione: sta nella temp di sistema, e un
reboot o una pulizia la svuotano a giro aperto. Non nella task folder del
perimetro: è tracciata, e il `git add -A` di un `checkpoint-task` linked
porterebbe nel commit lo stato a metà giro. `.claude/loom/` è ignorata da git
dove il progetto la ignora, e `check` lo verifica: dove non la ignora la regia si
ferma, perché `init` non scrive la regola.

La testa dello stato, le prime righe prima del primo heading:

  Stato: attiva · <sessionId>       una regia in corso, e la sessione che la tiene
  Stato: passata a <sessionId>      consegne passate a un'altra sessione
  Stato: ferma · <sessionId>        la regia si è fermata allo stop
  Perimetro: T<id> · Created on <data del task file del perimetro>

La riga `Perimetro` è l'identità. Un id non identifica un perimetro per sempre:
`get-next-task-id.sh` dà il massimo più uno fra i task file e le righe di
`tasks.md`, quindi l'id di un perimetro purgato torna a una task nuova se era il
più alto, e lo stato vecchio resterebbe col suo nome. Uno stato il cui
`Created on` non è quello del task file vale come assente. Nessuno script
cancella lo stato: la regia allo stop toglierebbe i fatti prima che un
`checkpoint-mandate` lanciato a mano li legga.

Verdetti di `check` (riga `STATE=`):

  assente      nessuno stato: giro nuovo                               exit 0
  altro        lo stato di un perimetro passato con lo stesso id:
               giro nuovo, la regia lo sovrascrive                     exit 0
  ferma        una regia fermata: giro nuovo che eredita i fatti       exit 0
  mia          `attiva` scritta da questa sessione: ripresa            exit 0
  morta        `attiva` o `passata a` di una sessione che non è
               più viva: ripresa, senza la delega                      exit 0
  viva         `attiva` o `passata a` di un'altra sessione viva        exit 2
  passata      `passata a` questa sessione: la ripresa della
               successora non c'è ancora                               exit 2
  illeggibile  il file c'è, ma la testa non si legge                   exit 2

Un giro nuovo toglie `-watch.json` (il monitor darebbe come eventi tutto ciò
che è cambiato dallo stop precedente) e `-filter.json` (le conversazioni che
l'utente ha escluso valgono per il giro, come la delega), e chiede di
riscrivere `-prima.json`; una ripresa li tiene, e riscrive le cifre solo se
mancano.

Uso:
  python -I regia_state.py [--project-root <radice>] check <perimetro> --own-session <session id>
  python -I regia_state.py [--project-root <radice>] facts <perimetro>

Exit: 0 avanti · 1 id malformato, task file del perimetro mancante, registro
delle sessioni illeggibile · 2 la regia si ferma: cartella non ignorata da git,
o uno dei verdetti sopra.
"""

import argparse
import os
import re
import subprocess
import sys

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import regia_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)

TASK_ID_PATTERN = re.compile(r"^T\d+$")
STATE_DIR = os.path.join(".claude", "loom", "regia")
GITIGNORE_RULE = ".claude/loom/"

STATE_LINE = re.compile(r"^Stato:\s*(attiva|ferma)\s*·\s*(\S+)\s*$")
HANDED_LINE = re.compile(r"^Stato:\s*passata a\s+(\S+)\s*$")
IDENTITY_LINE = re.compile(r"^Perimetro:\s*(T\d+)\s*·\s*Created on\s*(.*?)\s*$")
FACTS_HEADING = "## Fatti del perimetro"

GO, STOP = 0, 2
VERDICT_EXIT = {"assente": GO, "altro": GO, "ferma": GO, "mia": GO, "morta": GO,
                "viva": STOP, "passata": STOP, "illeggibile": STOP}
NEW_ROUND = {"assente", "altro", "ferma"}


def state_paths(project_root, perimeter):
    directory = os.path.join(project_root, STATE_DIR)
    return {"dir": directory,
            "state": os.path.join(directory, f"{perimeter}.md"),
            "before": os.path.join(directory, f"{perimeter}-prima.json"),
            "watch": os.path.join(directory, f"{perimeter}-watch.json"),
            "filter": os.path.join(directory, f"{perimeter}-filter.json")}


def perimeter_created_on(project_root, perimeter):
    """Il `Created on` del task file del perimetro: `None` se il file non c'è,
    stringa vuota se il campo manca."""
    path = regia_common.find_task_file(project_root, regia_common.docs_root(project_root), perimeter)
    if path is None:
        return None
    with open(path, encoding="utf-8", errors="replace") as task_handle:
        return regia_common.header_field(task_handle.read().splitlines(), "Created on")


def read_head(state_path):
    """La testa dello stato: `{kind, holder, perimeter, created_on}`, oppure
    `None` se manca la riga `Stato:` o la riga `Perimetro:`.

    La testa sono le righe prima del primo heading: la regia la scrive in cima
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
            elif identity_match:
                head["perimeter"], head["created_on"] = identity_match.group(1), identity_match.group(2)
    if "kind" not in head or "perimeter" not in head:
        return None
    return head


def same_session(first, second):
    """Due session id sono la stessa sessione: uguali, o uno prefisso dell'altro
    (la regia può scrivere l'id corto)."""
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
    if head["kind"] == "attiva" and same_session(holder, own_session):
        return "mia"
    if head["kind"] == "passata" and same_session(holder, own_session):
        return "passata"
    if any(same_session(holder, session_id) for session_id in live_session_ids):
        return "viva"
    return "morta"


def command_check(project_root, perimeter, own_session):
    created_on = perimeter_created_on(project_root, perimeter)
    if created_on is None:
        print(f"ERROR: task file di {perimeter} non trovato", file=sys.stderr)
        return 1
    paths = state_paths(project_root, perimeter)
    print(f"STATE_DIR={paths['dir']}")
    print(f"STATE_FILE={paths['state']}")
    print(f"BEFORE_FILE={paths['before']}")
    print(f"WATCH_FILE={paths['watch']}")
    print(f"FILTER_FILE={paths['filter']}")
    print(f"CREATED_ON={created_on}")

    ignored = gitignore_state(project_root, paths["state"])
    print(f"IGNORED={ignored}")
    if ignored == "no":
        print(f"IGNORE_RULE={GITIGNORE_RULE}")
        print("CHECK=stop")
        return STOP
    os.makedirs(paths["dir"], exist_ok=True)

    if not os.path.exists(paths["state"]):
        verdict, head = "assente", None
    else:
        head = read_head(paths["state"])
        live_session_ids = []
        if head is not None and head["kind"] != "ferma":
            registry = regia_common.read_registry(project_root)
            if not registry.readable:
                print("ERROR: registro delle sessioni illeggibile: ~/.claude/sessions", file=sys.stderr)
                return 1
            live_session_ids = [session.session_id for session in registry.sessions]
        verdict = verdict_of(head, perimeter, created_on, own_session, live_session_ids)
    print(f"STATE={verdict}")
    if head is not None:
        print(f"STATE_HOLDER={head['holder']}")
        print(f"STATE_CREATED_ON={head['created_on']}")

    if verdict in NEW_ROUND:
        for key, word in (("watch", "WATCH"), ("filter", "FILTER")):
            if os.path.exists(paths[key]):
                os.remove(paths[key])
                print(f"{word}=tolto")
            else:
                print(f"{word}=assente")
        print("BEFORE=scrivi")
        print("ROUND=nuovo")
    elif VERDICT_EXIT[verdict] == GO:
        print(f"WATCH={'resta' if os.path.exists(paths['watch']) else 'assente'}")
        print(f"FILTER={'resta' if os.path.exists(paths['filter']) else 'assente'}")
        print(f"BEFORE={'tieni' if os.path.exists(paths['before']) else 'scrivi'}")
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
    parser = argparse.ArgumentParser(description="Lo stato su disco della regia di un perimetro")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    check_parser = subcommands.add_parser("check")
    check_parser.add_argument("perimeter", help="l'id del perimetro: un'epica o un mandato")
    check_parser.add_argument("--own-session", required=True, help="session id della regia che chiede")
    facts_parser = subcommands.add_parser("facts")
    facts_parser.add_argument("perimeter", help="l'id del perimetro: un'epica o un mandato")
    return parser.parse_args()


def main():
    regia_common.setup_stdout()
    arguments = parse_arguments()
    if not TASK_ID_PATTERN.match(arguments.perimeter):
        print(f"ERROR: id task malformato: '{arguments.perimeter}' (atteso T<numero>)", file=sys.stderr)
        return 1
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else regia_common.find_project_root(os.getcwd())
    if arguments.command == "check":
        return command_check(project_root, arguments.perimeter, arguments.own_session)
    return command_facts(project_root, arguments.perimeter)


if __name__ == "__main__":
    sys.exit(main())
