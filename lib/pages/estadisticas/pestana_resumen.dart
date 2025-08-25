import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:efikasa/pages/global_tarifa.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Esta clase representa la pestaña de resumen general de consumo energético.

class PestanaResumen extends StatelessWidget {
  const PestanaResumen({super.key});

  /// Obtiene el consumo en kWh para día, semana, mes y año.
  /// Hace una única petición histórica y reparte los consumos por rangos con integración trapezoidal.
  Future<Map<String, dynamic>> obtenerResumenGeneral() async {
    try {
      // 1) Configurar conexión a Home Assistant
      final String haUrl = dotenv.env['HOME_ASSISTANT_URL']!;
      final String token = dotenv.env['HOME_ASSISTANT_TOKEN']!;
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // 2) Obtener lista de sensores de potencia (_power)
      final uriStates = Uri.parse('$haUrl/api/states');
      final resStates = await http
          .get(uriStates, headers: headers)
          .timeout(const Duration(seconds: 5));
      if (resStates.statusCode != 200) {
        throw Exception('Error al obtener estados: ${resStates.statusCode}');
      }
      final entities = json.decode(resStates.body) as List<dynamic>;
      final devices = entities
          .map((e) => e['entity_id'] as String? ?? '')
          .where((id) =>
              id.startsWith('sensor.') &&
              id.endsWith('_power') &&
              !id.endsWith('_power_factor'))
          .toList();

      // 3) Definir ahora y límites de rangos
      final now = DateTime.now();
      final startYear = now.subtract(const Duration(days: 365));
      final startMonth = now.subtract(const Duration(days: 30));
      final startWeek = now.subtract(const Duration(days: 7));
      final startDay = DateTime(now.year, now.month, now.day);

      // 4) Formato ISO sin milisegundos
      String toIsoNoMs(DateTime dt) =>
          dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
      final startIso = toIsoNoMs(startYear);
      final endIso = toIsoNoMs(now); // instante actual truncado

      // 5) Petición única de historial para todos los sensores
      final filter = devices.join(',');
      final uriHistory = Uri.parse(
        '$haUrl/api/history/period/$startIso'
        '?end_time=$endIso'
        '&filter_entity_id=$filter',
      );
      final resHistory = await http
          .get(uriHistory, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (resHistory.statusCode != 200) {
        throw Exception('Error HA API historial: ${resHistory.statusCode}');
      }
      final history = json.decode(resHistory.body) as List<dynamic>;

      // 6) Inicializar acumuladores de energía (kWh)
      double totalYear = 0.0;
      double totalMonth = 0.0;
      double totalWeek = 0.0;
      double totalDay = 0.0;

      // 7) Distribuir energía por rangos usando integración trapezoidal
      for (var series in history) {
        if (series is List) {
          DateTime? prevTime;
          double? prevPower;
          for (var pt in series) {
            final currTime = DateTime.parse(pt['last_changed'] as String);
            final currPower =
                double.tryParse(pt['state']?.toString() ?? '') ?? 0.0;

            if (prevTime != null && prevPower != null) {
              final deltaSec = currTime.difference(prevTime).inSeconds;
              final avgPower = (prevPower + currPower) / 2.0;
              final energy = avgPower * deltaSec / 3600000.0;

              // Acumular energía en cada rango
              totalYear += energy;
              if (currTime.isAfter(startMonth)) totalMonth += energy;
              if (currTime.isAfter(startWeek)) totalWeek += energy;
              if (currTime.isAfter(startDay)) totalDay += energy;
            }

            prevTime = currTime;
            prevPower = currPower;
          }
        }
      }

      // 8) Formatear y devolver resultados
      return {
        'dia': totalDay.toStringAsFixed(2),
        'semana': totalWeek.toStringAsFixed(2),
        'mes': totalMonth.toStringAsFixed(2),
        'anio': totalYear.toStringAsFixed(2),
        'promedio': (totalWeek / 7).toStringAsFixed(2),
      };
    } catch (e, st) {
      debugPrint('Error en obtenerResumenGeneral: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  String formatoDolares(double valor) {
    final formatter = NumberFormat.simpleCurrency(decimalDigits: 2);
    return formatter.format(valor);
  }

  Color getColorPorNivel(double kwh) {
    if (kwh < 5) return Colors.green.shade100;
    if (kwh < 20) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  Widget buildStatCardMoneda(
      String titulo, String kwhStr, IconData iconKwh, IconData iconUsd) {
    final double kwh = double.tryParse(kwhStr) ?? 0.0;
    final double totalUSD = kwh * tarifaKwHGlobal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: getColorPorNivel(kwh),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                children: [
                  Icon(iconKwh, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconKwh, size: 16, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      '$kwhStr kWh',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconUsd, size: 16, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      formatoDolares(totalUSD),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void exportarResumenPDF(Map<String, dynamic> data) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("Resumen de Consumo Energético",
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            ...data.entries.map((e) => pw.Text(
                "${e.key.toUpperCase()}: ${e.value} kWh | \$${(double.parse(e.value) * tarifaKwHGlobal).toStringAsFixed(2)}")),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (format) => doc.save(),
      name: 'Resumen de Consumo Energético',
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: FutureBuilder<Map<String, dynamic>>(
        future: obtenerResumenGeneral(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Ocupamos todo el alto de la pantalla menos AppBar y notch
            final fullHeight = MediaQuery.of(context).size.height -
                kToolbarHeight -
                MediaQuery.of(context).padding.top;

            return SizedBox(
              height: fullHeight,
              width: double.infinity,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.access_time, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Cargando resumen…',
                      style:
                          TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            );
          } else if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar resumen'));
          } else {
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildStatCardMoneda('Consumo total diario', data["dia"],
                    Icons.calendar_today, Icons.attach_money),
                buildStatCardMoneda('Consumo total ultimos 7 dias',
                    data["semana"], Icons.date_range, Icons.money),
                buildStatCardMoneda('Consumo total mensual', data["mes"],
                    Icons.calendar_view_month, Icons.monetization_on),
                buildStatCardMoneda('Consumo total anual', data["anio"],
                    Icons.event, Icons.euro),
                buildStatCardMoneda('Promedio diario (ultimos 7 dias)',
                    data["promedio"], Icons.show_chart, Icons.price_change),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: () => exportarResumenPDF(data),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Exportar Resumen a PDF"),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}
