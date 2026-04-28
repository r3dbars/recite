# Contributing

Thanks for taking a look at Recite.

## Development Setup

```bash
git submodule update --init --recursive
brew install espeak-ng
swift build
./scripts/build-and-run.sh
```

The script builds a local `Recite.app`, signs it ad-hoc by default, and launches it.

## What To Keep In Mind

- Recite is local-first. Selected text, clipboard text, and generated audio should stay on the Mac.
- Avoid logging user text. Log counts, states, and errors instead.
- Keep UI copy short and plain.
- Keep changes small when possible.

## Pull Requests

Before opening a PR, run:

```bash
swift build
```

There are no automated tests yet, so please include a short manual test note when a change affects text capture, queue behavior, model loading, or playback.
