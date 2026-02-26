# Firmware

This folder contains the Arduino sketches for the Nano clock project.

- **Matrix_Clock** – Main clock sketch. Reads time, date, and temperature from the DS3231 and drives the Max7219 dot matrix display. Open `Matrix_Clock/Matrix_Clock.ino` in the Arduino IDE.
- **SetTimeUseMe** – Optional utility to set the RTC from compile-time date/time. Uses DS1307RTC; the main clock uses DS3231. Open `SetTimeUseMe/SetTimeUseMe.ino` if you use this sketch.

**Board:** Arduino Nano, Processor: ATmega328P (Old Bootloader) for typical clones.

**Library dependencies:**

| Sketch        | Libraries                          |
|---------------|------------------------------------|
| Matrix_Clock  | MD_Parola, MD_MAX72XX, DS3231      |
| SetTimeUseMe  | Time, DS1307RTC                    |

For full build and upload steps, see the [root README](../README.md).
