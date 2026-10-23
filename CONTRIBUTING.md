# Contributing to Parrot

Thanks for helping! Parrot is intentionally small, so focused changes are easiest to review.

## Development setup

```sh
./install.sh      # once: Python environment + app
./build.sh        # rebuild after changing the Swift files, speakd.py or assets/icon-source.png
```

`build.sh` signs the app ad hoc with a designated requirement pinned to the bundle ID, so rebuilds keep the Accessibility permission.

To work on the daemon alone:

```sh
"$HOME/Library/Application Support/Parrot/venv/bin/python" speakd.py
curl -X POST --data "Hello from Parrot." 127.0.0.1:47811/speak
```

Quit Parrot first so the port is free.

## Pull requests

- Open an issue first for larger changes.
- Keep the app dependency-free beyond the Swift standard frameworks, and keep the daemon to `requirements.txt`.
- Describe how you tested it (macOS version, apps you read from).
- Add a line to [CHANGELOG.md](CHANGELOG.md) under **Unreleased**.
