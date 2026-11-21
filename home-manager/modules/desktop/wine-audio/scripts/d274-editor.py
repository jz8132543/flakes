import signal
import sys
from pathlib import Path

from PyQt5.QtCore import QTimer
from PyQt5.QtWidgets import QApplication


def main(tools, project, client):
    sys.path.insert(0, str(tools / "share/carla"))
    import carla_backend as carla

    app = QApplication([])
    app.setQuitOnLastWindowClosed(False)
    host = carla.CarlaHostDLL(str(tools / "lib/carla/libcarla_standalone2.so"), False)
    for option, value, text in (
        (carla.ENGINE_OPTION_PROCESS_MODE, carla.ENGINE_PROCESS_MODE_SINGLE_CLIENT, ""),
        (carla.ENGINE_OPTION_TRANSPORT_MODE, carla.ENGINE_TRANSPORT_MODE_DISABLED, ""),
        (carla.ENGINE_OPTION_AUDIO_DEVICE, 0, "Auto-Connect OFF"),
        (carla.ENGINE_OPTION_OSC_ENABLED, 0, ""),
        (carla.ENGINE_OPTION_PATH_BINARIES, 0, str(tools / "lib/carla")),
        (carla.ENGINE_OPTION_PATH_RESOURCES, 0, str(tools / "share/carla/resources")),
    ):
        host.set_engine_option(option, value, text)

    editor_opened = False

    def callback(_ptr, action, _plugin, state, _v2, _v3, _vf, text):
        nonlocal editor_opened
        if action == carla.ENGINE_CALLBACK_UI_STATE_CHANGED:
            if state == 1:
                editor_opened = True
            elif state == -1 or (state == 0 and editor_opened):
                if state == -1:
                    print(f"VSL editor failed: {text}", file=sys.stderr, flush=True)
                QTimer.singleShot(0, lambda: app.exit(int(state == -1)))

    host.set_engine_callback(callback)
    if not host.engine_init("JACK", client):
        raise RuntimeError(host.get_last_error())
    try:
        if not host.load_project(str(project)) or host.get_current_plugin_count() != 1:
            raise RuntimeError(host.get_last_error())
        if not host.get_plugin_info(0)["hints"] & carla.PLUGIN_HAS_CUSTOM_UI:
            raise RuntimeError("The D-274 project has no plugin editor")

        timer = QTimer()
        timer.timeout.connect(host.engine_idle)
        timer.start(30)
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, lambda *_: app.quit())
        QTimer.singleShot(0, lambda: host.show_custom_ui(0, True))
        print("D-274 project loaded", flush=True)
        return app.exec()
    finally:
        host.engine_close()


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]))
