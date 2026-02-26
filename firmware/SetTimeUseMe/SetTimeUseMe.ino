#include <Wire.h>

#include <TimeLib.h>
#include <DS1307RTC.h>

const char *monthName[12] = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

tmElements_t tm;
tmElements_t tm_new;

void setup() {
  bool parse = false;
  bool config = false;

  Serial.begin(9600);
  while (!Serial)
    ;  // wait for Serial Monitor
  delay(200);

  if (getDate(__DATE__) && getTime(__TIME__)) {
    parse = true;

    // Calculate the day of week (0 = Monday, ..., 6 = Sunday)
    int year = tmYearToCalendar(tm.Year);
    int wday = calculateWeekday(tm.Day, tm.Month, year);
    tm.Wday = wday + 1;  // TimeLib uses 1 = Sunday to 7 = Saturday

    if (RTC.write(tm)) {
      config = true;
    }
  }

  if (parse && config) {
    Serial.println("DS1307 configured Time=");
    Serial.print(__TIME__);
    Serial.print(", Date=");
    Serial.print(__DATE__);
    Serial.print(", DAY=");
    Serial.print(tm.Wday);
    Serial.println("  ");
  } else if (parse) {
    Serial.println("DS1307 Communication Error :-{");
    Serial.println("Please check your circuitry");
  } else {
    Serial.print("Could not parse info from the compiler, Time=\"");
    Serial.print(__TIME__);
    Serial.print("\", Date=\"");
    Serial.print(__DATE__);
    Serial.println("\"");
  }
}

void loop() {
  RTC.read(tm_new);
  Serial.print("DS1307 configured ");
  Serial.print(" | WDay = ");
  Serial.print(tm_new.Wday);
  Serial.print(" | Day = ");
  Serial.print(tm_new.Day);
  Serial.print(" | Month = ");
  Serial.print(tm_new.Month);
  Serial.print(" | Year = ");
  Serial.print(tm_new.Year);
  Serial.print(" | Time = ");
  Serial.print(tm_new.Hour);
  Serial.print(":");
  Serial.print(tm_new.Minute);
  Serial.print(":");
  Serial.print(tm_new.Second);
  // Serial.print(__TIME__);
  // Serial.print(", Date=");
  // Serial.print(__DATE__);
  // Serial.print(", DAY=");
  // Serial.print(tm.Wday);
  Serial.println(" ");
}

// Helper to get time from __TIME__
bool getTime(const char *str) {
  int Hour, Min, Sec;
  if (sscanf(str, "%d:%d:%d", &Hour, &Min, &Sec) != 3) return false;
  tm.Hour = Hour;
  tm.Minute = (Min + 5) % 60;
  tm.Second = Sec;
  return true;
}

// Helper to get date from __DATE__
bool getDate(const char *str) {
  char Month[12];
  int Day, Year;
  uint8_t monthIndex;

  if (sscanf(str, "%s %d %d", Month, &Day, &Year) != 3) return false;
  for (monthIndex = 0; monthIndex < 12; monthIndex++) {
    if (strcmp(Month, monthName[monthIndex]) == 0) break;
  }
  if (monthIndex >= 12) return false;
  tm.Day = Day;
  tm.Month = monthIndex + 1;
  tm.Year = CalendarYrToTm(Year);
  return true;
}

// Zeller's Congruence to calculate weekday
int calculateWeekday(int d, int m, int y) {
  if (m < 3) {
    m += 12;
    y -= 1;
  }
  int K = y % 100;
  int J = y / 100;
  int f = d + 13 * (m + 1) / 5 + K + K / 4 + J / 4 + 5 * J;
  int weekday = ((f + 5) % 7);  // Monday = 0, ..., Sunday = 6
  return weekday;
}
