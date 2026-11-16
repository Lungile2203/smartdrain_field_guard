/*
  Smart Drainage Guard - sensor node
  ----------------------------------
  Measures the water level in a drain with an ultrasonic sensor (HC-SR04 /
  JSN-SR04T), warns people on site with LEDs and a buzzer, and publishes the
  level to the MQTT broker so the workers' dashboard updates live.

  Local alarm (works even with no Wi-Fi):
    below 70%  green LED
    70% - 85%  yellow LED (warning)
    85% +      red LED + buzzer (overflow risk)

  MQTT (TLS, port 8883):
    sdg/drain/<DRAIN_ID>/level   JSON: id, name, max_cm, level_cm, pct, rssi
    sdg/drain/<DRAIN_ID>/status  "online" / "offline" (retained, last will)

  Boards: ESP32 (default) or ESP8266.
  Libraries (Arduino Library Manager): PubSubClient by Nick O'Leary

  BEFORE UPLOADING: fill in the four values marked FILL IN.
  NEVER commit real passwords to GitHub - keep the placeholders in the repo.
*/

#if defined(ESP32)
  #include <WiFi.h>
#elif defined(ESP8266)
  #include <ESP8266WiFi.h>
#endif
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

// ---------- FILL IN ----------
const char* WIFI_SSID     = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
const char* MQTT_USER     = "sdg-node-01";
const char* MQTT_PASSWORD = "YOUR_NODE_PASSWORD";

// ---------- broker ----------
const char* MQTT_HOST = "your-broker-host.emqxsl.com";   // EMQX -> Overview -> Address
const int   MQTT_PORT = 8883;

// ---------- this drain ----------
const char* DRAIN_ID   = "D01";
const char* DRAIN_NAME = "Prototype drain";
const float SENSOR_HEIGHT_CM = 30.0;   // sensor to the bottom of the drain (empty)
const float DRAIN_DEPTH_CM   = 25.0;   // water depth that counts as 100% (full)

// ---------- thresholds ----------
const float WARN_PCT = 70.0;
const float CRIT_PCT = 85.0;

// ---------- pins (ESP32 defaults; change for your wiring) ----------
#if defined(ESP32)
  const int PIN_TRIG = 5,  PIN_ECHO = 18;
  const int PIN_GREEN = 25, PIN_YELLOW = 26, PIN_RED = 27, PIN_BUZZER = 14;
#else
  const int PIN_TRIG = D5, PIN_ECHO = D6;
  const int PIN_GREEN = D1, PIN_YELLOW = D2, PIN_RED = D7, PIN_BUZZER = D8;
#endif

// ---------- timing ----------
const unsigned long READ_EVERY_MS    = 2000;   // read the sensor
const unsigned long PUBLISH_EVERY_MS = 10000;  // send to the dashboard
const unsigned long RETRY_EVERY_MS   = 5000;   // Wi-Fi / MQTT reconnect attempts

WiFiClientSecure net;
PubSubClient mqtt(net);

char topicLevel[48], topicStatus[48];
float levelCm = 0, pct = 0;
unsigned long lastRead = 0, lastPublish = 0, lastRetry = 0;

// Distance in cm from the sensor to the water (median of 5 readings), or -1
float readDistanceCm() {
  float r[5];
  int n = 0;
  for (int i = 0; i < 5; i++) {
    digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
    digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
    digitalWrite(PIN_TRIG, LOW);
    unsigned long us = pulseIn(PIN_ECHO, HIGH, 30000);   // 30 ms timeout
    if (us > 0) r[n++] = us / 58.0;
    delay(30);
  }
  if (n == 0) return -1;
  for (int i = 1; i < n; i++)            // sort, then take the middle value
    for (int j = i; j > 0 && r[j] < r[j - 1]; j--) { float t = r[j]; r[j] = r[j - 1]; r[j - 1] = t; }
  return r[n / 2];
}

void setAlarm(float p) {
  bool crit = p >= CRIT_PCT, warn = p >= WARN_PCT && !crit;
  digitalWrite(PIN_GREEN,  !warn && !crit);
  digitalWrite(PIN_YELLOW, warn);
  digitalWrite(PIN_RED,    crit);
  // Beep on/off every half second while critical
  digitalWrite(PIN_BUZZER, crit && (millis() / 500) % 2);
}

void startWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);   // connects in the background
}

// Non-blocking: one attempt per call, so the local alarm never stops
void keepConnected() {
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastRetry > RETRY_EVERY_MS * 4) { lastRetry = millis(); WiFi.disconnect(); startWifi(); }
    return;
  }
  if (mqtt.connected() || millis() - lastRetry < RETRY_EVERY_MS) return;
  lastRetry = millis();

  char clientId[32];
  snprintf(clientId, sizeof(clientId), "sdg-node-%s", DRAIN_ID);
  // Last will: the broker marks this drain offline if the node disappears
  if (mqtt.connect(clientId, MQTT_USER, MQTT_PASSWORD, topicStatus, 1, true, "offline")) {
    mqtt.publish(topicStatus, "online", true);
    Serial.println("MQTT connected");
  } else {
    Serial.printf("MQTT failed, state %d\n", mqtt.state());
  }
}

void publishLevel() {
  if (!mqtt.connected()) return;
  char json[200];
  snprintf(json, sizeof(json),
           "{\"id\":\"%s\",\"name\":\"%s\",\"max_cm\":%.1f,\"level_cm\":%.1f,\"pct\":%.1f,\"rssi\":%d}",
           DRAIN_ID, DRAIN_NAME, DRAIN_DEPTH_CM, levelCm, pct, (int)WiFi.RSSI());
  mqtt.publish(topicLevel, json);
  Serial.println(json);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_TRIG, OUTPUT);  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_GREEN, OUTPUT); pinMode(PIN_YELLOW, OUTPUT);
  pinMode(PIN_RED, OUTPUT);   pinMode(PIN_BUZZER, OUTPUT);

  snprintf(topicLevel,  sizeof(topicLevel),  "sdg/drain/%s/level",  DRAIN_ID);
  snprintf(topicStatus, sizeof(topicStatus), "sdg/drain/%s/status", DRAIN_ID);

  // Encrypted (TLS) connection. For the pilot, replace setInsecure() with the
  // broker's CA certificate (net.setCACert(...)) so the server is verified too.
  net.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);

  startWifi();
}

void loop() {
  keepConnected();
  mqtt.loop();

  if (millis() - lastRead >= READ_EVERY_MS) {
    lastRead = millis();
    float d = readDistanceCm();
    if (d > 0) {
      levelCm = constrain(SENSOR_HEIGHT_CM - d, 0, DRAIN_DEPTH_CM);
      pct = levelCm / DRAIN_DEPTH_CM * 100.0;
    }
  }
  setAlarm(pct);

  // Send straight away when it becomes critical, otherwise every 10 s
  if (millis() - lastPublish >= PUBLISH_EVERY_MS || (pct >= CRIT_PCT && millis() - lastPublish >= 2000)) {
    lastPublish = millis();
    publishLevel();
  }
}
