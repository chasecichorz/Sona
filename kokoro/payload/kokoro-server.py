#!/opt/kokoro-speechd/venv/bin/python -I
"""Kokoro TTS helper for speech-dispatcher.

Keeps the Kokoro model loaded and answers requests on a private unix socket.
Started on demand by kokoro-speak; exits after IDLE_EXIT seconds of no use.
Protocol: client sends one JSON line {"text","voice","speed","gain"};
server streams raw signed 16-bit mono PCM at 24000 Hz, then closes.

Tuned for screen-reader use (2026-11-12):
- the newest request wins: older ones stop rendering, so fast arrowing
  never queues up stale speech or fights it for the CPU;
- only one render runs at a time, on the physical cores;
- the first piece is kept short so speech starts sooner;
- leading silence is trimmed and trailing silence shortened;
- short phrases (menu items, keys, "blank") are cached and replay instantly.
"""
import json, os, re, socket, sys, threading, time
from collections import OrderedDict

import numpy as np
import onnxruntime as ort
from kokoro_onnx import Kokoro

MODELS = "/opt/kokoro-speechd/models"
IDLE_EXIT = 2 * 60 * 60
RATE = 24000
THREADS = max(1, min(8, (os.cpu_count() or 2) // 2))
CACHE_ITEMS, CACHE_CHARS = 600, 80
LEAD_KEEP = int(0.010 * RATE)   # keep 10 ms before the first sound
TAIL_KEEP = int(0.070 * RATE)   # keep 70 ms after the last sound
LANGS = {"a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr",
         "h": "hi", "i": "it", "p": "pt-br"}


def sock_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(
        os.path.expanduser("~"), ".cache")
    d = os.path.join(base, "kokoro-speechd")
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return os.path.join(d, "kokoro.sock")


SPLIT = re.compile(r"(?<=[.!?;:])\s+|\n+")


def cut_at(part, limit, minimum):
    """Index to cut part at, preferring a comma, then a space."""
    for mark in (", ", " "):
        cut = part.rfind(mark, 0, limit)
        if cut >= minimum:
            return cut + 1
    return limit


def pieces(text, first_limit=70, limit=220):
    """Sentences, with a short first piece so audio starts quickly."""
    first = True
    for part in SPLIT.split(text):
        part = part.strip()
        while part:
            lim = first_limit if first else limit
            if len(part) <= lim:
                yield part
                break
            cut = cut_at(part, lim, 15 if first else 40)
            yield part[:cut].strip()
            part = part[cut:].strip()
            first = False
        first = False


def trim(audio):
    loud = np.flatnonzero(np.abs(audio) > 0.01)
    if not len(loud):
        return audio[:0]
    return audio[max(0, loud[0] - LEAD_KEEP):loud[-1] + TAIL_KEEP]


class Server:
    def __init__(self):
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = THREADS
        opts.inter_op_num_threads = 1
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess = ort.InferenceSession(f"{MODELS}/kokoro-v1.0.onnx", opts,
                                    providers=["CPUExecutionProvider"])
        self.kokoro = Kokoro.from_session(sess, f"{MODELS}/voices-v1.0.bin")
        self.voices = set(self.kokoro.get_voices())
        self.render_lock = threading.Lock()
        self.gen_lock = threading.Lock()
        self.generation = 0
        self.cache = OrderedDict()
        self.last_use = time.monotonic()
        for warm in ("ready", "Ready, set, go."):
            self.kokoro.create(warm, voice="af_heart", speed=1.0, lang="en-us")

    def render(self, text, voice, speed, lang):
        key = (text, voice, round(speed, 2))
        if key in self.cache:
            self.cache.move_to_end(key)
            return self.cache[key]
        audio, _ = self.kokoro.create(text, voice=voice, speed=speed,
                                      lang=lang, trim=False)
        audio = trim(audio)
        if len(text) <= CACHE_CHARS:
            self.cache[key] = audio
            if len(self.cache) > CACHE_ITEMS:
                self.cache.popitem(last=False)
        return audio

    def handle(self, conn):
        with self.gen_lock:
            self.generation += 1
            me = self.generation
        self.last_use = time.monotonic()
        try:
            with conn, conn.makefile("rb") as f:
                req = json.loads(f.readline() or b"{}")
                voice = req.get("voice", "af_heart")
                if voice not in self.voices:
                    voice = "af_heart"
                lang = LANGS.get(voice[0], "en-us")
                speed = min(max(float(req.get("speed", 1.0)), 0.5), 2.0)
                gain = min(max(float(req.get("gain", 1.0)), 0.0), 2.0)
                for text in pieces(str(req.get("text", ""))):
                    if me != self.generation:
                        return          # newer speech arrived; drop this
                    with self.render_lock:
                        if me != self.generation:
                            return
                        audio = self.render(text, voice, speed, lang)
                    pcm = np.clip(audio * gain * 32767, -32768, 32767)
                    conn.sendall(pcm.astype("<i2").tobytes())
                    self.last_use = time.monotonic()
        except (BrokenPipeError, ConnectionResetError):
            pass  # speech was interrupted; stop rendering
        except Exception as e:  # keep serving other requests
            print(f"kokoro-server: {e!r}", file=sys.stderr)

    def run(self):
        path = sock_path()
        if os.path.exists(path):
            os.unlink(path)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        os.chmod(path, 0o600)
        srv.listen(8)
        srv.settimeout(30)
        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                if time.monotonic() - self.last_use > IDLE_EXIT:
                    srv.close()
                    os.unlink(path)
                    return
                continue
            threading.Thread(target=self.handle, args=(conn,),
                             daemon=True).start()


if __name__ == "__main__":
    Server().run()
