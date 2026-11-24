"""
flow_engine — il processo del flusso: porta il flusso meccanico di un giro.

A ogni giro di `--poll-seconds`, in quest'ordine:

  1. l'orchestrator: la testa di `T<id>.md` dice chi è (`Stato: attiva · <sid>`,
     `passata a <sid>`), e il registro dei vivi se è vivo. `ferma` chiude il
     processo: l'orchestrator si è fermato;
  2. il piano: riletto quando il file cambia, e verificato (`schedule.check`);
  3. gli scanner del monitor (`watch_sessions.py`), col loro stato in
     `T<id>-watch.json`: ogni evento del perimetro diventa una riga del flusso;
  4. gli ordini dell'orchestrator (`T<id>-ordini.jsonl`);
  5. i passi aperti: l'esito di ogni turno headless finito, classificato a
     lista bianca (`flow_turns`), e il passo successivo dello stesso ciclo —
     la richiesta di checkpoint dopo un run pulito;
  6. i passi nuovi: i membri pronti secondo il piano — `dopo`, risorse, nessuna
     conversazione viva sulla task, un checkpoint alla volta —, poi il
     checkpoint del perimetro a fine giro;
  7. il keep-alive della cache dell'orchestrator.

Ogni decisione che chiede un giudizio diventa una riga `risveglio`: domande,
segnalazioni, esiti non classificati, errori, permessi negati, un piano che non
vale, un giro che non ha più niente da lanciare, la soglia di contesto, gli
eventi di una tab dell'orchestrator. Il resto lo porta lo script, senza
svegliare nessuno.

Senza un orchestrator vivo lo script non apre passi e non manda messaggi: i
turni in corso finiscono, il loro esito si scrive, e i risvegli aspettano chi si
riattacca. Dal gradino del 100% della soglia di contesto il giro è in chiusura:
nessun passo nuovo, ma i cicli aperti arrivano al checkpoint, e il checkpoint
del perimetro parte a fine giro.
"""

import os
import time
import types

import flow_deck
import flow_log
import flow_turns
import mandate
import orchestrator_common
import orchestrator_state
import schedule
import watch_sessions

REVERIFY_S = 600
CLOSING_STEP = 100
KEEPALIVE_MAX = 25
# Gli eventi di una tab aperta dall'orchestrator che lo svegliano (P12): fine
# turno, domanda, permesso, chiusura, stallo.
TAB_WAKE_KINDS = ("turno", "domanda", "permesso", "fine", "ferma")
STEP_FIELDS = ("membro", "passo", "fase", "sessione", "titolo", "dlv", "turno", "genere", "corrente",
               "atteso", "avanzamenti", "motivo_checkpoint", "dettaglio")
NOT_RUNNABLE = schedule.NOT_RUNNABLE
CLOSED = schedule.CLOSED

CHECKPOINT_MESSAGE = """Checkpoint del ciclo: lancia /loom-works:checkpoint-task {member} — richiesta automatica del flusso dell'orchestrator di {head}.

{why} Il ciclo passa quindi al checkpoint in questa conversazione, che ha il contesto del run."""
CHECKPOINT_WHY = {
    "run": "Il tuo run si è chiuso con «🚦 Segnalazioni — nessuna» e con tutti i DLV del suo perimetro spuntati.",
    "risposta": "Le risposte alle segnalazioni del tuo run sono registrate, e i DLV del suo perimetro sono spuntati.",
    "ordine": "L'orchestrator ha letto il tuo ultimo turno e lascia proseguire il ciclo.",
}


def first_line(text):
    return orchestrator_common.first_meaningful_line(text or "")[:200]


class Engine:
    def __init__(self, project_root, head, threshold=0, poll_seconds=15, stall_minutes=10,
                 keepalive_minutes=55):
        self.root = project_root
        self.head = head
        self.poll_seconds = poll_seconds
        self.keepalive_s = keepalive_minutes * 60
        self.paths = flow_log.paths(project_root, head)
        os.makedirs(self.paths["dir"], exist_ok=True)
        self.round, _ = flow_log.replay(self.paths["flow"], head)
        self.writer = flow_log.FlowWriter(self.paths["flow"], self.round.last_seq)
        self.watch_state = watch_sessions.load_state(self.paths["watch"])
        docs = orchestrator_common.docs_root(project_root)
        repos = {"root": project_root}
        for relative_path in watch_sessions.submodule_paths(project_root):
            repos[relative_path] = os.path.join(project_root, relative_path)
        self.settings = types.SimpleNamespace(
            project_root=project_root, docs_root=docs, docs_path=os.path.join(project_root, docs),
            repos=repos, own_session="", stall_minutes=stall_minutes, context_threshold=threshold,
            poll_seconds=poll_seconds)
        self.threshold = threshold
        self.plan = None
        self.plan_ok = False
        self.plan_signature = None
        self.plan_problem = None
        if self.round.plan is not None and self.round.plan.get("stato") == "non valido":
            self.plan_problem = self.round.plan.get("motivo")
        self.verify_due = True
        self.last_verify = 0.0
        self.members = []
        self.snapshot = None
        self.orchestrator = None
        self.orchestrator_alive = False
        self.marks = {}
        self.round_wakes = {row.get("firma") for row in self.round.wakes if row.get("firma")}

    # ---------------------------------------------------------------- righe

    def write(self, kind, **fields):
        row = self.writer.append(kind, **fields)
        self.round.apply(row)
        return row

    def write_step(self, step, **changes):
        fields = {key: step[key] for key in STEP_FIELDS if key in step}
        fields.update(changes)
        return self.write("passo", **{key: value for key, value in fields.items() if value is not None})

    def wake(self, reason, member=None, session=None, detail=None, signature=None):
        if signature is not None:
            if signature in self.round_wakes:
                return None
            self.round_wakes.add(signature)
        return self.write("risveglio", motivo=reason, membro=member, sessione=session, dettaglio=detail,
                          firma=signature)

    def hold(self, member, reason, detail=None):
        """Un membro su cui lo script non apre passi finché un ordine non lo
        libera, e il risveglio che lo dice."""
        if member in self.round.held:
            return
        self.write("fermo", membro=member, motivo=reason)
        self.wake(reason, member=member, detail=detail)

    # ---------------------------------------------------------- l'orchestrator

    def read_orchestrator(self):
        """Chi è l'orchestrator, dalla testa del suo stato: `False` se si è fermato."""
        try:
            head = orchestrator_state.read_head(self.paths["state"])
        except OSError:
            head = None
        if head is None or head.get("perimeter") != self.head:
            self.orchestrator = None
            return True
        if head["kind"] == "ferma":
            return False
        self.orchestrator = head["holder"]
        return True

    def closing(self):
        """Il giro è in chiusura: il contesto dell'orchestrator di adesso ha
        passato il 100% della soglia."""
        context = self.watch_state.get("context")
        live = watch_sessions.own_live
        if not self.threshold or not isinstance(context, dict) or live is None:
            return False
        return context.get("session_id") == live["session_id"] and max(context.get("said") or [0]) >= CLOSING_STEP

    # ------------------------------------------------------------- il piano

    def refresh_plan(self):
        path, reason = schedule.plan_path(self.root, self.head)
        try:
            info = os.stat(path) if path else None
            signature = (info.st_mtime_ns, info.st_size) if info else None
        except OSError:
            signature = None
        if signature == self.plan_signature and self.plan_signature is not None:
            return
        self.plan_signature = signature
        self.verify_due = True

    def verify(self):
        self.verify_due = False
        self.last_verify = time.time()
        try:
            result = schedule.check(self.root, self.head, history=False)
        except schedule.PlanError as error:
            self.write("guasto", dove="verify", errore=str(error))
            return
        if result.plan is not None:
            self.plan = result.plan
        self.members = result.members
        if result.blocking:
            problem = "; ".join(result.errors + [f"{kind} {who}: {detail}" for kind, who, detail in result.diffs])
            if self.plan_ok or problem != self.plan_problem:
                self.write("piano", stato="non valido", motivo=problem)
                self.wake("piano", detail=problem, signature=f"piano:{self.plan_signature}:{problem}")
            self.plan_ok = False
            self.plan_problem = problem
            return
        last = self.round.plan or {}
        if last.get("stato") != "valido" or last.get("sha") != self.plan.sha[:12]:
            self.write("piano", stato="valido", sha=self.plan.sha[:12], membri=self.plan.ids)
        self.plan_ok = True
        self.plan_problem = None

    def refresh_snapshot(self):
        members = self.members or (self.plan.ids if self.plan else [])
        self.snapshot = mandate.snapshot(self.root, self.head, members)
        if self.round.before is None and self.plan_ok:
            figures = {task_id: {key: self.snapshot["tasks"][task_id][key] for key in ("prog", "dlv", "ac", "title")}
                       for task_id in [self.head] + self.snapshot["mandate"]}
            self.write("prima", cifre=figures)

    def task(self, task_id):
        return (self.snapshot or {}).get("tasks", {}).get(task_id)

    def is_closed(self, task_id):
        task = self.task(task_id)
        if task is not None:
            return task.get("next") == "chiusa" or task.get("prog") == CLOSED
        overview = (self.snapshot or {}).get("overview", {})
        return mandate.normalize_glyph(overview.get(task_id, ("", ""))[0]) == CLOSED

    # ----------------------------------------------------------- gli scanner

    def scan(self):
        self.marks = orchestrator_common.load_orchestrator_marks(self.root)
        self.settings.own_session = self.orchestrator or ""
        watch_sessions.sink = self.on_event
        started = time.time()
        for scanner in (watch_sessions.scan_sessions, watch_sessions.scan_context, watch_sessions.scan_task_files,
                        watch_sessions.scan_progress_table, watch_sessions.scan_git):
            try:
                scanner(self.watch_state, self.settings)
            except Exception as error:  # una fonte che si rompe non ferma il flusso
                self.write("guasto", dove=scanner.__name__, errore=f"{type(error).__name__}: {error}")
        self.watch_state["initialized"] = True
        self.watch_state["last_scan"] = started
        live = watch_sessions.own_live
        self.orchestrator_alive = live is not None and bool(self.orchestrator) \
            and live["session_id"].startswith(self.orchestrator)

    def relevant_tasks(self):
        tasks = {self.head}
        tasks.update(self.members)
        if self.plan is not None:
            tasks.update(self.plan.ids)
        return tasks

    def step_of_session(self, session):
        for member, step in self.round.open_steps().items():
            if session and step.get("sessione") == session:
                return member
        return None

    def on_event(self, event):
        kind = event["genere"]
        if kind in ("monitor", "contesto"):
            self.write("evento", genere=kind, testo=event["testo"])
            if kind == "contesto" and (event.get("gradino") or 0) >= CLOSING_STEP:
                self.wake("contesto", session=event.get("sessione"), detail=event["testo"],
                          signature=f"contesto:{event.get('sessione')}:{event.get('gradino')}")
            return
        tasks = set(event["task"]) & self.relevant_tasks()
        if not tasks:
            return
        self.write("evento", genere=kind, testo=event["testo"], task=sorted(tasks))
        if kind == "task file":
            self.verify_due = True
        session = event.get("sessione")
        if not session or kind not in TAB_WAKE_KINDS:
            return
        owner = self.step_of_session(session)
        if owner is not None:
            if kind == "ferma":
                self.wake("stallo", member=owner, session=session, detail=event["testo"])
            return
        if not event.get("headless") and self.marks.get(session) == self.head:
            self.wake("tab", member=sorted(tasks)[0], session=session, detail=event["testo"])

    def live_sessions(self, task_id):
        """Le sessioni vive sulla task, tab o turni headless: lo stato degli
        scanner le tiene etichettate con la loro task."""
        return [process for process in self.watch_state.get("processes", {}).values()
                if process.get("label") == task_id]

    def taken_in_tab(self, session):
        """La conversazione di un passo dello script ripresa in una tab
        dall'utente: un processo vivo non headless con quel sessionId."""
        return any(process.get("session_id") == session and not process.get("headless")
                   for process in self.watch_state.get("processes", {}).values())

    # ------------------------------------------------------------ gli ordini

    def apply_orders(self):
        for order in flow_log.read_orders(self.paths["orders"], self.round.orders_done):
            member, kind = order["membro"], order["ordine"]
            step = self.round.open_steps().get(member)
            outcome = "niente da fare"
            if kind == "tieni":
                if member not in self.round.held:
                    self.write("fermo", membro=member, motivo="tenuto dall'orchestrator")
                    outcome = "tenuto"
            elif kind == "abbandona":
                if step is not None:
                    self.write_step(step, fase="abbandonato", dettaglio=f"ordine {order['n']}")
                    outcome = "passo abbandonato"
                if member in self.round.held:
                    self.write("libero", membro=member, forza=True)
                    outcome = "passo abbandonato" if step is not None else "liberato"
            elif kind == "prosegui":
                done = []
                if step is not None and step.get("fase") == "attesa":
                    done.append(self.go_on(step))
                if member in self.round.held:
                    self.write("libero", membro=member, forza=True)
                    done.append("liberato")
                outcome = ", ".join(done) or outcome
            self.write("ordine", n=order["n"], ordine=kind, membro=member, esito=outcome)

    def go_on(self, step):
        """`prosegui` su un passo in attesa: l'ultimo turno vale come pulito."""
        effective = step.get("genere")
        if effective == "risposta":
            effective = step["passo"]
        if effective == "run" and step["passo"] == "run":
            self.write_step(step, fase="coda", motivo_checkpoint="ordine")
            return "checkpoint in coda"
        self.write_step(step, fase="chiuso", dettaglio="chiuso su ordine")
        return "passo chiuso"

    # --------------------------------------------------------- i passi aperti

    def follow_steps(self):
        for member, step in list(self.round.open_steps().items()):
            entry = self.plan.by_id.get(member) if self.plan is not None else None
            if entry is not None and entry.human:
                self.write_step(step, fase="abbandonato", dettaglio="membro seguito dall'umano")
                continue
            if step["fase"] == "in apertura":
                self.resolve_opening(step)
                continue
            session = step.get("sessione")
            if self.taken_in_tab(session):
                continue
            data = flow_deck.turn_status(self.root, session)
            if data is None:
                self.write_step(step, fase="abbandonato", dettaglio="conversazione ignota al deck")
                self.wake("errore", member=member, session=session, detail="loom-deck-headless status non la conosce")
                continue
            state, outcome = data["state"], data["outcome"]
            turn = state.get("turn") or 0
            accounted = step.get("turno") or 0
            if step["fase"] == "checkpoint" and turn < (step.get("atteso") or 0):
                self.send_checkpoint(step)  # la richiesta non è partita prima di un crash
                continue
            if outcome.get("cls") == "in corso":
                if turn > accounted and step["fase"] == "attesa":
                    self.write_step(step, fase="turno", corrente=flow_turns.turn_genre(state))
                continue
            if turn > accounted:
                self.read_turn(step, data)
        for member, step in list(self.round.open_steps().items()):
            if step["fase"] == "coda":
                self.send_checkpoint(step)

    def resolve_opening(self, step):
        """Un `open` annunciato e mai confermato: il processo è morto in mezzo.
        Se il deck ha lo stato della conversazione è nata, e si adotta;
        altrimenti l'apertura non è avvenuta, e il passo si riapre da capo."""
        since = flow_log.parse_iso(step.get("ts")) or 0
        session = flow_deck.adopt_open(self.root, self.head, step["membro"], step["passo"], since)
        if session is None:
            self.write_step(step, fase="abbandonato", dettaglio="apertura non avvenuta")
        else:
            self.write_step(step, fase="turno", sessione=session, turno=0)

    def facts(self, step):
        member = step["membro"]
        task = self.task(member) or {}
        marks = flow_deck.dlv_marks(self.root, member) or {}
        scope = step.get("dlv") or []
        return {
            "preflight": task.get("preflight"),
            "scope_done": bool(scope) and all(marks.get(number) for number in scope),
            "progress_grew": flow_deck.progress_entries(self.root, member) > (step.get("avanzamenti") or 0),
        }

    def read_turn(self, step, data):
        state, outcome = data["state"], data["outcome"]
        turn = state.get("turn") or 0
        member, session = step["membro"], step.get("sessione")
        genre = flow_turns.turn_genre(state)
        text = flow_deck.final_text(data)
        verdict = flow_turns.classify(step["passo"], genre, step.get("genere"), outcome.get("cls"), text,
                                      self.facts(step))
        # Il testo sta nella riga: il file d'esito del deck tiene solo l'ultimo
        # turno della conversazione, e il turno dopo lo riscrive.
        self.write("turno", membro=member, sessione=session, turno=turn, genere=genre, esito=outcome.get("cls"),
                   verdetto=verdict.reason or verdict.outcome, out=flow_deck.output_path(self.root, session),
                   testo=text)
        if verdict.outcome == "chiuso":
            self.write_step(step, fase="chiuso", turno=turn, genere=genre, corrente=None)
        elif verdict.outcome == "checkpoint":
            self.write_step(step, fase="coda", turno=turn, genere=genre, corrente=None,
                            motivo_checkpoint="risposta" if genre == "risposta" else "run")
        else:
            self.write_step(step, fase="attesa", turno=turn, genere=genre, corrente=None)
            detail = first_line(text) or (outcome.get("reason") or "")
            self.wake(verdict.reason, member=member, session=session, detail=detail)

    def checkpoint_holder(self):
        """Il membro che tiene il checkpoint, o `None`: un checkpoint alla volta
        in tutto il perimetro, perché due insieme fanno gara su `tasks.md` e su
        git. Lo tiene un passo di checkpoint aperto, una richiesta di
        checkpoint in corso, un turno di checkpoint in corso, un checkpoint con
        segnalazioni che aspetta le risposte."""
        for member, step in self.round.open_steps().items():
            if step["passo"] == "checkpoint" or step["fase"] == "checkpoint" or step.get("corrente") == "checkpoint" \
                    or (step.get("genere") == "checkpoint" and step["fase"] in ("attesa", "turno")):
                return member
        return None

    def send_checkpoint(self, step):
        member = step["membro"]
        if not self.orchestrator_alive:
            return
        holder = self.checkpoint_holder()
        if holder is not None and holder != member:
            return
        why = CHECKPOINT_WHY[step.get("motivo_checkpoint") or "run"]
        message = CHECKPOINT_MESSAGE.format(member=member, head=self.head, why=why)
        expected = (step.get("turno") or 0) + 1
        step = self.write_step(step, fase="checkpoint", atteso=expected,
                               avanzamenti=flow_deck.progress_entries(self.root, member))
        reason = flow_deck.reply(self.root, self.head, step["sessione"], message, self.orchestrator)
        if reason:
            self.write_step(step, fase="attesa", atteso=None)
            self.wake("rifiuto", member=member, session=step["sessione"], detail=reason)

    # ----------------------------------------------------------- i passi nuovi

    def step_kind(self, member, task):
        """Il passo da aprire su un membro, o `None` se il membro si ferma qui."""
        released = member.id in self.round.released
        if task["preflight"] == "decaduta" and not released:
            self.hold(member.id, "premessa decaduta")
            return None
        if not self.round.has_stepped(member.id) and member.step:
            marks = flow_deck.dlv_marks(self.root, member.id) or {}
            open_dlv = [number for number, done in marks.items() if not done]
            if member.step == "preflight" and task["preflight"] != "ok":
                return "preflight"
            if member.step == "run" and open_dlv and not (
                    task["next"] == "preflight" and (task["preflight"] == "decaduta"
                                                     or mandate.is_size_large(task["size"]))):
                return "run"
            if member.step == "checkpoint":
                return "checkpoint"
        next_step = task["next"]
        if next_step == "preflight":
            return "preflight"
        if next_step == "run":
            return "run"
        if next_step == "checkpoint":
            if released:
                return "checkpoint"
            last = self.round.steps.get(member.id)
            reason = "non chiusa" if last is not None and last.get("fase") == "chiuso" else "ciclo interrotto"
            self.hold(member.id, reason, detail="DLV tutti spuntati, Prog non ✔️")
            return None
        return None

    def cycle_open(self, task_id):
        step = self.round.open_steps().get(task_id)
        return step is not None and step["passo"] in ("run", "checkpoint")

    def after_ok(self, member):
        """Il `dopo` del membro: ogni voce soddisfatta."""
        for dependency in member.after:
            if dependency.target == schedule.ALL_OTHERS:
                others = [other.id for other in self.plan.members if other.id != member.id]
                if not all(self.is_closed(other) for other in others):
                    return False
                continue
            if dependency.dlv is None:
                if not self.is_closed(dependency.target):
                    return False
                continue
            marks = flow_deck.dlv_marks(self.root, dependency.target) or {}
            if not all(marks.get(number) for number in dependency.dlv):
                return False
            if dependency.target in self.plan.by_id and self.cycle_open(dependency.target):
                return False
        return True

    def outside_ok(self, member, task):
        """Le dipendenze aperte verso task fuori dal perimetro fermano il
        membro, salvo una voce del `dopo` per DLV sulla stessa task."""
        by_dlv = {dependency.target for dependency in member.after if dependency.dlv}
        for dependency in task.get("open_dependencies", []):
            if dependency not in self.plan.by_id and dependency != self.head and dependency not in by_dlv:
                return False
        return True

    def resources_taken(self):
        taken = set()
        for member, step in self.round.open_steps().items():
            entry = self.plan.by_id.get(member)
            if entry is not None and step["passo"] in ("run", "checkpoint"):
                taken.update(entry.resources)
        return taken

    def unblocks(self, member_id):
        return sum(1 for other in self.plan.members
                   if any(dependency.target == member_id for dependency in other.after))

    def schedule(self):
        """I passi nuovi, poi la fine del giro. Niente senza un piano valido e
        un orchestrator vivo."""
        if self.plan is None or not self.plan_ok or not self.orchestrator_alive or self.snapshot is None:
            return
        closing = self.closing()
        candidates = []
        if not closing:
            for position, member in enumerate(self.plan.members):
                if member.human or member.id in self.round.held or member.id in self.round.open_steps():
                    continue
                task = self.task(member.id)
                if task is None or task.get("next") in NOT_RUNNABLE or self.live_sessions(member.id):
                    continue
                if not self.after_ok(member) or not self.outside_ok(member, task):
                    continue
                kind = self.step_kind(member, task)
                if kind is not None:
                    candidates.append((-self.unblocks(member.id), position, member, kind))
        launched = 0
        taken = self.resources_taken()
        for _, _, member, kind in sorted(candidates, key=lambda item: item[:2]):
            if kind in ("run", "checkpoint") and taken & set(member.resources):
                continue
            if kind == "checkpoint" and self.checkpoint_holder() is not None:
                continue
            if self.open_step(member, kind):
                launched += 1
                if kind in ("run", "checkpoint"):
                    taken.update(member.resources)
        if not launched:
            self.round_end()

    def open_step(self, member, kind):
        dlv = None
        spec = None
        if kind == "run":
            marks = flow_deck.dlv_marks(self.root, member.id) or {}
            open_dlv = sorted(number for number, done in marks.items() if not done)
            chosen = [number for number in (member.dlv or []) if number in open_dlv]
            dlv = chosen or open_dlv
            spec = schedule.format_dlv(chosen) if chosen else None
        step = self.write("passo", membro=member.id, passo=kind, fase="in apertura", dlv=dlv,
                          avanzamenti=flow_deck.progress_entries(self.root, member.id))
        return self.launch(step, spec)

    def launch(self, step, spec):
        member = step["membro"]
        session, title, reason = flow_deck.open_step(self.root, self.head, member, step["passo"], spec,
                                                     self.orchestrator)
        if reason:
            self.write_step(step, fase="abbandonato", dettaglio=reason)
            self.hold(member, "rifiuto", detail=reason)
            return False
        self.write_step(step, fase="turno", sessione=session, titolo=title, turno=0)
        return True

    def round_end(self):
        """Niente di lanciabile: con passi aperti si aspetta; con un ciclo
        chiuso dall'ultimo checkpoint del perimetro parte il checkpoint del
        perimetro; altrimenti l'orchestrator si sveglia, una volta per stato."""
        if self.round.open_steps():
            return
        remaining = [member.id for member in self.plan.members
                     if (self.task(member.id) or {}).get("next") not in NOT_RUNNABLE]
        if self.round.cycles > 0 and self.checkpoint_holder() is None and self.head not in self.round.held:
            step = self.write("passo", membro=self.head, passo="checkpoint", fase="in apertura",
                              avanzamenti=flow_deck.progress_entries(self.root, self.head))
            self.launch(step, None)
            return
        if remaining:
            detail = ", ".join(f"{task_id} ({self.waiting_reason(task_id)})" for task_id in remaining)
            self.wake("fermo", detail=detail, signature=f"fermo:{self.round.last_step_seq}:{detail}")
        else:
            self.wake("fine giro", detail=f"{self.round.closed_cycles} cicli chiusi",
                      signature=f"fine:{self.round.last_step_seq}")

    def waiting_reason(self, task_id):
        member = self.plan.by_id.get(task_id)
        if member is not None and member.human:
            return "lo segue l'umano"
        if task_id in self.round.held:
            return self.round.held[task_id] or "fermo"
        if self.live_sessions(task_id):
            return "conversazione viva"
        if self.closing():
            return "giro in chiusura"
        if member is not None and not self.after_ok(member):
            return "aspetta " + ", ".join(dependency.text for dependency in member.after)
        return "dipendenza aperta fuori dal perimetro"

    # ------------------------------------------------------------- keep-alive

    def keep_alive(self):
        """Un risveglio quando l'orchestrator tace da `keepalive_minutes`, la cache
        è a un'ora e ogni risveglio è stato letto; al più `KEEPALIVE_MAX` di
        fila. Il silenzio si misura dall'ultimo turno nel transcript
        dell'orchestrator, così un prompt dell'utente azzera il conto."""
        live = watch_sessions.own_live
        if not self.orchestrator_alive or live is None:
            return
        transcript = orchestrator_common.transcript_path(live["cwd"], live["session_id"])
        entry = flow_deck.read_orchestrator_transcript(self.watch_state.get("orchestrator_transcript"),
                                                       live["session_id"], transcript)
        self.watch_state["orchestrator_transcript"] = entry
        if entry.get("ttl") != "1h" or entry.get("last_turn") is None:
            return
        now = time.time()
        if now - entry["last_turn"] < self.keepalive_s:
            return
        last = self.round.last_wake()
        if last is not None and (flow_log.parse_iso(last.get("ts")) or 0) > entry["last_turn"]:
            return
        other = self.round.last_wake(exclude_keepalive=True)
        since = max((flow_log.parse_iso(other.get("ts")) or 0) if other else 0, entry.get("last_prompt") or 0)
        streak = sum(1 for row in self.round.wakes
                     if row.get("motivo") == flow_log.KEEPALIVE and (flow_log.parse_iso(row.get("ts")) or 0) > since)
        if streak >= KEEPALIVE_MAX:
            return
        self.wake(flow_log.KEEPALIVE, detail=f"{int((now - entry['last_turn']) / 60)} min di silenzio, "
                                             f"keep-alive {streak + 1} di {KEEPALIVE_MAX}")

    # -------------------------------------------------------------- il giro

    def tick(self):
        """Un giro intero. `False` quando il processo deve chiudersi."""
        if not self.read_orchestrator():
            return False
        self.refresh_plan()
        if self.verify_due or time.time() - self.last_verify > REVERIFY_S:
            self.verify()
        self.scan()
        if self.verify_due:  # un task file del perimetro è cambiato in questo giro
            self.verify()
        self.refresh_snapshot()
        self.apply_orders()
        self.follow_steps()
        self.refresh_snapshot()
        self.schedule()
        self.keep_alive()
        watch_sessions.save_state(self.paths["watch"], self.watch_state)
        return True
