"""DocScan as a Windows program.

The reader server runs inside this process on a private local port, and a WebView2 window (pywebview, the
Edge engine built into Windows) shows the app: no browser, no Docker, works offline. Closing the window ends
the program, readers and all, so nothing is left in memory. Drafts and templates live in
%LOCALAPPDATA%\\DocScan, so updating or reinstalling keeps them.

Folder layout (desktop/build.ps1 makes it; the installer copies it):
    python\\            embedded Python and the base packages     app\\server, app\\web, app\\templates, app\\desktop
    tesseract\\         tesseract.exe and its tessdata folders    models\\            PaddleOCR (and optional) models
    parts\\<name>\\site-packages   optional readers (EasyOCR, Nuqta), downloaded by the installer when chosen
"""
from __future__ import annotations

import ctypes
import os
import shutil
import socket
import sys
import threading
import time
import traceback
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent  # {app}\app\desktop
APP = HERE.parent                       # {app}\app
ROOT = APP.parent                       # {app}
VERSION = (HERE / "VERSION").read_text(encoding="utf-8").strip() if (HERE / "VERSION").exists() else "0.0.0"
TITLE = "تحويل الوثائق المصوّرة إلى مستندات"
LOCAL = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "DocScan"
SPLASH = """<!doctype html><html lang="ar" dir="rtl"><body style="margin:0;height:100vh;display:grid;place-items:center;
background:#f2f5f2;font:18px Segoe UI,Tahoma,sans-serif;color:#1d2a20"><div style="text-align:center">
<div style="width:56px;height:56px;margin:0 auto 18px;border-radius:12px;background:#14532d"></div>
<b>تحويل الوثائق المصوّرة إلى مستندات</b><p style="color:#5b6b5f">جارٍ تشغيل البرنامج…</p></div></body></html>"""


def message(text: str, error: bool = False) -> None:
    ctypes.windll.user32.MessageBoxW(None, text, TITLE, 0x10 if error else 0x40)


def setup() -> None:
    """Where everything is, before the server is imported (it reads these when it starts)."""
    data, templates = LOCAL / "data", LOCAL / "templates"
    data.mkdir(parents=True, exist_ok=True)
    templates.mkdir(parents=True, exist_ok=True)
    for f in (APP / "templates").glob("*"):  # the bundled plain template, once; the user's own are kept
        if not (templates / f.name).exists():
            shutil.copy2(f, templates / f.name)
    tess = ROOT / "tesseract"
    os.environ.update({
        "DOCSCAN_DATA": str(data), "DOCSCAN_TEMPLATES": str(templates),
        "DOCSCAN_DESKTOP": "1", "DOCSCAN_VERSION": VERSION,
        "TESSDATA_FAST": str(tess / "tessdata" / "fast"), "TESSDATA_STANDARD": str(tess / "tessdata" / "standard"),
        "TESSDATA_BEST": str(tess / "tessdata" / "best"),
        # every model ships with the program: no downloads, no "checking connectivity" at start
        "PADDLE_PDX_CACHE_HOME": str(ROOT / "models" / "paddlex"), "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK": "True",
        "EASYOCR_MODELS": str(ROOT / "models" / "easyocr"),
        "HF_HOME": str(ROOT / "models" / "hf"), "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
    })
    os.environ["PATH"] = str(tess) + os.pathsep + os.environ.get("PATH", "")
    for part in sorted((ROOT / "parts").glob("*/site-packages")):
        sys.path.append(str(part))
    sys.path.insert(0, str(APP / "server"))
    os.chdir(APP / "server")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main() -> None:
    # one copy at a time: a second start would read the same drafts from two places
    ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\DocScan.single")
    if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        message("البرنامج مفتوح بالفعل.")
        return
    ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Eyasbzour.DocScan")  # taskbar: our icon and name
    (LOCAL / "logs").mkdir(parents=True, exist_ok=True)
    log = open(LOCAL / "logs" / "docscan.log", "a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stderr = log  # pythonw has no console
    print(f"\n--- {time.strftime('%Y-%m-%d %H:%M:%S')} DocScan {VERSION}")
    setup()

    import webview

    webview.settings["ALLOW_DOWNLOADS"] = True  # produced files go to the Downloads folder
    window = webview.create_window(TITLE, html=SPLASH, width=1440, height=920, min_size=(900, 600))
    port = free_port()
    state: dict = {}

    def start_server():
        try:
            import uvicorn

            import main as server

            server.QUIT_APP[0] = window.destroy  # the updater closes the program this way
            state["server"] = uvicorn.Server(uvicorn.Config(server.app, host="127.0.0.1", port=port, log_level="warning"))
            threading.Thread(target=state["server"].run, daemon=True, name="server").start()
            for _ in range(240):  # the readers import slowly the first time
                try:
                    urllib.request.urlopen(f"http://127.0.0.1:{port}/api/engines", timeout=1).close()
                    break
                except Exception:
                    time.sleep(0.25)
            window.load_url(f"http://127.0.0.1:{port}/")
        except Exception:
            traceback.print_exc()
            message("تعذر تشغيل البرنامج. التفاصيل في:\n" + str(LOCAL / "logs" / "docscan.log"), error=True)
            window.destroy()

    def shown():
        try:  # the window's own icon (WinForms; the taskbar takes it from here)
            import clr  # noqa: F401  (pythonnet, which pywebview uses on Windows)
            from System.Drawing import Icon

            window.native.Icon = Icon(str(ROOT / "docscan.ico"))
        except Exception:
            pass

    window.events.shown += shown
    webview.start(start_server, gui="edgechromium", private_mode=False, storage_path=str(LOCAL / "webview"))
    # the window is closed: stop the server and leave nothing running (readers may hold threads)
    if state.get("server"):
        state["server"].should_exit = True
    print("closed")
    log.flush()
    os._exit(0)


if __name__ == "__main__":
    main()
