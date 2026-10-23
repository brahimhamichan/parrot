"""Adds Parrot commands to Tinycast's Custom Commands, keeping any existing non-Parrot commands. Restarts Tinycast."""
import json, subprocess, time, uuid

DOMAIN = "com.tinycast.app"
COMMANDS = [("Parrot: Read Selection", "speak"), ("Parrot: Pause / Resume", "pause"), ("Parrot: Stop", "stop"),
            ("Parrot: Skip Sentence", "skip"), ("Parrot: Faster", "faster"), ("Parrot: Slower", "slower")]


def read_existing():
    # `defaults export` gives a plist with customCommands as <data>.
    import plistlib
    out = subprocess.run(["defaults", "export", DOMAIN, "-"], capture_output=True).stdout
    data = plistlib.loads(out).get("customCommands") if out else None
    return json.loads(data) if data else []


existing = read_existing()
by_name = {c["name"]: c for c in existing}
kept = [c for c in existing if not c["command"].startswith("open -g parrot://")]
ours = [{"id": by_name.get(n, {}).get("id") or str(uuid.uuid4()).upper(), "name": n, "command": f"open -g parrot://{a}",
         "loadsShellEnvironment": False, "requiresConfirmation": False, "showsConfirmation": False} for n, a in COMMANDS]

subprocess.run(["osascript", "-e", 'tell application "Tinycast" to quit'], capture_output=True)
time.sleep(2)  # Tinycast rewrites its defaults on quit
subprocess.run(["defaults", "write", DOMAIN, "customCommands", "-data", json.dumps(kept + ours).encode().hex()], check=True)
subprocess.run(["defaults", "write", DOMAIN, "customCommandsEnabled", "-bool", "true"], check=True)
subprocess.run(["open", "-a", "Tinycast"])
