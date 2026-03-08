import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import zipfile

from flask import Flask, render_template_string, request, Response

try:
    import serial
except ImportError:
    serial = None

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 10 * 1024 * 1024  # 10 MB

WORKSPACE = os.environ.get("WORKSPACE", "/workspace")
LOCK = threading.Lock()
BUSY = False
serial_process = None
SERIAL_BAUD = os.environ.get("SERIAL_BAUD", "9600")
FQBN = os.environ.get("ARDUINO_FQBN", "arduino:avr:nano:cpu=atmega328old")
FQBN_OLD = "arduino:avr:nano:cpu=atmega328old"
FQBN_NEW = "arduino:avr:nano:cpu=atmega328"
ALLOWED_EXTENSIONS = (".ino", ".zip")
BUILTIN_SKETCHES = ("SetTimeUseMe", "Matrix_Clock")
# Libraries required by each built-in sketch (arduino-cli lib install name)
BUILTIN_LIBS = {
    "SetTimeUseMe": ["Time", "DS1307RTC"],
    "Matrix_Clock": ["MD_Parola", "MD_MAX72XX", "DS3231"],
}


def run_script(script_name, extra_args=None):
    global BUSY
    if BUSY:
        return "Another operation is already running.\n", 409
    with LOCK:
        BUSY = True
    try:
        path = os.path.join(WORKSPACE, script_name)
        if not os.path.isfile(path):
            return f"Script not found: {path}\n", 404
        cmd = ["bash", path]
        if extra_args:
            cmd.extend(extra_args)
        result = subprocess.run(
            cmd,
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=300,
            env={**os.environ, "HOME": os.environ.get("HOME", "/app")},
        )
        out = (result.stdout or "") + (result.stderr or "")
        if result.returncode != 0:
            return out + f"\nExit code: {result.returncode}\n", 400
        return out, 200
    except subprocess.TimeoutExpired:
        return "Operation timed out (5 min).\n", 408
    except Exception as e:
        return f"Error: {e}\n", 500
    finally:
        with LOCK:
            BUSY = False


def get_arduino_port():
    port = os.environ.get("ARDUINO_PORT", "").strip()
    if port:
        return port
    try:
        result = subprocess.run(
            ["arduino-cli", "board", "list"],
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, "HOME": os.environ.get("HOME", "/app")},
        )
        out = (result.stdout or "") + (result.stderr or "")
        for line in out.splitlines():
            m = re.search(r"(/dev/tty(?:USB|ACM)\d+)", line)
            if m:
                return m.group(1)
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        pass
    return "/dev/ttyUSB0"


def reset_arduino_bootloader(port):
    """Pulse DTR (1200 baud open) to put Nano into bootloader before upload."""
    if serial is None:
        return
    try:
        ser = serial.Serial(port, 1200)
        time.sleep(0.1)
        ser.close()
        time.sleep(0.5)
    except Exception:
        pass


def run_flash_upload(file_storage):
    global BUSY
    if BUSY:
        return "Another operation is already running.\n", 409
    filename = (file_storage and file_storage.filename) or ""
    if not filename.lower().endswith(ALLOWED_EXTENSIONS):
        return "Only .ino or .zip files are allowed.\n", 400
    with LOCK:
        BUSY = True
    tmpdir = None
    try:
        tmpdir = tempfile.mkdtemp(prefix="flash_upload_")
        sketch_dir = tmpdir
        if filename.lower().endswith(".zip"):
            with zipfile.ZipFile(file_storage, "r") as zf:
                for name in zf.namelist():
                    if ".." in name or name.startswith("/") or os.path.isabs(name):
                        return "Invalid path in zip.\n", 400
                zf.extractall(tmpdir)
            entries = [e for e in os.listdir(tmpdir) if not e.startswith(".")]
            if len(entries) == 1 and os.path.isdir(os.path.join(tmpdir, entries[0])):
                sub = os.path.join(tmpdir, entries[0])
                if any(f.lower().endswith(".ino") for f in os.listdir(sub)):
                    sketch_dir = sub
            if not any(
                f.lower().endswith(".ino")
                for r, _, files in os.walk(tmpdir)
                for f in files
            ):
                return "Zip must contain at least one .ino file.\n", 400
        else:
            path = os.path.join(tmpdir, "sketch.ino")
            file_storage.save(path)
        port = get_arduino_port()
        env = {**os.environ, "HOME": os.environ.get("HOME", "/app")}
        log_parts = []
        comp = subprocess.run(
            ["arduino-cli", "compile", "--fqbn", FQBN, sketch_dir],
            capture_output=True,
            text=True,
            timeout=300,
            env=env,
        )
        log_parts.append(comp.stdout or "")
        log_parts.append(comp.stderr or "")
        if comp.returncode != 0:
            log_parts.append(f"\nCompile failed (exit code {comp.returncode}).\n")
            return "".join(log_parts), 400
        log_parts.append("\n--- Upload ---\n")
        log_parts.append("Resetting Arduino to bootloader...\n")
        reset_arduino_bootloader(port)
        fqbn_upload = FQBN
        up = subprocess.run(
            ["arduino-cli", "upload", "-p", port, "--fqbn", fqbn_upload, sketch_dir, "--verbose"],
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
        )
        log_parts.append(up.stdout or "")
        log_parts.append(up.stderr or "")
        if up.returncode != 0 and fqbn_upload == FQBN_OLD:
            log_parts.append("\nTrying new bootloader (115200 baud)...\n")
            reset_arduino_bootloader(port)
            up = subprocess.run(
                ["arduino-cli", "upload", "-p", port, "--fqbn", FQBN_NEW, sketch_dir, "--verbose"],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
            log_parts.append(up.stdout or "")
            log_parts.append(up.stderr or "")
        if up.returncode != 0:
            log_parts.append(f"\nUpload failed (exit code {up.returncode}).\n")
            return "".join(log_parts), 400
        return "".join(log_parts), 200
    except zipfile.BadZipFile:
        return "Invalid or corrupted zip file.\n", 400
    except subprocess.TimeoutExpired:
        return "Operation timed out (5 min).\n", 408
    except Exception as e:
        return f"Error: {e}\n", 500
    finally:
        if tmpdir and os.path.isdir(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)
        with LOCK:
            BUSY = False


@app.route("/")
def index():
    with open(os.path.join(os.path.dirname(__file__), "templates", "index.html")) as f:
        return render_template_string(f.read())


@app.route("/run/reset", methods=["POST"])
def run_reset():
    port = request.form.get("port") or os.environ.get("ARDUINO_PORT", "")
    extra = [port] if port.strip() else None
    body, status = run_script("reset_arduino.sh", extra)
    return Response(body, status=status, mimetype="text/plain")


@app.route("/run/flash", methods=["POST"])
def run_flash():
    body, status = run_script("flash_arduino.sh")
    return Response(body, status=status, mimetype="text/plain")


def run_flash_builtin(sketch):
    global BUSY
    if BUSY:
        return "Another operation is already running.\n", 409
    if sketch not in BUILTIN_SKETCHES:
        return f"Unknown sketch. Choose one of: {', '.join(BUILTIN_SKETCHES)}\n", 400
    sketch_dir = os.path.join(WORKSPACE, "firmware", sketch)
    if not os.path.isdir(sketch_dir):
        return f"Sketch not found: {sketch_dir}\n", 404
    with LOCK:
        BUSY = True
    try:
        port = get_arduino_port()
        env = {**os.environ, "HOME": os.environ.get("HOME", "/app")}
        log_parts = []
        for lib in BUILTIN_LIBS.get(sketch, []):
            log_parts.append(f"Installing library: {lib}\n")
            inst = subprocess.run(
                ["arduino-cli", "lib", "install", lib],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
            log_parts.append(inst.stdout or "")
            log_parts.append(inst.stderr or "")
        log_parts.append("\n--- Compile ---\n")
        comp = subprocess.run(
            ["arduino-cli", "compile", "--fqbn", FQBN, sketch_dir],
            capture_output=True,
            text=True,
            timeout=300,
            env=env,
        )
        log_parts.append(comp.stdout or "")
        log_parts.append(comp.stderr or "")
        if comp.returncode != 0:
            log_parts.append(f"\nCompile failed (exit code {comp.returncode}).\n")
            return "".join(log_parts), 400
        log_parts.append("\n--- Upload ---\n")
        log_parts.append("Resetting Arduino to bootloader...\n")
        reset_arduino_bootloader(port)
        fqbn_upload = FQBN
        up = subprocess.run(
            ["arduino-cli", "upload", "-p", port, "--fqbn", fqbn_upload, sketch_dir, "--verbose"],
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
        )
        log_parts.append(up.stdout or "")
        log_parts.append(up.stderr or "")
        if up.returncode != 0 and fqbn_upload == FQBN_OLD:
            log_parts.append("\nTrying new bootloader (115200 baud)...\n")
            reset_arduino_bootloader(port)
            up = subprocess.run(
                ["arduino-cli", "upload", "-p", port, "--fqbn", FQBN_NEW, sketch_dir, "--verbose"],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
            log_parts.append(up.stdout or "")
            log_parts.append(up.stderr or "")
        if up.returncode != 0:
            log_parts.append(f"\nUpload failed (exit code {up.returncode}).\n")
            return "".join(log_parts), 400
        return "".join(log_parts), 200
    except subprocess.TimeoutExpired:
        return "Operation timed out (5 min).\n", 408
    except Exception as e:
        return f"Error: {e}\n", 500
    finally:
        with LOCK:
            BUSY = False


@app.route("/run/flash-builtin", methods=["POST"])
def run_flash_builtin_route():
    sketch = (request.form.get("sketch") or "").strip()
    body, status = run_flash_builtin(sketch)
    return Response(body, status=status, mimetype="text/plain")


@app.route("/run/flash-upload", methods=["POST"])
def run_flash_upload_route():
    if "file" not in request.files:
        return Response("No file provided.\n", status=400, mimetype="text/plain")
    body, status = run_flash_upload(request.files["file"])
    return Response(body, status=status, mimetype="text/plain")


def _serial_stream_generator():
    global BUSY, serial_process
    port = get_arduino_port()
    if not os.path.exists(port):
        yield "data: Error: port %s not found. Is the Arduino connected?\n\n" % port
        with LOCK:
            BUSY = False
        return
    yield "data: Connecting to %s at %s baud (no reset)...\n\n" % (port, SERIAL_BAUD)
    if serial is not None:
        try:
            ser = serial.Serial(port, int(SERIAL_BAUD))
            ser.dtr = False
            ser.rts = False
        except Exception as e:
            yield "data: Error opening port: %s\n\n" % e
            with LOCK:
                BUSY = False
            return
        serial_process = ser
        try:
            while True:
                line = ser.readline()
                if not line:
                    break
                yield "data: " + line.decode("utf-8", errors="replace").rstrip("\r\n") + "\n\n"
        except Exception:
            pass
        finally:
            try:
                ser.close()
            except Exception:
                pass
            serial_process = None
            with LOCK:
                BUSY = False
        return
    env = {**os.environ, "HOME": os.environ.get("HOME", "/app")}
    try:
        proc = subprocess.Popen(
            ["arduino-cli", "monitor", "-p", port, "-c", "baudrate=" + SERIAL_BAUD],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
    except Exception as e:
        yield "data: Error starting monitor: %s\n\n" % e
        with LOCK:
            BUSY = False
        return
    serial_process = proc
    try:
        for line in iter(proc.stdout.readline, ""):
            if line:
                yield "data: " + line.rstrip("\n") + "\n\n"
        if proc.returncode is not None and proc.returncode != 0:
            yield "data: [Monitor exited with code %s]\n\n" % proc.returncode
    except Exception:
        pass
    finally:
        if proc.poll() is None:
            proc.terminate()
        serial_process = None
        with LOCK:
            BUSY = False


@app.route("/run/serial-stream")
def run_serial_stream():
    global BUSY
    if BUSY:
        return Response("Another operation is already running.\n", status=409, mimetype="text/plain")
    with LOCK:
        BUSY = True
    return Response(
        _serial_stream_generator(),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.route("/run/serial-stop", methods=["POST"])
def run_serial_stop():
    global BUSY, serial_process
    with LOCK:
        if serial_process is not None:
            try:
                if hasattr(serial_process, "close"):
                    serial_process.close()
                elif hasattr(serial_process, "poll") and serial_process.poll() is None:
                    serial_process.terminate()
            except Exception:
                pass
            serial_process = None
            BUSY = False
    return Response("Stopped.\n", status=200, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
