// Archivo: pestana_eficiencia.dart
// Muestra estadísticas energéticas relacionadas a eficiencia por dispositivo desde InfluxDB

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PestanaEficiencia extends StatefulWidget {
  const PestanaEficiencia({super.key});

  @override
  State<PestanaEficiencia> createState() => _PestanaEficienciaState();
}

class _PestanaEficienciaState extends State<PestanaEficiencia> {
  // Lista de dispositivos obtenidos desde InfluxDB
  List<String> dispositivos = ['Seleccionar...'];

  // Lista de estadísticas disponibles para eficiencia energética
  final List<String> estadisticas = [
    'Consumo vs Tiempo encendido',
    'Consumo promedio por uso',
    'Porcentaje de tiempo en uso',
    'Consumo en reposo (standby)',
  ];

  // Variables para almacenar selección del usuario y resultado calculado
  String dispositivoSeleccionado = 'Seleccionar...';
  String estadisticaSeleccionada = 'Consumo vs Tiempo encendido';
  String resultado = '--';

  @override
  void initState() {
    super.initState();
    cargarDispositivos(); // Llama automáticamente al cargar la pantalla
  }

  Future<void> cargarDispositivos() async {
    try {
      // Obtiene las credenciales de autenticación básica desde el archivo .env (usuario:contraseña)
      final influxAuth = dotenv.env['INFLUXDB_AUTH']!;

      // Codifica las credenciales en base64 para autenticación HTTP Basic
      final auth = base64Encode(utf8.encode(influxAuth));

      // Construye las cabeceras HTTP con la autenticación básica para la petición
      final headers = {'Authorization': 'Basic $auth'};

      // Obtiene la URL base de InfluxDB desde el archivo .env
      final influxUrl = dotenv.env['INFLUXDB_URL']!;

      // Obtiene el nombre de la base de datos desde el archivo .env
      final influxDBName = dotenv.env['INFLUXDB_DB']!;

      // Construye la consulta completa hacia InfluxDB para obtener los entity_id únicos desde la medición "W"
      final query = Uri.parse(
          '$influxUrl/query?q=${Uri.encodeComponent('SHOW TAG VALUES FROM "W" WITH KEY = "entity_id"')}&db=$influxDBName');

      // Realiza la petición GET hacia InfluxDB usando la consulta y cabeceras construidas
      final res = await http.get(query, headers: headers);

      // Verifica si la respuesta de la petición fue exitosa (código HTTP 200)
      if (res.statusCode != 200) {
        throw Exception('Error al consultar dispositivos desde InfluxDB');
      }

      // Decodifica la respuesta JSON recibida desde InfluxDB
      final decoded = json.decode(res.body);

      // Accede a los valores específicos del resultado JSON devuelto por InfluxDB
      final values = decoded['results']?[0]['series']?[0]['values'];

      // Extrae los entity_id que terminan con '_power' y los convierte a una lista de Strings
      final lista = (values as List?)
              ?.map((e) => e[1].toString())
              .where((id) => id.toString().endsWith('_power'))
              .toList() ??
          [];

      // Actualiza el estado de la aplicación con la nueva lista de dispositivos obtenidos
      setState(() {
        dispositivos = ['Seleccionar...'] + lista;
      });
    } catch (e) {
      // En caso de error, actualiza el estado de la aplicación con una lista predeterminada
      setState(() {
        dispositivos = ['Seleccionar...'];
      });
    }
  }

  /// Widget de UI para mostrar tarjeta con la estadística calculada
  Widget _tarjetaResultado(String texto) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              '$estadisticaSeleccionada de ${dispositivoSeleccionado.replaceAll('_power', '')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              texto,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Estructura principal de la pestaña
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Lista desplegable para seleccionar dispositivo
                DropdownButton<String>(
                  isExpanded: true,
                  value: dispositivoSeleccionado,
                  items: dispositivos.map((dispositivo) {
                    return DropdownMenuItem<String>(
                      value: dispositivo,
                      child: Text(dispositivo.replaceAll('_power', '')),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        dispositivoSeleccionado = value;
                        resultado = '--';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Lista desplegable para seleccionar estadística
                DropdownButton<String>(
                  isExpanded: true,
                  value: estadisticaSeleccionada,
                  items: estadisticas.map((opcion) {
                    return DropdownMenuItem<String>(
                      value: opcion,
                      child: Text(opcion),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        estadisticaSeleccionada = value;
                        resultado = '--';
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          // Tarjeta con el resultado de la estadística seleccionada
          Expanded(
            child: Center(
              child: dispositivoSeleccionado == 'Seleccionar...'
                  ? const Text('Por favor seleccione un dispositivo.')
                  : _tarjetaResultado(resultado),
            ),
          ),
        ],
      ),
    );
  }
}

// Clase modelo para gráficas de barras si se requieren posteriormente
class BarChartData {
  final String mes;
  final double valor;

  BarChartData({required this.mes, required this.valor});
}
