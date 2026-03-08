# Contributing

Contributions are welcome. This document explains how to run the project locally and how to submit changes.

## Running locally

**Prerequisites:** Docker, Arduino connected (e.g. `/dev/ttyUSB0`).

1. Clone the repo and `cd` into it.
2. Build and run the web app:
   ```bash
   docker build -t arduino-remote-flasher ./webapp
   docker run -d --name arduino-webapp -p 5000:5000 --device /dev/ttyUSB0 \
     -v "$(pwd)":/workspace -v arduino15:/app/.arduino15 \
     -e HOME=/app \
     arduino-remote-flasher
   ```
   Or use `./restart_webapp.sh` (edit it for your port/device).
3. Open `http://localhost:5000` (or your host IP).

To test without an Arduino, you can run the container without `--device`; flash and serial will fail, but you can check the UI and error messages.

## Code style

- **Python (webapp):** Follow PEP 8; keep functions small; no unnecessary dependencies.
- **Shell:** Use `set -e` where appropriate; prefer portable constructs.
- **HTML/JS:** Vanilla JS; no frameworks. Keep the single page simple and accessible (focus states, contrast).

## Submitting changes

1. Open an issue to discuss larger changes, or just open a PR for small fixes.
2. Fork the repo, create a branch, make your changes.
3. Ensure the web app still builds and runs (`docker build -t arduino-remote-flasher ./webapp`).
4. Open a pull request against `main`. Describe what you changed and why.
5. A maintainer will review and merge or request updates.
