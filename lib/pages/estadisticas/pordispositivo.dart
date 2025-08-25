import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fl_chart/fl_chart.dart';

/// Modelo para mini-gráficos de barras
class ChartBarData {
  final String label;
  final double value;
  ChartBarData({required this.label, required this.value});
}

class PorDispositivo extends StatefulWidget {
  const PorDispositivo({super.key});
  @override
  State<PorDispositivo> createState() => _PorDispositivoState();
}

class _PorDispositivoState extends State<PorDispositivo> {
  final String haUrl = dotenv.env['HOME_ASSISTANT_URL']!;
  final String token = dotenv.env['HOME_ASSISTANT_TOKEN']!;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  List<String> _devices = [];
  String? _selectedDevice;
  final List<String> _stats = [
    'Consumo total histórico',
    'Consumo mensual',
    'Promedio diario',
    'Hora mayor consumo promedio',
    'Hora menor consumo promedio',
    'Día semana mayor consumo',
    'Mes mayor consumo histórico',
  ];
  String _selectedStat = 'Consumo total histórico';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final uri = Uri.parse('$haUrl/api/states');
    final res = await http.get(uri, headers: _headers);
    final list = json.decode(res.body) as List<dynamic>;
    setState(() {
      _devices = list
          .map((e) => e['entity_id'] as String? ?? '')
          .where((id) =>
              id.startsWith('sensor.') &&
              id.endsWith('_power') &&
              !id.contains('_power_factor') &&
              !id.contains('_status'))
          .toList();
      if (_devices.isNotEmpty) _selectedDevice = _devices.first;
    });
  }

  String _displayName(String id) =>
      id.replaceFirst('sensor.', '').replaceFirst('_power', '');

  Future<List<Map<String, dynamic>>> _fetchHistoryRaw(
      DateTime start, DateTime end, String device) async {
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final uri = Uri.parse(
      '$haUrl/api/history/period/${iso(start)}'
      '?end_time=${iso(end)}'
      '&filter_entity_id=$device',
    );
    final res = await http.get(uri, headers: _headers);
    final decoded = json.decode(res.body) as List<dynamic>;
    return decoded.isNotEmpty
        ? List<Map<String, dynamic>>.from(decoded[0] as List)
        : <Map<String, dynamic>>[];
  }

  double _integralKWh(List<Map<String, dynamic>> series) {
    double sum = 0.0;
    DateTime? prevT;
    double? prevP;
    for (var pt in series) {
      final t = DateTime.parse(pt['last_changed'] as String);
      final p = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
      if (prevT != null && prevP != null) {
        final dt = t.difference(prevT).inSeconds;
        sum += ((prevP + p) / 2) * dt / 3600000;
      }
      prevT = t;
      prevP = p;
    }
    return sum;
  }

  Future<String> _consumoTotalHistorico(String dev) async {
    final data = await _fetchHistoryRaw(DateTime(2000), DateTime.now(), dev);
    return ' ${_integralKWh(data).toStringAsFixed(2)} kWh';
  }

  Future<String> _consumoMensual(String dev) async {
    final now = DateTime.now();
    final data =
        await _fetchHistoryRaw(DateTime(now.year, now.month, 1), now, dev);
    return '  ${_integralKWh(data).toStringAsFixed(2)} kWh';
  }

  Future<String> _promedioDiario(String dev) async {
    final now = DateTime.now();
    final data =
        await _fetchHistoryRaw(now.subtract(Duration(days: 7)), now, dev);
    final avg = _integralKWh(data) / 7;
    return ' ${avg.toStringAsFixed(2)} kWh/día';
  }

  Future<String> _horaExtremoPromedio(String dev, bool mayor) async {
    final now = DateTime.now();
    final raw =
        await _fetchHistoryRaw(now.subtract(Duration(days: 7)), now, dev);
    final byHour = <int, double>{for (var i = 0; i < 24; i++) i: 0.0};
    DateTime? prevT;
    double? prevP;
    for (var pt in raw) {
      final t = DateTime.parse(pt['last_changed'] as String);
      final p = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
      if (prevT != null && prevP != null) {
        final dt = t.difference(prevT).inSeconds;
        byHour[prevT.hour] =
            byHour[prevT.hour]! + ((prevP + p) / 2) * dt / 3600;
      }
      prevT = t;
      prevP = p;
    }
    final entry = byHour.entries.reduce((a, b) =>
        mayor ? (a.value > b.value ? a : b) : (a.value < b.value ? a : b));
    final label = '${entry.key.toString().padLeft(2, '0')}:00';
    return '  $label → ${(entry.value / 1000).toStringAsFixed(2)} kWh';
  }

  /// 6. Día de la semana con mayor consumo (mini-gráfico corregido)
  Future<List<ChartBarData>> _diaSemanaMayor(String device) async {
    final now = DateTime.now();
    // 1) Acumuladores por weekday (1=Lun … 7=Dom)
    final Map<int, List<double>> temp = {
      for (var wd = 1; wd <= 7; wd++) wd: []
    };

    // 2) Para cada día de la semana y para las 4 semanas anteriores
    for (var wd = 1; wd <= 7; wd++) {
      for (var w = 0; w < 4; w++) {
        final offset = (now.weekday - wd) + 7 * w;
        final day = now.subtract(Duration(days: offset));
        final start = DateTime(day.year, day.month, day.day);
        final end = start.add(const Duration(days: 1));
        final raw = await _fetchHistoryRaw(start, end, device);
        temp[wd]!.add(_integralKWh(raw));
      }
    }

    // 3) Nombres abreviados y cálculo de promedio
    const names = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return List.generate(7, (i) {
      final lista = temp[i + 1]!;
      final avg =
          lista.isEmpty ? 0.0 : lista.reduce((a, b) => a + b) / lista.length;
      return ChartBarData(label: names[i], value: avg);
    });
  }

  Future<String> _mesMayorHistorico(String dev) async {
    final now = DateTime.now();
    final totals = <String, double>{};
    for (var m = 1; m <= now.month; m++) {
      final start = DateTime(now.year, m, 1);
      final end = m < now.month ? DateTime(now.year, m + 1, 1) : now;
      final data = await _fetchHistoryRaw(start, end, dev);
      totals[_nombreMes(m)] = _integralKWh(data);
    }
    final entry = totals.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '  ${entry.key} → ${entry.value.toStringAsFixed(2)} kWh';
  }

  String _nombreMes(int m) {
    const meses = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    return meses[m - 1];
  }

  Widget _buildContent() {
    if (_selectedDevice == null) return const SizedBox();
    final dev = _selectedDevice!;
    switch (_selectedStat) {
      case 'Consumo total histórico':
        return FutureBuilder<String>(
          future: _consumoTotalHistorico(dev),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      case 'Consumo mensual':
        return FutureBuilder<String>(
          future: _consumoMensual(dev),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.date_range, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      case 'Promedio diario':
        return FutureBuilder<String>(
          future: _promedioDiario(dev),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      case 'Hora mayor consumo promedio':
        return FutureBuilder<String>(
          future: _horaExtremoPromedio(dev, true),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      case 'Hora menor consumo promedio':
        return FutureBuilder<String>(
          future: _horaExtremoPromedio(dev, false),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.nights_stay, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      case 'Día semana mayor consumo':
        return FutureBuilder<List<ChartBarData>>(
          future: _diaSemanaMayor(_selectedDevice!),
          builder: (ctx, snap) {
            if (!snap.hasData) return const CircularProgressIndicator();
            final data = snap.data!;

            // Encuentro el pico (mayor valor)
            final peak = data.reduce((a, b) => a.value > b.value ? a : b);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) =>
                                Text(data[v.toInt()].label),
                          ),
                        ),
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: data.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(toY: e.value.value, width: 16),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '${peak.value.toStringAsFixed(2)} kWh',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            );
          },
        );

      case 'Mes mayor consumo histórico':
        return FutureBuilder<String>(
          future: _mesMayorHistorico(dev),
          builder: (c, s) => s.hasData
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 32),
                    const SizedBox(width: 8),
                    Text(s.data!, style: const TextStyle(fontSize: 24)),
                  ],
                )
              : const CircularProgressIndicator(),
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Por Dispositivo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedDevice,
              items: _devices
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(_displayName(d)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDevice = v),
              decoration: const InputDecoration(labelText: 'Sensor'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedStat,
              items: _stats
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedStat = v!),
              decoration: const InputDecoration(labelText: 'Métrica'),
            ),
            const SizedBox(height: 20),
            Expanded(child: Center(child: _buildContent())),
          ],
        ),
      ),
    );
  }
}
