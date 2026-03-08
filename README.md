# Arduino Remote Flasher

Lightweight web-based Arduino flasher for Raspberry Pi (or any Linux host). Flash and monitor an Arduino over the network from your phone or laptop—no SSH required.

**Repository:** [github.com/NikhilMehta1501/arduino-remote-flasher](https://github.com/NikhilMehta1501/arduino-remote-flasher)

## Features

- **Flash built-in sketches** or **upload your own** (.ino or .zip) and flash to the connected board
- **Serial monitor** in the browser (live stream, no reset on connect)
- **Reset** Arduino to bootloader from the UI
- **Docker-based** – one image, no host install of arduino-cli beyond Docker
- **No authentication** – intended for trusted networks only

## Prerequisites

- Docker on the host (e.g. Raspberry Pi)
- Arduino connected via USB (typically `/dev/ttyUSB0` or `/dev/ttyACM0` on Linux)
- Optional: set host timezone (e.g. `TZ=Asia/Kolkata`) so compile-time RTC sketches get the right time

## Quick start

**Build** (from repo root):

```bash
docker build -t arduino-remote-flasher ./webapp
```

**Run:**

```bash
docker run -d --name arduino-webapp -p 5000:5000 --device /dev/ttyUSB0 \
  -v "$(pwd)":/workspace -v arduino15:/app/.arduino15 \
  -e HOME=/app \
  arduino-remote-flasher
```

Use `--device /dev/ttyACM0` if your board appears as ttyACM0. Open `http://<host-ip>:5000` in a browser.

**Restart script:** `./restart_webapp.sh` stops, rebuilds, and runs the container (edit the script to change port or device).

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ARDUINO_PORT` | auto-detect | Serial port (e.g. `/dev/ttyUSB0`) |
| `ARDUINO_FQBN` | `arduino:avr:nano:cpu=atmega328old` | Board FQBN for compile/upload |
| `TZ` | (none) | Timezone for compile time (e.g. `Asia/Kolkata`) |
| `SERIAL_BAUD` | `9600` | Baud rate for serial monitor |
| `WORKSPACE` | `/workspace` | Path to mounted project (used for built-in sketches and scripts) |

## Included example: Arduino Nano matrix clock

This repo includes firmware and PCB for a **desk clock** (Arduino Nano + Max7219 matrix + DS3231 RTC) as an example. The web app can flash the built-in sketches **SetTimeUseMe** (set RTC from compile time) and **Matrix_Clock** (main clock), or you can flash your own sketches.

- **Firmware:** `firmware/Matrix_Clock`, `firmware/SetTimeUseMe` – see [firmware/README.md](firmware/README.md)
- **Scripts:** `flash_arduino.sh` (full flash workflow), `reset_arduino.sh` (bootloader reset)
- **PCB:** `pcb/` – custom board for the clock (see [PCB](#pcb) below); Gerber included, note known trace flaw

Based on the [Arduino Matrix Clock](https://www.instructables.com/Arduino-Matrix-Clock-1/) Instructables post.

### PCB

Custom PCB for the Nano + display + RTC. Gerber: [pcb/Gerber_arduino_nano_clock_PCB_arduino_nano_clock_3_2025-10-06.zip](pcb/Gerber_arduino_nano_clock_PCB_arduino_nano_clock_3_2025-10-06.zip). There is a known trace flaw; check before building.

![Circuit diagram](circuit%20diagram.png)
![Component wiring and layout](component%20wireing%20and%20layout.png)

## Documentation

- [Architecture and file reference](docs/README.md) – how the web app and scripts work, per-file overview.

## License

This project is open source under the [MIT License](LICENSE).
