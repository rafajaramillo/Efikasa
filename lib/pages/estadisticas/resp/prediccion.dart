// Widget para mostrar predicciones de consumo energético obteniendo datos desde Home Assistant

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
//import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PrediccionConsumo extends StatefulWidget {
  const PrediccionConsumo({super.key});

  @override
  State<PrediccionConsumo> createState() => _PrediccionConsumoState();
}

class _PrediccionConsumoState extends State<PrediccionConsumo> {
  //final String apiUrl = 'http://192.168.0.121:8123/api/history/period/';
  final String apiUrl =
      '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/';
  final String authToken = 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}';

  List<double> consumosMensuales = [];
  List<String> mesesSinDatos = [];
  bool isLoading = true;
  int mesesAPredecir = 3;
  List<List<dynamic>>? prediccionesCSV;

  @override
  void initState() {
    super.initState();
    obtenerConsumoMensual();
  }

  Future<void> obtenerConsumoMensual() async {
    final now = DateTime.now();
    final List<double> consumos = [];
    final List<String> mesesSinData = [];

    for (int i = 5; i >= 0; i--) {
      final inicio = DateTime(now.year, now.month - i, 1);
      final fin = DateTime(now.year, now.month - i + 1, 1);

      final response = await http.get(
        Uri.parse(
            '${apiUrl}${inicio.toIso8601String()}?end_time=${fin.toIso8601String()}'),
        headers: {
          'Authorization': authToken,
          'Content-Type': 'application/json',
        },
      );

      double totalKwh = 0.0;
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        for (var registro in data) {
          for (int i = 1; i < registro.length; i++) {
            var anterior = registro[i - 1];
            var actual = registro[i];

            if (anterior['state'] != 'unavailable' &&
                actual['state'] != 'unavailable') {
              double? potenciaW = double.tryParse(anterior['state']);
              DateTime t1 = DateTime.parse(anterior['last_changed']);
              DateTime t2 = DateTime.parse(actual['last_changed']);
              if (potenciaW != null) {
                int duracion = t2.difference(t1).inSeconds;
                totalKwh += (potenciaW * duracion) / (1000 * 3600);
              }
            }
          }
        }
      }

      consumos.add(totalKwh);
      if (totalKwh == 0.0) {
        mesesSinData.add("${inicio.month}/${inicio.year}");
      }
    }

    setState(() {
      consumosMensuales = consumos;
      mesesSinDatos = mesesSinData;
      isLoading = false;
    });

    if (mesesSinData.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Meses sin datos: ${mesesSinData.join(', ')}"),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  void prepararCSV(List<double> predicciones) {
    final List<List<dynamic>> csv = [
      ['Mes Futuro', 'Consumo (kWh)'],
      for (int i = 0; i < predicciones.length; i++)
        ['+${i + 1} mes', predicciones[i].toStringAsFixed(2)]
    ];
    prediccionesCSV = csv;
  }

  Future<void> exportarPDF(List<double> predicciones) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/predicciones_consumo.pdf';
    final file = File(path);

    final buffer = StringBuffer();
    buffer.writeln('Predicciones de Consumo Energético');
    buffer.writeln('------------------------------');
    for (int i = 0; i < predicciones.length; i++) {
      buffer
          .writeln('+${i + 1} mes: ${predicciones[i].toStringAsFixed(2)} kWh');
    }

    await file.writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF guardado en: $path')),
      );
    }
  }

  Widget _buildGraficos(List<double> predicciones) {
    final puntos = List.generate(predicciones.length,
        (i) => FlSpot((i + 1).toDouble(), predicciones[i]));
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: true),
              titlesData: FlTitlesData(
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: true)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: true)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: puntos,
                  isCurved: true,
                  color: Colors.deepOrange,
                  barWidth: 4,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(
                      show: true, color: Colors.orange.withOpacity(0.3)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 1.6,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: BarChart(
              BarChartData(
                barGroups: List.generate(predicciones.length, (i) {
                  return BarChartGroupData(
                    x: i + 1,
                    barRods: [
                      BarChartRodData(
                        toY: predicciones[i],
                        color: Colors.orange,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      )
                    ],
                  );
                }),
                borderData: FlBorderData(show: true),
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  bottomTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: true)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTablaPredicciones(List<double> predicciones) {
    return Table(
      border: TableBorder.all(color: Colors.grey),
      columnWidths: const {
        0: FixedColumnWidth(120),
        1: FlexColumnWidth(),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Colors.black12),
          children: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Mes Futuro",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Consumo (kWh)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        ...List.generate(predicciones.length, (i) {
          return TableRow(children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("+${i + 1} mes"),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(predicciones[i].toStringAsFixed(2)),
            ),
          ]);
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (consumosMensuales.length < 2) {
      return const Scaffold(
        body: Center(
          child: Text(
            "No hay suficientes datos históricos para generar predicciones.",
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final meses = List.generate(consumosMensuales.length, (i) => i + 1);
    final n = meses.length;
    final sumX = meses.reduce((a, b) => a + b);
    final sumY = consumosMensuales.reduce((a, b) => a + b);
    final sumXY = List.generate(n, (i) => meses[i] * consumosMensuales[i])
        .reduce((a, b) => a + b);
    final sumX2 = meses.map((x) => x * x).reduce((a, b) => a + b);
    final m = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final b = (sumY - m * sumX) / n;

    final predicciones =
        List.generate(mesesAPredecir, (i) => m * (n + i + 1) + b);
    prepararCSV(predicciones);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Predicción de Consumo',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 114, 6, 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => exportarPDF(predicciones),
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label:
            const Text('Exportar PDF', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 114, 6, 2),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Meses a predecir: ",
                    style: TextStyle(fontSize: 16)),
                DropdownButton<int>(
                  value: mesesAPredecir,
                  items: [1, 2, 3, 4, 5, 6]
                      .map((e) =>
                          DropdownMenuItem<int>(value: e, child: Text("$e")))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        mesesAPredecir = value;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildGraficos(predicciones),
            const SizedBox(height: 16),
            _buildTablaPredicciones(predicciones),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
