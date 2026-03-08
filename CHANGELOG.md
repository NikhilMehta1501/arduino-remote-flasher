# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.0.0] - 2025-02-27

### Added

- Web app: flash built-in sketches (SetTimeUseMe, Matrix_Clock) or upload .ino/.zip and flash
- Serial monitor in browser (SSE stream; pyserial with no-reset when available)
- Reset Arduino to bootloader from UI
- Docker image with arduino-cli, Flask, pyserial
- Bootloader reset before upload; retry with new bootloader if old fails
- Copy log button; output area with max height
- Included example: Arduino Nano matrix clock firmware and PCB
- Scripts: flash_arduino.sh, reset_arduino.sh, restart_webapp.sh
- Docs: architecture overview and file reference (docs/README.md)
- CONTRIBUTING.md, CODE_OF_CONDUCT.md, issue/PR templates, LICENSE (MIT)
