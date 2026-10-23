import json, uuid, subprocess, plistlib
cmds = [("Parrot: Read Selection","speak"),("Parrot: Pause / Resume","pause"),("Parrot: Stop","stop"),("Parrot: Skip Sentence","skip"),("Parrot: Faster","faster"),("Parrot: Slower","slower")]
data = [{"id":str(uuid.uuid4()).upper(),"name":n,"command":f"open -g parrot://{a}","loadsShellEnvironment":False,"requiresConfirmation":False,"showsConfirmation":False} for n,a in cmds]
blob = json.dumps(data).encode()
subprocess.run(["defaults","write","com.tinycast.app","customCommands","-data",blob.hex()],check=True)
subprocess.run(["defaults","write","com.tinycast.app","customCommandsEnabled","-bool","true"],check=True)
