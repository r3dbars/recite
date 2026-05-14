# Third-Party Notices

Recite source code is MIT licensed.

Release app bundles also include or download the third-party components below.
Those components keep their own licenses. The build script copies upstream
license files into `Recite.app/Contents/Resources/ThirdParty/` when it bundles
runtime helpers.

## eSpeak NG

- Project: https://github.com/espeak-ng/espeak-ng
- Version bundled in the current release build: 1.52.0
- Purpose: pronunciation and phoneme generation before Kokoro creates audio
- License: GPL-3.0-or-later
- Source archive: https://github.com/espeak-ng/espeak-ng/archive/refs/tags/1.52.0.tar.gz

## pcaudiolib

- Project: https://github.com/espeak-ng/pcaudiolib
- Version bundled in the current release build: 1.3
- Purpose: runtime library used by the bundled `espeak-ng` command-line tool
- License: GPL-3.0-or-later
- Source archive: https://github.com/espeak-ng/pcaudiolib/releases/download/1.3/pcaudiolib-1.3.tar.gz

## Kokoro 82M

- Model available in Recite: https://huggingface.co/mlx-community/Kokoro-82M-bf16
- Original model: https://huggingface.co/hexgrad/Kokoro-82M
- Purpose: local neural text-to-speech voice generation
- License: Apache-2.0
- Note: the model is downloaded when selected and is not bundled in the app DMG.

## Qwen3-TTS

- Model available in Recite: https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit
- Original model family: https://github.com/QwenLM/Qwen3-TTS
- Purpose: local neural text-to-speech voice generation
- License: Apache-2.0
- Note: the model is downloaded when selected and is not bundled in the app DMG.

## Chatterbox Turbo

- Model available in Recite: https://huggingface.co/mlx-community/chatterbox-turbo-4bit
- Original project: https://github.com/resemble-ai/chatterbox
- Purpose: local neural text-to-speech voice generation
- Model license: Apache-2.0
- Original project license: MIT
- Note: the model is downloaded when selected and is not bundled in the app DMG.

## mlx-audio-swift

- Project: https://github.com/Blaizzy/mlx-audio-swift
- Purpose: Swift text-to-speech runtime on Apple MLX
- License: MIT
