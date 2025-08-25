# Efikasa

[🇪🇸 Español](#-descripción-en-español) | [🇬🇧 English](#-description-in-english)

---

## 🇪🇸 Descripción en Español

**Efikasa** es una plataforma IoT desarrollada para la **eficiencia energética en hogares conectados**.  
Integra dispositivos inteligentes Zigbee, Home Assistant, InfluxDB y una aplicación móvil en **Flutter**, ofreciendo monitoreo en tiempo real, análisis histórico y predicciones de consumo energético.  

### ✨ Características principales
- 📊 **Visualización en tiempo real** del consumo eléctrico por dispositivo.  
- 🔄 **Actualización automática** de estados (ON/OFF, W consumidos, horas en uso).  
- 🗄️ **Histórico de consumo** almacenado en Home Assistant + InfluxDB.  
- 📈 **Estadísticas avanzadas**: consumo promedio, standby, tiempo de uso, etc.  
- 🤖 **Modelos predictivos (regresión lineal simple)** para estimar el consumo futuro.  
- 💵 **Gestión de tarifas**: cálculo automático de costos en dólares.  
- 📱 **Aplicación móvil en Flutter** con dashboards e interfaz intuitiva.  
- 🔔 **Alertas inteligentes** (picos de consumo, consumo nocturno, standby prolongado, ausencia de datos).  

### 🛠️ Tecnologías utilizadas
- **Frontend**: Flutter (Dart)  
- **Backend**: Home Assistant + SQLite 
- **Predicciones**: Python (ARIMA, regresión lineal)  
- **Infraestructura**: Raspberry Pi 5 + Sonoff Zigbee 3.0 Dongle Plus E + Zigbee Plugs  

### 🎯 Objetivo
Brindar una herramienta práctica y escalable para **mejorar la eficiencia energética en hogares inteligentes**, optimizando el uso de dispositivos y reduciendo costos eléctricos.  

---

## 🇬🇧 Description in English

**Efikasa** is an IoT platform designed for **energy efficiency in smart homes**.  
It integrates Zigbee smart devices, Home Assistant, InfluxDB, and a **Flutter** mobile application, providing real-time monitoring, historical analysis, and energy consumption forecasting.  

### ✨ Key Features
- 📊 **Real-time visualization** of power consumption per device.  
- 🔄 **Automatic status updates** (ON/OFF, watts consumed, hours in use).  
- 🗄️ **Historical data** stored in Home Assistant + InfluxDB.  
- 📈 **Advanced statistics**: average consumption, standby, usage time, etc.  
- 🤖 **Predictive models (simple linear regression)** to estimate future consumption.  
- 💵 **Tariff management**: automatic calculation of energy costs in USD.  
- 📱 **Flutter mobile app** with dashboards and an intuitive UI.  
- 🔔 **Smart alerts** (consumption peaks, night usage, extended standby, missing data).  

### 🛠️ Tech Stack
- **Frontend**: Flutter (Dart)  
- **Backend**: Home Assistant + SQLite  
- **Forecasting**: Python (ARIMA, linear regression)  
- **Infrastructure**: Raspberry Pi 5 + Sonoff Zigbee 3.0 Dongle Plus E + Zigbee Plugs  

### 🎯 Goal
To provide a practical and scalable tool for **improving energy efficiency in smart homes**, optimizing device usage, and reducing electricity costs.  

---

## 📜 Licencia / License

Este proyecto está licenciado bajo **GNU Affero General Public License v3.0 (AGPL-3.0)**.  
This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.  

- Puedes usarlo, modificarlo y redistribuirlo siempre que mantengas la atribución y publiques los cambios.  
- You may use, modify, and redistribute it as long as you keep attribution and publish your changes.  

👉 Si deseas una licencia **comercial/cerrada**, contacta: **santy_jara@hotmail.com**  
👉 If you need a **commercial/closed license**, contact: **santy_jara@hotmail.com**

### Cómo citar / How to cite
Si utilizas este software en tu investigación o publicaciones, por favor cítalo:  
If you use this software in your research or publications, please cite it:  
→ Ver [`CITATION.cff`](./CITATION.cff).  
