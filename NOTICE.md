# Third-party notices

Parrot's own code is MIT-licensed (see [LICENSE](LICENSE)). It bundles or installs the following:

| Component | Use | License |
|---|---|---|
| [uv](https://github.com/astral-sh/uv) | Bundled in the DMG installer to set up the Python environment | Apache-2.0 or MIT |
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) model weights and voices (`models/`) | Bundled in the repo and app | Apache-2.0 |
| [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) | Downloaded during voice engine setup; source of the int8 ONNX export in `models/` | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | Downloaded during voice engine setup | MIT |
| [sounddevice](https://github.com/spatialaudio/python-sounddevice) / PortAudio | Downloaded during voice engine setup | MIT |
| [phonemizer](https://github.com/bootphon/phonemizer) | Downloaded during voice engine setup | GPL-3.0 |
| [eSpeak NG](https://github.com/espeak-ng/espeak-ng) via espeakng-loader | Downloaded during voice engine setup | GPL-3.0 |
| [NumPy](https://numpy.org) | Downloaded during voice engine setup | BSD-3-Clause |

The GPL-licensed components are installed separately from PyPI into the user's own Python environment; they are downloaded from PyPI and stored in the local voice engine environment.
