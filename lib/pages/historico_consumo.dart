import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math';
import 'global_tarifa.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HistoricoConsumo extends StatefulWidget {
  const HistoricoConsumo({super.key});

  @override
  _HistoricoConsumoState createState() => _HistoricoConsumoState();
}

class _HistoricoConsumoState extends State<HistoricoConsumo> {
  //final String apiUrl = 'http://192.168.0.121:8123/api/history/period/';
  final String apiUrl =
      '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/';
  final String authToken =
      'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}'; // Reemplaza con tu token de Home Assistant

  late DateTime fechaInicio;
  late DateTime fechaFin;
  late String fechaInicioStr;
  late String fechaFinStr;

  Map<String, double> consumoDispositivos = {};
  Map<String, Color> deviceColors = {};
  bool isLoading = true;
  int selectedChart = 0;

  @override
  void initState() {
    super.initState();
    calcularRangoFechas();
    fetchConsumo();
  }

  void calcularRangoFechas() {
    fechaFin = DateTime.now();
    fechaInicio = fechaFin.subtract(
        Duration(days: fechaFin.weekday - 1)); // Lunes de la semana actual
    fechaInicioStr = fechaInicio.toIso8601String();
    fechaFinStr = fechaFin.toIso8601String();
  }

  Future<void> seleccionarFechas() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: fechaInicio, end: fechaFin),
    );
    if (picked != null) {
      setState(() {
        fechaInicio = picked.start;
        fechaFin = picked.end;
        fechaInicioStr = fechaInicio.toIso8601String();
        fechaFinStr = fechaFin.toIso8601String();
        isLoading = true;
      });
      fetchConsumo();
    }
  }

  Future<void> fetchConsumo() async {
    consumoDispositivos.clear();
    deviceColors.clear();

    List<Color> colorPalette = [
      Colors.blue,
      Colors.green,
      Colors.red,
      Colors.orange,
      Colors.purple,
      Colors.yellow,
      Colors.cyan,
      Colors.teal,
      Colors.pink,
      Colors.brown
    ];

    final dispositivosResponse = await http.get(
      Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states'),
      headers: {'Authorization': authToken, 'Content-Type': 'application/json'},
    );

    if (dispositivosResponse.statusCode == 200) {
      List<dynamic> dispositivos = json.decode(dispositivosResponse.body);
      List<String> dispositivosZigbee = dispositivos
          .where((d) =>
              d['entity_id'].contains('_power') &&
              !d['entity_id'].contains('_factor') &&
              !d['entity_id'].contains('_status'))
          .map<String>((d) => d['entity_id'].toString())
          .toList();

      int colorIndex = 0;
      for (String dispositivo in dispositivosZigbee) {
        deviceColors[dispositivo] =
            colorPalette[colorIndex % colorPalette.length];
        colorIndex++;
      }

      for (String dispositivo in dispositivosZigbee) {
        final response = await http.get(
          Uri.parse(
              '$apiUrl$fechaInicioStr?end_time=$fechaFinStr&filter_entity_id=$dispositivo'),
          headers: {
            'Authorization': authToken,
            'Content-Type': 'application/json'
          },
        );

        if (response.statusCode == 200) {
          List<dynamic> data = json.decode(response.body);
          if (data.isNotEmpty) {
            /*     Para obtener energía en kWh reales, se procede de la siguiente manera:
            1. Leer el valor de potencia (W o kW) en intervalos de tiempo conocidos (por ejemplo, cada 5 minutos, cada 1 hora).
            2. Convertir la potencia a energía con esta fórmula: kWh = (Potencia_Watt × Intervalo_segundos) / (1000 × 3600)
            3. Esto nos da los kWh consumidos entre cada muestra.
            4. Finalmente. se suman todos esos kWh entre intervalos para obtener el consumo total. */

            double totalConsumo = 0.0;
            for (int i = 1; i < data[0].length; i++) {
              var prev = data[0][i - 1];
              var curr = data[0][i];

              if (prev['state'] != 'unavailable' &&
                  curr['state'] != 'unavailable') {
                double? powerPrev = double.tryParse(prev['state']);
                double? powerCurr = double.tryParse(curr['state']);
                DateTime t1 = DateTime.parse(prev['last_changed']);
                DateTime t2 = DateTime.parse(curr['last_changed']);

                if (powerPrev != null && powerCurr != null) {
                  final deltaSec = t2.difference(t1).inSeconds;
                  final avgPower = (powerPrev + powerCurr) / 2.0; // W promedio
                  // W·s → Wh → kWh
                  final energiaKwh = (avgPower * deltaSec) / 3600000.0;
                  totalConsumo += energiaKwh;
                }
              }
            }

            consumoDispositivos[dispositivo] = totalConsumo;
          }
        }
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Widget buildBarChart() {
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: consumoDispositivos.entries.map((entry) {
                return BarChartGroupData(
                  x: consumoDispositivos.keys.toList().indexOf(entry.key),
                  barRods: [
                    BarChartRodData(
                      toY: entry.value,
                      color: deviceColors[entry.key] ?? Colors.grey,
                      width: 16,
                      borderRadius: BorderRadius.zero,
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Sensores',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget buildChart() {
    consumoDispositivos.values.fold(0.0, (sum, value) => sum + value) / 1000;

    if (selectedChart == 0) {
      return buildBarChart();
    } else if (selectedChart == 1) {
      return buildPieChart();
    } else if (selectedChart == 2) {
      return buildLineChart();
    } else if (selectedChart == 3) {
      return buildRadialBarChart();
    } else if (selectedChart == 4) {
      return buildCO2Emission();
    } else {
      return consumoDolares();
    }
  }

  Widget buildPieChart() {
    return PieChart(
      PieChartData(
        sections: consumoDispositivos.entries.map((entry) {
          return PieChartSectionData(
            value: entry.value,
            color: deviceColors[entry.key] ?? Colors.grey,
            title: entry.value.toStringAsFixed(1),
            radius: 50,
          );
        }).toList(),
      ),
    );
  }

  Widget buildLineChart() {
    if (consumoDispositivos.isEmpty) {
      return Center(child: Text("No hay datos de consumo"));
    }

    // 1) Trata los valores como kWh
    final double maxConsumo = consumoDispositivos.values.reduce(max);
    final String unidad = 'kWh';

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                drawVerticalLine: true,
                horizontalInterval: maxConsumo / 5,
                verticalInterval: 1,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: Colors.grey.withOpacity(0.5), strokeWidth: 1),
                getDrawingVerticalLine: (v) =>
                    FlLine(color: Colors.grey.withOpacity(0.5), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxConsumo / 5,
                    getTitlesWidget: (v, meta) => Text(
                      '${v.toStringAsFixed(1)} $unidad',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: false,
                    interval: 1, // un tick por índice
                    getTitlesWidget: (i, meta) {
                      final keys = consumoDispositivos.keys.toList();
                      if (i.toInt() >= 0 && i.toInt() < keys.length) {
                        return Transform.rotate(
                          angle:
                              -pi / 4, // opcional: gira 45º para que no solape
                          child: Text(keys[i.toInt()],
                              style: TextStyle(fontSize: 9)),
                        );
                      }
                      return Container();
                    },
                  ),
                ),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.black, width: 1),
              ),
              minY: 0,
              maxY: maxConsumo * 1.1,
              lineBarsData: consumoDispositivos.entries.map((entry) {
                final device = entry.key;
                final x = consumoDispositivos.keys
                    .toList()
                    .indexOf(device)
                    .toDouble();
                final y = entry.value; // ya en kWh
                return LineChartBarData(
                  spots: [FlSpot(x, y)],
                  isCurved: true,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  color: deviceColors[device], // color según dispositivo
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /*  Widget buildRadialBarChart() {
    return Column(
      children: [
        Expanded(
          child: SfCircularChart(
            title: ChartTitle(text: 'Consumo por Dispositivo'),
            //legend: Legend(isVisible: true),
            series: <RadialBarSeries<MapEntry<String, double>, String>>[
              RadialBarSeries<MapEntry<String, double>, String>(
                dataSource: consumoDispositivos.entries.toList(),
                xValueMapper: (entry, _) => entry.key,
                yValueMapper: (entry, _) => entry.value / 1000,
                pointColorMapper: (entry, _) =>
                    deviceColors[entry.key] ?? Colors.grey,
                dataLabelSettings: DataLabelSettings(isVisible: true),
              )
            ],
          ),
        ),
      ],
    );
  } */

  Widget buildRadialBarChart() {
    return Column(
      children: [
        Expanded(
          child: SfCircularChart(
            title: ChartTitle(text: 'Consumo por Dispositivo'),
            series: <RadialBarSeries<MapEntry<String, double>, String>>[
              RadialBarSeries<MapEntry<String, double>, String>(
                dataSource: consumoDispositivos.entries.toList(),
                xValueMapper: (entry, _) => entry.key,
                // Los valores ya están en kWh
                yValueMapper: (entry, _) => entry.value,
                pointColorMapper: (entry, _) =>
                    deviceColors[entry.key] ?? Colors.grey,
                dataLabelSettings: DataLabelSettings(
                  isVisible: true,
                  // opcional: ajustar posición o estilo
                ),
                // Aquí se define el texto exacto de la etiqueta
                dataLabelMapper: (entry, _) =>
                    '${entry.value.toStringAsFixed(2)} kWh',
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget buildCO2Emission() {
    // 1) Sumar todos los consumos (kWh) por dispositivo
    final double totalKwh =
        consumoDispositivos.values.fold(0.0, (sum, value) => sum + value);

    // 2) Calcular emisión de CO₂: 0.5 kg CO₂/kWh
    final double co2Kg = totalKwh * 0.5;
    final bool usarGramos = co2Kg < 1.0;
    final double totalCO2 = usarGramos ? co2Kg * 1000.0 : co2Kg;
    final String unidadCO2 = usarGramos ? 'g' : 'kg';

    // 3) Mostrar en UI
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Emisión de CO₂
          Column(
            children: [
              const SizedBox(height: 50),
              const Icon(
                Icons.cloud_outlined,
                color: Colors.green,
                size: 60,
              ),
              const SizedBox(height: 8),
              const Text(
                'Total CO₂ Emitido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                '${totalCO2.toStringAsFixed(2)} $unidadCO2',
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          // Consumo diario
          Column(
            children: [
              const SizedBox(height: 50),
              const Icon(
                Icons.electric_bolt,
                color: Colors.orange,
                size: 60,
              ),
              const SizedBox(height: 8),
              const Text(
                'Total Consumo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                '${totalKwh.toStringAsFixed(2)} kWh',
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget consumoDolares() {
    double totalKwh =
        consumoDispositivos.values.fold(0.0, (sum, value) => sum + value);
    double totalDolares = totalKwh * tarifaKwHGlobal;

    return Column(
      children: [
        SizedBox(height: 10),
        Text(
          'Valor Consumido',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 5),
        IconButton(
          icon: Icon(Icons.attach_money, color: Colors.green, size: 40),
          onPressed: () {},
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monetization_on, color: Colors.green),
            Text(totalDolares.toStringAsFixed(2),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text('Histórico de Consumo'),
            SizedBox(height: 4),
            Text(
              'Consumo desde ${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year} hasta ${fechaFin.day}/${fechaFin.month}/${fechaFin.year}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.bar_chart),
                            onPressed: () => setState(() => selectedChart = 0),
                          ),
                          IconButton(
                            icon: Icon(Icons.pie_chart),
                            onPressed: () => setState(() => selectedChart = 1),
                          ),
                          IconButton(
                            icon: Icon(Icons.show_chart),
                            onPressed: () => setState(() => selectedChart = 2),
                          ),
                          IconButton(
                            icon: Icon(Icons.ads_click),
                            onPressed: () => setState(() => selectedChart = 3),
                          ),
                          IconButton(
                            icon: Icon(Icons.co2),
                            onPressed: () => setState(() => selectedChart = 4),
                          ),
                          IconButton(
                            icon: Icon(Icons.monetization_on),
                            onPressed: () => setState(() => selectedChart = 5),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.calendar_today),
                        onPressed: seleccionarFechas,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Expanded(child: buildChart()),
                  SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: consumoDispositivos.entries.map((entry) {
                        final device = entry.key;
                        final double energiaKwh = entry.value; // ya está en kWh
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: deviceColors[device],
                            ),
                            title: Text(device.replaceAll('_power', '')),
                            subtitle: Text(
                              '${energiaKwh.toStringAsFixed(2)} kWh', // muestra el total histórico
                            ),
                            trailing: Image.asset(
                              'assets/images/smart_plug.png',
                              width: 30,
                              height: 30,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
