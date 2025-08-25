import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math';

class HistoricoConsumo extends StatefulWidget {
  @override
  _HistoricoConsumoState createState() => _HistoricoConsumoState();
}

class _HistoricoConsumoState extends State<HistoricoConsumo> {
  final String apiUrl = 'http://192.168.0.121:8123/api/history/period/';
  final String authToken =
      'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIxZDY1ZTUyMmRiMDY0NWFjOWI5YjlmZDE3N2EzMzM2YyIsImlhdCI6MTczOTU4MDAzNywiZXhwIjoyMDU0OTQwMDM3fQ.SH_FZuWcuVc8jP3Ta81P4dJ0wqWicDtPGK23Cyb3954'; // Reemplaza con tu token de Home Assistant

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
      Uri.parse('http://192.168.0.121:8123/api/states'),
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
            double totalConsumo = 0.0;
            for (var entry in data[0]) {
              if (entry['state'] != 'unavailable') {
                double? consumo = double.tryParse(entry['state']);
                if (consumo != null) {
                  totalConsumo += consumo;
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
    if (selectedChart == 0) {
      return buildBarChart();
    } else if (selectedChart == 1) {
      return buildPieChart();
    } else if (selectedChart == 2) {
      return buildLineChart();
    } else if (selectedChart == 3) {
      return buildRadialBarChart();
    } else {
      return buildCO2Emission();
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
    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                drawVerticalLine: true,
                horizontalInterval: consumoDispositivos.values.isNotEmpty
                    ? consumoDispositivos.values.reduce(max) / 5
                    : 10,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.5),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.5),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      double consumoKw = value / 1000;
                      return Text(
                        '${consumoKw.toStringAsFixed(1)} KW',
                        style: TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return value == 0
                          ? Text(
                              '',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            )
                          : Container();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.black, width: 1),
              ),
              maxY: consumoDispositivos.values.isNotEmpty
                  ? consumoDispositivos.values.reduce(max) * 1.1
                  : 10,
              lineBarsData: consumoDispositivos.entries.map((entry) {
                return LineChartBarData(
                  spots: [
                    FlSpot(0, 0),
                    FlSpot(1, entry.value),
                  ],
                  isCurved: true,
                  color: deviceColors[entry.key] ?? Colors.grey,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  belowBarData: BarAreaData(show: false),
                );
              }).toList(),
            ),
          ),
        ),
        Text(
          'Dispositivos',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget buildRadialBarChart() {
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
  }

  Widget buildCO2Emission() {
    double totalKW = consumoDispositivos.values
            .fold(0.0, (double sum, double value) => sum + value) /
        1000;
    double totalCO2 =
        totalKW * 0.5; // Factor de emisión de CO2 (0.5 kg por kWh)

    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              SizedBox(height: 50),
              Icon(
                Icons.cloud_outlined,
                color: Colors.green,
                size: 60,
              ),
              Text(
                'Total CO2 Emitido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 5),
              Text(
                '${totalCO2.toStringAsFixed(2)} kg',
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Column(
            children: [
              SizedBox(height: 50),
              Icon(
                Icons.electric_bolt,
                color: Colors.orange,
                size: 60,
              ),
              Text(
                'Total Consumo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 5),
              Text(
                '${totalKW.toStringAsFixed(2)} KW',
                style: TextStyle(
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
                        double consumo = entry.value;
                        String unidad = consumo > 1000 ? 'KW' : 'W';
                        if (unidad == 'KW') {
                          consumo /= 1000;
                        }
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: deviceColors[entry.key],
                            ),
                            title: Text(entry.key.replaceAll('_power', '')),
                            subtitle:
                                Text('${consumo.toStringAsFixed(2)} $unidad'),
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
