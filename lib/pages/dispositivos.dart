import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DispositivosScreen extends StatefulWidget {
  const DispositivosScreen({super.key});

  @override
  _DispositivosScreenState createState() => _DispositivosScreenState();
}

class _DispositivosScreenState extends State<DispositivosScreen> {
  //final String homeAssistantUrl = 'http://192.168.0.121:8123';
  final String homeAssistantUrl = '${dotenv.env['HOME_ASSISTANT_URL']}';
  final String bearerToken = '${dotenv.env['HOME_ASSISTANT_TOKEN']}';
  List<Map<String, dynamic>> devices = [];

  @override
  void initState() {
    super.initState();
    fetchZigbeeDevices();
  }

  /// Obtiene la lista de dispositivos Zigbee
  Future<void> fetchZigbeeDevices() async {
    final url = Uri.parse('$homeAssistantUrl/api/states');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> allEntities = json.decode(response.body);

      setState(() {
        devices = allEntities
            .where((entity) =>
                (entity['entity_id'].startsWith('switch.') ||
                    entity['entity_id'].startsWith('light.')) &&
                entity['attributes'] != null &&
                entity['attributes']['friendly_name'] != null &&
                !entity['attributes']['friendly_name']
                    .toLowerCase()
                    .contains('zigbee2mqtt')) // Omite Zigbee2MQTT
            .map((entity) => {
                  'id': entity['attributes']['device_id'],
                  'entity_id': entity['entity_id'],
                  'name': entity['attributes']['friendly_name'],
                  'isOn': entity['state'] == 'on',
                })
            .toList();
      });
    } else {
      //print('Error al obtener dispositivos Zigbee: ${response.statusCode}');
    }
  }

  /// Enciende o apaga un dispositivo Zigbee
  Future<void> toggleDevice(String entityId, bool turnOn) async {
    final action = turnOn ? 'turn_on' : 'turn_off';
    final domain = entityId.startsWith('light.') ? 'light' : 'switch';
    final url = Uri.parse('$homeAssistantUrl/api/services/$domain/$action');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'entity_id': entityId,
      }),
    );

    if (response.statusCode == 200) {
      setState(() {
        devices = devices.map((device) {
          if (device['entity_id'] == entityId) {
            device['isOn'] = turnOn;
          }
          return device;
        }).toList();
      });
    } else {
      //print('Error al cambiar estado del dispositivo: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Control de Dispositivos')),
      body: devices.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // Dos tarjetas por fila
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1, // Cuadrado
                ),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          device['isOn'] ? Icons.power : Icons.power_off,
                          size: 40,
                          color: device['isOn'] ? Colors.green : Colors.grey,
                        ),
                        SizedBox(height: 5),
                        Text(
                          device['name'],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        Switch(
                          value: device['isOn'],
                          onChanged: (value) =>
                              toggleDevice(device['entity_id'], value),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
