# ORION CubeSat — Firmware ESP32

```
 ██████╗██╗   ██╗██████╗ ███████╗███████╗ █████╗ ████████╗
██╔════╝██║   ██║██╔══██╗██╔════╝██╔════╝██╔══██╗╚══██╔══╝
██║     ██║   ██║██████╔╝█████╗  ███████╗███████║   ██║
██║     ██║   ██║██╔══██╗██╔══╝  ╚════██║██╔══██║   ██║
╚██████╗╚██████╔╝██████╔╝███████╗███████║██║  ██║   ██║
 ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝
         ESP32  ·  BMP180  ·  FreeRTOS  ·  MQTT TLS
```

Firmware de simulation CubeSat sur ESP32 avec architecture FreeRTOS multi-tâches, capteur BMP180 (température / pression / altitude), potentiomètre simulant la batterie, et communication MQTT over TLS vers HiveMQ Cloud.

---

## Sommaire

1. [Matériel requis](#matériel-requis)
2. [Schéma de câblage](#schéma-de-câblage)
3. [Bibliothèques Arduino](#bibliothèques-arduino)
4. [Configuration](#configuration)
5. [Architecture FreeRTOS](#architecture-freertos)
6. [Machine à états — modes satellite](#machine-à-états--modes-satellite)
7. [FDIR — Fault Detection Isolation Recovery](#fdir--fault-detection-isolation-recovery)
8. [Topics MQTT](#topics-mqtt)
9. [Commandes reçues (cubesat/cmd)](#commandes-reçues-cubesatcmd)
10. [Format des payloads](#format-des-payloads)
11. [LED — codes visuels](#led--codes-visuels)
12. [Mutexes et sections critiques](#mutexes-et-sections-critiques)
13. [Flasher le firmware](#flasher-le-firmware)
14. [Dépannage](#dépannage)

---

## Matériel requis

| Composant | Référence | Rôle |
|---|---|---|
| Microcontrôleur | ESP32 (DevKit v1 ou équivalent) | Cœur du système |
| Capteur pression | BMP180 (Adafruit ou module GY-68) | Temp / Pression / Altitude |
| Potentiomètre | 10 kΩ | Simulation batterie |
| LED | 3mm ou 5mm, n'importe quelle couleur | Indicateur mode |
| Résistance | 220–330 Ω | Limitation courant LED |
| Câbles Dupont | — | Connexions breadboard |

---

## Schéma de câblage

### BMP180 → ESP32 (I2C)

```
BMP180          ESP32
──────          ──────────────────────
VCC     ────→   3.3V
GND     ────→   GND
SDA     ────→   GPIO 21   (SDA_PIN)
SCL     ────→   GPIO 19   (SCL_PIN)
```

> ⚠ Alimenter le BMP180 en **3.3V uniquement** — il n'est pas tolérant 5V.

### Potentiomètre → ESP32

```
Potentiomètre   ESP32
──────────────  ──────────────────────
Borne gauche    3.3V
Curseur (mid)   GPIO 35   (POT_PIN — ADC1_CH7, entrée analogique)
Borne droite    GND
```

> ⚠ GPIO 35 est **input only** sur l'ESP32 — parfait pour l'ADC.

### LED → ESP32

```
LED             ESP32
────            ──────────────────────
Anode (+)   ──[ 220Ω ]──   GPIO 2  (LED_PIN)
Cathode (−) ────────────   GND
```

### Vue d'ensemble

```
         ┌─────────────────────────────────┐
         │          ESP32 DevKit           │
         │                                 │
  3.3V ──┤ 3V3      GPIO 21 (SDA) ─────────┼── SDA ──┐
   GND ──┤ GND      GPIO 19 (SCL) ─────────┼── SCL ──┼── BMP180
         │          GPIO 35 (ADC) ─────────┼── Pot   │
         │          GPIO  2 (LED) ──[R]────┼── LED   │
         └─────────────────────────────────┘         │
                                           GND ──────┘
```

---

## Bibliothèques Arduino

Installer via **Sketch → Include Library → Manage Libraries** :

| Bibliothèque | Auteur | Version testée | Rôle |
|---|---|---|---|
| **Adafruit BMP085/BMP180** | Adafruit | 1.2.2+ | Driver BMP180 |
| **Adafruit Unified Sensor** | Adafruit | 1.1.9+ | Dépendance du BMP driver |
| **PubSubClient** | Nick O'Leary | 2.8.0+ | Client MQTT |
| **WiFiClientSecure** | Espressif | (bundlée ESP32 core) | TLS over WiFi |
| **Wire** | — | (bundlée Arduino core) | I2C |
| **ArduinoJson** | Benoit Blanchon | **6.x** (pas 7.x) | Parse JSON des commandes |

> Dans **Arduino IDE** : File → Preferences → Additional boards manager URLs → ajouter :
> `https://dl.espressif.com/dl/package_esp32_index.json`
> puis Tools → Board → Boards Manager → chercher **esp32** → installer **esp32 by Espressif Systems**

---

## Configuration

Modifier en haut du fichier `.ino` avant de flasher :

```cpp
// ── WiFi ────────────────────────────────────────────────
const char* ssid     = "NOM_DU_RESEAU";
const char* password = "MOT_DE_PASSE_WIFI";

// ── HiveMQ Cloud ────────────────────────────────────────
const char* mqtt_server = "VOTRE_CLUSTER.s1.eu.hivemq.cloud";
const int   mqtt_port   = 8883;                // TLS — ne pas changer
const char* mqtt_user   = "VOTRE_USERNAME";
const char* mqtt_pass   = "VOTRE_PASSWORD";
```

> Les credentials HiveMQ se trouvent dans la console HiveMQ Cloud → votre cluster → **Access Management**.

---

## Architecture FreeRTOS

Le firmware utilise **6 tâches FreeRTOS** s'exécutant en parallèle sur les 2 cœurs de l'ESP32 :

```
Cœur 0                          Cœur 1
──────────────────────────       ──────────────────────────────
MQTTLoopTask  (prio 3)          SensorTask      (prio 2)
LEDTask       (prio 1)          MQTTTask        (prio 2)
                                HealthMonitorTask (prio 4) ← FDIR
                                BeaconTask      (prio 1)
```

### Tableau des tâches

| Tâche | Cœur | Priorité | Stack | Période | Rôle |
|---|---|---|---|---|---|
| `SensorTask` | 1 | 2 | 4096 | 2 s | Lit BMP180 + potentiomètre |
| `MQTTTask` | 1 | 2 | 8192 | 3 s (nominal) / 8 s (safe) | Publie les paquets HK |
| `MQTTLoopTask` | 0 | 3 | 6144 | 10 ms | Maintient la connexion MQTT active |
| `HealthMonitorTask` | 1 | 4 | 4096 | 1 s | FDIR — transitions de modes |
| `BeaconTask` | 1 | 1 | 4096 | 2 s | Envoie le beacon alive |
| `LEDTask` | 0 | 1 | 2048 | variable | Clignotement selon le mode |

> **Pourquoi séparer MQTTLoopTask ?** `client.loop()` doit être appelé très fréquemment (≤ 10 ms) pour traiter les messages entrants (callback) et maintenir le keep-alive MQTT. Le séparer des publications évite que les délais de publication ne bloquent la réception.

---

## Machine à états — modes satellite

```
                    ┌──────────┐
                    │   BOOT   │  ← État initial au démarrage
                    └────┬─────┘
                         │ (WiFi + MQTT connectés)
                         ▼
              ┌──── NOMINAL MODE ◄──────────────────────────┐
              │    (batterie ≥50%, temp ≤45°C)              │
              │    HK toutes les 3s                         │
              │                                             │
              │  bat <50% ou temp >45°C                     │
              ▼                                             │
       ┌─────────────┐   auto=false / cmd "nominal"         │
       │  SAFE MODE  │──────────────────────────────────────┘
       │ HK réduit   │
       │ toutes 8s   │
       └──────┬──────┘
              │ bat <20% ou temp >60°C
              ▼
    ┌──────────────────┐
    │  EMERGENCY MODE  │  ← HK désactivé, alertes seulement
    │  (FDIR critique) │
    └──────────────────┘
```

### Transitions automatiques (FDIR actif — `autoModeEnabled = true`)

| Condition | Mode déclenché |
|---|---|
| Batterie < 20% **OU** Temp > 60°C | `EMERGENCY_MODE` |
| Batterie < 50% **OU** Temp > 45°C | `SAFE_MODE` |
| Batterie ≥ 50% **ET** Temp ≤ 45°C | `NOMINAL_MODE` |

### Commandes ground (FDIR désactivé — `autoModeEnabled = false`)

Quand un `{"cmd":"safe"}` ou `{"cmd":"nominal"}` est reçu, `autoModeEnabled` passe à `false` et `HealthMonitorTask` ne modifie plus le mode automatiquement. L'envoi de `{"cmd":"auto"}` réactive le FDIR.

---

## FDIR — Fault Detection Isolation Recovery

**Fault Detection** : `HealthMonitorTask` lit batterie + température chaque seconde et compare aux seuils.

**Fault Isolation** : En `EMERGENCY_MODE`, `MQTTTask` arrête d'envoyer les paquets HK et envoie uniquement des alertes — réduction de la charge RF et consommation.

**Recovery** :
- Automatique : si les valeurs reviennent dans les limites normales et que `autoModeEnabled = true`, le mode remonte vers NOMINAL.
- Ground : la station au sol peut forcer le mode via `cubesat/cmd`.

---

## Topics MQTT

### Publiés par l'ESP32

| Topic | Période | Condition |
|---|---|---|
| `cubesat/hk` | 3 s | Mode NOMINAL uniquement (payload complet) |
| `cubesat/hk` | 8 s | Mode SAFE (payload réduit — heartbeat) |
| `cubesat/hk` | — | Mode EMERGENCY : **non publié** |
| `cubesat/beacon` | 2 s | Tous les modes |
| `cubesat/alert` | Sur événement | Changement de mode critique ou commande reçue |
| `cubesat/ack` | Sur réception | Après chaque commande `cubesat/cmd` |

### Souscriptions de l'ESP32

| Topic | Contenu |
|---|---|
| `cubesat/cmd` | Commandes JSON de la station sol |
| `esp/led` | `"ON"` / `"OFF"` (legacy) |

---

## Commandes reçues (cubesat/cmd)

| Payload JSON | Action |
|---|---|
| `{"cmd":"safe"}` | Force `SAFE_MODE`, désactive FDIR auto |
| `{"cmd":"nominal"}` | Force `NOMINAL_MODE`, désactive FDIR auto |
| `{"cmd":"auto"}` | Réactive le FDIR automatique |
| `{"cmd":"reboot"}` | `ESP.restart()` après 2 secondes |

Chaque commande envoie un ACK sur `cubesat/ack` :
```json
{"ack":"safe","success":true,"mode":"SAFE"}
```

---

## Format des payloads

### HK Nominal
```json
{
  "temp": 24.53,
  "pressure": 101325,
  "altitude": 12.34,
  "battery": 72,
  "mode": "NOMINAL"
}
```

### HK Safe (heartbeat)
```json
{
  "mode": "SAFE",
  "battery": 34,
  "temp": 47.21,
  "heartbeat": true
}
```

### Beacon
```json
{
  "alive": true,
  "mode": "NOMINAL",
  "battery": 72
}
```

### Alert
```json
{
  "alert": "FDIR: Safe mode — reduced operations",
  "mode": "SAFE",
  "battery": 34,
  "temp": 47.21
}
```

> **Note unités** : `pressure` est en **Pascals bruts** (BMP180 natif). Diviser par 100 pour obtenir des hPa. `altitude` est en mètres calculés par `bmp.readAltitude()` qui utilise la pression standard au niveau de la mer (1013.25 hPa) comme référence — c'est une altitude barométrique, pas GPS.

---

## LED — codes visuels

| Mode | Pattern LED | Fréquence |
|---|---|---|
| `BOOT_MODE` | Clignotement rapide | 200 ms ON / 200 ms OFF |
| `NOMINAL_MODE` | Allumée en permanence | — |
| `SAFE_MODE` | Clignotement lent | 500 ms ON / 500 ms OFF |
| `EMERGENCY_MODE` | Clignotement très rapide | 100 ms ON / 100 ms OFF |

---

## Mutexes et sections critiques

Le firmware utilise **2 mutexes FreeRTOS** pour protéger les ressources partagées :

### `telemetryMutex`
Protège les variables globales : `bmpTemp`, `pressure`, `altitude`, `potValue`.

- **Acquis par** : `SensorTask` (écriture) et `MQTTTask` + `HealthMonitorTask` (lecture)
- **Pattern** :
```cpp
xSemaphoreTake(telemetryMutex, portMAX_DELAY);
// accès aux variables partagées
xSemaphoreGive(telemetryMutex);
```

### `mqttMutex`
Protège l'accès au client PubSubClient (non thread-safe).

- **Acquis par** : `MQTTTask`, `BeaconTask`, `sendAlert()`
- **Important** : Ne jamais appeler `client.publish()` sans ce mutex — deux tâches publiant simultanément corrompent le buffer TCP.

### Règles d'or

1. Toujours relâcher le mutex dans le même bloc — pas de `return` entre Take et Give.
2. Ne jamais prendre `telemetryMutex` puis `mqttMutex` dans le même bloc (risque de deadlock si une autre tâche fait l'inverse).
3. Utiliser `pdMS_TO_TICKS(timeout)` plutôt que `portMAX_DELAY` en production pour détecter les blocages.

---

## Flasher le firmware

### Arduino IDE 2.x

1. **Board** : Tools → Board → ESP32 Arduino → **ESP32 Dev Module**
2. **Upload Speed** : 921600 (ou 115200 si instable)
3. **Flash Size** : 4MB (selon votre module)
4. **Port** : le port COM/ttyUSB apparu lors de la connexion USB
5. Cliquer **Upload** (▶)

### Vérification après flash

Ouvrir le **Serial Monitor** (115200 baud) :
```
BMP180 detected
Connecting WiFi...
.....
WiFi connected — 192.168.1.x
Connecting MQTT...
MQTT connected
====== SENSOR TASK ======
Temperature: 24.53 °C
Pressure: 101325 Pa
Altitude: 12.34 m
Pot: 72.0%
=========================
Beacon sent: {"alive":true,"mode":"NOMINAL","battery":72}
HK packet published: {"temp":24.53,"pressure":101325,...}
```

---

## Dépannage

### BMP180 non détecté (`BMP180 not found!`)

- Vérifier SDA → GPIO 21 et SCL → GPIO 19
- Vérifier l'alimentation : **3.3V uniquement**
- Vérifier les résistances de pull-up I2C (certains modules les ont intégrées, d'autres non)
- Tester avec `Wire.begin()` et un scan I2C — l'adresse du BMP180 est `0x77`

### Connexion MQTT échoue (rc=-2, rc=-4)

| Code | Signification |
|---|---|
| -1 | Connexion refusée (mauvais host/port) |
| -2 | Socket fermé |
| -4 | Timeout de connexion |
| 4 | Bad credentials (mauvais user/pass) |
| 5 | Non autorisé |

**Solutions** :
- Vérifier `mqtt_server`, `mqtt_user`, `mqtt_pass`
- `espClient.setInsecure()` doit être appelé avant `client.connect()`
- Le port 8883 est-il ouvert sur le réseau Wi-Fi ? Certains réseaux d'entreprise le bloquent.
- Vérifier que le cluster HiveMQ est actif (console HiveMQ → Status)

### Valeur potentiomètre toujours à 0 ou 4095

- GPIO 35 est un **ADC entrée seule** — correct
- Vérifier le câblage : curseur → GPIO 35, bornes aux rails 3.3V et GND
- `analogRead(35)` retourne 0–4095 (12 bits)

### Messages MQTT non reçus côté Flutter

- Vérifier que l'ESP souscrit à `cubesat/cmd` dans `reconnectMQTT()`
- Vérifier le QoS — l'ESP utilise `MqttQos.atMostOnce` (QoS 0), les messages peuvent se perdre
- Activer `client.logging(on: true)` côté Flutter pour voir les paquets

### Stack overflow dans une tâche (`Task stack size too small`)

Augmenter la stack dans `xTaskCreatePinnedToCore()` :
```cpp
xTaskCreatePinnedToCore(
    MQTTTask, "MQTT Publish Task",
    12288,   // augmenter ici (était 8192)
    ...
```

### Watchdog reset (WDT triggered)

Une tâche bloque trop longtemps. Causes fréquentes :
- `portMAX_DELAY` sur un mutex jamais relâché
- `while(!client.connected())` sans `vTaskDelay` → affame le watchdog

**Solution** : S'assurer que chaque tâche a au moins un `vTaskDelay(pdMS_TO_TICKS(10))` dans sa boucle.