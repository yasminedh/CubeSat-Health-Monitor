# CubeSat Health Monitor

A real-time CubeSat telemetry monitoring system built with:

- 🛰 ESP32 + FreeRTOS
- 📡 MQTT communication
- 📱 Flutter dashboard
- ☁ Firebase cloud storage

This project simulates how an onboard computer (OBC) monitors and reacts to critical spacecraft conditions such as high temperature, low battery level, and safe mode activation.

---

# ✨ Features

## 📡 Real-Time Telemetry
- Live telemetry streaming using MQTT
- Real-time dashboard visualization
- Connection status monitoring

## 🛰 CubeSat Health Monitoring
- Battery level tracking
- Temperature monitoring
- Pressure and altitude visualization
- Potentiometer / analog sensor monitoring

## ⚠ Fault Detection & Safe Mode
- Automatic anomaly detection
- Safe mode triggering simulation
- Manual command system from the dashboard

## ☁ Firebase Cloud Integration
- Telemetry packet storage in Firestore
- Historical telemetry replay
- Session-based telemetry organization
- Date-range history loading

## 📊 Dashboard Interface
- Interactive Flutter dashboard
- Telemetry charts
- Live logs console
- Session history viewer

---

# 🏗 System Architecture

```text
ESP32 + Sensors
       │
       ▼
 FreeRTOS Tasks
       │
       ▼
 MQTT Broker (HiveMQ)
       │
       ▼
 Flutter Dashboard
       │
       ├── Live Visualization
       └── Firebase Firestore Storage
