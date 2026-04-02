# Contributing to OpenEarable Flutter

Thank you for contributing to `open_earable_flutter`.

This package is published publicly and supports multiple wearable integrations, so contribution quality matters. Keep changes small, reviewable, and well documented.

## Core Expectations

- Use [Conventional Commits](https://www.conventionalcommits.org/) for every commit.
- Rebase your branch on top of the target branch. Do not merge the target branch into your feature branch.
- Run `dart format .` and ensure `flutter analyze` passes before pushing.
- Document classes, public APIs, and non-obvious functions.
- Update package documentation when public behavior, setup, or capabilities change.
- Keep pull requests focused. Do not mix refactors, formatting-only edits, and feature work unless they are directly related.
- Never commit secrets, local environment files, build artifacts, or unrelated generated output.

## Development Setup

The repository uses the Flutter version pinned in [`.flutter_version`](https://github.com/OpenEarable/open_earable_flutter/blob/main/.flutter_version).

1. Install the required Flutter SDK version.
2. Fetch dependencies:

```bash
flutter pub get
```

3. If you work on the example app as well, fetch its dependencies too:

```bash
cd example
flutter pub get
```

## Branching Workflow

1. Create a feature branch from the current target branch.
2. Make focused commits with conventional commit messages.
3. Rebase onto the latest target branch before opening or updating your pull request.
4. Resolve conflicts locally and rerun the verification steps.

Example commit messages:

```text
feat(sensor): add open ring calibration support
fix(fota): avoid duplicate update state emission
docs(readme): clarify bluetooth permission setup
refactor(device): simplify wearable factory registration
test(pairing): cover stereo reconnection flow
```

## Code Quality Standards

### Architecture

- Prefer small, composable abstractions over large multi-purpose classes.
- Keep responsibilities clearly separated across managers, models, capabilities, and utilities.
- Avoid introducing tight coupling between device-specific implementations and shared infrastructure.
- Preserve backward compatibility for public APIs unless the change is intentional and clearly documented.

### Documentation

- Add Dart documentation comments for every public class, enum, extension, mixin, typedef, constructor, method, and top-level function you introduce or materially change.
- Add documentation for internal functions and classes when the behavior is not immediately obvious.
- Explain why something exists or how it should be used, not just what the code literally does.
- Update the relevant files in [`doc/`](https://github.com/OpenEarable/open_earable_flutter/tree/main/doc) and [README.md](https://github.com/OpenEarable/open_earable_flutter/blob/main/README.md) when contributors change user-facing functionality.

### Style

- Follow the repository lint rules in [analysis_options.yaml](https://github.com/OpenEarable/open_earable_flutter/blob/main/analysis_options.yaml).
- Use trailing commas where appropriate and keep return types explicit.
- Prefer clear naming over clever shorthand.
- Avoid unrelated drive-by changes in files touched for another purpose.

## Verification Before Pushing

Run these commands from the repository root:

```bash
dart format .
flutter analyze
flutter test
```

Also validate the example app when your change can affect it:

```bash
cd example
flutter test
flutter build web --dart-define=BUILD_COMMIT=$(git rev-parse --short HEAD) --dart-define=BUILD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

Notes:

- CI currently enforces `flutter analyze` and builds the example web app for pull requests.
- If `flutter test` does not cover your change sufficiently, add targeted tests instead of relying on manual verification only.
- If a command is not applicable to your change, mention what you ran and why in the pull request description.

## Pull Requests

Before opening a pull request, make sure:

- the branch is rebased on the latest target branch;
- commits use conventional commit messages;
- formatting, analysis, tests, and relevant example validation pass;
- documentation is updated for API or behavior changes;
- the pull request description explains the problem, the solution, and any migration or validation notes.

If your change affects public APIs, protocol behavior, permissions, supported devices, or firmware update flows, call that out explicitly in the pull request.

## Commit and History Hygiene

- Prefer multiple clean commits over one noisy commit history during development, then squash if the maintainers request it.
- Do not rewrite shared branch history after others have based work on it unless you have coordinated the change.
- Do not use merge commits to sync your branch with the target branch. Use `git fetch` followed by `git rebase`.

## What To Update When You Change Behavior

Depending on the change, update one or more of the following:

- [README.md](https://github.com/OpenEarable/open_earable_flutter/blob/main/README.md)
- files in [`doc/`](https://github.com/OpenEarable/open_earable_flutter/tree/main/doc)
- [CHANGELOG.md](https://github.com/OpenEarable/open_earable_flutter/blob/main/CHANGELOG.md)
- example code in [`example/lib/`](https://github.com/OpenEarable/open_earable_flutter/tree/main/example/lib)
- tests in [`example/test/`](https://github.com/OpenEarable/open_earable_flutter/tree/main/example/test)

High-quality contributions are easier to review, safer to release, and faster to maintain. Optimize for clarity, correctness, and a clean project history.
