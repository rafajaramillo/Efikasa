import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PestanaMasConsumo extends StatefulWidget {
  const PestanaMasConsumo({super.key});

  @override
  State<PestanaMasConsumo> createState() => _PestanaMasConsumoState();
}

class _PestanaMasConsumoState extends State<PestanaMasConsumo> {
  //  URL y token de Nabu Casa desde .env
  final String haUrl = dotenv.env['HOME_ASSISTANT_URL']!;
  final String token = dotenv.env['HOME_ASSISTANT_TOKEN']!;

// Lista de sensores _power
  late Future<List<String>> futureDevices;

  // HTTP headers for Bearer authentication
  Map<String, String> get headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

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

  @override
  void initState() {
    super.initState();
    futureDevices = _obtenerDispositivosPower();
  }

  /// Descarga el histórico crudo para cada sensor en el rango especificado.
  /// Devuelve una lista donde cada posición i corresponde a la lista de puntos
  /// (Map con keys 'last_changed' y 'state') para el dispositivo devices[i].
  Future<List<List<Map<String, dynamic>>>> _fetchHistoryRaw(
    DateTime start,
    DateTime end,
    List<String> devices,
  ) async {
    // Función auxiliar para formatear DateTime en ISO sin milisegundos
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

    // Construye la URL con rango y filtro de dispositivos
    final uri = Uri.parse(
      '$haUrl/api/history/period/${iso(start)}'
      '?end_time=${iso(end)}'
      '&filter_entity_id=${devices.join(',')}',
    );

    // Petición HTTP
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Error histórico HA: ${res.statusCode}');
    }

    // Decodifica respuesta JSON en lista de series
    final decoded = json.decode(res.body) as List<dynamic>;

    // Genera resultado: para cada dispositivo, toma su serie (o lista vacía)
    return List<List<Map<String, dynamic>>>.generate(
      devices.length,
      (i) {
        if (i < decoded.length && decoded[i] is List) {
          return List<Map<String, dynamic>>.from(decoded[i]);
        }
        return <Map<String, dynamic>>[];
      },
    );
  }

  /// Devuelve una lista de entity_id de sensores de potencia desde Home Assistant
  Future<List<String>> _obtenerDispositivosPower() async {
    final uri = Uri.parse('$haUrl/api/states');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Error al consultar estados HA: ${res.statusCode}');
    }
    final list = json.decode(res.body) as List<dynamic>;
    return list
        .map((e) => e['entity_id'] as String? ?? '')
        .where((id) =>
            id.startsWith('sensor.') &&
            id.endsWith('_power') &&
            !id.contains('_power_factor') &&
            !id.contains('_status'))
        .toList();
  }

  /// Consulta histórico y aplica integración trapezoidal para cada sensor
  Future<Map<String, double>> _fetchConsumoRange(
      DateTime start, DateTime end, List<String> devices) async {
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final uri = Uri.parse(
      '$haUrl/api/history/period/${iso(start)}'
      '?end_time=${iso(end)}'
      '&filter_entity_id=${devices.join(',')}',
    );
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Error histórico HA: ${res.statusCode}');
    }
    final history = json.decode(res.body) as List<dynamic>;
    // Inicializa acumulador por dispositivo
    Map<String, double> resultado = {for (var d in devices) d: 0.0};

    for (int i = 0; i < history.length; i++) {
      final series = history[i] as List<dynamic>?;
      final device = devices[i];
      DateTime? prevT;
      double? prevP;
      if (series != null) {
        for (var pt in series) {
          final currT = DateTime.parse(pt['last_changed'] as String);
          final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
          if (prevT != null && prevP != null) {
            final dt = currT.difference(prevT).inSeconds;
            final avgP = (prevP + currP) / 2.0;
            resultado[device] = resultado[device]! + (avgP * dt / 3600000.0);
          }
          prevT = currT;
          prevP = currP;
        }
      }
    }
    return resultado;
  }

  // 6 estadísticas

  /// Mes de mayor consumo en el año actual
  Future<String> _mesMayorConsumo(List<String> devices) async {
    final now = DateTime.now();
    Map<String, double> mesTotales = {};
    for (int m = 1; m <= 12; m++) {
      final inicio = DateTime(now.year, m, 1);
      final fin = (m < 12)
          ? DateTime(now.year, m + 1, 1)
          : DateTime(now.year + 1, 1, 1);
      final c = await _fetchConsumoRange(inicio, fin, devices);
      final total = c.values.fold(0.0, (a, b) => a + b);
      mesTotales[_nombreMes(m)] = total;
    }
    final maxMes =
        mesTotales.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${maxMes.key} - ${maxMes.value.toStringAsFixed(2)} kWh';
  }

  /// Dispositivo que más consumió hoy
  Future<String> _dispositivoMasConsumioHoy(List<String> devices) async {
    final now = DateTime.now();
    final c = await _fetchConsumoRange(
        DateTime(now.year, now.month, now.day), now, devices);
    final maxDev = c.entries.reduce((a, b) => a.value > b.value ? a : b);
    final id = maxDev.key.replaceAll('sensor.', '').replaceAll('_power', '');
    return '$id - ${maxDev.value.toStringAsFixed(2)} kWh';
  }

  /// Dispositivo que más consumió en el mes anterior
  Future<String> _dispositivoMasConsumioMesAnterior(
      List<String> devices) async {
    final now = DateTime.now();
    final inicio = DateTime(now.year, now.month - 1, 1);
    final fin = DateTime(now.year, now.month, 1);
    final c = await _fetchConsumoRange(inicio, fin, devices);
    final maxDev = c.entries.reduce((a, b) => a.value > b.value ? a : b);
    final id = maxDev.key.replaceAll('sensor.', '').replaceAll('_power', '');
    return '$id - ${maxDev.value.toStringAsFixed(2)} kWh';
  }

  /// Integra trapezoidal y agrupa por hora (mes actual)
  Future<String> _horaPicoMesActual(List<String> devices) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    // Obtener datos brutos
    final raw = await _fetchHistoryRaw(start, now, devices);

    // Sumar energía (Wh) por cada hora del día
    Map<int, double> sumPorHora = {}; // hora (0–23) -> Wh
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2.0;
          final energyWh = avgP * dt / 3600.0;
          final hora = prevT.hour;
          sumPorHora[hora] = (sumPorHora[hora] ?? 0.0) + energyWh;
        }
        prevT = currT;
        prevP = currP;
      }
    }

    if (sumPorHora.isEmpty) return 'Sin datos';

    // Encuentra la hora con mayor energía consumida
    final peak = sumPorHora.entries.reduce((a, b) => a.value > b.value ? a : b);
    final horaStr = peak.key.toString().padLeft(2, '0') + ':00';
    // Convertir a kWh y formatear
    return '$horaStr - ${(peak.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// Integra trapezoidal y agrupa por día (semana actual)
  Future<String> _diaMayorSemana(List<String> devices) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    final raw = await _fetchHistoryRaw(start, now, devices);

    // Sumar energía por cada día ('YYYY-MM-DD')
    Map<String, double> sumPorDia = {};
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2.0;
          final energyWh = avgP * dt / 3600.0;
          final dia = prevT.toIso8601String().substring(0, 10);
          sumPorDia[dia] = (sumPorDia[dia] ?? 0.0) + energyWh;
        }
        prevT = currT;
        prevP = currP;
      }
    }

    if (sumPorDia.isEmpty) return 'Sin datos';

    // Encuentra el día de la semana con mayor consumo
    final peak = sumPorDia.entries.reduce((a, b) => a.value > b.value ? a : b);
    // Formatea la fecha legible
    return '${formatearFecha(peak.key)} - ${(peak.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// Integra trapezoidal y agrupa por día (mes actual)
  Future<String> _diaMayorMes(List<String> devices) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final raw = await _fetchHistoryRaw(start, now, devices);

    Map<String, double> sumPorDia = {};
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2.0;
          final energyWh = avgP * dt / 3600.0;
          final dia = prevT.toIso8601String().substring(0, 10);
          sumPorDia[dia] = (sumPorDia[dia] ?? 0.0) + energyWh;
        }
        prevT = currT;
        prevP = currP;
      }
    }

    if (sumPorDia.isEmpty) return 'Sin datos';

    // Encuentra el día del mes con mayor consumo
    final peak = sumPorDia.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${formatearFecha(peak.key)} - ${(peak.value / 1000).toStringAsFixed(2)} kWh';
  }

  // Helpers
  String _nombreMes(int m) {
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
    return meses[m - 1];
  }

  String formatearFecha(String fechaIso) {
    try {
      final fecha = DateTime.parse(fechaIso).toLocal();
      const dias = [
        'lunes',
        'martes',
        'miércoles',
        'jueves',
        'viernes',
        'sábado',
        'domingo'
      ];
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
      return '${dias[fecha.weekday - 1]} '
          '${fecha.day.toString().padLeft(2, '0')} de '
          '${meses[fecha.month - 1]} ${fecha.year}';
    } catch (_) {
      return fechaIso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: futureDevices,
      builder: (ctxDevices, snapDev) {
        if (!snapDev.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final devices = snapDev.data!;
        return FutureBuilder<List<String>>(
          future: Future.wait([
            _mesMayorConsumo(devices),
            _dispositivoMasConsumioHoy(devices),
            _dispositivoMasConsumioMesAnterior(devices),
            _horaPicoMesActual(devices),
            _diaMayorSemana(devices),
            _diaMayorMes(devices),
          ]),
          builder: (ctx, snapStats) {
            if (!snapStats.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final stats = snapStats.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                buildStatCard(
                  'Mes de mayor consumo (${DateTime.now().year})',
                  stats[0],
                ),
                buildStatCard(
                  'Dispositivo que más consumió hoy',
                  stats[1],
                ),
                buildStatCard(
                  'Dispositivo que más consumió en el mes anterior',
                  stats[2],
                ),
                buildStatCard(
                  'Horas pico de mayor consumo ($mesActualNombre)',
                  stats[3],
                ),
                buildStatCard(
                  'Día de mayor consumo (semana actual)',
                  stats[4],
                ),
                buildStatCard(
                  'Día de mayor consumo ($mesActualNombre)',
                  stats[5],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildStatCard(String titulo, String valor) {
    final ok = !valor.startsWith('Sin datos');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 2,
        color: ok ? Colors.white : Colors.grey.shade200,
        child: ListTile(
          leading: Icon(Icons.bolt, color: ok ? Colors.green : Colors.red),
          title:
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(valor),
        ),
      ),
    );
  }
}
