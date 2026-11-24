"""
flow_deck — ciò che lo script del flusso chiede fuori da sé.

  - `loom-deck-headless`: `open` di un passo, `reply` della richiesta di
    checkpoint, `status --json` dell'ultimo turno di una conversazione;
  - i DLV di una task, con lo stesso conteggio di `task-deliverables.sh`, con
    cui `run-task` li spunta, e gli avanzamenti del suo Progress Log;
  - il transcript dell'orchestrator: quando ha finito l'ultimo turno, a che durata
    ha scritto la cache, quando l'utente gli ha scritto l'ultima volta.

Ogni comando esterno ha un tetto di tempo e un esito che non solleva: un
comando che non risponde è un guasto del giro, non la fine del processo.
"""

import glob
import json
import os
import re
import shutil
import subprocess

import flow_log
import mandate
import orchestrator_common

HEADLESS_COMMAND = "loom-deck-headless"
COMMAND_TIMEOUT_S = 60
PROGRESS_ENTRY = re.compile(r"^###\s+Avanzamento\s+\d+")
SESSION_ID = re.compile(r"^sessionId:\s*(\S+)", re.M)
TITLE = re.compile(r"^titolo:\s*(.+)$", re.M)
# Le conversazioni di un `open` cercate fra gli stati headless alla ripresa:
# nate al più tanti secondi prima della riga che ha annunciato l'apertura.
ADOPT_SLACK_S = 5


def deck_environment(orchestrator_session):
    """L'ambiente dei comandi del deck: quello del processo, con la sessione
    dell'orchestrator di adesso in `CLAUDE_CODE_SESSION_ID`. Il deck la scrive nel
    sidecar come `orchestratorSession`; lo script è nato dall'ambiente
    dell'orchestrator che l'ha lanciato, e dopo un passaggio di consegne
    l'orchestrator è un altro."""
    environment = dict(os.environ)
    if orchestrator_session and len(orchestrator_session) == 36:
        environment["CLAUDE_CODE_SESSION_ID"] = orchestrator_session
    return environment


def run_command(arguments, project_root, environment=None, stdin_text=None):
    """(exit, stdout, stderr); exit `None` se il comando non parte o non
    risponde in tempo."""
    try:
        completed = subprocess.run(arguments, cwd=project_root, env=environment, input=stdin_text,
                                   stdin=None if stdin_text is not None else subprocess.DEVNULL,
                                   capture_output=True, encoding="utf-8", errors="replace",
                                   timeout=COMMAND_TIMEOUT_S)
    except (OSError, subprocess.SubprocessError) as error:
        return None, "", str(error)
    return completed.returncode, completed.stdout, completed.stderr


def headless():
    return shutil.which(HEADLESS_COMMAND)


def last_line(text):
    lines = [line for line in (text or "").strip().splitlines() if line.strip()]
    return lines[-1] if lines else ""


def open_step(project_root, head, member, kind, dlv, orchestrator_session):
    """Apre il passo headless: `(sessionId, titolo, None)` o `(None, None, motivo)`."""
    command = headless()
    if command is None:
        return None, None, f"{HEADLESS_COMMAND} assente dal PATH"
    arguments = [command, "open", member, kind]
    if kind == "run" and dlv:
        arguments.append(dlv)
    arguments += ["--orchestrator", head, "--root", project_root]
    code, out, err = run_command(arguments, project_root, deck_environment(orchestrator_session))
    if code != 0:
        return None, None, f"open uscita {code}: {last_line(err) or last_line(out)}"
    session = SESSION_ID.search(out)
    if session is None:
        return None, None, f"open senza sessionId: {last_line(out)}"
    title = TITLE.search(out)
    return session.group(1), title.group(1).strip() if title else "", None


def reply(project_root, head, session, message, orchestrator_session):
    """Un turno nuovo sulla conversazione: `None` se è partito, il motivo se no."""
    command = headless()
    if command is None:
        return f"{HEADLESS_COMMAND} assente dal PATH"
    arguments = [command, "reply", session, "-", "--orchestrator", head, "--root", project_root]
    code, out, err = run_command(arguments, project_root, deck_environment(orchestrator_session), message)
    return None if code == 0 else f"reply uscita {code}: {last_line(err) or last_line(out)}"


def turn_status(project_root, session):
    """`{state, outcome}` dell'ultimo turno headless della conversazione, da
    `status --json`; `None` se il deck non la conosce o non risponde."""
    command = headless()
    if command is None:
        return None
    code, out, _ = run_command([command, "status", session, "--json", "--root", project_root], project_root)
    if code is None or code == 2:
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return None
    if not isinstance(data, dict) or not isinstance(data.get("state"), dict) or not isinstance(data.get("outcome"), dict):
        return None
    return data


def final_text(data):
    result = (data.get("outcome") or {}).get("result") or {}
    return result.get("text") or ""


def output_path(project_root, session):
    """Il file dell'esito di un turno, relativo alla radice: lo stato su disco
    del deck, `.claude/loom/headless/<sessionId>.out.json`. Tiene l'ultimo turno
    della conversazione: il costo del turno, `total_cost_usd`, sta lì finché il
    turno dopo non lo riscrive."""
    return f".claude/loom/headless/{session}.out.json"


def adopt_open(project_root, head, member, kind, since):
    """Il sessionId di una conversazione aperta su `member` col passo `kind`
    dall'orchestrator di `head` non prima di `since` (epoch), o `None`.

    Serve alla ripresa: il processo può essere morto fra `open` e la riga che
    ne scrive il sessionId. Lo stato che il deck scrive prima di lanciare il
    turno dice task, azione, orchestrator e ora: se c'è, la conversazione è nata,
    e aprirne un'altra la raddoppierebbe."""
    directory = os.path.join(project_root, ".claude", "loom", "headless")
    found = []
    for path in glob.glob(os.path.join(glob.escape(directory), "*.json")):
        if path.endswith(".out.json"):
            continue
        try:
            with open(path, encoding="utf-8") as state_handle:
                state = json.load(state_handle)
        except (OSError, ValueError):
            continue
        if not isinstance(state, dict) or state.get("task") != member or state.get("kind") != kind \
                or state.get("orchestrator") != head:
            continue
        started = flow_log.parse_iso(state.get("startedAt"))
        if started is not None and started >= since - ADOPT_SLACK_S and isinstance(state.get("sessionId"), str):
            found.append((started, state["sessionId"]))
    return max(found)[1] if found else None


def task_lines(project_root, task_id):
    path = orchestrator_common.find_task_file(project_root, orchestrator_common.docs_root(project_root), task_id)
    if path is None:
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as task_handle:
            return task_handle.read().splitlines()
    except OSError:
        return None


def dlv_marks(project_root, task_id):
    """n → spuntato, per ogni DLV della task; `None` senza task file. La
    numerazione è quella di `task-deliverables.sh`, con cui `run-task` spunta:
    posizionale 1-based sulle sole checkbox a colonna zero di
    `## Deliverables Checklist`."""
    lines = task_lines(project_root, task_id)
    if lines is None:
        return None
    marks = [mandate.CHECKBOX.match(line) for line in mandate.section_lines(lines, "Deliverables Checklist")]
    return {index + 1: match.group(1) in "xX" for index, match in enumerate(item for item in marks if item)}


def progress_entries(project_root, task_id):
    """Quanti `### Avanzamento N` porta il task file: la prova su disco che un
    checkpoint ha registrato il suo giro."""
    lines = task_lines(project_root, task_id)
    return 0 if lines is None else sum(1 for line in lines if PROGRESS_ENTRY.match(line))


# ---------------------------------------------------------------------------
# Il transcript dell'orchestrator, per il keep-alive
# ---------------------------------------------------------------------------


def read_orchestrator_transcript(entry, session_id, transcript):
    """L'entry di lettura aggiornata: `last_turn` (epoch dell'ultima risposta
    del modello nella conversazione principale), `ttl` (`1h` o `5m`, la
    durata dell'ultima scrittura in cache), `last_prompt` (epoch dell'ultimo
    prompt dell'utente). Lettura incrementale: un transcript diverso — il
    successore, un /clear — riparte da capo."""
    if not isinstance(entry, dict) or entry.get("session_id") != session_id or entry.get("path") != transcript:
        entry = {"session_id": session_id, "path": transcript, "offset": 0,
                 "last_turn": None, "ttl": None, "last_prompt": None}
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return entry
    if size < entry["offset"]:
        entry["offset"] = 0
    with open(transcript, "rb") as transcript_handle:
        transcript_handle.seek(entry["offset"])
        for raw_line in transcript_handle:
            if not raw_line.endswith(b"\n"):
                break
            entry["offset"] += len(raw_line)
            if b'"assistant"' not in raw_line and b'"user"' not in raw_line:
                continue
            try:
                record = json.loads(raw_line)
            except ValueError:
                continue
            if not isinstance(record, dict) or record.get("isSidechain"):
                continue
            moment = flow_log.parse_iso(record.get("timestamp"))
            if record.get("type") == "assistant" and moment is not None:
                entry["last_turn"] = moment
                usage = (record.get("message") or {}).get("usage") or {}
                creation = usage.get("cache_creation") if isinstance(usage, dict) else None
                if isinstance(creation, dict):
                    if (creation.get("ephemeral_1h_input_tokens") or 0) > 0:
                        entry["ttl"] = "1h"
                    elif (creation.get("ephemeral_5m_input_tokens") or 0) > 0:
                        entry["ttl"] = "5m"
            elif moment is not None and orchestrator_common.user_prompt_text(record) is not None:
                entry["last_prompt"] = moment
    return entry
