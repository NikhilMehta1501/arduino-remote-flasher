# Arduino Nano Clock

A custom clock built from scratch using an Arduino Nano, a Max7219 dot matrix display, and an RTC DS3231 real-time clock module, with a custom-designed PCB. This project is based on the [Arduino Matrix Clock](https://www.instructables.com/Arduino-Matrix-Clock-1/) Instructables post.

**Disclaimer:** This is an experimental project and may have flaws or bugs.

## Overview

It's a standalone desk clock that shows time (24-hour, 7-segment style with blinking colon), date, day of week, and temperature from the DS3231 on a 4-module Max7219 LED matrix. The firmware cycles through these views and can put the display to sleep at night. Everything's wired up on a custom PCB to keep things tidy between the Nano, display, and RTC. Had a lot of fun building this.

## Components

- **Arduino Nano** – Main microcontroller (ATmega328P)
- **Max7219 dot matrix display** – 4 modules in a row, FC16 hardware type; driven via SPI (CLK 13, DATA 11, CS 10)
- **RTC DS3231** – Real-time clock module (I2C); provides time, date, and temperature
- **Custom PCB** – Designed for this project to connect the Nano, display, and RTC

## PCB

Everything's on a custom PCB so the Nano, display, and RTC are wired up cleanly.

![Circuit diagram](circuit%20diagram.png)
![Component wiring and layout](component%20wireing%20and%20layout.png)

**Note:** The PCB design has a flaw, an incorrect path/trace that only showed up after soldering and testing. That was pretty disappointing. The Gerber file is here for reference, but be aware of this if you're building one.

- Gerber export: [pcb/Gerber_arduino_nano_clock_PCB_arduino_nano_clock_3_2025-10-06.zip](pcb/Gerber_arduino_nano_clock_PCB_arduino_nano_clock_3_2025-10-06.zip)  
- PCB design source files (e.g. KiCad) to be added.

## Firmware

The main sketch (`firmware/Matrix_Clock`) reads time, date, and temperature from the DS3231 over I2C and drives the 4-module Max7219 display via SPI. It rotates through: optional special-date messages, temperature in Celsius, day of week, full date, and the main clock (7-segment digits with blinking colon). The display can shut down between midnight and 6:00. There's a custom 7-segment font in `Font_Data.h`.

**Libraries:** MD_Parola, MD_MAX72xx, DS3231, Wire, SPI (all available via Arduino Library Manager).

The optional `firmware/SetTimeUseMe` sketch sets the RTC from the compile-time date/time (uses Time and DS1307RTC). The main clock uses a **DS3231**; if you're DS3231-only, you might need a small set-time sketch or another way to set the clock initially.

## How to Build

1. **Libraries** (Arduino IDE: Sketch → Include Library → Manage Libraries):  
   - Matrix_Clock: **MD_Parola**, **MD_MAX72XX**, **DS3231**  
   - SetTimeUseMe (optional): **Time**, **DS1307RTC**

2. **Board:** Tools → Board → Arduino AVR Boards → **Arduino Nano**. For typical clones, use **Processor: ATmega328P (Old Bootloader)**.

3. **Upload:** Open `firmware/Matrix_Clock/Matrix_Clock.ino` in the Arduino IDE and upload. For the full workflow (SetTimeUseMe then Matrix_Clock), run from the repo root:  
   `./flash_arduino.sh`  
   (Needs `arduino-cli` and, for serial monitoring, `screen`. See the script for details.)

## What I Learned

Overall this was a lot of fun. A few takeaways:

- Embedded C on AVR: structuring a sketch for real-time display updates and multiple display modes.
- I2C and SPI: interfacing the DS3231 (I2C) and Max7219 display (SPI), and using library abstractions (MD_Parola, DS3231).
- PCB design and Gerber export: taking a design to manufacture; importance of design review before ordering.
- Real-time clock and dot-matrix display programming: RTC registers, date/time formatting, and scrolling/text effects on the matrix.
- Soldering: through-the-hole assembly and debugging after discovering the PCB trace error. That part was a bit of a pain, but learned a lot from it.
