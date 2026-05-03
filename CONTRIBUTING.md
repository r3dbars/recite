# Contributing

Thanks for taking a look at Recite.

## Local Setup

```bash
git submodule update --init --recursive
brew install espeak-ng
swift build
./scripts/build-and-run.sh
```

## Before A Pull Request

Run:

```bash
swift build
```

There are no automated tests yet. If your change touches text capture, queue behavior, model loading, or playback, include a short manual test note.

## Privacy Rules

- Keep selected text, clipboard text, generated audio, and reading history local.
- Do not add a network service for user text or generated audio.
- Do not log selected text, clipboard text, or text snippets.
- Counts, states, timings, and error names are fine.
- Preserve the user's clipboard when using the copy fallback.

## Code Style

- Keep UI copy short and plain.
- Prefer small changes that are easy to review.
- Keep setup scripts friendly for a fresh Mac.
- Use ad-hoc signing by default. Only use a real signing identity when `RECITE_CODESIGN_IDENTITY` is set.
