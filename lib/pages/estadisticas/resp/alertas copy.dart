import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';

class AlarmasScreen extends StatefulWidget {
  @override
  _AlarmasScreenState createState() => _AlarmasScreenState();
}

class _AlarmasScreenState extends State<AlarmasScreen> {
  List<Map<String, dynamic>> alertas = [];
  Timer? _timer;
  List<String> devices = [];
  bool alertasActivadas = false;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    fetchDevices();
    loadAlertas();
    loadSwitchState();
    initNotifications();
    fetchConsumptionData();
    _timer = Timer.periodic(
        // Comprueba el consumo cada 3 minutos
        Duration(minutes: 3),
        (Timer t) => fetchConsumptionData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> initNotifications() async {
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: androidInitializationSettings);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> fetchDevices() async {
    final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      List<String> deviceList = data
          .where((entity) =>
              entity["entity_id"].startsWith("sensor.") &&
              entity["entity_id"].contains("_power") &&
              !entity["entity_id"].contains("_power_factor"))
          .map<String>((entity) => entity["entity_id"] as String)
          .toList();

      setState(() {
        devices = deviceList;
      });
    }
  }

  Future<void> fetchConsumptionData() async {
    if (!alertasActivadas) return;
    DateTime now = DateTime.now();
    String today = DateFormat('yyyy-MM-dd').format(now);

    for (String device in devices) {
      final url = Uri.parse(
          "${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device");
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        double lastHourEnergyWh = 0.0;

        if (data.isNotEmpty) {
          DateTime oneHourAgo = now.subtract(Duration(hours: 1));
          for (var entry in data[0]) {
            DateTime timestamp = DateTime.parse(entry["last_changed"]);
            if (timestamp.isAfter(oneHourAgo)) {
              double power = double.tryParse(entry["state"]) ?? 0.0;
              lastHourEnergyWh += power / 60;
            }
          }
        }

        // Comprueba si el consumo es superior a 500 W durante la última hora
        if (lastHourEnergyWh > 500) {
          addAlerta({
            "device": device,
            "time": DateFormat('yyyy-MM-dd HH:mm').format(now),
            "last_hour_energy": lastHourEnergyWh
          });
          sendNotification(device, now, lastHourEnergyWh);
        }
      }
    }
  }

  // Dispara la ALERTA si el consumo es superior a 500 W durante la última hora
  Future<void> addAlerta(Map<String, dynamic> alerta) async {
    if (alerta["last_hour_energy"] != null &&
        alerta["last_hour_energy"] > 500) {
      setState(() {
        alertas.add(alerta);
      });
      await saveAlertas();
    }
  }

  Future<void> saveAlertas() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('alertas', json.encode(alertas));
  }

  Future<void> loadAlertas() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedAlertas = prefs.getString('alertas');
    if (storedAlertas != null) {
      var decoded = json.decode(storedAlertas);
      if (decoded is List) {
        alertas = List<Map<String, dynamic>>.from(decoded);
      } else if (decoded is Map) {
        alertas = [Map<String, dynamic>.from(decoded)];
      }
    }
  }

  Future<void> loadSwitchState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      alertasActivadas = prefs.getBool('alertas_activadas') ?? false;
    });
  }

  Future<void> sendNotification(
      String device, DateTime time, double energy) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'channel_id',
      'Alertas de Consumo',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Alerta de Consumo',
      'Dispositivo: $device\nFecha: ${DateFormat('yyyy-MM-dd HH:mm').format(time)}\nConsumo: ${energy.toStringAsFixed(2)} Wh',
      notificationDetails,
    );
  }

  Future<void> saveSwitchState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alertas_activadas', alertasActivadas);
  }

  void clearAlertas() async {
    setState(() {
      alertas.clear();
    });
    await saveAlertas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Alertas de Consumo"),
        actions: [
          Switch(
            value: alertasActivadas,
            onChanged: (value) {
              setState(() {
                alertasActivadas = value;
              });
              saveSwitchState();
              if (value) {
                fetchConsumptionData();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: clearAlertas,
          ),
        ],
      ),
      body: alertasActivadas
          ? (alertas.isEmpty
              ? Center(child: Text("No hay Alertas por el momento!"))
              : ListView.builder(
                  itemCount: alertas.length,
                  itemBuilder: (context, index) {
                    var alerta = alertas[index];
                    double lastHourEnergy = alerta['last_hour_energy'] ?? 0;
                    return Card(
                      color: Colors.red[200],
                      child: ListTile(
                        title:
                            Text(alerta['device'] ?? "Dispositivo desconocido"),
                        subtitle: Text(
                            "Fecha y hora: ${alerta['time']}\nÚltima hora: ${lastHourEnergy.toStringAsFixed(2)} Wh"),
                      ),
                    );
                  },
                ))
          : Center(child: Text("Alertas NO disponibles. Active las Alertas")),
    );
  }
}
