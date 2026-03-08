#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>
#include "Font_Data.h"
//These are for the clock
#include <DS3231.h>
#include <Wire.h>

DS3231 Clock;

bool Century = false;
bool h12;
bool PM;
byte dd, mm, yyy;
uint16_t h, m, s;

#define MAX_DEVICES 4  // Set the number of devices
#define HARDWARE_TYPE MD_MAX72XX::FC16_HW
#define CLK_PIN 13
#define DATA_PIN 11
#define CS_PIN 10
#define SPEED_TIME 75  // speed of the transition
#define PAUSE_TIME 0
#define MAX_MESG 25

#define DEBUG true

MD_Parola P = MD_Parola(HARDWARE_TYPE, CS_PIN, MAX_DEVICES);

// Global variables
char szTime[9];  // mm:ss\0
char szMesg[MAX_MESG + 1] = "";

uint8_t degC[] = { 6, 3, 3, 56, 68, 68, 68 };  // Deg C
uint8_t degF[] = { 6, 3, 3, 124, 20, 20, 4 };  // Deg F

char* mon2str(uint8_t mon, char* psz, uint8_t len) {
  // Get a label from PROGMEM into a char array
  static const __FlashStringHelper* str[] = { F("Jan"), F("Feb"), F("Mar"), F("Apr"), F("May"), F("Jun"), F("Jul"), F("Aug"), F("Sep"), F("Oct"), F("Nov"), F("Dec") };
  strncpy_P(psz, (const char PROGMEM*)str[mon - 1], len);
  psz[len] = '\0';
  return (psz);
}

char* dow2str(uint8_t code, char* psz, uint8_t len) {
  static const __FlashStringHelper* str[] = {
    F("Monday"),
    F("Tuesday"),
    F("Wednesday"),
    F("Thursday"),
    F("Friday"),
    F("Saturday"),
    F("Sunday")
  };
  if (code >= 7) code = 0;  // Ensure valid index
  strncpy_P(psz, (const char PROGMEM*)str[code], len);
  psz[len] = '\0';
  return (psz);
}

// Time Setup: Code for reading clock time (+5 mins display offset)
void getTime(char* psz, bool f = true) {
  s = Clock.getSecond();
  m = Clock.getMinute();
  h = Clock.getHour(h12, PM);  // 24hr Format
  m += 5;
  if (m >= 60) { m -= 60; h++; }
  if (h >= 24) { h -= 24; }
  sprintf(psz, "%02d%c%02d", h, (f ? ':' : ' '), m);
  //12hr Format
  //uncomment if you want the clock to be in 12hr Format
  /*if (Clock.getHour(h12,PM)>=13 || Clock.getHour(h12,PM)==0)
  {
    h = Clock.getHour(h12,PM) - 12;
  }
  else
  {
    h = Clock.getHour(h12,PM);
  }*/
}

void getDate(char* psz) {
  // Date Setup: Code for reading clock date
  char szBuf[10];
  dd = Clock.getDate();
  mm = Clock.getMonth(Century);  //12
  yyy = Clock.getYear();
  sprintf(psz, "%d %s %04d", dd, mon2str(mm, szBuf, sizeof(szBuf) - 1), (yyy + 2000));
}

bool checkSpecialDate(byte day, byte month, char* messageBuffer, size_t bufferLen) {
  (void)day;
  (void)month;
  (void)messageBuffer;
  (void)bufferLen;
  return false;
}


void setup(void) {
  Serial.begin(9600);
  P.begin(2);
  P.setInvert(false);  //we don't want to invert anything so it is set to false
  Wire.begin();
  P.setZone(0, MAX_DEVICES - 4, MAX_DEVICES - 1);
  P.setZone(1, MAX_DEVICES - 4, MAX_DEVICES - 1);
  P.setIntensity(0);
  P.displayZoneText(1, szTime, PA_CENTER, SPEED_TIME, PAUSE_TIME, PA_PRINT, PA_NO_EFFECT);
  P.displayZoneText(0, szMesg, PA_CENTER, SPEED_TIME, 0, PA_PRINT, PA_NO_EFFECT);
  P.addChar('$', degC);
  P.addChar('&', degF);
  // P.addChar('~', batmanLogo);  // Adding Batman logo as custom character
  // P.setSpriteData(rocket, W_ROCKET, F_ROCKET, rocket, W_ROCKET, F_ROCKET);
}

void loop(void) {
  static uint32_t lastTime = 0;  // millis() memory
  static uint8_t display = 0;    // current display mode
  static bool flasher = false;   // seconds passing flasher

  P.displayAnimate();

  // For debugging the RTC, print all RTC data to serial monitor
  // if (DEBUG) {
    // if (millis() - lastTime >= 1000) {
    //   lastTime = millis();

    //   // Fetch and print time
    //   getTime(szTime);
    //   Serial.print("Time: ");
    //   Serial.println(szTime);

    //   // Fetch and print date
    //   getDate(szMesg);
    //   Serial.print("Date: ");
    //   Serial.println(szMesg);

    //   // Fetch and print day of the week
    //   char szDay[10];
    //   dow2str(Clock.getDoW() + 1, szDay, sizeof(szDay));
    //   Serial.print("Day of Week: ");
    //   Serial.println(szDay);

    //   // Fetch and print temperature
    //   float tempC = Clock.getTemperature();
    //   float tempF = (tempC * 1.8) + 32;
    //   Serial.print("Temperature: ");
    //   Serial.print(tempC);
    //   Serial.print(" °C, ");
    //   Serial.print(tempF);
    //   Serial.println(" °F");
    // }
  // }


  if (P.getZoneStatus(0)) {
    switch (display) {
      // Check for special date-based messages
      case 0:
        if (checkSpecialDate(Clock.getDate(), Clock.getMonth(Century), szMesg, MAX_MESG)) {
          P.setTextEffect(0, PA_SCROLL_LEFT, PA_SCROLL_LEFT);
          P.displayReset(0);
          if (DEBUG) { Serial.print(F("0:")); Serial.println(szMesg); }
          delay(100);  // small pause to prevent constant reset flicker
        } else {
          display++;
        }
        break;

      case 1:  // Temperature deg C
        P.setPause(0, 5000);
        //P.setTextEffect(0, PA_SCROLL_LEFT, PA_SCROLL_UP);
        P.setTextEffect(0, PA_MESH, PA_GROW_DOWN);
        display++;
        dtostrf(Clock.getTemperature(), 3, 1, szMesg);
        strcat(szMesg, "$");
        if (DEBUG) { Serial.print(F("1:")); Serial.println(szMesg); }
        break;

      case 2:  // Temperature deg F
        // P.setTextEffect(0, PA_SCROLL_UP, PA_SCROLL_LEFT);
        display++;
        // dtostrf((1.8 * Clock.getTemperature()) + 32, 3, 1, szMesg);
        // strcat(szMesg, "&");
        if (DEBUG) { Serial.println(F("2:skip")); }
        break;

      case 3:  // day of week
        P.setFont(0, nullptr);
        P.setTextEffect(0, PA_SCROLL_RIGHT, PA_SCROLL_RIGHT);
        display++;
        dow2str((Clock.getDoW() + 6) % 7, szMesg, MAX_MESG);  // Map Sunday (0) to 6, Monday (1) to 0, etc.
        if (DEBUG) { Serial.print(F("3:")); Serial.println(szMesg); }
        break;

      case 4:  // Calendar
        P.setTextEffect(0, PA_SCROLL_RIGHT, PA_SCROLL_RIGHT);
        display++;
        getDate(szMesg);
        if (DEBUG) { Serial.print(F("4:")); Serial.println(szMesg); }
        break;

      case 5:  // Clock
        P.setFont(0, numeric7Seg);
        P.setTextEffect(0, PA_PRINT, PA_NO_EFFECT);
        //Sleep Mode
        //Uncomment to enable Sleep Mode and adjust the hours to your needs
        P.displayShutdown(h == 00 || h < 6);  //Set display to shutdown
        P.setPause(0, 0);

        if (millis() - lastTime >= 1000) {
          lastTime = millis();
          getTime(szMesg, flasher);
          if (DEBUG) { Serial.print(F("5:")); Serial.println(szMesg); }
          flasher = !flasher;
        }
        if (m % 10 == 0) {
          display = 0;
          P.setTextEffect(0, PA_PRINT, PA_SCROLL_UP);
        }
        break;

      // default:  // Calendar
      //   P.setTextEffect(0, PA_SCROLL_RIGHT, PA_SCROLL_RIGHT);
      //   display = 0;
      //   getDate(szMesg);
      //   break;
    }
    P.displayReset(0);
  }

}  //END of code
