#include <WiFi.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <Adafruit_BMP085.h>

// ================= PINS =================
#define LED_PIN 2
#define POT_PIN 35

#define SDA_PIN 21
#define SCL_PIN 19

//================= Sattelite Modes =================
typedef enum {
    BOOT_MODE,
    NOMINAL_MODE,
    SAFE_MODE,
    EMERGENCY_MODE
} SatelliteMode;

volatile SatelliteMode currentMode = BOOT_MODE;
volatile bool autoModeEnabled = true;
volatile SatelliteMode forcedMode = NOMINAL_MODE;

//================ Mutex on Telemtry data =================
SemaphoreHandle_t telemetryMutex;
//================ Mutex on MQTT =================
SemaphoreHandle_t mqttMutex;

// ================= WIFI =================
const char* ssid = "MAXBOX5G_A82F";
const char* password = "dmc4dgx4i9uh";
/*const char* ssid = "Deku";
const char* password = "999999999";*/

// ================= MQTT =================
const char* mqtt_server = "9a49bca53d684a54b7315926c0d27f88.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;

const char* mqtt_user = "yasminedh";
const char* mqtt_pass = "pOOkie55";

// =====================================================

WiFiClientSecure espClient;
PubSubClient client(espClient);

Adafruit_BMP085 bmp;

// =====================================================
// Shared sensor variables
// =====================================================

float bmpTemp = 0.0;
int32_t pressure = 0;
float altitude = 0.0;
int potValue = 0;

// =====================================================

const char* modeToString(SatelliteMode mode)
{
    switch(mode)
    {
        case BOOT_MODE:
            return "BOOT";

        case NOMINAL_MODE:
            return "NOMINAL";

        case SAFE_MODE:
            return "SAFE";

        case EMERGENCY_MODE:
            return "EMERGENCY";

        default:
            return "UNKNOWN";
    }
}

// =====================================================
void sendAlert(const char* message)
{
    char payload[128];

    snprintf(payload, sizeof(payload),
             "{\"alert\":\"%s\",\"mode\":\"%s\"}",
             message,
             modeToString(currentMode));

    if (xSemaphoreTake(mqttMutex, portMAX_DELAY))
    {
        client.publish("cubesat/alert", payload);
        xSemaphoreGive(mqttMutex);
    }

    Serial.println("ALERT SENT:");
    Serial.println(payload);
}
//====================================================

void setup_wifi() {

  Serial.println("Connecting WiFi...");

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {

    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connected");
  Serial.println(WiFi.localIP());
  WiFi.setSleep(false);
}

// =====================================================

void reconnectMQTT() {

  while (!client.connected()) {

    Serial.println("Connecting MQTT...");

    if (client.connect("ESP32Client", mqtt_user, mqtt_pass)) {

      Serial.println("MQTT connected");
      
      if (xSemaphoreTake(mqttMutex, portMAX_DELAY)) {

        client.subscribe("esp/led");
        client.subscribe("cubesat/cmd");

        xSemaphoreGive(mqttMutex);  
      }

    } else {

      Serial.print("MQTT failed rc=");
      Serial.println(client.state());

      vTaskDelay(5000 / portTICK_PERIOD_MS);
    }
  }
}

// =====================================================

void callback(char* topic, byte* payload, unsigned int length)
{
    String message;

    for (int i = 0; i < length; i++)
    {
        message += (char)payload[i];
    }

    Serial.print("MQTT message on topic ");
    Serial.print(topic);
    Serial.print(" : ");
    Serial.println(message);

    // =====================================================
    // LED COMMANDS
    // =====================================================

    if (String(topic) == "esp/led")
    {
        if (message == "ON")
        {
            digitalWrite(LED_PIN, HIGH);
            Serial.println("LED ON");
        }

        else if (message == "OFF")
        {
            digitalWrite(LED_PIN, LOW);
            Serial.println("LED OFF");
        }
    }

    // =====================================================
    // SATELLITE COMMANDS
    // =====================================================

    else if (String(topic) == "cubesat/cmd")
    {
        // FORCE SAFE
        if (message == "{\"cmd\":\"safe\"}")
        {
            autoModeEnabled = false;
            currentMode = SAFE_MODE;

            Serial.println("===== COMMAND RECEIVED =====");
            Serial.println("SAFE MODE FORCED");
        }

        // FORCE NOMINAL
        else if (message == "{\"cmd\":\"nominal\"}")
        {
            autoModeEnabled = false;
            currentMode = NOMINAL_MODE;

            Serial.println("===== COMMAND RECEIVED =====");
            Serial.println("NOMINAL MODE FORCED");
        }

        // RETURN TO AUTO
        else if (message == "{\"cmd\":\"auto\"}")
        {
            autoModeEnabled = true;

            Serial.println("===== COMMAND RECEIVED =====");
            Serial.println("AUTO MODE ENABLED");
        }

        // REBOOT
        else if (message == "{\"cmd\":\"reboot\"}")
        {
            Serial.println("===== COMMAND RECEIVED =====");
            Serial.println("REBOOTING ESP32...");

            ESP.restart();
        }
    }
}
// =====================================================
// LED TASK
// =====================================================

void LEDTask(void * parameter)
{
    while(true)
    {
        switch(currentMode)
        {
            case BOOT_MODE:
                digitalWrite(LED_PIN, HIGH);
                vTaskDelay(200 / portTICK_PERIOD_MS);
                digitalWrite(LED_PIN, LOW);
                vTaskDelay(200 / portTICK_PERIOD_MS);
                break;

            case NOMINAL_MODE:
                digitalWrite(LED_PIN, HIGH);
                vTaskDelay(1000 / portTICK_PERIOD_MS);
                break;

            case SAFE_MODE:
                digitalWrite(LED_PIN, HIGH);
                vTaskDelay(500 / portTICK_PERIOD_MS);
                digitalWrite(LED_PIN, LOW);
                vTaskDelay(500 / portTICK_PERIOD_MS);
                break;

            case EMERGENCY_MODE:
                digitalWrite(LED_PIN, HIGH);
                vTaskDelay(100 / portTICK_PERIOD_MS);
                digitalWrite(LED_PIN, LOW);
                vTaskDelay(100 / portTICK_PERIOD_MS);
                break;
        }
    }
}
//===========================================
//========== Health Monioring Task ==========
//===========================================

void HealthMonitorTask(void * parameter)
{
    while(true)
    {
        int batteryPercent;
        float tempCopy;

        // =============================
        // READ TELEMETRY SAFELY
        // =============================

        xSemaphoreTake(telemetryMutex, portMAX_DELAY);

        batteryPercent = (potValue * 100) / 4095;
        tempCopy = bmpTemp;

        xSemaphoreGive(telemetryMutex);

        // =============================
        // AUTONOMOUS FDIR MODE
        // =============================

        if (autoModeEnabled)
        {
            SatelliteMode newMode;

            // CRITICAL
            if (batteryPercent < 20 || tempCopy > 60)
            {
                newMode = EMERGENCY_MODE;
            }

            // DEGRADED
            else if (batteryPercent < 50 || tempCopy > 45)
            {
                newMode = SAFE_MODE;
            }

            // HEALTHY
            else
            {
                newMode = NOMINAL_MODE;
            }

            // =============================
            // APPLY ONLY IF MODE CHANGED
            // =============================

            if (newMode != currentMode)
            {
                currentMode = newMode;

                Serial.println("===== AUTO MODE CHANGE =====");
                Serial.println(modeToString(currentMode));

                if (currentMode == SAFE_MODE)
                {
                    Serial.println("FDIR: SAFE MODE ACTIVATED");
                }

                if (currentMode == EMERGENCY_MODE)
                {
                    Serial.println("FDIR: EMERGENCY MODE ACTIVATED");
                }
            }
        }

        // =============================
        // FORCED MODE
        // =============================

        else
        {
            Serial.println("FORCED MODE ACTIVE");
            Serial.println(modeToString(currentMode));
        }

        vTaskDelay(1000 / portTICK_PERIOD_MS);
    }
}
// =====================================================
// SENSOR TASK
// =====================================================

void SensorTask(void * parameter) {

  while (true) {

    xSemaphoreTake(telemetryMutex, portMAX_DELAY);

    bmpTemp = bmp.readTemperature();

    pressure = bmp.readPressure();

    altitude = bmp.readAltitude();

    potValue = analogRead(POT_PIN);

    Serial.println("====== SENSOR TASK ======");

    Serial.print("Temperature: ");
    Serial.print(bmpTemp);
    Serial.println(" °C");

    Serial.print("Pressure: ");
    Serial.print(pressure);
    Serial.println(" Pa");

    Serial.print("Altitude: ");
    Serial.print(altitude);
    Serial.println(" m");

    Serial.print("Pot: ");
    Serial.print(potValue/4095.0*100, 1);
    Serial.println("%");

    Serial.println("=========================");

    xSemaphoreGive(telemetryMutex);

    vTaskDelay(2000 / portTICK_PERIOD_MS);
  }
}

// =====================================================
// MQTT PUBLISH TASK
// =====================================================

void MQTTTask(void * parameter)
{
    char hkPayload[256];

    while (true)
    {
        if (!client.connected())
        {
            reconnectMQTT();
        }

        // =============================
        // EMERGENCY MODE FIRST (CRITICAL)
        // =============================

        if (currentMode == EMERGENCY_MODE)
        {
            sendAlert("EMERGENCY MODE - HK DISABLED");
            vTaskDelay(5000 / portTICK_PERIOD_MS);
            continue;
        }

        // =============================
        // READ TELEMETRY SAFELY
        // =============================

        float tempCopy;
        int32_t pressureCopy;
        float altitudeCopy;
        int batteryPercent;

        xSemaphoreTake(telemetryMutex, portMAX_DELAY);

        tempCopy = bmpTemp;
        pressureCopy = pressure;
        altitudeCopy = altitude;

        batteryPercent = (potValue * 100) / 4095;

        xSemaphoreGive(telemetryMutex);

        // =============================
        // BUILD HK PACKET (ONLY IF NOT EMERGENCY)
        // =============================

        snprintf(
            hkPayload,
            sizeof(hkPayload),
            "{\"temp\":%.2f,"
            "\"pressure\":%ld,"
            "\"altitude\":%.2f,"
            "\"battery\":%d,"
            "\"mode\":\"%s\"}",
            tempCopy,
            pressureCopy,
            altitudeCopy,
            batteryPercent,
            modeToString(currentMode)
        );

        // =============================
        // SAFE MODE BEHAVIOR
        // =============================

        int delayTime = 3000; // NOMINAL default

        if (currentMode == SAFE_MODE)
        {
            // =============================
            // SAFE HEARTBEAT HK (reduced telemetry)
            // =============================

            snprintf(
                hkPayload,
                sizeof(hkPayload),
                "{\"mode\":\"SAFE\","
                "\"battery\":%d,"
                "\"temp\":%.2f,"
                "\"heartbeat\":true}",
                batteryPercent,
                tempCopy
            );

            if (xSemaphoreTake(mqttMutex, portMAX_DELAY))
            {
                client.publish("cubesat/hk", hkPayload);

                Serial.println("SAFE HK (heartbeat) published:");
                Serial.println(hkPayload);

                xSemaphoreGive(mqttMutex);
            }

            vTaskDelay(8000 / portTICK_PERIOD_MS);
            continue;
        }

        // =============================
        // MQTT PUBLISH (SAFE + NOMINAL ONLY)
        // =============================

        if (xSemaphoreTake(mqttMutex, portMAX_DELAY))
        {
            client.publish("cubesat/hk", hkPayload);

            Serial.println("HK packet published:");
            Serial.println(hkPayload);

            xSemaphoreGive(mqttMutex);
        }

        vTaskDelay(delayTime / portTICK_PERIOD_MS);
    }
}

// =====================================================
// MQTT LOOP TASK
// =====================================================

void MQTTLoopTask(void * parameter)
{
    while (true)
    {
        if (client.connected())
        {
            client.loop();
        }

        vTaskDelay(10 / portTICK_PERIOD_MS);
    }
}
// =====================================================
// BEACON TASK
// =====================================================

void BeaconTask(void * parameter)
{
    char beaconPayload[128];

    while(true)
    {
        int beaconDelay = 2000;

        // =========================
        // BUILD BEACON
        // =========================

        if (currentMode == EMERGENCY_MODE)
        {
            snprintf(
                beaconPayload,
                sizeof(beaconPayload),
                "{\"alive\":true,\"mode\":\"EMERGENCY\"}"
            );

        }

        else if (currentMode == SAFE_MODE)
        {
            snprintf(
                beaconPayload,
                sizeof(beaconPayload),
                "{\"alive\":true,\"mode\":\"SAFE\"}"
            );
        }

        else
        {
            snprintf(
                beaconPayload,
                sizeof(beaconPayload),
                "{\"alive\":true,\"mode\":\"NOMINAL\"}"
            );
        }

        // =========================
        // PUBLISH IMMEDIATELY
        // =========================

        if (xSemaphoreTake(mqttMutex, portMAX_DELAY))
        {
            client.publish("cubesat/beacon", beaconPayload);

            Serial.println("Beacon sent:");
            Serial.println(beaconPayload);

            xSemaphoreGive(mqttMutex);
        }

        // =========================
        // THEN WAIT
        // =========================

        vTaskDelay(beaconDelay / portTICK_PERIOD_MS);
    }
}
// =====================================================

void setup() {

  Serial.begin(115200);

  // LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // I2C
  Wire.begin(SDA_PIN, SCL_PIN);

  // BMP180
  if (!bmp.begin()) {

    Serial.println("BMP180 not detected!");

    while (1);
  }

  Serial.println("BMP180 detected");

  // creation of mutex 
  telemetryMutex = xSemaphoreCreateMutex();
  mqttMutex = xSemaphoreCreateMutex();

  // WiFi
  setup_wifi();

  // MQTT
  espClient.setInsecure();

  client.setServer(mqtt_server, mqtt_port);

  client.setCallback(callback);

  // =====================================================
  // CREATE TASKS
  // =====================================================

  // =====================================================
// SENSOR TASK
// =====================================================

xTaskCreatePinnedToCore(
    SensorTask,
    "Sensor Task",
    4096,
    NULL,
    2,
    NULL,
    1
);

// =====================================================
// MQTT PUBLISH TASK
// =====================================================

xTaskCreatePinnedToCore(
    MQTTTask,
    "MQTT Publish Task",
    8192,
    NULL,
    2,
    NULL,
    1
);

// =====================================================
// MQTT LOOP TASK
// =====================================================

xTaskCreatePinnedToCore(
    MQTTLoopTask,
    "MQTT Loop Task",
    6144,
    NULL,
    3,
    NULL,
    0
);

// =====================================================
// HEALTH MONITOR TASK
// =====================================================

xTaskCreatePinnedToCore(
    HealthMonitorTask,
    "Health Monitor Task",
    4096,
    NULL,
    4,
    NULL,
    1
);

// =====================================================
// BEACON TASK
// =====================================================

xTaskCreatePinnedToCore(
    BeaconTask,
    "Beacon Task",
    4096,
    NULL,
    1,
    NULL,
    1
);

// =====================================================
// LED TASK
// =====================================================

xTaskCreatePinnedToCore(
    LEDTask,
    "LED Task",
    2048,
    NULL,
    1,
    NULL,
    0
);
}

// =====================================================

void loop() {

  // Empty
}