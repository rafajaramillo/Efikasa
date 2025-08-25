import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ExcluirDispositivosScreen extends StatefulWidget {
  const ExcluirDispositivosScreen({super.key});

  @override
  _ExcluirDispositivosScreenState createState() =>
      _ExcluirDispositivosScreenState();
}

class _ExcluirDispositivosScreenState extends State<ExcluirDispositivosScreen> {
  List<String> dispositivos = [];
  List<String> excluidos = [];

  @override
  void initState() {
    super.initState();
    cargarDispositivosYExcluidos();
  }

  Future<List<String>> fetchDevices() async {
    final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data
          .where((entity) =>
              entity["entity_id"].startsWith("sensor.") &&
              entity["entity_id"].contains("_power") &&
              !entity["entity_id"].contains("_power_factor"))
          .map<String>((entity) => entity["entity_id"] as String)
          .toList();
    }

    return [];
  }

  void cargarDispositivosYExcluidos() async {
    dispositivos = await fetchDevices();
    excluidos = await loadExcludedDevices();
    setState(() {});
  }

  Future<void> saveExcludedDevices(List<String> excludedDevices) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('excluded_devices_continuo', excludedDevices);
  }

  Future<List<String>> loadExcludedDevices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('excluded_devices_continuo') ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Excluir dispositivos de Alertas")),
      body: dispositivos.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: dispositivos.map((device) {
                return CheckboxListTile(
                  title: Text(device),
                  value: excluidos.contains(device),
                  onChanged: (bool? selected) {
                    setState(() {
                      if (selected!) {
                        excluidos.add(device);
                      } else {
                        excluidos.remove(device);
                      }
                      saveExcludedDevices(excluidos);
                    });
                  },
                );
              }).toList(),
            ),
    );
  }
}
