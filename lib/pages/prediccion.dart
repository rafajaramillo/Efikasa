import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Widget que proyecta el consumo mensual usando regresión lineal simple
class PrediccionConsumo extends StatefulWidget {
  /// Constructor por defecto
  const PrediccionConsumo({super.key});

  @override
  State<PrediccionConsumo> createState() => _PrediccionConsumoState();
}

class _PrediccionConsumoState extends State<PrediccionConsumo> {
  // URL base de la API de Home Assistant, leída de .env
  late final String _apiUrl;
  // Token de autenticación para llamadas a la API
  late final String _authToken;
  // Lista donde almacenamos los kWh de cada mes histórico
  List<double> consumosMensuales = [];
  // Indicador de carga de datos
  bool isLoading = true;
  // Número de meses que deseamos predecir (1–12)
  int mesesAPredecir = 3;

  @override
  void initState() {
    super.initState();
    // Al iniciar el widget, cargamos la URL y el token del entorno
    _apiUrl = dotenv.env['HOME_ASSISTANT_URL']?.trim() ?? '';
    _authToken = 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']?.trim() ?? ''}';
    // Comenzar a obtener los consumos históricos
    _cargarConsumos();
  }

  /// Obtiene la lista de sensores de energía (unidad kWh) desde la API de estados
  Future<List<String>> _fetchEnergySensors() async {
    try {
      // Petición GET a /api/states para obtener todos los estados
      final res = await http.get(
        Uri.parse('$_apiUrl/api/states'),
        headers: {'Authorization': _authToken},
      );
      // Si la respuesta es 200 OK
      if (res.statusCode == 200) {
        // Decodificar el JSON como lista dinámica
        final all = json.decode(res.body) as List<dynamic>;
        // Filtrar solo las entidades tipo sensor con unidad kWh
        return all
            .where((s) {
              final eid = s['entity_id'] as String?;
              final attrs = s['attributes'] as Map<String, dynamic>?;
              return eid != null &&
                  eid.startsWith('sensor.') &&
                  attrs?['unit_of_measurement'] == 'kWh';
              // Mapear al campo entity_id
            })
            .map((s) => s['entity_id'] as String)
            .toList();
      }
    } catch (_) {
      // En caso de error de red o parseo, caemos al respaldo
    }
    // Si falla o no hay sensores, usar sensor.total_energy por defecto
    return ['sensor.total_energy'];
  }

  /// Recupera la historia de un sensor entre fechas start y end
  Future<List<Map<String, dynamic>>> _fetchHistoryRaw(
      DateTime start, DateTime end, String sensor) async {
    // Función interna para formatear DateTime a ISO sin milisegundos
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z\$'), 'Z');
    // Construir la URI con periodo y filtro de sensor
    final uri = Uri.parse(
      '$_apiUrl/api/history/period/${iso(start)}'
      '?end_time=${iso(end)}&filter_entity_id=$sensor',
    );
    try {
      // Petición GET a la API de history
      final res = await http.get(uri, headers: {'Authorization': _authToken});
      // Decodificar la respuesta JSON
      final decoded = json.decode(res.body) as List<dynamic>;
      // La API devuelve lista de listas; tomamos el primer sub-listado
      if (decoded.isNotEmpty && decoded[0] is List) {
        return List<Map<String, dynamic>>.from(decoded[0]);
      }
    } catch (_) {
      // Ignorar errores y devolver lista vacía
    }
    return [];
  }

  /// Integra la serie de potencias para obtener kWh totales (método trapezoidal)
  double _integralKWh(List<Map<String, dynamic>> series) {
    double sumKwh = 0.0;
    DateTime? prevT;
    double? prevP;
    // Iterar sobre cada punto de la serie
    for (final pt in series) {
      // Timestamp actual
      final ts = DateTime.parse(pt['last_changed'] as String);
      // Potencia actual (en W)
      final p = double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;
      // Si existe punto anterior, calcular área del trapecio
      if (prevT != null && prevP != null) {
        final dtSec = ts.difference(prevT).inSeconds;
        sumKwh += ((prevP + p) / 2) * dtSec / 3600000.0;
      }
      prevT = ts;
      prevP = p;
    }
    return sumKwh;
  }

  /// Carga los consumos de los últimos 3 meses y actualiza el estado
  Future<void> _cargarConsumos() async {
    // 1) Obtener sensores de energía
    final sensors = await _fetchEnergySensors();
    // 2) Fecha actual
    final now = DateTime.now();
    // Lista temporal para almacenar cada total mensual
    final temp = <double>[];
    // 3) Iterar los últimos 3 meses: i=2 (hace 2 meses)…0 (mes actual)
    for (int i = 2; i >= 0; i--) {
      final inicio = DateTime(now.year, now.month - i, 1);
      final fin = DateTime(now.year, now.month - i + 1, 1);
      double monthTotal = 0.0;
      // 4) Para cada sensor, sumar su integral de consumo en el mes
      for (final sensor in sensors) {
        final history = await _fetchHistoryRaw(inicio, fin, sensor);
        monthTotal += _integralKWh(history);
      }
      // Agregar total del mes a la lista
      temp.add(monthTotal);
    }
    // 5) Actualizar estado y ocultar spinner
    setState(() {
      consumosMensuales = temp;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Si aún carga, mostrar indicador
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Preparar datos para regresión lineal
    final indices = List.generate(consumosMensuales.length, (i) => i + 1);
    final y = consumosMensuales;
    final n = y.length;
    final sumX = indices.reduce((a, b) => a + b);
    final sumY = y.reduce((a, b) => a + b);
    final sumXY =
        List.generate(n, (i) => indices[i] * y[i]).reduce((a, b) => a + b);
    final sumX2 = indices.map((x) => x * x).reduce((a, b) => a + b);
    // Cálculo de pendiente (m) y ordenada (b)
    final m = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final b = (sumY - m * sumX) / n;
    // Generar predicciones para los próximos meses seleccionados
    final predicciones = List.generate(
      mesesAPredecir,
      (i) => m * (n + i + 1) + b,
    );

    // Construir la UI principal
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proyección con Regresión Lineal',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 114, 6, 2),
        leading: const BackButton(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selector desplegable de meses a predecir
            Row(
              children: [
                const Text('Meses a predecir: '),
                DropdownButton<int>(
                  value: mesesAPredecir,
                  items: List.generate(12, (i) => i + 1)
                      .map((val) => DropdownMenuItem(
                            value: val,
                            child: Text(val == 1 ? '1 mes' : '$val meses'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => mesesAPredecir = v!),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Gráfico de barras con eje Y derecho
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY:
                      (y + predicciones).reduce((a, b) => a > b ? a : b) * 1.1,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt() - 1;
                          final dt = DateTime.now();
                          final monthDate = DateTime(
                            dt.year,
                            dt.month - y.length + idx + 1,
                          );
                          const monthNames = [
                            'ENE',
                            'FEB',
                            'MAR',
                            'ABR',
                            'MAY',
                            'JUN',
                            'JUL',
                            'AGO',
                            'SEP',
                            'OCT',
                            'NOV',
                            'DIC'
                          ];
                          return Text(monthNames[monthDate.month - 1]);
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    y.length + predicciones.length,
                    (i) {
                      final value =
                          i < y.length ? y[i] : predicciones[i - y.length];
                      return BarChartGroupData(
                        x: i + 1,
                        barRods: [BarChartRodData(toY: value)],
                        barsSpace: 4,
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Tabla con mes y consumo proyectado
            DataTable(
              columns: const [
                DataColumn(label: Text('Mes')),
                DataColumn(label: Text('Consumo (kWh)')),
              ],
              rows: List.generate(predicciones.length, (i) {
                final mesDate = DateTime(
                    DateTime.now().year, DateTime.now().month + i + 1, 1);
                const monthNames = [
                  'ENE',
                  'FEB',
                  'MAR',
                  'ABR',
                  'MAY',
                  'JUN',
                  'JUL',
                  'AGO',
                  'SEP',
                  'OCT',
                  'NOV',
                  'DIC'
                ];
                return DataRow(cells: [
                  DataCell(Text(monthNames[mesDate.month - 1])),
                  DataCell(Text(predicciones[i].toStringAsFixed(2))),
                ]);
              }),
            ),
          ],
        ),
      ),
      // Botón flotante para exportar PDF
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              build: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Proyección con Regresión Lineal',
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                  pw.Table.fromTextArray(
                    headers: ['Mes', 'Consumo (kWh)'],
                    data: List<List<String>>.generate(
                      predicciones.length,
                      (i) {
                        final mesDate = DateTime(DateTime.now().year,
                            DateTime.now().month + i + 1, 1);
                        const monthNames = [
                          'ENE',
                          'FEB',
                          'MAR',
                          'ABR',
                          'MAY',
                          'JUN',
                          'JUL',
                          'AGO',
                          'SEP',
                          'OCT',
                          'NOV',
                          'DIC'
                        ];
                        return [
                          monthNames[mesDate.month - 1],
                          predicciones[i].toStringAsFixed(2)
                        ];
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
          final bytes = await pdf.save();
          await Printing.sharePdf(
              bytes: bytes, filename: 'proyeccion_consumo.pdf');
        },
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label:
            const Text('Exportar PDF', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 114, 6, 2),
      ),
    );
  }
}
