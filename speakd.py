"""Local Kokoro TTS daemon on 127.0.0.1:47811.

POST /speak (text body)  stream speech sentence by sentence (replaces current speech)
POST /stop | /pause | /resume | /toggle-pause | /skip
POST /config  voice=af_heart&speed=1.25&model=/abs/path.onnx  (applies from the next sentence)
GET  /status  idle | speaking | paused
GET  /voices  newline-separated English voice ids
"""
import queue, re, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

import numpy as np
import sounddevice as sd
from kokoro_onnx import Kokoro

MODELS = Path(__file__).resolve().parent / "models"
PORT, SR = 47811, 24000

VOICES_FILE = str(MODELS / "voices-v1.0.bin")
config = {"voice": "af_heart", "speed": 1.25, "model": str(MODELS / "kokoro-v1.0.int8.onnx")}
model_lock = threading.Lock()  # held while synthesizing or swapping models


def load(model_path: str) -> Kokoro:
    k = Kokoro(model_path, VOICES_FILE)
    k.create("Ready.", voice=config["voice"], speed=config["speed"])  # warm up
    return k


kokoro = load(config["model"])
VOICES = [v for v in kokoro.get_voices() if v[:2] in ("af", "am", "bf", "bm")]


def switch_model(path: str):
    """Load a different model file in the background; keeps the current one until the new one is ready."""
    global kokoro
    if path == config["model"] or not path.endswith(".onnx") or not Path(path).is_file(): return
    new = load(path)
    with model_lock:
        kokoro, config["model"] = new, path


class Player:
    """One persistent output stream fed by a queue of sentence buffers; pausing outputs silence."""

    def __init__(self):
        self.q: queue.Queue = queue.Queue()
        self.buf = np.zeros(0, np.float32)
        self.paused = False
        self.lock = threading.Lock()
        self.generation = 0  # bumping this cancels the in-flight job
        self.pending = 0     # sentences synthesized or queued but not finished playing
        self.stream = sd.OutputStream(samplerate=SR, channels=1, dtype="float32", callback=self._cb)
        self.stream.start()

    def _cb(self, out, frames, *_):
        out.fill(0)
        if self.paused: return
        n = 0
        with self.lock:
            while n < frames:
                if not len(self.buf):
                    try: self.buf = self.q.get_nowait()
                    except queue.Empty: break
                    if self.buf is None:  # end-of-sentence marker
                        self.pending -= 1; self.buf = np.zeros(0, np.float32); continue
                take = min(frames - n, len(self.buf))
                out[n:n + take, 0] = self.buf[:take]
                self.buf, n = self.buf[take:], n + take

    def clear(self):
        with self.lock:
            self.generation += 1
            self.q = queue.Queue(); self.buf = np.zeros(0, np.float32); self.pending = 0
        self.paused = False

    def skip(self):
        with self.lock:  # drop the rest of the current sentence
            self.buf = np.zeros(0, np.float32)
            while True:
                try: item = self.q.get_nowait()
                except queue.Empty: break
                if item is None: self.pending -= 1; break

    @property
    def status(self):
        return "idle" if self.pending <= 0 else "paused" if self.paused else "speaking"


player = Player()


def chunks(text: str):
    """Split into sentences, merging tiny ones and splitting very long ones on commas."""
    text = re.sub(r"\s+", " ", text).strip()
    out = []
    for s in re.split(r"(?<=[.!?;:])\s+", text):
        while len(s) > 300:
            cut = s.rfind(",", 0, 300) + 1 or s.rfind(" ", 0, 300) + 1 or 300
            out.append(s[:cut]); s = s[cut:].strip()
        if out and len(out[-1]) < 40:
            out[-1] += " " + s
        elif s:
            out.append(s)
    return out


def synth(text: str, gen: int):
    parts = chunks(text)
    with player.lock:
        if gen == player.generation: player.pending = len(parts)
    for c in parts:
        if gen != player.generation: return
        # Stay at most ~2 sentences ahead so voice/speed changes apply quickly.
        while player.q.qsize() > 2 and gen == player.generation:
            threading.Event().wait(0.05)
        voice = config["voice"]
        with model_lock:
            samples, _ = kokoro.create(c, voice=voice, speed=config["speed"], lang="en-gb" if voice[0] == "b" else "en-us")
        with player.lock:
            if gen != player.generation: return
            player.q.put(samples.astype(np.float32)); player.q.put(None)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        p = self.path
        if p == "/speak" and body.strip():
            player.clear()
            threading.Thread(target=synth, args=(body, player.generation), daemon=True).start()
        elif p == "/stop": player.clear()
        elif p == "/pause": player.paused = True
        elif p == "/resume": player.paused = False
        elif p == "/toggle-pause": player.paused = not player.paused
        elif p == "/skip": player.skip()
        elif p == "/config":
            q = {k: v[0] for k, v in parse_qs(body).items()}
            if q.get("voice") in VOICES: config["voice"] = q["voice"]
            if "speed" in q: config["speed"] = min(3.0, max(0.5, float(q["speed"])))
            if "model" in q: threading.Thread(target=switch_model, args=(q["model"],), daemon=True).start()
        self._reply("ok")

    def do_GET(self):
        if self.path == "/voices": self._reply("\n".join(VOICES))
        elif self.path == "/model": self._reply(config["model"])
        else: self._reply(player.status)

    def _reply(self, msg: str):
        self.send_response(200); self.end_headers(); self.wfile.write(msg.encode())

    def log_message(self, *_): pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
