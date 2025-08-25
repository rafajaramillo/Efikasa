// Muestra estadísticas energéticas por dispositivo, seleccionadas desde un menú desplegable
// Los dispositivos se obtienen automáticamente desde InfluxDB

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PorDispositivo extends StatefulWidget {
  const PorDispositivo({super.key});

  @override
  State<PorDispositivo> createState() => _PorDispositivoState();
}

class _PorDispositivoState extends State<PorDispositivo> {
  final influxAuth = dotenv.env['INFLUXDB_AUTH']!;

  // Obtiene la URL base de InfluxDB desde el archivo .env
  final influxUrl = dotenv.env['INFLUXDB_URL']!;

  // Obtiene el nombre de la base de datos desde el archivo .env
  final influxDBName = dotenv.env['INFLUXDB_DB']!;

  final List<String> estadisticas = [
    'Consumo total histórico',
    'Consumo mensual',
    'Promedio diario de consumo',
    'Horas de mayor consumo promedio',
    'Hora de menor consumo promedio',
    'Día de la semana con mayor consumo',
    'Mes con mayor consumo histórico'
  ];

  String estadisticaSeleccionada = 'Consumo total histórico';
  String dispositivoSeleccionado = 'Seleccionar...';
  List<String> dispositivos = ['Seleccionar...'];
  String valorEstadistica = '--';
  List<BarChartData> datosMensuales = [];
  List<BarChartData> datosCategoria =
      []; // Para día de semana o mes con gráfico

  @override
  void initState() {
    super.initState();
    cargarDispositivos();
  }

  Future<void> cargarDispositivos() async {
    try {
      final auth = base64Encode(utf8.encode(influxAuth));
      final headers = {'Authorization': 'Basic $auth'};
      final query = Uri.parse(
          '$influxUrl/query?q=${Uri.encodeComponent('SHOW TAG VALUES FROM "W" WITH KEY = "entity_id"')}&db=$influxDBName');
      final res = await http.get(query, headers: headers);
      if (res.statusCode != 200)
        throw Exception('Error al consultar dispositivos');
      final decoded = json.decode(res.body);
      final series = decoded['results']?[0]['series']?[0]['values'];
      final lista = (series as List?)
              ?.map((e) => e[1].toString())
              .where((id) => id.endsWith('_power'))
              .toList() ??
          [];
      setState(() {
        dispositivos = ['Seleccionar...'] + lista;
      });
    } catch (e) {
      setState(() {
        dispositivos = ['Seleccionar...'];
      });
    }
  }

  Future<void> calcularEstadistica() async {
    if (dispositivoSeleccionado == 'Seleccionar...') return;

    switch (estadisticaSeleccionada) {
      case 'Consumo total histórico':
        valorEstadistica = await calcularConsumoTotalHistorico();
        datosMensuales.clear();
        break;
      case 'Consumo mensual':
        await calcularConsumoMensual();
        break;
      case 'Promedio diario de consumo':
        valorEstadistica = await calcularPromedioDiario();
        datosMensuales.clear();
        break;
      case 'Horas de mayor consumo promedio':
        valorEstadistica = await calcularHoraMayorConsumoPromedio();
        datosMensuales.clear();
        break;
      case 'Hora de menor consumo promedio':
        valorEstadistica = await calcularHoraMenorConsumoPromedio();
        datosMensuales.clear();
        break;
      case 'Día de la semana con mayor consumo':
        valorEstadistica = await calcularDiaSemanaMayorConsumo();
        datosMensuales.clear();
        break;
      case 'Mes con mayor consumo histórico':
        valorEstadistica = await calcularMesMayorConsumo();
        datosMensuales.clear();
        break;
      default:
        valorEstadistica = '--';
        datosMensuales.clear();
    }

    if (mounted) setState(() {});
  }

  // Función para obtener el día de la semana con mayor consumo histórico
  Future<String> calcularDiaSemanaMayorConsumo() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final inicio = DateTime.utc(DateTime.now().year, 1, 1);

    final queryStr =
        "SELECT \"value\" FROM \"W\" WHERE time >= '${inicio.toIso8601String()}' AND \"entity_id\" = '$dispositivoSeleccionado'";

    final url = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) return '--';

    final decoded = json.decode(res.body);
    final values = decoded['results']?[0]['series']?[0]['values'];
    if (values == null) return '--';

    Map<int, double> consumoPorDia = {};
    for (int i = 1; i < values.length; i++) {
      final anterior = values[i - 1];
      final actual = values[i];
      final potencia = anterior[1];
      final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
      final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
      final duracionSeg = t2.difference(t1).inSeconds;
      if (potencia != null) {
        final energia = (potencia * duracionSeg) / 3600000;
        final diaSemana = t1.weekday;
        consumoPorDia[diaSemana] = (consumoPorDia[diaSemana] ?? 0) + energia;
      }
    }

    if (consumoPorDia.isEmpty) return '--';
    final dias = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo'
    ];
    datosCategoria = consumoPorDia.entries
        .map((e) => BarChartData(mes: dias[e.key - 1], valor: e.value))
        .toList();

    final diaMax =
        consumoPorDia.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${dias[diaMax.key - 1]} - ${diaMax.value.toStringAsFixed(2)} kWh';
  }

  // Función para obtener el mes con mayor consumo histórico
  Future<String> calcularMesMayorConsumo() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final ahora = DateTime.now();
    //final inicioAnio = DateTime.utc(ahora.year, 1, 1);

    Map<int, double> consumoMensual = {};

    for (int mes = 1; mes <= ahora.month; mes++) {
      final inicio = DateTime.utc(ahora.year, mes, 1);
      final fin = mes < 12
          ? DateTime.utc(ahora.year, mes + 1, 1)
          : DateTime.utc(ahora.year + 1, 1, 1);

      final queryStr =
          "SELECT \"value\" FROM \"W\" WHERE time >= '${inicio.toIso8601String()}' AND time < '${fin.toIso8601String()}' AND \"entity_id\" = '$dispositivoSeleccionado'";

      final url = Uri.parse(
          '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

      final res = await http.get(url, headers: headers);
      if (res.statusCode != 200) continue;

      final decoded = json.decode(res.body);
      final values = decoded['results']?[0]['series']?[0]['values'];
      if (values == null || values.length < 2) continue;

      double total = 0;
      for (int i = 1; i < values.length; i++) {
        final anterior = values[i - 1];
        final actual = values[i];
        final potencia = anterior[1];
        final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
        final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
        final duracionSeg = t2.difference(t1).inSeconds;
        if (potencia != null) {
          total += (potencia * duracionSeg) / 3600000;
        }
      }

      if (total > 0) {
        consumoMensual[mes] = total;
      }
    }

    if (consumoMensual.isEmpty) return '--';
    final meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    final mesMax =
        consumoMensual.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${meses[mesMax.key - 1]} - ${mesMax.value.toStringAsFixed(2)} kWh';
  }

  Widget _graficoBarras(List<BarChartData> datos) {
    return SizedBox(
      height: 200,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: datos.map((data) {
          return Container(
            width: 50,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(data.valor.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  height: data.valor * 10,
                  width: 20,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 4),
                Text(data.mes, style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<String> calcularHoraMenorConsumoPromedio() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final ahora = DateTime.now();
    final inicio = DateTime.utc(ahora.year, 1, 1);

    final queryStr =
        "SELECT mean(\"value\") FROM \"W\" WHERE time >= '${inicio.toIso8601String()}' AND time < now() AND \"entity_id\" = '$dispositivoSeleccionado' GROUP BY time(1h) fill(null)";

    final url = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) return '--';

    final decoded = json.decode(res.body);
    final series = decoded['results']?[0]['series'];
    if (series == null) return '--';

    Map<int, double> sumaHoras = {};
    for (var serie in series) {
      for (var row in serie['values']) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(row[0]);
        final hora = timestamp.hour;
        final promedio = row[1];
        if (promedio != null) {
          sumaHoras[hora] = (sumaHoras[hora] ?? 0) + promedio;
        }
      }
    }

    if (sumaHoras.isEmpty) return '--';
    final horaMin =
        sumaHoras.entries.reduce((a, b) => a.value < b.value ? a : b);
    return '${horaMin.key.toString().padLeft(2, '0')}:00 - ${horaMin.value.toStringAsFixed(2)} W promedio';
  }

  Future<String> calcularConsumoTotalHistorico() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final queryStr =
        "SELECT \"value\" FROM \"W\" WHERE \"entity_id\" = '$dispositivoSeleccionado'";

    final url = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) return '--';

    final decoded = json.decode(res.body);
    final values = decoded['results']?[0]['series']?[0]['values'];
    if (values == null || values.length < 2) return '--';

    double totalKwh = 0.0;
    for (int i = 1; i < values.length; i++) {
      final anterior = values[i - 1];
      final actual = values[i];
      final potencia = anterior[1];
      final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
      final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
      final duracionSeg = t2.difference(t1).inSeconds;
      if (potencia != null) {
        totalKwh += (potencia * duracionSeg) / 3600000;
      }
    }

    return '${totalKwh.toStringAsFixed(2)} kWh';
  }

  Future<String> calcularHoraMayorConsumoPromedio() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final ahora = DateTime.now();
    final inicio = DateTime.utc(ahora.year, 1, 1);

    final queryStr =
        "SELECT mean(\"value\") FROM \"W\" WHERE time >= '${inicio.toIso8601String()}' AND time < now() AND \"entity_id\" = '$dispositivoSeleccionado' GROUP BY time(1h) fill(null)";

    final url = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) return '--';

    final decoded = json.decode(res.body);
    final series = decoded['results']?[0]['series'];
    if (series == null) return '--';

    Map<int, double> sumaHoras = {};
    for (var serie in series) {
      for (var row in serie['values']) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(row[0]);
        final hora = timestamp.hour;
        final promedio = row[1];
        if (promedio != null) {
          sumaHoras[hora] = (sumaHoras[hora] ?? 0) + promedio;
        }
      }
    }

    if (sumaHoras.isEmpty) return '--';
    final horaMax =
        sumaHoras.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${horaMax.key.toString().padLeft(2, '0')}:00 - ${horaMax.value.toStringAsFixed(2)} W promedio';
  }

  Future<void> calcularConsumoMensual() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final ahora = DateTime.now();
    datosMensuales.clear();

    for (int mes = 1; mes <= ahora.month; mes++) {
      final inicio = DateTime.utc(ahora.year, mes, 1);
      final fin = mes < 12
          ? DateTime.utc(ahora.year, mes + 1, 1)
          : DateTime.utc(ahora.year + 1, 1, 1);

      final queryStr =
          "SELECT \"value\" FROM \"W\" WHERE time >= '${inicio.toIso8601String()}' AND time < '${fin.toIso8601String()}' AND \"entity_id\" = '$dispositivoSeleccionado'";

      final url = Uri.parse(
          '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

      final res = await http.get(url, headers: headers);
      if (res.statusCode != 200) continue;
      final decoded = json.decode(res.body);
      final values = decoded['results']?[0]['series']?[0]['values'];
      if (values == null || values.length < 2) continue;

      double total = 0.0;
      for (int i = 1; i < values.length; i++) {
        final anterior = values[i - 1];
        final actual = values[i];
        final potencia = anterior[1];
        final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
        final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
        final duracionSeg = t2.difference(t1).inSeconds;
        if (potencia != null) {
          total += (potencia * duracionSeg) / 3600000;
        }
      }

      datosMensuales.add(
          BarChartData(mes: DateFormat.MMM().format(inicio), valor: total));
    }

    valorEstadistica = '--';
  }

  Future<String> calcularPromedioDiario() async {
    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};
    final queryStr =
        "SELECT \"value\" FROM \"W\" WHERE \"entity_id\" = '$dispositivoSeleccionado'";

    final url = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) return '--';

    final decoded = json.decode(res.body);
    final values = decoded['results']?[0]['series']?[0]['values'];
    if (values == null || values.length < 2) return '--';

    double totalKwh = 0.0;
    final tInicio = DateTime.fromMillisecondsSinceEpoch(values.first[0]);
    final tFin = DateTime.fromMillisecondsSinceEpoch(values.last[0]);
    final dias = tFin.difference(tInicio).inDays;
    if (dias == 0) return '--';

    for (int i = 1; i < values.length; i++) {
      final anterior = values[i - 1];
      final actual = values[i];
      final potencia = anterior[1];
      final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
      final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
      final duracionSeg = t2.difference(t1).inSeconds;
      if (potencia != null) {
        totalKwh += (potencia * duracionSeg) / 3600000;
      }
    }

    final promedio = totalKwh / dias;
    return '${promedio.toStringAsFixed(2)} kWh/día';
  }

  Widget construirContenidoEstadistico() {
    if (dispositivoSeleccionado == 'Seleccionar...') {
      return const Center(child: Text('Por favor seleccione un dispositivo.'));
    }

    calcularEstadistica();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _tarjetaEstadistica(
            '$estadisticaSeleccionada de ${dispositivoSeleccionado.replaceAll('_power', '')}',
            valorEstadistica,
            Colors.blueAccent,
          ),
          const SizedBox(height: 16),
          datosMensuales.isNotEmpty ? _graficoMensual() : const SizedBox()
        ],
      ),
    );
  }

  Widget _graficoMensual() {
    return SizedBox(
      height: 200,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: datosMensuales.map((data) {
          return Container(
            width: 50,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(data.valor.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  height: data.valor * 10,
                  width: 20,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 4),
                Text(data.mes, style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tarjetaEstadistica(String titulo, String valor, Color color) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(valor,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            if (datosCategoria.isNotEmpty &&
                estadisticaSeleccionada == 'Día de la semana con mayor consumo')
              _graficoBarras(datosCategoria)
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
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
                        valorEstadistica = '--';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
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
                        valorEstadistica = '--';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(child: construirContenidoEstadistico()),
        ],
      ),
    );
  }
}

class BarChartData {
  final String mes;
  final double valor;

  BarChartData({required this.mes, required this.valor});
}
