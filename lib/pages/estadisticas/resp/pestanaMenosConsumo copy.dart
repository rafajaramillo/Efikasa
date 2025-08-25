// Este archivo muestra las 6 estadísticas de menor consumo energético
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PestanaMenosConsumo extends StatefulWidget {
  const PestanaMenosConsumo({super.key});

  @override
  State<PestanaMenosConsumo> createState() => _PestanaMenosConsumoState();
}

class _PestanaMenosConsumoState extends State<PestanaMenosConsumo> {
  final influxAuth = dotenv.env['INFLUXDB_AUTH']!;

  // Obtiene la URL base de InfluxDB desde el archivo .env
  final influxUrl = dotenv.env['INFLUXDB_URL']!;

  // Obtiene el nombre de la base de datos desde el archivo .env
  final influxDBName = dotenv.env['INFLUXDB_DB']!;

  Map<String, String> get headers {
    final auth = base64Encode(utf8.encode(influxAuth));
    return {'Authorization': 'Basic $auth'};
  }

  String get mesActualNombre {
    const meses = [
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
    final ahora = DateTime.now();
    return meses[ahora.month - 1];
  }

  double calcularEnergiaDesdeValores(List<dynamic> values) {
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
    return totalKwh;
  }

  Future<Map<String, double>> obtenerTotalConsumoPorMes() async {
    final dispositivos = await obtenerDispositivosPower();
    final ahora = DateTime.now();

    Map<String, double> totales = {};

    for (final dispositivo in dispositivos) {
      for (int mes = 1; mes <= ahora.month; mes++) {
        final inicio = DateTime.utc(ahora.year, mes, 1);
        final fin = mes < 12
            ? DateTime.utc(ahora.year, mes + 1, 1)
            : DateTime.utc(ahora.year + 1, 1, 1);

        final inicioStr = inicio.toIso8601String();
        final finStr = fin.toIso8601String();

        final queryStr =
            "SELECT \"value\" FROM \"W\" WHERE time >= '$inicioStr' AND time < '$finStr' AND \"entity_id\" = '$dispositivo'";

        final query = Uri.parse(
            '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');

        final res = await http.get(query, headers: headers);
        if (res.statusCode != 200) continue;
        final decoded = json.decode(res.body);
        final values = decoded['results']?[0]['series']?[0]['values'];
        if (values == null || values.length < 2) continue;

        double total = calcularEnergiaDesdeValores(values);

        if (total > 0) {
          final clave = '${_nombreMes(inicio.month)} ${inicio.year}';
          totales[clave] = (totales[clave] ?? 0) + total;
        }
      }
    }

    return totales;
  }

  String _nombreMes(int mes) {
    const meses = [
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
    return meses[mes - 1];
  }

  String formatearHoraDesdeFechaISO(String isoDate) {
    try {
      final dateTime = DateTime.parse(isoDate);
      final hora = dateTime.hour.toString().padLeft(2, '0');
      final minutos = dateTime.minute.toString().padLeft(2, '0');
      return '$hora:$minutos';
    } catch (_) {
      return isoDate;
    }
  }

  Future<List<String>> obtenerDispositivosPower() async {
    final query = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent('SHOW TAG VALUES FROM "W" WITH KEY = "entity_id"')}&db=$influxDBName');

    final res = await http.get(query, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Error al consultar dispositivos');
    }
    final decoded = json.decode(res.body);
    final series = decoded['results']?[0]['series']?[0]['values'];
    return (series as List?)
            ?.map((e) => e[1].toString())
            .where((id) => id.endsWith('_power'))
            .toList() ??
        [];
  }

  Future<Map<String, double>> obtenerConsumoDispositivoPorRango(
      String rango) async {
    final query = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent('SELECT "value" FROM "W" WHERE time >= $rango AND time < now() AND "entity_id" =~ /.*_power/ GROUP BY "entity_id"')}&db=$influxDBName&epoch=ms');
    final res = await http.get(query, headers: headers);
    if (res.statusCode != 200) throw Exception('Error al consultar InfluxDB');
    final decoded = json.decode(res.body);
    final series = decoded['results']?[0]['series'];
    if (series == null) return {};

    Map<String, double> consumos = {};
    for (var serie in series) {
      final id = serie['tags']['entity_id'];
      final values = serie['values'];
      consumos[id] = calcularEnergiaDesdeValores(values);
    }
    return consumos;
  }

  Future<Map<String, double>> obtenerAgrupadoIntegral(String queryStr) async {
    final query = Uri.parse(
        '$influxUrl/query?q=${Uri.encodeComponent(queryStr)}&db=$influxDBName&epoch=ms');
    final res = await http.get(query, headers: headers);
    if (res.statusCode != 200) return {};
    final decoded = json.decode(res.body);
    final series = decoded['results']?[0]['series'];
    if (series == null) return {};

    Map<String, double> agrupado = {};
    for (var serie in series) {
      final values = serie['values'];
      for (var row in values) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(row[0]);
        final consumo = row[1];
        final clave = timestamp.toIso8601String().substring(0, 10);
        if (consumo != null) {
          agrupado[clave] = (agrupado[clave] ?? 0) + consumo;
        }
      }
    }
    return agrupado;
  }

  String formatearFecha(String fechaIso) {
    final fecha = DateTime.parse(fechaIso).toLocal();
    final dias = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo'
    ];
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
    final nombreDia = dias[fecha.weekday - 1];
    final nombreMes = meses[fecha.month - 1];
    return '$nombreDia ${fecha.day.toString().padLeft(2, '0')} de $nombreMes ${fecha.year}';
  }

  Widget buildStatCard(String titulo, String valor) {
    final bool tieneDatos = !valor.contains('Sin datos');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: tieneDatos
              ? const Color.fromARGB(255, 188, 248, 225)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  tieneDatos ? Icons.bolt : Icons.warning,
                  color: tieneDatos ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text(valor, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final anio = ahora.year;
    final inicioHoy =
        DateTime(ahora.year, ahora.month, ahora.day).toUtc().toIso8601String();
    final inicioMesAnterior = DateTime.utc(
            ahora.month == 1 ? ahora.year - 1 : ahora.year,
            ahora.month == 1 ? 12 : ahora.month - 1,
            1)
        .toIso8601String();
    final inicioMesActual =
        DateTime.utc(ahora.year, ahora.month, 1).toIso8601String();

    return FutureBuilder(
      future: Future.wait([
        obtenerTotalConsumoPorMes(),
        obtenerConsumoDispositivoPorRango("'$inicioHoy'"),
        obtenerConsumoDispositivoPorRango(
            "'$inicioMesAnterior' AND time < '$inicioMesActual'"),
        obtenerAgrupadoIntegral(
            "SELECT integral(\"value\") / 3600000 FROM \"W\" WHERE time >= '$inicioMesActual' AND time < now() AND \"entity_id\" =~ /.*_power/ GROUP BY time(1h) fill(null)"),
        obtenerAgrupadoIntegral(
            "SELECT integral(\"value\") / 3600000 FROM \"W\" WHERE time >= '$inicioMesActual' AND time < now() AND \"entity_id\" =~ /.*_power/ GROUP BY time(1d) fill(null)"),
        obtenerAgrupadoIntegral(
            "SELECT integral(\"value\") / 3600000 FROM \"W\" WHERE time >= '${DateTime.now().toUtc().subtract(Duration(days: ahora.weekday - 1)).toIso8601String()}' AND time < now() AND \"entity_id\" =~ /.*_power/ GROUP BY time(1d) fill(null)"),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return const Center(child: Text('Error al obtener estadísticas'));
        } else {
          final datos = snapshot.data as List;
          final meses = datos[0] as Map<String, double>;
          final hoy = datos[1] as Map<String, double>;
          final mesAnterior = datos[2] as Map<String, double>;
          final horasMes = datos[3] as Map<String, double>;
          final diasMes = datos[4] as Map<String, double>;
          final diasSemana = datos[5] as Map<String, double>;

          final mesMin = meses.entries.isNotEmpty
              ? meses.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;
          final minHoy = hoy.entries.isNotEmpty
              ? hoy.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;
          final minMesAnterior = mesAnterior.entries.isNotEmpty
              ? mesAnterior.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;
          final horaMenor = horasMes.entries.isNotEmpty
              ? horasMes.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;
          final diaMenorSemana = diasSemana.entries.isNotEmpty
              ? diasSemana.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;
          final diaMenorMes = diasMes.entries.isNotEmpty
              ? diasMes.entries.reduce((a, b) => a.value < b.value ? a : b)
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              buildStatCard(
                'Mes de menor consumo ($anio)',
                mesMin != null
                    ? '${mesMin.key} - ${mesMin.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
              buildStatCard(
                'Dispositivo que menos consumió hoy',
                minHoy != null
                    ? '${minHoy.key.replaceAll('_power', '')} - ${minHoy.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
              buildStatCard(
                'Dispositivo que menos consumió en el mes anterior',
                minMesAnterior != null
                    ? '${minMesAnterior.key.replaceAll('_power', '')} - ${minMesAnterior.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
              buildStatCard(
                'Horas de menor consumo ($mesActualNombre)',
                horaMenor != null
                    ? '${formatearHoraDesdeFechaISO(horaMenor.key)} - ${horaMenor.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
              buildStatCard(
                'Día de menor consumo (semana actual)',
                diaMenorSemana != null
                    ? '${formatearFecha(diaMenorSemana.key)} - ${diaMenorSemana.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
              buildStatCard(
                'Día de menor consumo ($mesActualNombre)',
                diaMenorMes != null
                    ? '${formatearFecha(diaMenorMes.key)} - ${diaMenorMes.value.toStringAsFixed(2)} kWh'
                    : 'Sin datos registrados en ese periodo',
              ),
            ],
          );
        }
      },
    );
  }
}
