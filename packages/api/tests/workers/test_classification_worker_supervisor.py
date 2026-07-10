"""Tests du superviseur du ClassificationWorker (bug-classification-worker-stopped).

Incident 2026-06-30 : la task asyncio du run-loop est morte isolément (probable
`CancelledError`, sous-classe de `BaseException` non attrapée par le
`except Exception` du loop) sans repasser `self.running=False` ni redémarrer →
classif à l'arrêt 10 j, `content.theme` NULL sur tout le frais, aucune alerte.

Le done-callback `_on_task_done` rend cette mort visible (Sentry) + relance la
task quand elle meurt alors qu'on n'a PAS demandé l'arrêt.
"""

from unittest.mock import MagicMock, patch

from app.workers.classification_worker import ClassificationWorker


def _bare_worker() -> ClassificationWorker:
    """Worker sans engine réel (init court-circuité)."""
    with patch.object(ClassificationWorker, "__init__", lambda self: None):
        worker = ClassificationWorker()
    worker.running = False
    worker._task = None
    worker._restart_count = 0
    worker._restart_window_start = 0.0
    return worker


def test_on_task_done_restarts_and_captures_exception_when_running():
    """Task morte sur exception + running=True ⇒ capture_exception + relance."""
    worker = _bare_worker()
    worker.running = True

    boom = RuntimeError("boom")
    dead = MagicMock()
    dead.cancelled.return_value = False
    dead.exception.return_value = boom

    new_task = MagicMock()

    def fake_create_task(coro):
        coro.close()  # évite le warning "coroutine never awaited"
        return new_task

    fake_sentry = MagicMock()
    with (
        patch(
            "app.workers.classification_worker.asyncio.create_task",
            side_effect=fake_create_task,
        ) as mock_create,
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
    ):
        worker._on_task_done(dead)

    fake_sentry.capture_exception.assert_called_once_with(boom)
    mock_create.assert_called_once()
    assert worker._task is new_task
    new_task.add_done_callback.assert_called_once_with(worker._on_task_done)


def test_on_task_done_restarts_and_alerts_on_cancellation_when_running():
    """Task annulée (CancelledError) + running=True ⇒ capture_message + relance.

    C'est le scénario exact de l'incident : une CancelledError termine la task
    sans que le worker le sache. On alerte et on relance.
    """
    worker = _bare_worker()
    worker.running = True

    dead = MagicMock()
    dead.cancelled.return_value = True  # annulée → on n'appelle pas exception()

    new_task = MagicMock()

    def fake_create_task(coro):
        coro.close()  # évite le warning "coroutine never awaited"
        return new_task

    fake_sentry = MagicMock()
    with (
        patch(
            "app.workers.classification_worker.asyncio.create_task",
            side_effect=fake_create_task,
        ) as mock_create,
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
    ):
        worker._on_task_done(dead)

    # On ne doit jamais appeler exception() sur une task annulée (lèverait).
    dead.exception.assert_not_called()
    fake_sentry.capture_message.assert_called_once()
    assert fake_sentry.capture_message.call_args.kwargs["level"] == "error"
    mock_create.assert_called_once()
    assert worker._task is new_task


def test_on_task_done_noop_on_voluntary_stop():
    """running=False (arrêt volontaire via stop()) ⇒ pas d'alerte, pas de relance."""
    worker = _bare_worker()
    worker.running = False

    dead = MagicMock()
    dead.cancelled.return_value = True

    fake_sentry = MagicMock()
    with (
        patch(
            "app.workers.classification_worker.asyncio.create_task",
        ) as mock_create,
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
    ):
        worker._on_task_done(dead)

    fake_sentry.capture_exception.assert_not_called()
    fake_sentry.capture_message.assert_not_called()
    mock_create.assert_not_called()


def test_supervisor_gives_up_after_rapid_restarts():
    """Morts en rafale ⇒ après _MAX_RAPID_RESTARTS, on abandonne (running=False)
    + alerte fatale, au lieu de relancer en boucle serrée (spam Sentry)."""
    from app.workers.classification_worker import _MAX_RAPID_RESTARTS

    worker = _bare_worker()
    worker.running = True

    new_task = MagicMock()

    def fake_create_task(coro):
        coro.close()
        return new_task

    dead = MagicMock()
    dead.cancelled.return_value = True

    fake_sentry = MagicMock()
    with (
        patch(
            "app.workers.classification_worker.asyncio.create_task",
            side_effect=fake_create_task,
        ) as mock_create,
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
    ):
        # Les morts se produisent dans la même fenêtre (temps réel << 60 s).
        for _ in range(_MAX_RAPID_RESTARTS + 2):
            if not worker.running:
                break
            worker._on_task_done(dead)

    # A abandonné : plus de relance, alerte fatale émise.
    assert worker.running is False
    # _MAX_RAPID_RESTARTS relances effectives, puis l'abandon (pas de spawn).
    assert mock_create.call_count == _MAX_RAPID_RESTARTS
    levels = [c.kwargs.get("level") for c in fake_sentry.capture_message.call_args_list]
    assert "fatal" in levels


def test_start_attaches_supervisor_callback():
    """start() attache _on_task_done au task créé (couverture de l'accroche)."""
    import asyncio

    worker = _bare_worker()
    worker.running = False

    async def _noop():
        return None

    # _recover_stuck_items est awaité dans start() → doit rester un awaitable.
    worker._recover_stuck_items = _noop

    created = {}

    def fake_create_task(coro):
        # Ferme la coroutine pour éviter le warning "never awaited".
        coro.close()
        task = MagicMock()
        created["task"] = task
        return task

    with patch(
        "app.workers.classification_worker.asyncio.create_task",
        side_effect=fake_create_task,
    ):
        asyncio.run(worker.start())

    created["task"].add_done_callback.assert_called_once_with(worker._on_task_done)
