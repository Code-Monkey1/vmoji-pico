"""The dashboard window.

Architecture, in one paragraph: a swappable byte ``Source`` is owned by a
``ReaderWorker`` living on a ``QThread``; the worker parses frames and emits them
as batched signals, which Qt queues onto the GUI thread; the GUI appends them to
a bounded ``TelemetryModel``; and a ``QTimer`` repaints from that model at a fixed
30 Hz. The arrival rate and the frame rate are therefore independent, which is
what lets the same UI serve a 10 Hz link or a 10 kHz one.

    Source  ->  ReaderWorker (QThread)  ->  queued signal  ->  TelemetryModel
                        |                                            |
                   CaptureWriter                            QTimer @ 30 Hz -> views
"""

from __future__ import annotations

import contextlib
import time
from pathlib import Path

import pyqtgraph as pg
from PySide6.QtCore import QSettings, Qt, QThread, QTimer, Slot
from PySide6.QtGui import QAction, QFont, QKeySequence
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDockWidget,
    QDoubleSpinBox,
    QFileDialog,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSlider,
    QSpinBox,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

import model as model_module
import panels
import protocol
import reader as reader_module
import reconnect
import sources
from sources import SourceSelection
from widgets import KeyValuePanel, MatrixView

REPAINT_INTERVAL_MS = 33  # ~30 FPS
STALE_AFTER_S = 1.0
PORT_RESCAN_INTERVAL_MS = 2000
SEEK_RESOLUTION = 1000  # slider steps across the whole capture


def _apply_dark_theme() -> None:
    """A dark palette because this is a monitoring tool that sits open all day,
    and pyqtgraph defaults to a white canvas that is punishing next to it."""
    pg.setConfigOptions(
        antialias=False,  # off by design: dense polylines cost more than they gain
        background="#1b1d22",
        foreground="#c8ccd4",
    )


WINDOW_TITLE = "vmoji telemetry dashboard"


class MainWindow(QMainWindow):
    def __init__(self, initial_selection: SourceSelection = sources.SIMULATOR,
                 baudrate: int = 115200, error_rate: float = 0.0) -> None:
        super().__init__()
        _apply_dark_theme()
        self.setWindowTitle(WINDOW_TITLE)
        self.resize(1440, 900)

        self.model = model_module.TelemetryModel()
        self._thread: QThread | None = None
        self._worker: reader_module.ReaderWorker | None = None
        self._source: sources.Source | None = None
        self._capture: sources.CaptureWriter | None = None
        self._source_name = "disconnected"
        self._last_message_time = 0.0
        self._stats = protocol.ParserStats()
        self._log_pending: list[str] = []
        self._sources = sources.SourceFactory(baudrate=baudrate, error_rate=error_rate)
        self._default_baud = baudrate
        self._replay_paths: list[str] = []
        self._board_identity = "-"
        self._active_selection: SourceSelection | None = None

        self._build_ui()
        self._build_menu()

        # Repaint on a timer, never on data arrival. This single decision is what
        # keeps the UI responsive independent of the telemetry rate.
        self._repaint_timer = QTimer(self)
        self._repaint_timer.timeout.connect(self._repaint)
        self._repaint_timer.start(REPAINT_INTERVAL_MS)

        # Notice a board being plugged in without making the user press Rescan.
        self._port_timer = QTimer(self)
        self._port_timer.timeout.connect(self._rescan_if_idle)
        self._port_timer.start(PORT_RESCAN_INTERVAL_MS)

        self._reconnect = reconnect.ReconnectPolicy()
        self._reconnect_timer = QTimer(self)
        self._reconnect_timer.setSingleShot(True)
        self._reconnect_timer.timeout.connect(self._attempt_reconnect)

        self._restore_layout()
        self._refresh_ports()
        self._select_source(initial_selection)
        self._connect_source()

    # ------------------------------------------------------------------ UI

    def _build_ui(self) -> None:
        splitter = QSplitter(Qt.Orientation.Horizontal, self)
        splitter.addWidget(self._build_plots())
        splitter.addWidget(self._build_side_panel())
        splitter.setStretchFactor(0, 1)
        splitter.setSizes([980, 460])
        self.main_splitter = splitter

        container = QWidget()
        outer = QVBoxLayout(container)
        outer.setContentsMargins(6, 6, 6, 6)
        outer.setSpacing(6)
        outer.addWidget(self._build_connection_bar())
        outer.addWidget(self._build_sim_banner())
        outer.addWidget(self._build_replay_bar())
        outer.addWidget(splitter, 1)
        self.setCentralWidget(container)

        self._build_log_dock()

        self.setMinimumSize(900, 600)

        self.status_label = QLabel("starting")
        self.statusBar().addWidget(self.status_label, 1)
        self.rate_label = QLabel("")
        self.statusBar().addPermanentWidget(self.rate_label)

    def _build_sim_banner(self) -> QWidget:
        """An unmissable marker while the simulator is driving the display.

        The simulator is convincing on purpose, which is exactly why an audience
        must never have to wonder which mode they are looking at.
        """
        banner = QLabel("SIMULATION - synthetic data, no hardware connected")
        banner.setAlignment(Qt.AlignmentFlag.AlignCenter)
        banner.setStyleSheet(
            "background-color: #7a4a12; color: #ffd9a0; font-weight: bold;"
            " padding: 4px; border-radius: 3px;"
        )
        banner.setVisible(False)
        self.sim_banner = banner
        return banner

    def _build_connection_bar(self) -> QWidget:
        bar = QGroupBox("Link")
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(8, 4, 8, 6)
        layout.setSpacing(4)

        layout.addWidget(QLabel("Source:"))
        self.source_combo = QComboBox()
        # Port descriptions are long, so let the combo take any spare width but
        # never demand it: a fixed 320 px floor here was most of the reason the
        # window could not be narrowed.
        self.source_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToMinimumContentsLengthWithIcon
        )
        self.source_combo.setMinimumContentsLength(16)
        self.source_combo.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        layout.addWidget(self.source_combo, 1)

        self.rescan_button = QPushButton("Rescan")
        self.rescan_button.setToolTip("Re-enumerate serial ports")
        self.rescan_button.clicked.connect(self._refresh_ports)
        layout.addWidget(self.rescan_button)

        layout.addWidget(QLabel("Baud:"))
        self.baud_combo = QComboBox()
        for rate in (9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600):
            self.baud_combo.addItem(str(rate), rate)
        self.baud_combo.setCurrentText(str(self._default_baud))
        layout.addWidget(self.baud_combo)

        self.connect_button = QPushButton("Connect")
        self.connect_button.clicked.connect(self._connect_source)
        layout.addWidget(self.connect_button)

        self.disconnect_button = QPushButton("Disconnect")
        self.disconnect_button.clicked.connect(self._disconnect_source)
        layout.addWidget(self.disconnect_button)

        layout.addSpacing(16)

        self.record_button = QPushButton("Record")
        self.record_button.setCheckable(True)
        self.record_button.setToolTip(
            "Capture the raw byte stream with host timestamps, for later replay"
        )
        self.record_button.clicked.connect(self._toggle_recording)
        layout.addWidget(self.record_button)

        self.open_button = QPushButton("Open...")
        self.open_button.setToolTip("Open a recorded capture for replay")
        self.open_button.clicked.connect(self._open_capture)
        layout.addWidget(self.open_button)

        layout.addStretch(1)
        return bar

    def _build_replay_bar(self) -> QWidget:
        """Transport controls, shown only while a recording is playing.

        A capture is the only source you can actually navigate, so it gets real
        transport controls rather than a lone speed box that sits greyed out and
        meaningless during a live session.
        """
        bar = QWidget()
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(0, 0, 0, 0)

        self.replay_play_button = QPushButton("Pause")
        self.replay_play_button.setCheckable(True)
        self.replay_play_button.setToolTip("Hold the playhead without losing your place")
        self.replay_play_button.toggled.connect(self._toggle_replay_pause)
        layout.addWidget(self.replay_play_button)

        self.replay_restart_button = QPushButton("Restart")
        self.replay_restart_button.clicked.connect(self._restart_replay)
        layout.addWidget(self.replay_restart_button)

        self.replay_loop_check = QCheckBox("Loop")
        self.replay_loop_check.setToolTip("Play the capture on repeat, for an unattended demo")
        self.replay_loop_check.toggled.connect(
            lambda on: self._control_replay(lambda source: source.set_loop(on))
        )
        layout.addWidget(self.replay_loop_check)

        self.replay_slider = QSlider(Qt.Orientation.Horizontal)
        self.replay_slider.setRange(0, SEEK_RESOLUTION)
        # valueChanged, not sliderMoved: the latter fires only while dragging, so
        # a click on the groove or an arrow key would move the handle without
        # seeking, and the next repaint would snap it back.
        # _update_replay_transport blocks signals around its own setValue, so
        # programmatic updates cannot feed back in here.
        self.replay_slider.valueChanged.connect(self._seek_replay)
        layout.addWidget(self.replay_slider, 1)

        self.replay_time_label = QLabel("0.0 / 0.0 s")
        self.replay_time_label.setMinimumWidth(110)
        layout.addWidget(self.replay_time_label)

        layout.addWidget(QLabel("Speed:"))
        self.speed_spin = QDoubleSpinBox()
        self.speed_spin.setRange(0.0, 100.0)
        self.speed_spin.setSingleStep(0.5)
        self.speed_spin.setValue(1.0)
        self.speed_spin.setSpecialValueText("max")
        self.speed_spin.setToolTip("1.0 replays at the recorded rate; 0 is as fast as possible")
        self.speed_spin.valueChanged.connect(self._apply_replay_speed)
        layout.addWidget(self.speed_spin)

        bar.setVisible(False)
        self.replay_bar = bar
        return bar

    def _build_plots(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        controls = QHBoxLayout()
        controls.addWidget(QLabel("Window:"))
        self.window_spin = QSpinBox()
        self.window_spin.setRange(5, 3600)
        self.window_spin.setValue(60)
        self.window_spin.setSuffix(" s")
        self.window_spin.setToolTip("Trailing time span shown on the plots")
        controls.addWidget(self.window_spin)
        controls.addStretch(1)
        layout.addLayout(controls)

        self.plot_refresh = self._make_plot("Refresh rate", "Hz")
        self.curve_refresh = self.plot_refresh.plot(pen=pg.mkPen("#5ec8ff", width=2))

        self.plot_period = self._make_plot("Scan period", "us")
        self.plot_period.addLegend(offset=(-10, 10), labelTextSize="8pt")
        self.curve_period_max = self.plot_period.plot(
            pen=pg.mkPen("#ff6b6b", width=1), name="max"
        )
        self.curve_period_mean = self.plot_period.plot(
            pen=pg.mkPen("#ffd166", width=2), name="mean"
        )
        self.curve_period_min = self.plot_period.plot(
            pen=pg.mkPen("#8ce99a", width=1), name="min"
        )

        self.plot_jitter = self._make_plot("Loop jitter (peak-to-peak)", "us")
        self.curve_jitter = self.plot_jitter.plot(
            pen=pg.mkPen("#c084fc", width=2), fillLevel=0, brush=(192, 132, 252, 40)
        )

        self.plot_temp = self._make_plot("Die temperature", "C")
        self.curve_temp = self.plot_temp.plot(pen=pg.mkPen("#ffa94d", width=2))

        # One shared x-axis: correlating a jitter spike against a temperature or
        # rate change is the entire reason these plots sit on one screen.
        for plot in (self.plot_period, self.plot_jitter, self.plot_temp):
            plot.setXLink(self.plot_refresh)

        # A splitter rather than a stack: four plots with a fixed share each
        # cannot be made readable on a short window, and which plot matters
        # depends on what you are chasing. Dragging a divider is the fix.
        stack = QSplitter(Qt.Orientation.Vertical)
        for plot in (self.plot_refresh, self.plot_period, self.plot_jitter, self.plot_temp):
            plot.setMinimumHeight(60)
            stack.addWidget(plot)
        stack.setChildrenCollapsible(False)
        layout.addWidget(stack, 1)
        self.plot_splitter = stack

        self.plot_temp.setLabel("bottom", "Time since first sample", units="s")
        return panel

    def _make_plot(self, title: str, units: str) -> pg.PlotWidget:
        plot = pg.PlotWidget(title=title)
        plot.showGrid(x=True, y=True, alpha=0.2)
        plot.setLabel("left", title, units=units)
        # pyqtgraph would otherwise rescale to an SI prefix and label the axis
        # "kus", which is not a unit any engineer reads. Microseconds stay
        # microseconds.
        plot.getAxis("left").enableAutoSIPrefix(False)
        plot.getAxis("bottom").enableAutoSIPrefix(False)
        plot.setMouseEnabled(x=True, y=True)
        # Downsampling plus clip-to-view means only the visible, decimated
        # samples are rasterised, so a long capture stays interactive.
        plot.setDownsampling(auto=True, mode="peak")
        plot.setClipToView(True)
        plot.getPlotItem().titleLabel.setText(title, size="9pt", color="#c8ccd4")
        return plot

    def _build_side_panel(self) -> QWidget:
        """The four stacked boxes, inside a scroll area.

        Their combined natural height is around 950 px, and a plain stack makes
        that a hard floor on the window: the dashboard could not be opened on a
        1080p laptop at all. Scrolling trades a little convenience on a short
        window for the ability to have a short window.
        """
        scroller = QScrollArea()
        scroller.setWidgetResizable(True)
        scroller.setFrameShape(QScrollArea.Shape.NoFrame)
        scroller.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        matrix_box = QGroupBox("Framebuffer (as reported by firmware)")
        matrix_layout = QVBoxLayout(matrix_box)
        self.matrix_view = MatrixView()
        matrix_layout.addWidget(self.matrix_view)
        layout.addWidget(matrix_box, 1)

        status_box = QGroupBox("Receiver status")
        status_layout = QVBoxLayout(status_box)
        self.status_panel = KeyValuePanel(panels.STATUS_KEYS)
        status_layout.addWidget(self.status_panel)
        layout.addWidget(status_box)

        link_box = QGroupBox("Link health")
        link_layout = QVBoxLayout(link_box)
        self.link_panel = KeyValuePanel(panels.LINK_KEYS)
        link_layout.addWidget(self.link_panel)
        layout.addWidget(link_box)

        layout.addWidget(self._build_control_panel())

        scroller.setWidget(panel)
        return scroller

    def _build_control_panel(self) -> QWidget:
        box = QGroupBox("Control")
        grid = QGridLayout(box)
        grid.setContentsMargins(8, 6, 8, 8)

        grid.addWidget(QLabel("Glyph:"), 0, 0)
        self.glyph_combo = QComboBox()
        for index, name in enumerate(protocol.GLYPH_NAMES):
            self.glyph_combo.addItem(f"{index}  {name}", index)
        self.glyph_combo.setCurrentIndex(1)
        self.glyph_combo.activated.connect(
            lambda: self._send(protocol.cmd_glyph(self.glyph_combo.currentData()))
        )
        grid.addWidget(self.glyph_combo, 0, 1, 1, 2)

        grid.addWidget(QLabel("Row dwell:"), 1, 0)
        self.dwell_slider = QSlider(Qt.Orientation.Horizontal)
        # The range the firmware accepts, not a narrower guess: a board set to
        # 3000 us from a terminal used to read as 2000 here.
        self.dwell_slider.setRange(protocol.DWELL_MIN_US, protocol.DWELL_MAX_US)
        self.dwell_slider.setValue(400)
        self.dwell_slider.setToolTip(
            "Per-row lit time. Raising it brightens the display and lowers the\n"
            "refresh rate: watch both plots respond."
        )
        # Send on release, not on every drag step, so a drag does not queue a
        # hundred commands the firmware has to parse mid-scan.
        self.dwell_slider.sliderReleased.connect(
            lambda: self._send(protocol.cmd_dwell(self.dwell_slider.value()))
        )
        self.dwell_slider.valueChanged.connect(
            lambda value: self.dwell_label.setText(f"{value} us")
        )
        grid.addWidget(self.dwell_slider, 1, 1)
        self.dwell_label = QLabel("400 us")
        self.dwell_label.setFont(QFont("monospace"))
        grid.addWidget(self.dwell_label, 1, 2)

        buttons = [
            ("Heartbeat", protocol.cmd_heartbeat),
            ("Blank", protocol.cmd_blank),
            ("Pause scan", protocol.cmd_pause),
            ("Reset counters", protocol.cmd_reset_counters),
            ("Query config", protocol.cmd_query),
        ]
        for offset, (label, factory) in enumerate(buttons):
            button = QPushButton(label)
            button.clicked.connect(lambda _=False, f=factory: self._send(f()))
            grid.addWidget(button, 2 + offset // 3, offset % 3)

        return box

    def _build_log_dock(self) -> None:
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(2000)  # bounded, like every other buffer
        self.log_view.setFont(QFont("monospace"))

        dock = QDockWidget("Device log and acknowledgements", self)
        # saveState keys docks by objectName and silently skips unnamed ones.
        dock.setObjectName("logDock")
        dock.setWidget(self.log_view)
        dock.setAllowedAreas(
            Qt.DockWidgetArea.BottomDockWidgetArea | Qt.DockWidgetArea.TopDockWidgetArea
        )
        self.addDockWidget(Qt.DockWidgetArea.BottomDockWidgetArea, dock)
        dock.resize(dock.width(), 160)
        self.log_dock = dock

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")

        open_action = QAction("&Open capture...", self)
        open_action.setShortcut(QKeySequence.StandardKey.Open)
        open_action.triggered.connect(self._open_capture)
        file_menu.addAction(open_action)

        record_action = QAction("Toggle &recording", self)
        record_action.setShortcut("Ctrl+R")
        record_action.triggered.connect(self.record_button.click)
        file_menu.addAction(record_action)

        file_menu.addSeparator()
        quit_action = QAction("&Quit", self)
        quit_action.setShortcut(QKeySequence.StandardKey.Quit)
        quit_action.triggered.connect(self.close)
        file_menu.addAction(quit_action)

        view_menu = self.menuBar().addMenu("&View")
        clear_action = QAction("&Clear history", self)
        clear_action.triggered.connect(self._clear_history)
        view_menu.addAction(clear_action)
        view_menu.addAction(self.log_dock.toggleViewAction())

    # -------------------------------------------------------- source control

    def _port_entries(self) -> list[tuple[str, SourceSelection]]:
        """The combo contents, hardware first and the simulator last.

        Ordering is the whole point: a real board should be what you get by
        default, and reaching the simulator should be a deliberate act.
        """
        entries: list[tuple[str, SourceSelection]] = []
        for candidate in sources.list_port_candidates():
            entries.append((candidate.label, SourceSelection("serial", candidate.device)))
        for path in self._replay_paths:
            entries.append(
                (f"Replay  -  {Path(path).name}", SourceSelection("replay", path))
            )
        entries.append(
            ("Simulator (synthetic data - no hardware)", sources.SIMULATOR)
        )
        return entries

    def _find_selection(self, data: SourceSelection | None) -> int:
        """Index of a (kind, device) entry, or -1.

        QComboBox.findData compares through QVariant, which does not recognise
        two equal Python tuples as the same value, so it silently reports "not
        found" and the caller ends up on whatever happens to be first.
        """
        if data is None:
            return -1
        for index in range(self.source_combo.count()):
            if self.source_combo.itemData(index) == data:
                return index
        return -1

    def _refresh_ports(self) -> None:
        remembered = self.source_combo.currentData()
        entries = self._port_entries()

        # Rebuilding on a timer would fight the user's selection and drop the
        # popup, so only touch the widget when the set of ports really changed.
        current = [
            (self.source_combo.itemText(i), self.source_combo.itemData(i))
            for i in range(self.source_combo.count())
        ]
        if current == entries:
            return

        self.source_combo.blockSignals(True)
        self.source_combo.clear()
        for label, data in entries:
            self.source_combo.addItem(label, data)
        index = self._find_selection(remembered)
        if index >= 0:
            self.source_combo.setCurrentIndex(index)
        self.source_combo.blockSignals(False)

    def _select_source(self, selection: SourceSelection) -> None:
        selection = SourceSelection(*selection)
        kind, device = selection
        if kind == "replay" and device:
            self._remember_replay(device)
            self._refresh_ports()

        index = self._find_selection(selection)
        if index < 0 and kind == "serial" and device:
            # A port named explicitly that enumeration did not report; honour it
            # rather than silently substituting something else.
            self.source_combo.addItem(f"{device}  -  (as specified)", selection)
            index = self.source_combo.count() - 1
        if index >= 0:
            self.source_combo.setCurrentIndex(index)

    def _rescan_if_idle(self) -> None:
        """Periodic re-enumeration, skipped while the user is in the combo.

        Rebuilding the list under an open popup closes it mid-click, which feels
        like the application fighting you.
        """
        view = self.source_combo.view()
        if view is not None and view.isVisible():
            return
        self._refresh_ports()

    def _remember_replay(self, path: str) -> None:
        if path not in self._replay_paths:
            self._replay_paths.append(path)

    def _build_source(self, selection: SourceSelection) -> sources.Source:
        # The baud combo is the live control, so it overrides the launch default.
        self._sources.baudrate = self.baud_combo.currentData()
        return self._sources.create(selection, speed=self._replay_speed())

    def _connect_source(self) -> None:
        selection = self.source_combo.currentData()
        if selection is None:
            return
        selection = SourceSelection(*selection)
        self._cancel_reconnect()
        try:
            source = self._build_source(selection)
        except sources.SourceError as exc:
            QMessageBox.warning(self, "Could not open source", str(exc))
            return

        self._start_worker(source, selection)

    def _start_worker(
        self, source: sources.Source, selection: SourceSelection | None = None
    ) -> None:
        self._stop_worker()
        self._clear_history()

        self._source_name = source.name
        self._source = source
        # Remember what we actually opened. The combo box is not a reliable
        # record of this: the periodic rescan repoints it whenever a port comes
        # or goes, so by the time a link fails it may name a different device.
        self._active_selection = selection
        self._update_source_indicators(source)

        # The window owns the writer and keeps it open across worker restarts,
        # so that a reconnect does not silently end the recording.
        capture = self._capture if self.record_button.isChecked() else None
        worker = reader_module.ReaderWorker(source, capture)
        thread = QThread(self)
        worker.moveToThread(thread)

        # started -> run() is what makes run() execute on the new thread.
        thread.started.connect(worker.run)
        worker.messagesReady.connect(self._on_messages)
        worker.statsUpdated.connect(self._on_stats)
        worker.sourceFailed.connect(self._on_source_failed)
        worker.replayFinished.connect(self._on_replay_finished)
        worker.finished.connect(thread.quit)

        self._worker = worker
        self._thread = thread
        thread.start()

        self._append_log(f"connected to {source.name}")
        self.connect_button.setEnabled(False)
        self.disconnect_button.setEnabled(True)

        if isinstance(source, sources.SerialSource):
            # Ask outright instead of waiting up to 10 s for the firmware's
            # periodic announcement, so the board id is on screen immediately.
            worker.send_command(protocol.cmd_identity())

    def _update_source_indicators(self, source: sources.Source | None) -> None:
        """Keep the banner and the title honest about what is driving the view."""
        simulated = isinstance(source, sources.SimSource)
        replaying = isinstance(source, sources.ReplaySource)
        self.sim_banner.setVisible(simulated)
        self.replay_bar.setVisible(replaying)

        if replaying:
            self.replay_play_button.setChecked(source.paused)
            self.replay_loop_check.setChecked(source.loop)
            self._update_replay_transport()

        if simulated:
            self.setWindowTitle(f"{WINDOW_TITLE}  -  [SIMULATION]")
        elif replaying:
            self.setWindowTitle(f"{WINDOW_TITLE}  -  [REPLAY] {source.name}")
        elif source is not None:
            self.setWindowTitle(f"{WINDOW_TITLE}  -  {source.name}")
        else:
            self.setWindowTitle(WINDOW_TITLE)

        if simulated:
            self._board_identity = "simulated"
        elif replaying:
            self._board_identity = "recorded"
        else:
            self._board_identity = "-"

    def _stop_worker(self) -> None:
        """Ordered shutdown: disconnect, flag, quit, join, release.

        Letting a QThread be garbage collected while running earns a
        "QThread: Destroyed while thread is still running" warning and can crash,
        so the join is not optional.
        """
        worker, thread = self._worker, self._thread
        # Nil the handles first, so anything reached during shutdown sees a
        # window with no active worker rather than a half-torn-down one.
        self._worker = None
        self._thread = None

        if worker is not None:
            # Signals are delivered as queued events, so any already sitting in
            # the event loop would arrive after the next session has started and
            # be mistaken for its own. One stale sourceFailed is enough to tear
            # down a healthy connection.
            for signal in (
                worker.messagesReady,
                worker.statsUpdated,
                worker.sourceFailed,
                worker.replayFinished,
                worker.finished,
            ):
                # RuntimeError simply means this one had no connections.
                with contextlib.suppress(RuntimeError):
                    signal.disconnect()
            worker.stop()

        if thread is not None:
            thread.quit()
            if not thread.wait(2000):
                thread.terminate()
                thread.wait(500)
            # Parented to the window, so without this every connect attempt
            # leaks a thread - and the reconnect loop retries indefinitely.
            thread.deleteLater()
        if worker is not None:
            worker.deleteLater()

    def _disconnect_source(self) -> None:
        self._cancel_reconnect()
        self._stop_worker()
        self._stop_recording()
        self._source = None
        self._source_name = "disconnected"
        self._update_source_indicators(None)
        self.matrix_view.set_stale(True)
        self.connect_button.setEnabled(True)
        self.disconnect_button.setEnabled(False)
        self._append_log("disconnected")

    def _replay_source(self) -> sources.ReplaySource | None:
        """The current source if it is a replay, else None.

        Every transport control needs this same question answered, and asking
        it in one place keeps the isinstance check from being scattered.
        """
        source = self._source
        return source if isinstance(source, sources.ReplaySource) else None

    def _replay_speed(self) -> float:
        return self.speed_spin.value()

    def _apply_replay_speed(self, value: float) -> None:
        self._control_replay(lambda source: source.set_speed(value))

    def _control_replay(self, operation) -> None:
        """Mutate the replay source on the thread that owns it."""
        if self._worker is None or self._replay_source() is None:
            return
        self._worker.invoke(operation)

    def _toggle_replay_pause(self, paused: bool) -> None:
        self.replay_play_button.setText("Play" if paused else "Pause")
        self._control_replay(lambda source: source.set_paused(paused))

    def _restart_replay(self) -> None:
        self._clear_history()
        self._control_replay(lambda source: source.restart())

    def _seek_replay(self, value: int) -> None:
        source = self._replay_source()
        if source is None:
            return
        target = source.duration_s * value / SEEK_RESOLUTION
        # Old samples describe a part of the recording we are no longer near, so
        # keeping them would draw a plot that mixes two different times.
        self._clear_history()
        self._control_replay(lambda src: src.seek(target))

    def _update_replay_transport(self) -> None:
        source = self._replay_source()
        if source is None:
            return
        elapsed = source.elapsed_s
        duration = source.duration_s
        self.replay_time_label.setText(f"{elapsed:,.1f} / {duration:,.1f} s")
        if not self.replay_slider.isSliderDown():
            self.replay_slider.blockSignals(True)
            self.replay_slider.setValue(int(source.progress * SEEK_RESOLUTION))
            self.replay_slider.blockSignals(False)

    def _open_capture(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Open capture", str(Path.cwd()), "vmoji captures (*.vmc);;All files (*)"
        )
        if not path:
            return
        try:
            source = sources.ReplaySource(path, speed=self._replay_speed())
        except sources.SourceError as exc:
            QMessageBox.warning(self, "Could not open capture", str(exc))
            return

        selection = SourceSelection("replay", path)
        self._remember_replay(path)
        self._refresh_ports()
        index = self._find_selection(selection)
        if index >= 0:
            self.source_combo.setCurrentIndex(index)

        self._start_worker(source, selection)
        self._append_log(f"replaying {Path(path).name} ({source.duration_s:.1f} s recorded)")

    # ------------------------------------------------------------ recording

    def start_recording(self, path: str) -> None:
        """Begin recording to an explicit path, bypassing the save dialog.

        Exposed so the app can be launched straight into recording from the
        command line, which is what makes an unattended bench capture possible.
        """
        if self._capture is not None:
            self._capture.close()  # never leak a half-written file handle
        self._capture = sources.CaptureWriter(path)
        self.record_button.setChecked(True)
        self._append_log(f"recording to {Path(path).name}")
        # A worker is handed the writer when it is constructed, so an already
        # running one has to be restarted before it will record anything.
        if self._worker is not None:
            self._connect_source()

    def _toggle_recording(self, checked: bool) -> None:
        if checked:
            default = time.strftime("vmoji-%Y%m%d-%H%M%S.vmc")
            path, _ = QFileDialog.getSaveFileName(
                self, "Record capture", str(Path.cwd() / default), "vmoji captures (*.vmc)"
            )
            if not path:
                self.record_button.setChecked(False)
                return
            self.start_recording(path)
        else:
            self._stop_recording()
            if self._worker is not None:
                self._connect_source()

    def _stop_recording(self) -> None:
        if self._capture is not None:
            self._append_log(
                f"recording stopped: {self._capture.bytes_written:,} bytes "
                f"in {self._capture.duration_s:.1f} s"
            )
            self._capture.close()
            self._capture = None
        self.record_button.setChecked(False)

    # -------------------------------------------------------------- signals

    @Slot(list)
    def _on_messages(self, messages: list) -> None:
        """Accumulate only. Drawing happens on the repaint timer."""
        new_lines = self.model.add_messages(messages)
        self._last_message_time = time.monotonic()
        self._log_pending.extend(new_lines)

        for message in messages:
            if isinstance(message, protocol.TextMessage):
                self._note_identity(message.text)

        self._sync_dwell_control()

    def _sync_dwell_control(self) -> None:
        """Follow the device's actual dwell, so a command sent from another
        terminal is reflected here too."""
        status = self.model.latest_status
        if status is None or self.dwell_slider.isSliderDown():
            return
        if status.row_dwell_us == self.dwell_slider.value():
            return
        clamped = min(
            protocol.DWELL_MAX_US, max(protocol.DWELL_MIN_US, status.row_dwell_us)
        )
        self.dwell_slider.blockSignals(True)
        self.dwell_slider.setValue(clamped)
        self.dwell_slider.blockSignals(False)
        self.dwell_label.setText(f"{status.row_dwell_us} us")

    def _note_identity(self, text: str) -> None:
        """Record the board id the firmware announces, if this line carries one."""
        fields = protocol.parse_identity(text)
        if fields is None:
            return
        board = fields.get("board", "?")
        version = fields.get("version")
        sha = fields.get("sha")
        detail = " ".join(part for part in (version, sha) if part)
        self._board_identity = f"{board}  (fw {detail})" if detail else board

    @Slot(object)
    def _on_stats(self, stats: protocol.ParserStats) -> None:
        self._stats = stats

    @Slot(str)
    def _on_source_failed(self, message: str) -> None:
        """A live link died. For a board that usually means the cable moved.

        Tearing the session down permanently is the wrong response: the board is
        typically back within a second, and during a demo a bumped cable should
        not be fatal. Replay and the simulator cannot come back, so they stop.
        """
        self._append_log(f"link error: {message}")
        selection = self._active_selection

        self._stop_worker()
        self._source = None
        self.matrix_view.set_stale(True)
        self.connect_button.setEnabled(True)
        self.disconnect_button.setEnabled(True)  # stays live, to cancel retrying

        if selection is not None and selection.kind == "serial":
            self._reconnect.arm(selection)
            self._schedule_reconnect()
        else:
            self.status_label.setText(f"link error: {message}")
            self._disconnect_source()

    def _reconnect_message(self) -> str:
        return self._reconnect.message(self._reconnect_timer.remainingTime())

    def _schedule_reconnect(self) -> None:
        target = self._reconnect.target
        if target is None:
            return
        self._reconnect_timer.start(int(self._reconnect.delay_s * 1000))
        self._source_name = f"{target.device} (reconnecting)"
        self.status_label.setText(self._reconnect_message())

    def _cancel_reconnect(self) -> None:
        self._reconnect_timer.stop()
        self._reconnect.reset()

    def _attempt_reconnect(self) -> None:
        target = self._reconnect.target
        if target is None:
            return

        device = target.device
        # Wait for the port node to reappear before opening it, so a replugged
        # board is met with a connection rather than a burst of failures.
        if device in {c.device for c in sources.list_port_candidates()}:
            try:
                source = self._build_source(target)
            except sources.SourceError as exc:
                self._append_log(f"reconnect failed: {exc}")
            else:
                self._cancel_reconnect()
                self._append_log(f"reconnected to {device}")
                # Pass the target through, so a second failure on the same
                # device still knows what to retry.
                self._start_worker(source, target)
                return

        self._reconnect.backoff()
        self._schedule_reconnect()

    @Slot()
    def _on_replay_finished(self) -> None:
        self._append_log("replay finished")
        self.status_label.setText("replay finished")

    def _send(self, command: protocol.Command) -> None:
        if self._worker is None:
            self._append_log(f"not connected, dropped: {command.line}")
            return
        self._worker.send_command(command)
        self._append_log(f"TX   {command.line}    ({command.description})")

    # --------------------------------------------------------------- render

    def _repaint(self) -> None:
        """The single redraw path, driven by a timer at a fixed rate."""
        window = float(self.window_spin.value())

        self.curve_refresh.setData(*self.model.refresh_hz.window(window))
        self.curve_period_mean.setData(*self.model.period_mean_us.window(window))
        self.curve_period_min.setData(*self.model.period_min_us.window(window))
        self.curve_period_max.setData(*self.model.period_max_us.window(window))
        self.curve_jitter.setData(*self.model.jitter_pp_us.window(window))
        self.curve_temp.setData(*self.model.die_temp_c.window(window))

        stale = (time.monotonic() - self._last_message_time) > STALE_AFTER_S
        framebuffer = self.model.latest_framebuffer
        if framebuffer is not None:
            self.matrix_view.set_grid(framebuffer.as_grid())
        self.matrix_view.set_stale(stale or self._worker is None)

        self._update_status_panel(stale)
        self._update_link_panel()
        self._update_replay_transport()
        self._flush_log()

        replay = self._replay_source()
        if self._reconnect.active:
            # This branch must come first. The repaint timer owns the status
            # label and rewrites it 30 times a second, so without an explicit
            # state here the countdown set by _schedule_reconnect is erased
            # within one frame and a recovering link just looks disconnected.
            self.status_label.setText(self._reconnect_message())
        elif self._worker is None:
            self.status_label.setText("disconnected")
        elif replay is not None and replay.paused:
            self.status_label.setText(f"{self._source_name} - paused")
        elif replay is not None and replay.exhausted:
            # Distinguish "the recording ran out" from "the link went quiet";
            # they look identical otherwise and mean entirely different things.
            self.status_label.setText(
                f"{self._source_name} - finished, use Restart or drag the slider"
            )
        elif stale:
            self.status_label.setText(f"{self._source_name} - no telemetry")
        else:
            self.status_label.setText(f"{self._source_name} - streaming")
        self.rate_label.setText(
            f"{self.model.status_rate_hz:5.1f} Hz telemetry   "
            f"{self.model.status_count:,} status   "
            f"{self.model.elapsed_s:,.0f} s history"
        )

    def _update_status_panel(self, stale: bool) -> None:
        status = self.model.latest_status
        if status is None:
            self.status_panel.clear_values()
            return
        self.status_panel.set_cells(panels.status_cells(status, stale))

    def _update_link_panel(self) -> None:
        recording = "-"
        if self._capture is not None:
            recording = f"{self._capture.bytes_written / 1024:,.1f} kB"

        self.link_panel.set_cells(
            panels.link_cells(
                self._stats,
                panels.LinkState(
                    source_name=self._source_name,
                    board_identity=self._board_identity,
                    rate_hz=self.model.status_rate_hz,
                    recording=recording,
                ),
            )
        )

    def _append_log(self, line: str) -> None:
        self._log_pending.append(f"[{model_module.stamp()}] {line}")

    def _flush_log(self) -> None:
        """Append log lines in one batch per frame.

        Appending to a QPlainTextEdit per message triggers a relayout each time;
        batching turns a hundred relayouts into one.
        """
        if not self._log_pending:
            return
        self.log_view.appendPlainText("\n".join(self._log_pending))
        self._log_pending.clear()

    def _clear_history(self) -> None:
        self.model.clear()
        self.log_view.clear()
        self._log_pending.clear()
        self._stats = protocol.ParserStats()
        self.matrix_view.clear()

    # ------------------------------------------------------------- shutdown

    def _save_layout(self) -> None:
        settings = QSettings()
        settings.setValue("geometry", self.saveGeometry())
        settings.setValue("windowState", self.saveState())
        settings.setValue("splitter", self.main_splitter.saveState())
        settings.setValue("plotSplitter", self.plot_splitter.saveState())

    def _restore_layout(self) -> None:
        """Reapply the last session's geometry, if it still makes sense.

        Guarded rather than trusted: a layout saved on a second monitor that is
        no longer attached would otherwise open the window off-screen, where it
        looks like the application failed to start.
        """
        settings = QSettings()
        geometry = settings.value("geometry")
        if geometry is not None and self.restoreGeometry(geometry):
            available = self.screen().availableGeometry() if self.screen() else None
            if available is not None and not available.intersects(self.frameGeometry()):
                self.resize(1440, 900)
                self.move(available.topLeft())
        for key, widget in (
            ("windowState", None),
            ("splitter", self.main_splitter),
            ("plotSplitter", self.plot_splitter),
        ):
            state = settings.value(key)
            if state is None:
                continue
            if widget is None:
                self.restoreState(state)
            else:
                widget.restoreState(state)

    def closeEvent(self, event) -> None:  # noqa: N802  (Qt naming)
        self._save_layout()
        self._repaint_timer.stop()
        self._port_timer.stop()
        self._reconnect_timer.stop()
        self._stop_worker()
        self._stop_recording()
        super().closeEvent(event)
