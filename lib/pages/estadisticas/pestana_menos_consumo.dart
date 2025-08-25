import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PestanaMenosConsumo extends StatefulWidget {
  const PestanaMenosConsumo({super.key});

  @override
  State<PestanaMenosConsumo> createState() => _PestanaMenosConsumoState();
}

class _PestanaMenosConsumoState extends State<PestanaMenosConsumo> {
  // URL y token de Nabu Casa desde .env
  final String haUrl = dotenv.env['HOME_ASSISTANT_URL']!;
  final String token = dotenv.env['HOME_ASSISTANT_TOKEN']!;

  // Encabezados HTTP para autenticación Bearer
  Map<String, String> get headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  // Futuro que carga la lista de sensores de potencia
  late Future<List<String>> futureDevices;

  @override
  void initState() {
    super.initState();
    futureDevices = _obtenerDispositivosPower();
  }

  /// 1) Obtiene todos los estados y filtra sensores que terminen en _power
  Future<List<String>> _obtenerDispositivosPower() async {
    final uri = Uri.parse('$haUrl/api/states');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Error HA: ${res.statusCode}');
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

  /// 2) Descarga histórico crudo para cada sensor en rango
  Future<List<List<Map<String, dynamic>>>> _fetchHistoryRaw(
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
    final decoded = json.decode(res.body) as List<dynamic>;
    return List.generate(devices.length, (i) {
      if (i < decoded.length && decoded[i] is List) {
        return List<Map<String, dynamic>>.from(decoded[i]);
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// 3) Integra trapezoidal y devuelve consumo kWh por sensor
  Future<Map<String, double>> _fetchConsumoRange(
      DateTime start, DateTime end, List<String> devices) async {
    final raw = await _fetchHistoryRaw(start, end, devices);
    final resultado = {for (var d in devices) d: 0.0};
    for (int i = 0; i < devices.length; i++) {
      DateTime? prevT;
      double? prevP;
      for (var pt in raw[i]) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2;
          resultado[devices[i]] = resultado[devices[i]]! + avgP * dt / 3600000;
        }
        prevT = currT;
        prevP = currP;
      }
    }
    return resultado;
  }

  // 6 estadísticas inversas:

  /// Mes de menor consumo (solo hasta mes actual)
  Future<String> _mesMenorConsumo(List<String> devices) async {
    final now = DateTime.now();
    final Map<String, double> totals = {};
    for (int m = 1; m <= now.month; m++) {
      final start = DateTime(now.year, m, 1);
      final end = (m < now.month)
          ? DateTime(now.year, m + 1, 1)
          : DateTime(now.year, now.month, now.day)
              .add(Duration(days: 1))
              .subtract(Duration(seconds: 1));
      final map = await _fetchConsumoRange(start, end, devices);
      totals[_nombreMes(m)] = map.values.fold(0.0, (a, b) => a + b);
    }
    if (totals.isEmpty) return 'Sin datos';
    final minEntry = totals.entries.reduce((a, b) => a.value < b.value ? a : b);
    return '${minEntry.key} - ${minEntry.value.toStringAsFixed(2)} kWh';
  }

  /// Dispositivo que menos consumió hoy (filtrando >0)
  Future<String> _dispositivoMenosHoy(List<String> devices) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: 1)).subtract(Duration(seconds: 1));
    final map = await _fetchConsumoRange(start, end, devices);
    final filtered = map.entries.where((e) => e.value > 0).toList();
    if (filtered.isEmpty) return '—';
    final minDev = filtered.reduce((a, b) => a.value < b.value ? a : b);
    final id = minDev.key.replaceAll('sensor.', '').replaceAll('_power', '');
    return '$id - ${minDev.value.toStringAsFixed(2)} kWh';
  }

  /// Dispositivo que menos consumió en mes anterior (filtrando >0)
  Future<String> _dispositivoMenosMesAnterior(List<String> devices) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, 1).subtract(Duration(seconds: 1));
    final map = await _fetchConsumoRange(start, end, devices);
    final filtered = map.entries.where((e) => e.value > 0).toList();
    if (filtered.isEmpty) return '—';
    final minDev = filtered.reduce((a, b) => a.value < b.value ? a : b);
    final id = minDev.key.replaceAll('sensor.', '').replaceAll('_power', '');
    return '$id - ${minDev.value.toStringAsFixed(2)} kWh';
  }

  /// Hora de menor consumo (mes actual), inicializando 0–23
  Future<String> _horaValleMesActual(List<String> devices) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final raw = await _fetchHistoryRaw(start, now, devices);
    final sumPorHora = {for (int h = 0; h < 24; h++) h: 0.0};
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2;
          sumPorHora[prevT.hour] = sumPorHora[prevT.hour]! + avgP * dt / 3600;
        }
        prevT = currT;
        prevP = currP;
      }
    }
    final minEntry =
        sumPorHora.entries.reduce((a, b) => a.value < b.value ? a : b);
    final hour = '${minEntry.key.toString().padLeft(2, '0')}:00';
    return '$hour - ${(minEntry.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// Día de menor consumo (semana actual), sólo desde lunes hasta hoy
  Future<String> _diaMenorSemana(List<String> devices) async {
    final now = DateTime.now();
    // Lunes de la semana
    final monday = now.subtract(Duration(days: now.weekday - 1));
    // Inicializa cada día desde lunes hasta hoy
    final sumPorDia = <String, double>{};
    for (int i = 0; i < now.weekday; i++) {
      final day = monday.add(Duration(days: i));
      final key = day.toIso8601String().substring(0, 10);
      sumPorDia[key] = 0.0;
    }
    // Descarga historial solo hasta instante actual
    final raw = await _fetchHistoryRaw(monday, now, devices);
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2;
          final key = prevT.toIso8601String().substring(0, 10);
          if (sumPorDia.containsKey(key)) {
            sumPorDia[key] = sumPorDia[key]! + avgP * dt / 3600;
          }
        }
        prevT = currT;
        prevP = currP;
      }
    }
    final minEntry =
        sumPorDia.entries.reduce((a, b) => a.value < b.value ? a : b);
    return '${formatearFecha(minEntry.key)} - ${(minEntry.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// Día de menor consumo (mes actual), sólo desde día 1 hasta hoy
  Future<String> _diaMenorMes(List<String> devices) async {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    // Inicializa solo los días hasta hoy
    final sumPorDia = <String, double>{};
    for (int d = 0; d < now.day; d++) {
      final day = firstOfMonth.add(Duration(days: d));
      final key = day.toIso8601String().substring(0, 10);
      sumPorDia[key] = 0.0;
    }
    // Historial desde inicio de mes hasta ahora
    final raw = await _fetchHistoryRaw(firstOfMonth, now, devices);
    for (var series in raw) {
      DateTime? prevT;
      double? prevP;
      for (var pt in series) {
        final currT = DateTime.parse(pt['last_changed'] as String);
        final currP = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
        if (prevT != null && prevP != null) {
          final dt = currT.difference(prevT).inSeconds;
          final avgP = (prevP + currP) / 2;
          final key = prevT.toIso8601String().substring(0, 10);
          if (sumPorDia.containsKey(key)) {
            sumPorDia[key] = sumPorDia[key]! + avgP * dt / 3600;
          }
        }
        prevT = currT;
        prevP = currP;
      }
    }
    final minEntry =
        sumPorDia.entries.reduce((a, b) => a.value < b.value ? a : b);
    return '${formatearFecha(minEntry.key)} - ${(minEntry.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// Devuelve nombre de mes en español
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

  /// Formatea fecha ISO a 'día de mes de año'
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
      builder: (ctxDev, snapDev) {
        if (!snapDev.hasData)
          return const Center(child: CircularProgressIndicator());
        final devices = snapDev.data!;
        return FutureBuilder<List<String>>(
          future: Future.wait([
            _mesMenorConsumo(devices),
            _dispositivoMenosHoy(devices),
            _dispositivoMenosMesAnterior(devices),
            _horaValleMesActual(devices),
            _diaMenorSemana(devices),
            _diaMenorMes(devices),
          ]),
          builder: (ctx, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final stats = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                buildStatCard(
                    'Mes de menor consumo (${DateTime.now().year})', stats[0]),
                buildStatCard('Dispositivo que menos consumió hoy', stats[1]),
                buildStatCard(
                    'Dispositivo que menos consumió en el mes anterior',
                    stats[2]),
                buildStatCard(
                    'Hora de menor consumo (${_nombreMes(DateTime.now().month)})',
                    stats[3]),
                buildStatCard('Día de menor consumo (semana actual)', stats[4]),
                buildStatCard(
                    'Día de menor consumo (${_nombreMes(DateTime.now().month)})',
                    stats[5]),
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
