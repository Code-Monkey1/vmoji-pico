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

import time
from pathlib import Path

import pyqtgraph as pg
from PySide6.QtCore import Qt, QThread, QTimer, Slot
from PySide6.QtGui import QAction, QFont, QKeySequence
from PySide6.QtWidgets import (
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
    QSlider,
    QSpinBox,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

import model as model_module
import protocol
import reader as reader_module
import sources
from widgets import KeyValuePanel, MatrixView

REPAINT_INTERVAL_MS = 33  # ~30 FPS
STALE_AFTER_S = 1.0

STATUS_KEYS = [
    "Uptime",
    "Refresh rate",
    "Scan period (mean)",
    "Scan period (min)",
    "Scan period (max)",
    "Jitter (pk-pk)",
    "Die temperature",
    "Row dwell",
    "Scans",
    "Glyph",
    "Commands OK",
    "Commands rejected",
    "Flags",
]

LINK_KEYS = [
    "Source",
    "Board",
    "Telemetry rate",
    "Bytes received",
    "Frames OK",
    "CRC errors",
    "Bad lengths",
    "Unknown ids",
    "Resync bytes",
    "Sequence gaps",
    "Frames lost (est.)",
    "Recording",
]


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
    def __init__(self, initial_selection: tuple[str, str | None] = ("sim", None),
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
        self._default_baud = baudrate
        self._default_error_rate = error_rate
        self._replay_paths: list[str] = []
        self._board_identity = "-"

        self._build_ui()
        self._build_menu()

        # Repaint on a timer, never on data arrival. This single decision is what
        # keeps the UI responsive independent of the telemetry rate.
        self._repaint_timer = QTimer(self)
        self._repaint_timer.timeout.connect(self._repaint)
        self._repaint_timer.start(REPAINT_INTERVAL_MS)

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

        container = QWidget()
        outer = QVBoxLayout(container)
        outer.setContentsMargins(6, 6, 6, 6)
        outer.setSpacing(6)
        outer.addWidget(self._build_connection_bar())
        outer.addWidget(self._build_sim_banner())
        outer.addWidget(splitter, 1)
        self.setCentralWidget(container)

        self._build_log_dock()

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

        layout.addWidget(QLabel("Source:"))
        self.source_combo = QComboBox()
        self.source_combo.setMinimumWidth(320)
        layout.addWidget(self.source_combo)

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

        self.open_button = QPushButton("Open capture...")
        self.open_button.clicked.connect(self._open_capture)
        layout.addWidget(self.open_button)

        layout.addWidget(QLabel("Replay speed:"))
        self.speed_spin = QDoubleSpinBox()
        self.speed_spin.setRange(0.0, 100.0)
        self.speed_spin.setSingleStep(0.5)
        self.speed_spin.setValue(1.0)
        self.speed_spin.setSpecialValueText("max")
        self.speed_spin.setToolTip("1.0 replays at the recorded rate; 0 is as fast as possible")
        self.speed_spin.valueChanged.connect(self._apply_replay_speed)
        layout.addWidget(self.speed_spin)

        layout.addStretch(1)
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

        for plot in (self.plot_refresh, self.plot_period, self.plot_jitter, self.plot_temp):
            layout.addWidget(plot, 1)

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
        self.status_panel = KeyValuePanel(STATUS_KEYS)
        status_layout.addWidget(self.status_panel)
        layout.addWidget(status_box)

        link_box = QGroupBox("Link health")
        link_layout = QVBoxLayout(link_box)
        self.link_panel = KeyValuePanel(LINK_KEYS)
        link_layout.addWidget(self.link_panel)
        layout.addWidget(link_box)

        layout.addWidget(self._build_control_panel())
        return panel

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
        self.dwell_slider.setRange(50, 2000)
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
        dock.setWidget(self.log_view)
        dock.setAllowedAreas(Qt.DockWidgetArea.BottomDockWidgetArea | Qt.DockWidgetArea.TopDockWidgetArea)
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

    def _port_entries(self) -> list[tuple[str, tuple[str, str | None]]]:
        """The combo contents, hardware first and the simulator last.

        Ordering is the whole point: a real board should be what you get by
        default, and reaching the simulator should be a deliberate act.
        """
        entries: list[tuple[str, tuple[str, str | None]]] = []
        for candidate in sources.list_port_candidates():
            entries.append((candidate.label, ("serial", candidate.device)))
        for path in self._replay_paths:
            entries.append((f"Replay  -  {Path(path).name}", ("replay", path)))
        entries.append(("Simulator (synthetic data - no hardware)", ("sim", None)))
        return entries

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
        if remembered is not None:
            index = self.source_combo.findData(remembered)
            if index >= 0:
                self.source_combo.setCurrentIndex(index)
        self.source_combo.blockSignals(False)

    def _select_source(self, selection: tuple[str, str | None]) -> None:
        kind, device = selection
        if kind == "replay" and device:
            self._remember_replay(device)
            self._refresh_ports()

        index = self.source_combo.findData((kind, device))
        if index < 0 and kind == "serial" and device:
            # A port named explicitly that enumeration did not report; honour it
            # rather than silently substituting something else.
            self.source_combo.addItem(f"{device}  -  (as specified)", ("serial", device))
            index = self.source_combo.count() - 1
        if index >= 0:
            self.source_combo.setCurrentIndex(index)

    def _remember_replay(self, path: str) -> None:
        if path not in self._replay_paths:
            self._replay_paths.append(path)

    def _connect_source(self) -> None:
        selection = self.source_combo.currentData()
        if selection is None:
            return
        kind, device = selection
        try:
            if kind == "serial":
                source = sources.SerialSource(device, self.baud_combo.currentData())
            elif kind == "replay":
                source = sources.ReplaySource(device, speed=self._replay_speed())
            else:
                source = sources.SimSource(error_rate=self._default_error_rate)
        except sources.SourceError as exc:
            QMessageBox.warning(self, "Could not open source", str(exc))
            return

        self._start_worker(source)

    def _start_worker(self, source: sources.Source) -> None:
        self._stop_worker()
        self._clear_history()

        self._source_name = source.name
        self._source = source
        self._update_source_indicators(source)

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

    def _update_source_indicators(self, source: sources.Source | None) -> None:
        """Keep the banner and the title honest about what is driving the view."""
        simulated = isinstance(source, sources.SimSource)
        replaying = isinstance(source, sources.ReplaySource)
        self.sim_banner.setVisible(simulated)

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
        """Ordered shutdown: flag, quit, join.

        Letting a QThread be garbage collected while running earns a
        "QThread: Destroyed while thread is still running" warning and can crash,
        so the join is not optional.
        """
        if self._worker is not None:
            self._worker.stop()
        if self._thread is not None:
            self._thread.quit()
            if not self._thread.wait(2000):
                self._thread.terminate()
                self._thread.wait(500)
        self._worker = None
        self._thread = None

    def _disconnect_source(self) -> None:
        self._stop_worker()
        self._stop_recording()
        self._source = None
        self._source_name = "disconnected"
        self._update_source_indicators(None)
        self.matrix_view.set_stale(True)
        self.connect_button.setEnabled(True)
        self.disconnect_button.setEnabled(False)
        self._append_log("disconnected")

    def _replay_speed(self) -> float:
        return self.speed_spin.value()

    def _apply_replay_speed(self, value: float) -> None:
        source = getattr(self, "_source", None)
        if isinstance(source, sources.ReplaySource):
            source.speed = value

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

        self._remember_replay(path)
        self._refresh_ports()
        index = self.source_combo.findData(("replay", path))
        if index >= 0:
            self.source_combo.setCurrentIndex(index)

        self._start_worker(source)
        self._append_log(f"replaying {Path(path).name} ({source.duration_s:.1f} s recorded)")

    # ------------------------------------------------------------ recording

    def start_recording(self, path: str) -> None:
        """Begin recording to an explicit path, bypassing the save dialog.

        Exposed so the app can be launched straight into recording from the
        command line, which is what makes an unattended bench capture possible.
        """
        self._capture = sources.CaptureWriter(path)
        self.record_button.setChecked(True)
        self._append_log(f"recording to {Path(path).name}")
        # The worker owns the writer, so restart it to pick the capture up.
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
        before = len(self.model.log_lines)
        self.model.add_messages(messages)
        self._last_message_time = time.monotonic()

        new_lines = list(self.model.log_lines)[before:]
        if new_lines:
            self._log_pending.extend(new_lines)

        # Keep the control widgets in step with the device's actual state, so a
        # command sent from another terminal is reflected here too.
        status = self.model.latest_status
        if status is not None and not self.dwell_slider.isSliderDown():
            if status.row_dwell_us != self.dwell_slider.value():
                self.dwell_slider.blockSignals(True)
                self.dwell_slider.setValue(min(2000, max(50, status.row_dwell_us)))
                self.dwell_slider.blockSignals(False)
                self.dwell_label.setText(f"{status.row_dwell_us} us")

    @Slot(object)
    def _on_stats(self, stats: protocol.ParserStats) -> None:
        self._stats = stats

    @Slot(str)
    def _on_source_failed(self, message: str) -> None:
        self._append_log(f"link error: {message}")
        self.status_label.setText(f"link error: {message}")
        self._disconnect_source()

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
        self._flush_log()

        if self._worker is None:
            self.status_label.setText("disconnected")
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

        flags = []
        if status.has_flag(protocol.StatusFlag.ACTIVITY):
            flags.append("ACTIVITY")
        if status.has_flag(protocol.StatusFlag.OVERRUN):
            flags.append("OVERRUN")
        if status.has_flag(protocol.StatusFlag.PAUSED):
            flags.append("PAUSED")

        glyph = protocol.GLYPH_NAMES[status.glyph_id] if status.glyph_id < len(
            protocol.GLYPH_NAMES
        ) else "?"

        self.status_panel.set_values(
            {
                "Uptime": f"{status.uptime_s:,.1f} s",
                "Refresh rate": f"{status.refresh_hz:,.2f} Hz",
                "Scan period (mean)": f"{status.period_mean_us:,} us",
                "Scan period (min)": f"{status.period_min_us:,} us",
                "Scan period (max)": f"{status.period_max_us:,} us",
                "Jitter (pk-pk)": f"{status.jitter_pp_us:,} us",
                "Die temperature": f"{status.die_temp_c:.2f} C",
                "Row dwell": f"{status.row_dwell_us:,} us",
                "Scans": f"{status.scan_count:,}",
                "Glyph": f"{status.glyph_id}  {glyph}",
                "Commands OK": f"{status.cmd_ok:,}",
                "Commands rejected": f"{status.cmd_err:,}",
                "Flags": " ".join(flags) if flags else "-",
            }
        )
        # Highlight the numbers that mean something is wrong.
        self.status_panel.set_value(
            "Commands rejected", f"{status.cmd_err:,}", warn=status.cmd_err > 0
        )
        self.status_panel.set_value(
            "Flags",
            " ".join(flags) if flags else "-",
            warn=status.has_flag(protocol.StatusFlag.OVERRUN),
        )
        self.status_panel.set_value(
            "Refresh rate", f"{status.refresh_hz:,.2f} Hz", warn=stale
        )

    def _update_link_panel(self) -> None:
        stats = self._stats
        recording = "-"
        if self._capture is not None:
            recording = f"{self._capture.bytes_written / 1024:,.1f} kB"

        self.link_panel.set_values(
            {
                "Source": self._source_name,
                "Board": self._board_identity,
                "Telemetry rate": f"{self.model.status_rate_hz:.1f} Hz",
                "Bytes received": f"{stats.bytes_in:,}",
                "Frames OK": f"{stats.frames_ok:,}",
                "Bad lengths": f"{stats.length_errors:,}",
                "Resync bytes": f"{stats.resync_bytes:,}",
                "Recording": recording,
            }
        )
        # These four are the ones that should draw the eye when non-zero.
        self.link_panel.set_value("CRC errors", f"{stats.crc_errors:,}", warn=stats.crc_errors > 0)
        self.link_panel.set_value(
            "Unknown ids", f"{stats.unknown_ids:,}", warn=stats.unknown_ids > 0
        )
        self.link_panel.set_value("Sequence gaps", f"{stats.seq_gaps:,}", warn=stats.seq_gaps > 0)
        self.link_panel.set_value(
            "Frames lost (est.)",
            f"{stats.frames_dropped_estimate:,}",
            warn=stats.frames_dropped_estimate > 0,
        )

    def _append_log(self, line: str) -> None:
        self._log_pending.append(f"[{time.strftime('%H:%M:%S')}] {line}")

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

    def closeEvent(self, event) -> None:  # noqa: N802  (Qt naming)
        self._repaint_timer.stop()
        self._stop_worker()
        self._stop_recording()
        super().closeEvent(event)
