"""The acquisition worker.

This is the only place in the application where threading exists, and it follows
one rule: **the worker never touches a widget.** It owns the source and the
parser, and it communicates with the GUI exclusively by emitting signals. Because
the connections are made from the GUI thread to a GUI-thread receiver, Qt
delivers them as queued connections, marshalling the arguments onto the event
loop. That is what makes the handoff safe without a single explicit lock.

The worker is a plain ``QObject`` moved onto a ``QThread``, rather than a
``QThread`` subclass. Subclassing is the common mistake: the thread *object*
still lives on the creating thread while only ``run()`` executes on the new one,
so ``self.anything`` becomes ambiguous. Moving a worker keeps the affinity
obvious.

Blocking reads are deliberate. A blocking read with a short timeout is cheaper
and lower latency than polling, and it is only acceptable *because* it happens
off the event loop.
"""

from __future__ import annotations

import dataclasses
import queue
import time
from typing import Callable

from PySide6.QtCore import QObject, Signal, Slot

import protocol
import sources


class ReaderWorker(QObject):
    """Reads bytes, parses frames, emits messages."""

    # Batched rather than one signal per message: at 10 Hz it makes no
    # difference, but the same code then survives a 1 kHz source without
    # flooding the event queue with tens of thousands of individual events.
    messagesReady = Signal(list)
    statsUpdated = Signal(object)
    sourceFailed = Signal(str)
    replayFinished = Signal()
    finished = Signal()

    STATS_INTERVAL_S = 0.25

    def __init__(self, source: sources.Source, capture: sources.CaptureWriter | None = None) -> None:
        super().__init__()
        self._source = source
        self._capture = capture
        self._parser = protocol.FrameParser()
        self._commands: queue.Queue[bytes] = queue.Queue()
        self._source_ops: queue.Queue[Callable[[sources.Source], None]] = queue.Queue()
        self._running = True
        self._last_stats_emit = 0.0
        self._replay_done = False

    # -- called from the GUI thread ----------------------------------------

    def stop(self) -> None:
        """Request shutdown.

        A plain bool is safe here: single writer, single word, and CPython's GIL
        makes the store atomic. In C++ this would be a ``std::atomic<bool>``.
        """
        self._running = False

    def send_command(self, command: protocol.Command) -> None:
        """Queue an outbound command.

        Writing to the port from the GUI thread would race with the reader, so
        commands go through a ``queue.Queue`` and are written by the thread that
        owns the source. ``queue.Queue`` is already thread-safe, so this needs no
        lock of its own.
        """
        self._commands.put(command.encode())

    def invoke(self, operation: Callable[[sources.Source], None]) -> None:
        """Run ``operation(source)`` on the worker thread.

        The source belongs to this thread. Replay controls - speed, seek, pause -
        used to mutate it straight from the GUI thread, which races with the read
        in progress; queueing the mutation keeps ownership in one place.
        """
        self._source_ops.put(operation)

    @property
    def parser_stats(self) -> protocol.ParserStats:
        return self._parser.stats

    # -- runs on the worker thread -----------------------------------------

    @Slot()
    def run(self) -> None:
        try:
            while self._running:
                self._drain_source_ops()
                self._drain_commands()

                try:
                    chunk = self._source.read(4096)
                except sources.SourceError as exc:
                    self.sourceFailed.emit(str(exc))
                    break

                if chunk:
                    if self._capture is not None:
                        self._capture.write(chunk)
                    messages = self._parser.feed(chunk)
                    if messages:
                        self.messagesReady.emit(messages)
                elif getattr(self._source, "is_finite", False) and getattr(
                    self._source, "exhausted", False
                ):
                    # Announce the end once, then idle rather than closing the
                    # source. Reaching the last frame is precisely when someone
                    # wants to scrub back, and a closed source cannot be seeked.
                    if not self._replay_done:
                        self._replay_done = True
                        self.replayFinished.emit()
                    time.sleep(0.01)
                else:
                    # Nothing available: yield so an idle link does not spin.
                    time.sleep(0.002)

                self._maybe_emit_stats()
        except Exception as exc:  # noqa: BLE001 - see below
            # Anything that is not a SourceError would otherwise kill this
            # thread silently: the GUI would keep its buttons in the connected
            # state and simply stop receiving data, which is the hardest kind of
            # failure to diagnose. Reporting it turns a hang into a reconnect.
            self.sourceFailed.emit(f"reader stopped: {exc!r}")
        finally:
            self._maybe_emit_stats(force=True)
            # The capture is deliberately *not* closed here. It outlives any one
            # worker - recording continues across a reconnect - so it belongs to
            # whoever created it. Closing it here left the next worker writing to
            # a closed file.
            self._source.close()
            self.finished.emit()

    def _drain_source_ops(self) -> None:
        while True:
            try:
                operation = self._source_ops.get_nowait()
            except queue.Empty:
                return
            try:
                operation(self._source)
            except Exception as exc:  # a bad control must not kill acquisition
                self.sourceFailed.emit(f"source control failed: {exc}")
                return
            # A seek or restart can move the playhead back off the end, so the
            # finished notice must be allowed to fire again next time.
            if not getattr(self._source, "exhausted", False):
                self._replay_done = False

    def _drain_commands(self) -> None:
        while True:
            try:
                payload = self._commands.get_nowait()
            except queue.Empty:
                return
            try:
                self._source.write(payload)
            except sources.SourceError as exc:
                self.sourceFailed.emit(str(exc))
                return

    def _maybe_emit_stats(self, force: bool = False) -> None:
        # Statistics are throttled for the same reason plots are: the GUI cannot
        # use updates faster than it can draw them.
        now = time.monotonic()
        if force or now - self._last_stats_emit >= self.STATS_INTERVAL_S:
            self._last_stats_emit = now
            # A copy, not the live object: anything crossing a thread boundary
            # should be a snapshot, or the receiver is reading a value that is
            # still being written.
            self.statsUpdated.emit(dataclasses.replace(self._parser.stats))
