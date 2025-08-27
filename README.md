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

## 🔧 Instrucciones de compilación e instalación

A continuación, se detallan los pasos para compilar e instalar la aplicación móvil Flutter desarrollada para el monitoreo energético en hogares conectados.

### 1. Requisitos previos

Antes de compilar, asegúrate de tener instalados los siguientes elementos:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versión recomendada: 3.13 o superior)
- Android Studio o VS Code con extensión Flutter
- Emulador o dispositivo Android conectado (minSdkVersion: 21+)
- Git (para clonar el repositorio)

### 2. Clonar el repositorio

```bash
git clone https://github.com/rafajaramillo/Efikasa.git
cd nombre-repo
```

### 3. Instalar dependencias

```bash
flutter pub get
```

### 4. Configurar archivo `.env` (si aplica)

Si el proyecto utiliza variables de entorno, crea un archivo `.env` en la raíz con el siguiente formato:

```
HOME_ASSISTANT_URL=https://yourdomain.com/api
HOME_ASSISTANT_TOKEN=
INFLUXDB_AUTH=
INFLUXDB_URL=
INFLUXDB_DB=
INFLUXDB_ALERT_HISTORY_DAYS=7
```

> ⚠️ Puedes omitir esta sección si no desea usar `.env`.

### 5. Ejecutar en dispositivo o emulador

```bash
flutter run
```

### 6. Compilar APK para producción

```bash
flutter build apk --release
```

El archivo generado se ubicará en:

```
build/app/outputs/flutter-apk/app-release.apk
```

## 👨‍💻 Autor

**Santiago Jaramillo**  
Trabajo Fin de Máster — Universidad de Granada  
Tutor académico: Dr. Juan Antonio Holgado Terriza

---

## 📬 Contacto

Para sugerencias o colaboraciones:  
📧 santy_jara@hotmail.com

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

## 🔧 Installation and Build Instructions

The following steps describe how to build and install the mobile application using Flutter.

### 1. Prerequisites

Ensure the following tools are installed:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (recommended version: 3.13+)
- Android Studio or VS Code with Flutter extension
- Android emulator or physical device (minSdkVersion: 21+)
- Git

### 2. Clone the repository

```bash
git clone https://github.com/username/project-name.git
cd project-name
```

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Configure `.env` file (if applicable)

If the project uses environment variables, create a `.env` file in the root directory:

```
HOME_ASSISTANT_URL=https://yourdomain.com/api
HOME_ASSISTANT_TOKEN=
INFLUXDB_AUTH=
INFLUXDB_URL=
INFLUXDB_DB=
INFLUXDB_ALERT_HISTORY_DAYS=7
```

> ⚠️ Skip this step if `.env` is not required.

### 5. Run on device or emulator

```bash
flutter run
```

### 6. Build release APK

```bash
flutter build apk --release
```

The APK will be generated at:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 👨‍💻 Author

**Santiago Jaramillo**  
Master’s Thesis — University of Granada  
Academic Advisor: Dr. Juan Antonio Holgado Terriza

---

## 📬 Contact

For contributions or suggestions:  
📧 santy_jarac@hotmail.com

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
