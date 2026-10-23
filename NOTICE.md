# Third-party notices

Parrot's own code is MIT-licensed (see [LICENSE](LICENSE)). It bundles or installs the following:

| Component | Use | License |
|---|---|---|
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) model weights and voices (`models/`) | Bundled in the repo and app | Apache-2.0 |
| [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) | Installed by `install.sh`; source of the int8 ONNX export in `models/` | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | Installed by `install.sh` | MIT |
| [sounddevice](https://github.com/spatialaudio/python-sounddevice) / PortAudio | Installed by `install.sh` | MIT |
| [phonemizer](https://github.com/bootphon/phonemizer) | Installed by `install.sh` | GPL-3.0 |
| [eSpeak NG](https://github.com/espeak-ng/espeak-ng) via espeakng-loader | Installed by `install.sh` | GPL-3.0 |
| [NumPy](https://numpy.org) | Installed by `install.sh` | BSD-3-Clause |

The GPL-licensed components are installed separately from PyPI into the user's own Python environment; they aren't included in this repository.
