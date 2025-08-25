import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DetalleDispositivoScreen extends StatefulWidget {
  final String entityId;
  final String nombre;

  const DetalleDispositivoScreen({
    super.key,
    required this.entityId,
    required this.nombre,
  });

  @override
  _DetalleDispositivoScreenState createState() =>
      _DetalleDispositivoScreenState();
}

class _DetalleDispositivoScreenState extends State<DetalleDispositivoScreen> {
  Map<String, dynamic>? deviceData;
  bool isLoading = true;

  //final String homeAssistantUrl = 'http://192.168.0.121:8123';
  final String homeAssistantUrl = '${dotenv.env['HOME_ASSISTANT_URL']}';

  final String authToken = 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}';

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  Future<void> fetchDeviceData() async {
    final url = Uri.parse('$homeAssistantUrl/api/states/${widget.entityId}');
    final response = await http.get(
      url,
      headers: {'Authorization': authToken, 'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final decodedResponse = json.decode(response.body);
      print(
          'Respuesta de la API: $decodedResponse'); // <-- Agregado para depuración
      setState(() {
        deviceData = decodedResponse;
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al obtener los datos del dispositivo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombre),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : deviceData != null
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDataRow('Frecuencia', 'frequency'),
                      _buildDataRow('Corriente', 'current'),
                      _buildDataRow(
                          'Instantaneous Demand', 'instantaneous_demand'),
                      _buildDataRow('Power', 'power'),
                      _buildDataRow('Power Factor', 'power_factor'),
                      _buildDataRow(
                          'Summation Delivered', 'summation_delivered'),
                      _buildDataRow('Voltaje', 'voltage'),
                    ],
                  ),
                )
              : Center(child: Text('No se pudieron cargar los datos.')),
    );
  }

  Widget _buildDataRow(String label, String attributeKey) {
    final value = deviceData?['attributes'][attributeKey]?.toString() ?? 'N/A';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
